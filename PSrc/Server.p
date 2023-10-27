type LogEntry = (term: int, command: Command);
type ServerId = int;

type tServerInit = (peers: map[ServerId, machine], id: ServerId);
event eServerInit: tServerInit;

machine Server {
    var peers: map[ServerId, machine];
    var id: ServerId;
    
    var currentTerm: int;
    var votedFor: ServerId;
    var log: seq[LogEntry];
    
    start state Init {
        entry {}
        
        on eServerInit do (payload: tServerInit) {
            peers = payload.peers;
            id = payload.id;
            currentTerm = 0;
            votedFor = 0;
            goto Candidate;
        }
    }
    
    state Leader {
        
    }
    
    state Candidate {
        
    }
    
    state Follower {
        
    }
    
    state Restart {
        
    }
}