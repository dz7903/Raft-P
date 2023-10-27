machine Client {
    var servers: map[ServerId, machine];
    
    start state Init {
        entry (payload: map[ServerId, machine]) {
            servers = payload;
        }
    }
}