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
    var nextIndex: seq[int];
    var matchIndex: seq[int];

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
            commitIndex = 0;
            lastApplied = 0;
            voteCount = 0;

            electionTimer = new ElectionTimer(this);
            
            appState = initialState();
            
            goto Follower;
        }
        
        on eClientQueryRequest do ignoreClientQueryRequest;
        on eClientCommandRequest do ignoreClientCommandRequest;
    }
    
    state Leader {
        entry{
            var key: int;
            send electionTimer, eCancelTimer;
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
                    if (nextIndex[key] <= sizeof(log) - 1){
                        // Fill the entry buffer and send all the entries from nextIndex[key]
                        i = 0;
                        while(i < sizeof(log) - nextIndex[key]){
                            entries += (i, log[i+nextIndex[key]]);
                            i = i + 1;
                        }
                        send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                            prevLogTerm=log[nextIndex[key]-1].term, entries=entries, leaderCommit=commitIndex);
                        // Empty the temporal entry buffer 
                        while(i > -1){
                            entries -= (i);
                            i = i-1;
                        }
                    }else{
                        // Send empty heartbeats
                        send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                            prevLogTerm=log[nextIndex[key]-1].term, entries=entries, leaderCommit=commitIndex);
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
                while(i > -1){
                    entries -= (i);
                    i = i - 1;
                }
            }
        }
        
        on eClientQueryRequest do (payload: tClientQueryRequest) {
            send payload.client, eClientQueryResult, (ok = true, result = query(appState, payload.query));
        }
        
        on eClientCommandRequest do (payload: tClientCommandRequest) {
            log += (sizeof(log), (term=currentTerm, command=payload.command));
            apply(appState, payload.command);
            clientCommands += (sizeof(clientCommands), payload);
            CheckAndCommit();
            // send payload.client, eClientCommandResult, (ok = true,);
            // TODO: Leader logic
        }
    }
    
    state Candidate {
        entry{
            var key: int;
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
                    send peers[key], eRequestVote, (term=currentTerm, candidateId=id, lastLogIndex=sizeof(log)-1, 
                                                    lastLogTerm=log[sizeof(log)-1].term);
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
        
        on eClientQueryRequest do ignoreClientQueryRequest;
        on eClientCommandRequest do ignoreClientCommandRequest;
    }
    
    state Follower {
        entry{
            while (commitIndex > lastApplied) {
                lastApplied = lastApplied + 1;
                apply(appState, log[lastApplied].command);
            }
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
        
        on eClientQueryRequest do ignoreClientQueryRequest;
        on eClientCommandRequest do ignoreClientCommandRequest;
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
            lastApplied = 0;
            goto Follower;
        }
        
        on eClientQueryRequest do ignoreClientQueryRequest;
        on eClientCommandRequest do ignoreClientCommandRequest;
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
        if (recvEntry.prevLogIndex > sizeof(log) || 
           (recvEntry.prevLogIndex <= sizeof(log) && log[recvEntry.prevLogIndex].term != recvEntry.prevLogTerm)){
            send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=false, fromId=id, 
                lastIndex=sizeof(log)-1);
            return;
        }
        // 3. If an existing entry conflicts with a new one (same index but different terms), delete the existing entry
        // and all that follow if (5.3)
        i = recvEntry.prevLogIndex;
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
        // 4. Append any new entries not already in the log
        i = recvEntry.prevLogIndex + sizeof(recvEntry.entries) - sizeof(log);
        j = sizeof(recvEntry.entries) - i;
        while(j < sizeof(recvEntry.entries)){
            log += (sizeof(log), recvEntry.entries[j]);
            j = j + 1;
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
        // 1. Reply false if term < currentTerm (5.1)
        if(recvVoteRequest.lastLogTerm < currentTerm){
            send peers[recvVoteRequest.candidateId], eRequestVoteResult, (term=currentTerm, voteGranted=false);
        }
        // 2. If votedFor is null or candidateId, and candidate's log is at least as up-to-date as receiver's log,
        // grant vote
        if((votedFor == -1 || votedFor == recvVoteRequest.candidateId) && 
           UpToDate(recvVoteRequest.lastLogTerm, recvVoteRequest.lastLogIndex, currentTerm, sizeof(log)-1)){
            send peers[recvVoteRequest.candidateId], eRequestVoteResult, (term=currentTerm, voteGranted=true);
            // goto Candidate; // Is this true? 
        }
    }

    fun CheckAndCommit(){
        var i: int;
        var N: int; // New commit index
        var majorMatchIndex: int;
        var prevCommitIndex: int;
        prevCommitIndex = commitIndex;
        
        // Commit up to the max N.
        N = sizeof(log) - 1;
        while (N > commitIndex) {
            majorMatchIndex = 1; // Leader always has it
            foreach(i in keys(peers)) {
                if (matchIndex[i] >= N) {
                    majorMatchIndex = majorMatchIndex + 1;
                    if (majorMatchIndex > sizeof(peers) / 2  && log[N].term == currentTerm) {
                        commitIndex = N;
                        break;
                    }
                }
            }
            if (commitIndex == N) {
                break;
            }
            N = N - 1;
        }
        // Response to client
        i = prevCommitIndex;
        while (i < commitIndex + 1) {
            send clientCommands[i].client, eClientCommandResult, (ok = true, );
            i = i + 1;
        }
        while (commitIndex > lastApplied) {
            lastApplied = lastApplied + 1;
            apply(appState, log[lastApplied].command);
        }
    }

    fun ignoreClientQueryRequest(req: tClientQueryRequest) {
        send req.client, eClientQueryResult, (ok = false, result = default(QueryResult));
    }
    
    fun ignoreClientCommandRequest(req: tClientCommandRequest) {
        send req.client, eClientCommandResult, (ok = false,);
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