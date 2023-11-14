machine Client {
    var servers: map[ServerId, Server];
    var timer: ElectionTimer;
    var clientKeys: seq[string];
    var counter: int;
    var nRequests: int;
    var retryDuration: tTimerTicks;
    
    start state Init {
        entry (payload: (servers: map[ServerId, Server], nRequests: int, retryDuration: tTimerTicks)) {
            var req: tClientCommandRequest;
            var req2: tClientQueryRequest;
            var k: string;
            
            servers = payload.servers;
            nRequests = payload.nRequests;
            retryDuration = payload.retryDuration;
            timer = new ElectionTimer(this);
            counter = 0;
            clientKeys += (0, "a");
            clientKeys += (1, "b");
            clientKeys += (2, "c");
            
            while (nRequests > 0) {
                nRequests = nRequests - 1;
                
                req = (client = this, reqId = counter, command = (key = choose(clientKeys), value = choose(100)));
                counter = counter + 1;
                loopCommandRequest(req);
                
                
                foreach (k in clientKeys) {
                    req2 = (client = this, reqId = counter, query = (key = k,));
                    counter = counter + 1;
                    loopQueryRequest(req2);
                }
            }
        }
    }
    
    fun loopQueryRequest(req: tClientQueryRequest) {
        var s: Server;
        
        while (true) {
            foreach (s in values(servers)) {
                send s, eClientQueryRequest, req;
            }
            send timer, eStartTimer, retryDuration;
            
            while (true) {
                receive {
                    case eClientQueryResult : (res: tClientQueryResult) {
                        if (res.ok) {
                            send timer, eCancelTimer;
                            return;
                        }
                    }
                    case eElectionTimeOut : {
                        break;
                    }
                }
            }
        }
    }
    
    fun loopCommandRequest(req: tClientCommandRequest) {
        var s: Server;
        
        while (true) {
            foreach (s in values(servers)) {
                send s, eClientCommandRequest, req;
            }
            send timer, eStartTimer, retryDuration;
            
            while (true) {
                receive {
                    case eClientCommandResult : (res: tClientCommandResult) {
                        if (res.ok) {
                            send timer, eCancelTimer;
                            return;
                        }
                    }
                    case eElectionTimeOut : {
                        break;
                    }
                }
            }
        }
    }
}