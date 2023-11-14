test tcSingleClientSingleServer [main = TestSingleClientSingleServer]:
    assert SynchorizedSafety, SynchorizedLiveness in
    union { Server }, { Client }, { ElectionTimer }, { TestSingleClientSingleServer };

test tcSingleClientMultipleServers [main = TestSingleClientMultipleServers]:
    assert SynchorizedSafety, SynchorizedLiveness in
    union { Server }, { Client }, { ElectionTimer }, { TestSingleClientMultipleServers };
