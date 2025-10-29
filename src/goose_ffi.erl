-module(goose_ffi).
-export([receive_ws_message/0]).

%% Receive a WebSocket text message from the process mailbox
receive_ws_message() ->
    receive
        %% Handle messages forwarded from handler process
        {ws_text, Text} ->
            {ok, Text};
        {ws_binary, _Binary} ->
            %% Ignore binary messages, try again
            receive_ws_message();
        {ws_closed, _Reason} ->
            {error, nil};
        {ws_error, _Reason} ->
            {error, nil};
        _Other ->
            %% Ignore unexpected messages
            receive_ws_message()
    after 60000 ->
        %% Timeout - return error to continue loop
        {error, nil}
    end.
