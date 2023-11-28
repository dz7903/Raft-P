machine Wrapper {
    var id: (int, int);
    var server: Server;
    var delayDuration: int;
    var dropRandomly: bool;
    
    start state Init {
        entry (payload: (id: (int, int), server: Server, delayDuration: int, dropRandomly: bool)) {
            id = payload.id;
            server = payload.server;
            delayDuration = payload.delayDuration;
            dropRandomly = payload.dropRandomly;
        }
        
        on eAppendEntriesRequest do (payload: tAppendEntriesRequest) { process(eAppendEntriesRequest, payload); }
        on eAppendEntriesResult do (payload: tAppendEntriesResult) { process(eAppendEntriesResult, payload); }
        on eRequestVote do (payload: tRequestVote) { process(eRequestVote, payload); }
        on eRequestVoteResult do (payload: tRequestVoteResult) { process(eRequestVoteResult, payload); }
        on eClientQueryRequest do (payload: tClientQueryRequest) { process(eClientQueryRequest, payload); }
        on eClientCommandRequest do (payload: tClientCommandRequest) { process(eClientCommandRequest, payload); }
        ignore eClientCommandResult, eClientQueryResult;
    }
    
    fun process(e: event, d: any) {
        var timer: ElectionTimer;
        var delay: int;
        if (dropRandomly && choose()) {
            // print format("message from {0} to {1} is dropped, event = {2} msg = {3}", id.0, id.1, e, d);
            return;
        }
        if (delayDuration > 0) {
            delay = choose(delayDuration);
            // print format("message from {0} to {1} is delayed for {2} ticks", id.0, id.1, delay);
            timer = new ElectionTimer(this);
            send timer, eStartTimer, delay;
            receive { case eElectionTimeOut: {} }
        }
        send server, e, d;
    }
}