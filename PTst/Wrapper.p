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
        on eRequestVoteResult do (payload: tRequestVoteResult) { process(eRequestVote, payload); }
    }
    
    fun process(e: event, d: any) {
        var timer: ElectionTimer;
        if (dropRandomly && choose()) return;
        if (delayDuration > 0) {
            timer = new ElectionTimer(this);
            send timer, eStartTimer, choose(delayDuration);
            receive { case eElectionTimeOut: {} }
        }
        send server, e, d;
    }
}