spec SynchorizedClientMonitor
    observes eClientQueryRequest, eClientQueryResult, eClientCommandRequest, eClientCommandResult {
    var monitorState: State;
    var lastQueryRequest: tClientQueryRequest;
    var lastCommandRequest: tClientCommandRequest;
    
    start state Init {
        entry {
            monitorState = initialState();
        }
        
        on eClientQueryRequest do (payload: tClientQueryRequest) {
            lastQueryRequest = payload;
        }
        
        on eClientQueryResult do (payload: tClientQueryResult) {
            if (payload.ok) {
                assert payload.result == query(monitorState, lastQueryRequest.query),
                format("query failed, state = {0}, req = {1}, result = {2}", monitorState, lastQueryRequest, payload);
            }
        }
        
        on eClientCommandRequest do (payload: tClientCommandRequest) {
            lastCommandRequest = payload;
        }
        
        on eClientCommandResult do (payload: tClientCommandResult) {
            if (payload.ok) {
                apply(monitorState, lastCommandRequest.command);
            }
        }
    }
}