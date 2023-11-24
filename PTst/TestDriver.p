fun SetUpRaft(
    numServers: int,
    numClients: int,
    numClientRequests: int,
    delayDuration: int,
    dropRandomly: bool
) {
    var servers: map[ServerId, Server];
    var wrappers: map[ServerId, Wrapper];
    var i: int;
    var j: int;
    
    i = 1;
    while (i <= numServers) {
        servers[i] = new Server();
        i = i + 1;
    }
    
    foreach (i in keys(servers)) {
        wrappers = default(map[ServerId, Wrapper]);
        foreach (j in keys(servers))
            if (j != i) {
                wrappers += (j, new Wrapper((
                    id = (i, j), server = servers[j], delayDuration = delayDuration, dropRandomly = dropRandomly)));
            }
        send servers[i], eServerInit, (peers = wrappers, id = i);
    }
    
    // foreach (i in keys(servers)) {
    //     send servers[i], eServerInit, (peers = servers, id = i);
    // }
    announce eSafetyMonitorInit, servers;
    
    i = 0;
    while (i < numClients) {
        new Client((servers = servers, nRequests = numClientRequests, retryDuration = 200));
        i = i + 1;
    }
}

machine TestSingleClientSingleServer {
    start state Init {
        entry {
            SetUpRaft(1, 1, 10, 0, false);
        }
    }
}

machine TestSingleClientMultipleServers {
    start state Init {
        entry {
            SetUpRaft(5, 1, 10, 0, false);
        }
    }
}

machine TestSingleClientMultipleServersWithDelay {
    start state Init {
        entry {
            // SetUpRaft(5, 1, 10, 300, false);
            SetUpRaft(5, 1, 10, 200, false);
        }
    }
}

machine TestSingleClientMultipleServersWithDrop {
    start state Init {
        entry {
            SetUpRaft(5, 1, 10, 0, true);
        }
    }
}

machine TestMultipleClientsMultipleServers {
    start state Init {
        entry {
            SetUpRaft(5, 5, 10, 0, false);
            // SetUpRaft(5, 3, 10, 0, false);
        }
    }
}