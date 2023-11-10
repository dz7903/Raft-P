machine SynchorizedClient {
    var servers: map[ServerId, machine];
    var n: int;
    var counter: int;
    var clientKeys: seq[string];
    
    start state Init {
        entry (payload: (servers: map[ServerId, machine], n: int)) {
            servers = payload.servers;
            n = payload.n;
            clientKeys = default(seq[string]);
            clientKeys += (0, "a");
            clientKeys += (1, "b");
            clientKeys += (2, "c");
            goto MainLoop;
        }
    }
    
    state MainLoop {
        entry {
            var s: machine;
            var b: bool;
            var k: string;
            var req: tClientCommandRequest;
            var req2: tClientQueryRequest;
            req = (client = this, reqId = counter, command = (key = choose(clientKeys), value = choose(100)));
            counter = counter + 1;
            
            b = false;
            while (!b) {
                foreach (s in values(servers)) {
                    send s, eClientCommandRequest, req;
                    receive { 
                        case eClientCommandResult : (payload: tClientCommandResult) {
                            if (payload.ok) {
                                b = true;
                                break;
                            } else {
                                continue;
                            }
                        }
                    }
                }
            }
            
            foreach (s in values(servers)) {
                foreach (k in clientKeys) {
                    req2 = (client = this, reqId = counter, query = (key = k,));
                    counter = counter + 1;
                    send s, eClientQueryRequest, req2;
                    receive { 
                        case eClientQueryResult: (payload: tClientQueryResult) { continue; }
                    }
                }
            }
            
            n = n - 1;
            if (n > 0) {
                goto MainLoop;
            }
        }
    }
}

machine TestSynchorizedSingleSever {
    start state Init {
        entry {
            var server: machine;
            var servers: map[ServerId, machine];
            var client: machine;
            
            server = new Server();
            servers[1] = server;
            send server, eServerInit, (peers = servers, id = 1);
            announce eSafetyMonitorInit, servers;
            
            client = new SynchorizedClient((servers = servers, n = 10));
        }
    }
}