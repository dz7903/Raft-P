type LogEntry = (term: int, command: Command);
type ServerId = int;

type tServerInit = (peers: map[ServerId, machine], id: ServerId);
event eServerInit: tServerInit;

type tClientQueryRequest = (client: machine, reqId: int, query: Query);
event eClientQueryRequest: tClientQueryRequest;
type tClientQueryResult = (ok: bool, result: QueryResult);
event eClientQueryResult: tClientQueryResult;
type tClientCommandRequest = (client: machine, reqId: int, command: Command);
event eClientCommandRequest: tClientCommandRequest;
type tClientCommandResult = (ok: bool);
event eClientCommandResult: tClientCommandResult;

type tAppendEntriesRequest = (term: int, leaderId: ServerId, prevLogIndex: int, prevLogTerm: int,
                              entries: seq[LogEntry], leaderCommit: int);
event eAppendEntriesRequest: tAppendEntriesRequest;

type tAppendEntriesResult = (term: int, success: bool, fromId: ServerId, lastIndex: int); // Discuss
event eAppendEntriesResult: tAppendEntriesResult;

type tRequestVote = (term: int, candidateId: ServerId, lastLogIndex: int, lastLogTerm: int);
event eRequestVote: tRequestVote;

type tRequestVoteResult = (term: int, voteGranted: bool);
event eRequestVoteResult: tRequestVoteResult;

machine Server {
    var peers: map[ServerId, machine];
    var id: ServerId;
    
    // Persistent state on all servers
    var currentTerm: int;
    var votedFor: ServerId;
    var log: seq[LogEntry];

    // Volatile state on all servers
    var commitIndex: int;
    var lastApplied: int;

    // Volatile state on leaders
    var nextIndex: map[ServerId, int];
    var matchIndex: map[ServerId, int];

    // Follower to candidate and candidate restart voting
    var electionTimer: ElectionTimer; 
    
    var appState: State;

    // Vote count for candidates
    var voteCount: int; 

    var clientCommands: seq[tClientCommandRequest];

    start state Init {
        entry {}
        
        on eServerInit do (payload: tServerInit) {
            peers = payload.peers;
            id = payload.id;
            currentTerm = 0;
            votedFor = -1;
            commitIndex = -1;
            lastApplied = -1;
            voteCount = 0;

            electionTimer = new ElectionTimer(this);
            
            appState = initialState();
            
            goto Follower;
        }
        
        ignore eClientQueryRequest, eClientCommandRequest, eRequestVote, eClientCommandResult, eClientQueryResult;
    }
    
    state Leader {
        entry{
            var key: int;
            send electionTimer, eCancelTimer;
            // foreach (key in keys(peers)){
            //     nextIndex -= (key);
            //     matchIndex -= (key)
            // }
            foreach (key in keys(peers)){
                if (key != id){
                    nextIndex += (key, sizeof(log));
                    matchIndex += (key, 0);
                    send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=currentTerm, entries=log, leaderCommit=commitIndex);
                }
            }

            while (commitIndex > lastApplied) {
                lastApplied = lastApplied + 1;
                apply(appState, log[lastApplied].command);
            }
            send electionTimer, eStartTimer, (50+choose(100)); 
        }
        
        on eElectionTimeOut do {
            var key: int;
            var entries: seq[LogEntry];
            var i: int;
            foreach (key in keys(peers)){
                if (key != id){
                    if (nextIndex[key] < sizeof(log)){
                        // Fill the entry buffer and send all the entries from nextIndex[key]
                        i = 0;
                        while(i < sizeof(log) - nextIndex[key]){
                            entries += (i, log[i+nextIndex[key]]);
                            i = i + 1;
                        }
                        if(nextIndex[key] > 0) {
                            send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=log[nextIndex[key]-1].term, entries=entries, leaderCommit=commitIndex);
                        }else{
                            send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=0, entries=entries, leaderCommit=commitIndex);
                        }
                        // Empty the temporal entry buffer 
                        while(sizeof(entries) > 0){
                            entries -= (sizeof(entries) - 1);
                        }
                    }else{
                        // Send empty heartbeats
                        if(nextIndex[key] > 0) {
                            send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=log[nextIndex[key]-1].term, entries=entries, leaderCommit=commitIndex);
                        }else{
                            send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=0, entries=entries, leaderCommit=commitIndex);
                        }
                    }
                }
            }
            send electionTimer, eStartTimer, (50+choose(100));
        }
        
        on eAppendEntriesResult do (recvAppendResult: tAppendEntriesResult) {
            var entries: seq[LogEntry];
            var i: int;

            if(recvAppendResult.term > currentTerm){
                currentTerm = recvAppendResult.term;
                goto Follower;
            }

            if(recvAppendResult.success) {
                nextIndex[recvAppendResult.fromId] = recvAppendResult.lastIndex + 1; // Is this correct?
                matchIndex[recvAppendResult.fromId] = recvAppendResult.lastIndex; // How to update?
                CheckAndCommit();
            } else {
                if(recvAppendResult.lastIndex > 0){
                    nextIndex[recvAppendResult.fromId] = nextIndex[recvAppendResult.fromId] - 1;
                    while(i < sizeof(log) - nextIndex[recvAppendResult.fromId]){
                        entries += (i, log[i+nextIndex[recvAppendResult.fromId]]);
                        i = i + 1;
                    }
                    send peers[recvAppendResult.fromId], eAppendEntriesRequest, (term=currentTerm, leaderId=id, 
                        prevLogIndex=nextIndex[recvAppendResult.fromId]-1, 
                        prevLogTerm=log[nextIndex[recvAppendResult.fromId]-1].term, 
                        entries=entries, leaderCommit=commitIndex);
                    // Empty the temporal entry buffer 
                    while(sizeof(entries) > 0){
                        entries -= (sizeof(entries) - 1);
                    }
                }
            }
        }
        
        on eClientQueryRequest do (payload: tClientQueryRequest) {
            send payload.client, eClientQueryResult, (ok = true, result = query(appState, payload.query));
        }
        
        on eClientCommandRequest do (payload: tClientCommandRequest) {
            var key: int;
            var i: int;
            var entries: seq[LogEntry];
            // print format("received command request {0}", payload);
            log += (sizeof(log), (term=currentTerm, command=payload.command));
            apply(appState, payload.command);
            if (sizeof(clientCommands) == 0 || clientCommands[sizeof(clientCommands) - 1] != payload) {
                clientCommands += (sizeof(clientCommands), payload);
            }
            // print format("clientCommands: {0}", clientCommands);
            foreach (key in keys(peers)){
                if (key != id){
                    if (nextIndex[key] < sizeof(log)){
                        // Fill the entry buffer and send all the entries from nextIndex[key]
                        i = 0;
                        while(i < sizeof(log) - nextIndex[key]){
                            entries += (i, log[i+nextIndex[key]]);
                            i = i + 1;
                        }
                        if(nextIndex[key] > 0) {
                            send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=log[nextIndex[key]-1].term, entries=entries, leaderCommit=commitIndex);
                        }else{
                            send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=0, entries=entries, leaderCommit=commitIndex);
                        }
                        // Empty the temporal entry buffer 
                        while(sizeof(entries) > 0){
                            entries -= (sizeof(entries) - 1);
                        }
                    }
                }
            }
            CheckAndCommit();
            // send payload.client, eClientCommandResult, (ok = true,);
            // TODO: Leader logic
        }
        ignore eRequestVote, eRequestVoteResult, eAppendEntriesRequest;
    }
    
    state Candidate {
        entry{
            var key: int;
            var emptyLogEntry: LogEntry;
            // On conversion to candidate, start election:s
            currentTerm = currentTerm + 1;
            votedFor = id;
            voteCount = 1;
            if (voteCount > sizeof(peers)/2) {
                goto Leader;
            }
            send electionTimer, eCancelTimer;
            foreach (key in keys(peers))
            {
                if (key != id){
                    if(sizeof(log) > 0){
                        send peers[key], eRequestVote, (term=currentTerm, candidateId=id, lastLogIndex=sizeof(log)-1, 
                                                    lastLogTerm=log[sizeof(log)-1].term);
                    }else{
                        send peers[key], eRequestVote, (term=currentTerm, candidateId=id, lastLogIndex=sizeof(log)-1, 
                                                    lastLogTerm=0); // To make sure the request is valid.
                    }
                    
                }
            }

            while (commitIndex > lastApplied) {
                lastApplied = lastApplied + 1;
                apply(appState, log[lastApplied].command);
            }

            send electionTimer, eStartTimer, (150+choose(150));
        }
        
        on eRequestVoteResult do (recvVoteResult: tRequestVoteResult){
            if(recvVoteResult.term > currentTerm) {
                currentTerm = recvVoteResult.term;
                goto Follower;
            }

            // Majority voting result
            if (recvVoteResult.voteGranted){
                voteCount = voteCount + 1;
                if (voteCount > sizeof(peers)/2) {
                    goto Leader;
                }
            }
        }
        
        on eAppendEntriesRequest do (recvEntry: tAppendEntriesRequest){
            AppendEntriesReceiver(recvEntry);
            if (UpToDate(recvEntry.term, recvEntry.prevLogIndex, currentTerm, sizeof(log)-1)){
                currentTerm = recvEntry.term;
                goto Follower;
            }
        }
        
        on eElectionTimeOut do {
            goto Candidate;
        }
        
        ignore eClientQueryRequest, eClientCommandRequest, eRequestVote, eClientCommandResult, eClientQueryResult;
    }
    
    state Follower {
        entry{
            while (commitIndex > lastApplied) {
                lastApplied = lastApplied + 1;
                apply(appState, log[lastApplied].command);
            }
            votedFor = -1;
            send electionTimer, eStartTimer, (150+choose(150));
        }
        
        on eAppendEntriesRequest do (recvEntry: tAppendEntriesRequest){
            // Reset electionTimer.
            send electionTimer, eCancelTimer;
            // AppendEntries RPC
            AppendEntriesReceiver(recvEntry);
            if (recvEntry.term > currentTerm) {
                currentTerm = recvEntry.term;
            }
            // Start the electionTimer again.
            send electionTimer, eStartTimer, (150+choose(150));
        }
        
        on eElectionTimeOut goto Candidate;
        
        on eRequestVote do (recvVoteRequest: tRequestVote){
            //RequestVote RPC
            RequestVoteReceiver(recvVoteRequest);
        }
        ignore eClientQueryRequest, eClientCommandRequest, eRequestVoteResult, eClientCommandResult, eClientQueryResult, eAppendEntriesResult;
    }
    
    state Restart {
        entry{
            var i: int;
            i = 0;
            while(i < sizeof(peers)) {
                nextIndex[i] = 0;
                matchIndex[i] = 0;
            }
            commitIndex = 0;
            lastApplied = -1;
            goto Follower;
        }
        
        ignore eClientQueryRequest, eClientCommandRequest;
    }

    fun AppendEntriesReceiver(recvEntry: tAppendEntriesRequest){
        // AppendEntries RPC
        var i: int;
        var j: int;
        // 1. Reply false if term < currentTerm (5.1)
        if (recvEntry.term < currentTerm){
            send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=false, 
                fromId=id, lastIndex=sizeof(log)-1);
            return;
        }
        // 2. Reply false if log doesn't contain an entry at prevLogIndex whose term matches prevLogTerm. (5.3)
        if(recvEntry.prevLogIndex > -1){
            if (recvEntry.prevLogIndex > sizeof(log) || 
            (recvEntry.prevLogIndex <= sizeof(log) && log[recvEntry.prevLogIndex].term != recvEntry.prevLogTerm)){
                send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=false, fromId=id, 
                    lastIndex=sizeof(log)-1);
                return;
            }
        }
        
        if (sizeof(recvEntry.entries) == 0){
            send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=false, fromId=id, 
                lastIndex=sizeof(log)-1);
            return;
        }
        // 3. If an existing entry conflicts with a new one (same index but different terms), delete the existing entry
        // and all that follow if (5.3)
        i = recvEntry.prevLogIndex;
        if(sizeof(log) > 0 && i >= 0) {
            while(i + 1 < sizeof(log) && i - recvEntry.prevLogIndex < sizeof(recvEntry.entries)){
                if(log[i + 1].term != recvEntry.entries[i - recvEntry.prevLogIndex].term){
                    break;
                }
                i = i + 1;
            }
            while(i + 1 < sizeof(log)){
                log -= (i + 1);
                i = i + 1;
            }
        }
        // 4. Append any new entries not already in the log
        if(recvEntry.prevLogIndex >= 0){
            i = recvEntry.prevLogIndex + sizeof(recvEntry.entries) - sizeof(log);
            j = sizeof(recvEntry.entries) - i;
            while(j < sizeof(recvEntry.entries)){
                log += (sizeof(log), recvEntry.entries[j]);
                j = j + 1;
            }
        }else{
            j = 0;
            while(j < sizeof(recvEntry.entries)){
                log += (sizeof(log), recvEntry.entries[j]);
                j = j + 1;
            }
        }
        // 5. If leaderCommit > commitIndex, set commitIndex = min(leaderCommit, index of last new entry)
        if(recvEntry.leaderCommit > commitIndex){
            commitIndex = Min(recvEntry.leaderCommit, sizeof(log));    
        }
        send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=true, 
            fromId=id, lastIndex=sizeof(log)-1);
        
        while (commitIndex > lastApplied) {
            lastApplied = lastApplied + 1;
            apply(appState, log[lastApplied].command);
        }
    }

    fun RequestVoteReceiver(recvVoteRequest: tRequestVote){
        var lastLogTerm: int;
        // 1. Reply false if term < currentTerm (5.1)
        if(recvVoteRequest.lastLogTerm < currentTerm){
            send peers[recvVoteRequest.candidateId], eRequestVoteResult, (term=currentTerm, voteGranted=false);
            return;
        }
        // 2. If votedFor is null or candidateId, and candidate's log is at least as up-to-date as receiver's log,
        // grant vote
        if(sizeof(log) > 0) {
            lastLogTerm = log[sizeof(log)-1].term;
        }else{
            lastLogTerm = -1;
        }
        if((votedFor == -1 || votedFor == recvVoteRequest.candidateId) && 
           UpToDate(recvVoteRequest.lastLogTerm, recvVoteRequest.lastLogIndex, lastLogTerm, sizeof(log)-1)){
            send peers[recvVoteRequest.candidateId], eRequestVoteResult, (term=currentTerm, voteGranted=true);
            return;
        }
    }

    fun CheckAndCommit(){
        var i: int;
        var N: int; // New commit index
        var majorMatchIndex: int;
        var prevCommitIndex: int;
        prevCommitIndex = commitIndex;
        // print format("commit index = {0}", commitIndex);
        
        // Commit up to the max N.
        N = sizeof(log) - 1;
        while (N > commitIndex) {
            majorMatchIndex = 1; // Leader always has it
            foreach(i in keys(peers)) {
                if (i != id) {
                    if (matchIndex[i] >= N) {
                        majorMatchIndex = majorMatchIndex + 1;
                    }
                }
            }
            if (majorMatchIndex > sizeof(peers) / 2  && log[N].term == currentTerm) {
                commitIndex = N;
                break;
            }
            if (commitIndex == N) {
                break;
            }
            N = N - 1;
        }
        // Response to client
        i = prevCommitIndex + 1;
        while (i < commitIndex + 1) {
            send clientCommands[i].client, eClientCommandResult, (ok = true, );
            i = i + 1;
        }
        while (commitIndex > lastApplied) {
            lastApplied = lastApplied + 1;
            apply(appState, log[lastApplied].command);
        }
    }
}

// Compare and return the minimum between a and b
fun Min(a: int, b: int): int{
    if(a <= b){
        return a;
    }else{
        return b;
    }
}

// Compare and return the minimum between a and b
fun Max(a: int, b: int): int{
    if(a <= b){
        return b;
    }else{
        return a;
    }
}

// If log_A is at least as up-to-date as log_B return true, else return false.
fun UpToDate(lastTermA: int, lastIndexA: int, lastTermB: int, lastIndexB: int): bool{
    if(lastTermA > lastTermB){
        return true;
    } else if(lastTermA == lastTermB){
        if(lastIndexA >= lastIndexB){
            return true;
        }else{
            return false;
        }
    }else{
        return false;
    }
}