-module(goose_ws_ffi).
-export([connect/3]).

%% Connect to WebSocket using gun
connect(Url, HandlerPid, Compress) ->
    %% Start gun application and dependencies
    application:ensure_all_started(ssl),
    application:ensure_all_started(gun),

    %% Start ezstd if compression is enabled
    case Compress of
        true -> application:ensure_all_started(ezstd);
        _ -> ok
    end,

    %% Spawn a connection process that will own the gun connection
    Parent = self(),
    spawn(fun() -> connect_worker(Url, HandlerPid, Compress, Parent) end),

    %% Wait for the connection result
    receive
        {connection_result, Result} -> Result
    after 60000 ->
        {error, connection_timeout}
    end.

%% Worker process that owns the connection
connect_worker(Url, HandlerPid, Compress, Parent) ->
    %% Parse URL using uri_string
    UriMap = uri_string:parse(Url),
    #{scheme := SchemeStr, host := Host, path := Path} = UriMap,

    %% Get query string if present and append to path
    Query = maps:get(query, UriMap, undefined),
    PathWithQuery = case Query of
        undefined -> Path;
        <<>> -> Path;
        Q -> <<Path/binary, "?", Q/binary>>
    end,

    %% Get port, use defaults if not specified
    Port = maps:get(port, uri_string:parse(Url),
                    case SchemeStr of
                        <<"wss">> -> 443;
                        <<"ws">> -> 80;
                        _ -> 443
                    end),

    %% Determine transport
    Transport = case SchemeStr of
        <<"wss">> -> tls;
        <<"ws">> -> tcp;
        _ -> tls
    end,

    %% TLS options for secure connections
    TlsOpts = [{verify, verify_none}],  %% For simplicity, disable cert verification
                                          %% In production, use proper CA certs

    %% Connection options
    Opts = case Transport of
        tls ->
            #{
                transport => tls,
                tls_opts => TlsOpts,
                protocols => [http],
                retry => 10,
                retry_timeout => 1000
            };
        tcp ->
            #{
                transport => tcp,
                protocols => [http],
                retry => 10,
                retry_timeout => 1000
            }
    end,

    %% Convert host to list if needed
    HostStr = case is_binary(Host) of
        true -> binary_to_list(Host);
        false -> Host
    end,

    %% Ensure path with query is binary
    PathBin = case is_binary(PathWithQuery) of
        true -> PathWithQuery;
        false -> list_to_binary(PathWithQuery)
    end,

    %% Open connection (this process will be the owner)
    case gun:open(HostStr, Port, Opts) of
        {ok, ConnPid} ->
            %% Monitor the connection
            MRef = monitor(process, ConnPid),

            %% Wait for connection
            receive
                {gun_up, ConnPid, _Protocol} ->
                    %% Upgrade to WebSocket (compression is controlled via query string, not headers)
                    StreamRef = gun:ws_upgrade(ConnPid, binary_to_list(PathBin), []),

                    %% Wait for upgrade
                    receive
                        {gun_upgrade, ConnPid, StreamRef, [<<"websocket">>], _ResponseHeaders} ->
                            %% Notify parent that connection is ready
                            Parent ! {connection_result, {ok, ConnPid}},
                            %% Now handle messages in this process (the connection owner)
                            handle_messages(ConnPid, StreamRef, HandlerPid, Compress);
                        {gun_response, ConnPid, _, _, Status, Headers} ->
                            gun:close(ConnPid),
                            Parent ! {connection_result, {error, {upgrade_failed, Status, Headers}}};
                        {gun_error, ConnPid, _StreamRef, Reason} ->
                            gun:close(ConnPid),
                            Parent ! {connection_result, {error, {gun_error, Reason}}};
                        {'DOWN', MRef, process, ConnPid, Reason} ->
                            Parent ! {connection_result, {error, {connection_down, Reason}}};
                        _Other ->
                            gun:close(ConnPid),
                            Parent ! {connection_result, {error, unexpected_message}}
                    after 30000 ->
                        gun:close(ConnPid),
                        Parent ! {connection_result, {error, upgrade_timeout}}
                    end;
                {'DOWN', MRef, process, ConnPid, Reason} ->
                    Parent ! {connection_result, {error, {connection_failed, Reason}}};
                _Other ->
                    gun:close(ConnPid),
                    Parent ! {connection_result, {error, unexpected_message}}
            after 30000 ->
                gun:close(ConnPid),
                Parent ! {connection_result, {error, connection_timeout}}
            end;
        {error, Reason} ->
            Parent ! {connection_result, {error, {open_failed, Reason}}}
    end.

%% Handle incoming WebSocket messages
handle_messages(ConnPid, StreamRef, HandlerPid, Compress) ->
    %% Load zstd dictionary if compression is enabled
    Decompressor = case Compress of
        true ->
            %% Load dictionary from priv directory
            PrivDir = code:priv_dir(goose),
            DictPath = filename:join(PrivDir, "zstd_dictionary"),
            case file:read_file(DictPath) of
                {ok, DictData} ->
                    %% Create decompression context and dictionary
                    DCtx = ezstd:create_decompression_context(1024 * 1024),
                    DDict = ezstd:create_ddict(DictData),
                    %% Select the dictionary for the decompression context
                    ok = ezstd:select_ddict(DCtx, DDict),
                    {ok, {DCtx, DDict}};
                {error, Err} ->
                    io:format("Failed to load zstd dictionary: ~p~n", [Err]),
                    {error, Err}
            end;
        _ ->
            none
    end,
    handle_messages_loop(ConnPid, StreamRef, HandlerPid, Compress, Decompressor).

%% Message handling loop
handle_messages_loop(ConnPid, StreamRef, HandlerPid, Compress, Decompressor) ->
    receive
        {gun_ws, _AnyConnPid, _AnyStreamRef, {text, Text}} ->
            HandlerPid ! {ws_text, Text},
            handle_messages_loop(ConnPid, StreamRef, HandlerPid, Compress, Decompressor);
        {gun_ws, _AnyConnPid, _AnyStreamRef, {binary, Binary}} ->
            %% If compression is enabled, decompress the binary data
            case {Compress, Decompressor} of
                {true, {ok, {DCtx, DDict}}} ->
                    %% Try decompress_using_ddict first (works for frames with content size)
                    case ezstd:decompress_using_ddict(Binary, DDict) of
                        Result when is_binary(Result) ->
                            HandlerPid ! {ws_text, Result};
                        Result when is_list(Result) ->
                            HandlerPid ! {ws_text, iolist_to_binary(Result)};
                        {error, <<"failed to decompress: ZSTD_CONTENTSIZE_UNKNOWN">>} ->
                            %% Frame doesn't have content size, use streaming with dictionary-loaded context
                            case ezstd:decompress_streaming(DCtx, Binary) of
                                StreamResult when is_binary(StreamResult) ->
                                    HandlerPid ! {ws_text, StreamResult};
                                StreamResult when is_list(StreamResult) ->
                                    HandlerPid ! {ws_text, iolist_to_binary(StreamResult)};
                                {error, _StreamReason} ->
                                    %% Skip frames that fail to decompress
                                    ok
                            end;
                        {error, _Reason} ->
                            %% Skip frames that fail to decompress
                            ok
                    end;
                _ ->
                    %% No compression, ignore binary messages
                    ok
            end,
            handle_messages_loop(ConnPid, StreamRef, HandlerPid, Compress, Decompressor);
        {gun_ws, ConnPid, StreamRef, close} ->
            HandlerPid ! {ws_closed, normal},
            gun:close(ConnPid);
        {gun_down, ConnPid, _Protocol, Reason, _KilledStreams} ->
            HandlerPid ! {ws_error, Reason},
            gun:close(ConnPid);
        {gun_error, ConnPid, StreamRef, Reason} ->
            HandlerPid ! {ws_error, Reason},
            handle_messages_loop(ConnPid, StreamRef, HandlerPid, Compress, Decompressor);
        stop ->
            gun:close(ConnPid);
        _Other ->
            %% Ignore unexpected messages
            handle_messages_loop(ConnPid, StreamRef, HandlerPid, Compress, Decompressor)
    after 30000 ->
        %% Heartbeat every 30 seconds to keep connection alive
        handle_messages_loop(ConnPid, StreamRef, HandlerPid, Compress, Decompressor)
    end.
