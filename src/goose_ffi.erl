-module(goose_ffi).
-export([priv_dir/0, decompress_using_ddict_safe/2, decompress_streaming_safe/2]).

%% Get the priv directory for the goose application
priv_dir() ->
    case code:priv_dir(goose) of
        {error, _} -> "./priv";
        Path when is_list(Path) -> list_to_binary(Path);
        Path -> Path
    end.

%% Safe wrapper for ezstd:decompress_using_ddict that always returns Result type
decompress_using_ddict_safe(Data, DDict) ->
    case ezstd:decompress_using_ddict(Data, DDict) of
        Result when is_binary(Result) ->
            {ok, Result};
        Result when is_list(Result) ->
            {ok, iolist_to_binary(Result)};
        {error, Err} when is_binary(Err) ->
            %% Keep error as binary (Gleam String)
            {error, Err};
        {error, Err} when is_list(Err) ->
            %% Convert list to binary
            {error, list_to_binary(Err)};
        {error, Err} ->
            %% Convert any other type to binary
            {error, list_to_binary(lists:flatten(io_lib:format("~p", [Err])))}
    end.

%% Safe wrapper for ezstd:decompress_streaming that always returns Result type
decompress_streaming_safe(DCtx, Data) ->
    case ezstd:decompress_streaming(DCtx, Data) of
        Result when is_binary(Result) ->
            {ok, Result};
        Result when is_list(Result) ->
            {ok, iolist_to_binary(Result)};
        {error, Err} when is_binary(Err) ->
            %% Keep error as binary (Gleam String)
            {error, Err};
        {error, Err} when is_list(Err) ->
            %% Convert list to binary
            {error, list_to_binary(Err)};
        {error, Err} ->
            %% Convert any other type to binary
            {error, list_to_binary(lists:flatten(io_lib:format("~p", [Err])))}
    end.
