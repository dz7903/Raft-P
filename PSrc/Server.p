type LogEntry = (term: int, command: Command);
type ServerId = int;

type tServerInit = (peers: map[ServerId, machine], id: ServerId);
event eServerInit: tServerInit;

type tAppendEntriesRequest = (term: int, leaderId: ServerId, prevLogIndex: int, prevLogTerm: int,
                              entries: seq[LogEntry], leaderCommit: int);
event eAppendEntriesRequest: tAppendEntriesRequest;

type tAppendEntriesResult = (term: int, success: bool);
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

    //Volatile state on leaders
    var nextIndex: seq[int];
    var matchIndex: seq[int];

    var electionTimer: ElectionTimer;

    start state Init {
        entry {}
        
        on eServerInit do (payload: tServerInit) {
            peers = payload.peers;
            id = payload.id;
            currentTerm = 0;
            votedFor = -1;
            commitIndex = 0;
            lastApplied = 0;

            electionTimer = new ElectionTimer(this);
            
            goto Follower;
        }
    }
    
    state Leader {
        
    }
    
    state Candidate {
        
    }
    
    state Follower {
        on eAppendEntriesRequest do (recvEntry: tAppendEntriesRequest){
            // Reset electionTimer.
            send electionTimer, eCancelTimer;
            // AppendEntries RPC
            AppendEntries(recvEntry);
            // Start the electionTimer again.
            send electionTimer, eStartTimer, (150+choose(150));
        }
        on eElectionTimeOut goto Candidate;
        on eRequestVote do (recvVoteRequest: tRequestVote){
            //RequestVote RPC
            RequestVote(recvVoteRequest);
        }
    }
    
    state Restart {
        
    }

    fun AppendEntries(recvEntry: tAppendEntriesRequest){
        // AppendEntries RPC
        var i: int;
        var j: int;
        // 1. Reply false if term < currentTerm (5.1)
        if (recvEntry.term < currentTerm){
            send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=false);
        }
        // 2. Reply false if log doesn't contain an entry at prevLogIndex whose term matches prevLogTerm. (5.3)
        if (recvEntry.prevLogIndex > sizeof(log) && currentTerm == recvEntry.term){
            send peers[recvEntry.leaderId], eAppendEntriesResult, (term=currentTerm, success=false);
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
        }
        // 5. If leaderCommit > commitIndex, set commitIndex = min(leaderCommit, index of last new entry)
        if(recvEntry.leaderCommit > commitIndex){
            commitIndex = Min(recvEntry.leaderCommit, sizeof(log));    
        }
    }

    fun RequestVote(recvVoteRequest: tRequestVote){
        // 1. Reply false if term < currentTerm (5.1)
        if(recvVoteRequest.lastLogTerm < currentTerm){
            send peers[recvVoteRequest.candidateId], eRequestVoteResult, (term=currentTerm, voteGranted=false);
        }
        // 2. If votedFor is null or candidateId, and candidate's log is at least as up-to-date as receiver's log,
        // grant vote
        if((votedFor == -1 || votedFor == recvVoteRequest.candidateId) && 
           UpToDate(recvVoteRequest.lastLogTerm, recvVoteRequest.lastLogIndex, currentTerm, sizeof(log)-1)){
            send peers[recvVoteRequest.candidateId], eRequestVoteResult, (term=currentTerm, voteGranted=true);
            goto Candidate; // Is this true? 
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