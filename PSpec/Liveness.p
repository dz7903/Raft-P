spec LivenessMonitor
    observes eClientQueryRequest, eClientQueryResult, eClientCommandRequest, eClientCommandResult {
    var pendingClients: set[Client];

    start state Init {
        entry { goto NoPending; }
    }
    
    cold state NoPending {
        on eClientQueryRequest do (req: tClientQueryRequest) {
            pendingClients += (req.client);
            goto Pending;
        }
        on eClientCommandRequest do (req: tClientCommandRequest) {
            pendingClients += (req.client);
            goto Pending;
        }
        // ignore eClientCommandResult, eClientQueryResult;
    }
    
    hot state Pending {
        on eClientCommandRequest do (req: tClientCommandRequest) {
            pendingClients += (req.client);
        }
        on eClientQueryRequest do (req: tClientQueryRequest) {
            pendingClients += (req.client);
        }
        on eClientCommandResult do (req: tClientCommandResult) {
            pendingClients -= (req.client);
            if (sizeof(pendingClients) == 0) {
                goto NoPending;
            }
        }
        on eClientQueryResult do (req: tClientQueryResult) {
            pendingClients -= (req.client);
            if (sizeof(pendingClients) == 0) {
                goto NoPending;
            }
        }
    }
}
    