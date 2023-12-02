event eCommandLinearizationPoint: (client: Client, reqId: int, command: Command);

spec Linearizability observes eClientQueryRequest, eClientQueryResult,
    eClientCommandRequest, eClientCommandResult, eCommandLinearizationPoint {
    var monitorState: State;
    var clientQueries: map[(Client, int), Query];
    var clientCommands: map[(Client, int), Command];
    var linearizedCommands: map[(Client, int), Command];
    
    start state Start {
        entry {
            monitorState = initialState();
        }
        
        on eClientQueryRequest do (req: tClientQueryRequest) {
            if ((req.client, req.reqId) in clientQueries) {
                assert clientQueries[(req.client, req.reqId)] == req.query,
                    format("Duplicated query {0} is different with recorded {1}", req, clientQueries[(req.client, req.reqId)]);
            } else {
                clientQueries += ((req.client, req.reqId), req.query);
            }
        }
        
        on eClientQueryResult do (res: tClientQueryResult) {
            var req: Query;
            assert (res.client, res.reqId) in clientQueries,
                format("Client query result {0} has no corresponding request", res);
            if (res.ok) {
                req = clientQueries[(res.client, res.reqId)];
                assert res.result == query(monitorState, req),
                    format("Linearizability failed: unmatched result, query = {0}, result = {1}, monitorState = {2}", req, res, monitorState);
            }
        }
        
        on eClientCommandRequest do (req: tClientCommandRequest) {
            if ((req.client, req.reqId) in clientCommands) {
                assert clientCommands[(req.client, req.reqId)] == req.command,
                    format("Duplicated command {0} is different with recorded {1}", req, clientCommands[(req.client, req.reqId)]);
            } else {
                clientCommands += ((req.client, req.reqId), req.command);
            }
        }
        
        on eCommandLinearizationPoint do (payload: (client: Client, reqId: int, command: Command)) {
            assert (payload.client, payload.reqId) in clientCommands,
                format("client {0} and reqId {1} has no corresponding request", payload.client, payload.reqId);
            assert clientCommands[(payload.client, payload.reqId)] == payload.command,
                format("command {0} is different with recorded command {1}, for client {2} and reqId {3}", payload.command, clientCommands[(payload.client, payload.reqId)], payload.client, payload.reqId);
            // assert !((payload.client, payload.reqId) in linearizedCommands),
                // format("Linearization failed: command {0} has two linearization points", payload);
            if (!((payload.client, payload.reqId) in linearizedCommands)) {
                linearizedCommands += ((payload.client, payload.reqId), payload.command);
            }
            apply(monitorState, payload.command);
        }
        
        on eClientCommandResult do (res: tClientCommandResult) {
            assert (res.client, res.reqId) in clientCommands,
                format("Client command result {0} has no corresponding request", res);
            if (res.ok) {
                assert (res.client, res.reqId) in linearizedCommands,
                    format("Linearizability failed: result = {0} haven't reached its linearization point", res);
            }
        }
    }
}
