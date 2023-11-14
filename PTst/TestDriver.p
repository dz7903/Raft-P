fun SetUpRaft(
    numServers: int,
    numClients: int,
    numClientRequests: int
) {
    var servers: map[ServerId, Server];
    var i: int;
    
    i = 1;
    while (i <= numServers) {
        servers[i] = new Server();
        i = i + 1;
    }
    
    foreach (i in keys(servers)) {
        send servers[i], eServerInit, (peers = servers, id = i);
    }
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
            SetUpRaft(1, 1, 10);
        }
    }
}

machine TestSingleClientMultipleServers {
    start state Init {
        entry {
            SetUpRaft(5, 1, 10);
        }
    }
}