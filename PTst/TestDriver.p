// fun SetUpRaft(
//     numServers: int,
//     numClients: int
// ) {
//     var servers: map[ServerId, machine];
//     var i: int;
    
//     i = 1;
//     while (i <= numServers) {
//         servers[i] = new Server();
//         i = i + 1;
//     }
    
//     foreach (i in keys(servers)) {
//         send servers[i], eServerInit, (peers = servers, id = i);
//     }
//     announce eSafetyMonitorInit, servers;
    
//     i = 0;
//     while (i < numClients) {
//         new Client(servers);
//         i = i + 1;
//     }
// }

// machine TestWithSingleClient {
//     start state Init {
//         entry {
//             SetUpRaft(5, 1);
//         }
//     }
// }

// machine TestWithMultipleClient {
//     start state Init {
//         entry {
//             SetUpRaft(5, 3);
//         }
//     }
// }