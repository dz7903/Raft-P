type LogEntry = (term: int, command: Command);
type ServerId = int;

type tServerInit = (peers: map[ServerId, machine], id: ServerId);
event eServerInit: tServerInit;

type tClientQueryRequest = (client: Client, reqId: int, query: Query);
event eClientQueryRequest: tClientQueryRequest;
type tClientQueryResult = (client: Client, reqId: int, ok: bool, result: QueryResult);
event eClientQueryResult: tClientQueryResult;
type tClientCommandRequest = (client: Client, reqId: int, command: Command);
event eClientCommandRequest: tClientCommandRequest;
type tClientCommandResult = (client: Client, reqId: int, ok: bool);
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
    var leaderId: ServerId;
    
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
    var clientCommandBuffer: seq[tClientCommandRequest];
    var clientQueryBuffer: seq[tClientQueryRequest];

    start state Init {
        entry {}
        
        on eServerInit do (payload: tServerInit) {
            peers = payload.peers;
            id = payload.id;
            currentTerm = 0;
            votedFor = -1;
            leaderId = -1;
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
            votedFor = -1;
            leaderId = id;
            send electionTimer, eCancelTimer;
            foreach (key in keys(nextIndex)){
                nextIndex -= (key);
            }
            foreach (key in keys(matchIndex)){
                matchIndex -= (key);
            }
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
            print "enter eElectionTimeOut";
            foreach (key in keys(peers)){
                if (key != id){
                    if (nextIndex[key] < sizeof(log)){
                        print "enter nextIndex[key] < sizeof(log) branch";
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
                        print "enter else branch";
                        // Send empty heartbeats
                        if(nextIndex[key] > 0 && nextIndex[key] < sizeof(log)) {
                            print "enter nextIndex[key] > 0 branch";
                            send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=log[nextIndex[key]-1].term, entries=entries, leaderCommit=commitIndex);
                        }else{
                            print "enter else branch";
                            send peers[key], eAppendEntriesRequest, (term=currentTerm, leaderId=id, prevLogIndex=nextIndex[key]-1, 
                                prevLogTerm=0, entries=entries, leaderCommit=commitIndex);
                        }
                    }
                }
            }
            CheckAndCommit();
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
                print "recvAppendResult.success branch";
                nextIndex[recvAppendResult.fromId] = recvAppendResult.lastIndex + 1;
                matchIndex[recvAppendResult.fromId] = recvAppendResult.lastIndex;
                CheckAndCommit();
            } else {
                print "else branch";
                if(recvAppendResult.lastIndex > 0 && nextIndex[recvAppendResult.fromId] > 0){
                    i = 0;
                    if(nextIndex[recvAppendResult.fromId] > recvAppendResult.lastIndex){
                        nextIndex[recvAppendResult.fromId] = recvAppendResult.lastIndex;
                    }else{
                        nextIndex[recvAppendResult.fromId] = nextIndex[recvAppendResult.fromId] - 1;
                    }
                    
                    while(i < sizeof(log) - nextIndex[recvAppendResult.fromId]){
                        entries += (i, log[i+nextIndex[recvAppendResult.fromId]]);
                        i = i + 1;
                    }
                    print "after first while";
                    if(nextIndex[recvAppendResult.fromId]-1 >= 0 && nextIndex[recvAppendResult.fromId]-1 < sizeof(log)){
                        send peers[recvAppendResult.fromId], eAppendEntriesRequest, (term=currentTerm, leaderId=id, 
                            prevLogIndex=nextIndex[recvAppendResult.fromId]-1, 
                            prevLogTerm=log[nextIndex[recvAppendResult.fromId]-1].term, 
                            entries=entries, leaderCommit=commitIndex);
                    }else{
                        send peers[recvAppendResult.fromId], eAppendEntriesRequest, (term=currentTerm, leaderId=id, 
                            prevLogIndex=nextIndex[recvAppendResult.fromId]-1, 
                            prevLogTerm=0, 
                            entries=entries, leaderCommit=commitIndex);
                    }
                    
                    print "after send";
                    // Empty the temporal entry buffer 
                    while(sizeof(entries) > 0){
                        entries -= (sizeof(entries) - 1);
                    }
                }
            }
        }
        
        on eClientQueryRequest do (payload: tClientQueryRequest) {
            send payload.client, eClientQueryResult, (
                client = payload.client, reqId = payload.reqId, ok = true, result = query(appState, payload.query));
        }
        
        on eClientCommandRequest do (payload: tClientCommandRequest) {
            var key: int;
            var i: int;
            var entries: seq[LogEntry];
            var recvedEntry: LogEntry;
            // print format("received command request {0}", payload);
            recvedEntry = (term=currentTerm, command=payload.command);
            // if(!(recvedEntry in log)){
            log += (sizeof(log), recvedEntry);
            apply(appState, payload.command);
            // }
            
            // if (!(payload in clientCommands)) {
            clientCommands += (sizeof(clientCommands), payload);
        
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
            // }
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
            leaderId = -1;
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
            if (recvEntry.term > currentTerm){
                currentTerm = recvEntry.term;
                goto Follower;
            }
        }
        
        on eElectionTimeOut do {
            goto Candidate;
        }

        on eRequestVote do (recvVoteRequest: tRequestVote){
            if(recvVoteRequest.term > currentTerm){
                RequestVoteReceiver(recvVoteRequest);
                goto Follower;
            }
        }

        on eClientQueryRequest do (payload: tClientQueryRequest){
            clientQueryBuffer += (sizeof(clientQueryBuffer), payload);
        }

        on eClientCommandRequest do (payload: tClientCommandRequest){
            clientCommandBuffer += (sizeof(clientCommandBuffer), payload);
        }
        
        ignore eClientCommandResult, eClientQueryResult, eAppendEntriesResult;
    }
    
    state Follower {
        entry{
            leaderId = -1;
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
            if(leaderId != -1){
                while(sizeof(clientCommandBuffer) > 0){
                    send peers[leaderId], eClientCommandRequest, clientCommandBuffer[0];
                    clientCommandBuffer -= 0;
                }
                while(sizeof(clientQueryBuffer) > 0){
                    send peers[leaderId], eClientQueryRequest, clientQueryBuffer[0];
                    clientQueryBuffer -= 0;
                }
            }
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

        on eClientQueryRequest do (payload: tClientQueryRequest){
            if(leaderId != -1){
                send peers[leaderId], eClientQueryRequest, payload; 
            }
            else{
                clientQueryBuffer += (sizeof(clientQueryBuffer), payload);
            }
        }

        on eClientCommandRequest do (payload: tClientCommandRequest){
            if(leaderId != -1){
                send peers[leaderId], eClientCommandRequest, payload;
            }
            else{
                clientCommandBuffer += (sizeof(clientCommandBuffer), payload);
            }
        }
        // eClientCommandRequest, eClientQueryRequest, 
        ignore eRequestVoteResult, eClientCommandResult, eClientQueryResult, eAppendEntriesResult;
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
        leaderId = recvEntry.leaderId;
        // 1. Reply false if term < currentTerm (5.1)
        if (recvEntry.term < currentTerm){
            send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=false, 
                fromId=id, lastIndex=sizeof(log)-1);
        }else{
             // 2. Reply false if log doesn't contain an entry at prevLogIndex whose term matches prevLogTerm. (5.3)
            if (recvEntry.prevLogIndex > -1 && (recvEntry.prevLogIndex > sizeof(log) || 
                (recvEntry.prevLogIndex < sizeof(log) && log[recvEntry.prevLogIndex].term != recvEntry.prevLogTerm))){
                    send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=false, fromId=id, 
                        lastIndex=sizeof(log)-1);
                    // return;
            }else{                
                if (sizeof(recvEntry.entries) == 0){
                    return;
                }
                print "before 3.";
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
                    print "after first while";
                    while(i + 1 < sizeof(log)){
                        log -= (sizeof(log) - 1);
                    }
                }
                print "after 3.";
                // 4. Append any new entries not already in the log
                if(recvEntry.prevLogIndex >= 0 && recvEntry.prevLogIndex < sizeof(log)){
                    print "3. if branch";
                    i = recvEntry.prevLogIndex + sizeof(recvEntry.entries) - sizeof(log);
                    j = sizeof(recvEntry.entries) - i;
                    while(j < sizeof(recvEntry.entries)){
                        log += (sizeof(log), recvEntry.entries[j]);
                        j = j + 1;
                    }
                }else{
                    print "3. else branch";
                    j = 0;
                    while(j < sizeof(recvEntry.entries)){
                        log += (sizeof(log), recvEntry.entries[j]);
                        j = j + 1;
                    }
                }
                print "after 4.";
                // 5. If leaderCommit > commitIndex, set commitIndex = min(leaderCommit, index of last new entry)
                if(recvEntry.leaderCommit > commitIndex){
                    commitIndex = Min(recvEntry.leaderCommit, sizeof(log)-1);    
                }
                print "before 5. send";
                send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=true, 
                    fromId=id, lastIndex=sizeof(log)-1);
                print "before 5. while";
                while (commitIndex > lastApplied) {
                    lastApplied = lastApplied + 1;
                    apply(appState, log[lastApplied].command);
                }
                print "after 5.";
            }
        }
    }

    fun RequestVoteReceiver(recvVoteRequest: tRequestVote){
        var lastLogTerm: int;
        // 1. Reply false if term < currentTerm (5.1)
        if(recvVoteRequest.term < currentTerm){
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
            votedFor = recvVoteRequest.candidateId;
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
        
        print "before while";
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
        print "after while";
        // Response to client
        i = prevCommitIndex + 1;
        if(commitIndex >= sizeof(log)){
            commitIndex = sizeof(log) - 1;
        }
        print "before if";
        while (i < commitIndex + 1 && i < sizeof(clientCommands)) {
            send clientCommands[i].client, eClientCommandResult, (
                client = clientCommands[i].client, reqId = clientCommands[i].reqId, ok = true);
            i = i + 1;
        }
        print "before last while";
        while (commitIndex > lastApplied) {
            lastApplied = lastApplied + 1;
            if(lastApplied < sizeof(log)){
                apply(appState, log[lastApplied].command);
            }else{
                lastApplied = sizeof(log) - 1;
                break;
            }
            
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