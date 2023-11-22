module Raft = union { Server }, { Client }, { ElectionTimer }, { Wrapper };

test tcSingleClientSingleServer [main = TestSingleClientSingleServer]:
    assert SynchorizedSafety, SynchorizedLiveness in
    union Raft, { TestSingleClientSingleServer };

test tcSingleClientMultipleServers [main = TestSingleClientMultipleServers]:
    assert SynchorizedSafety, SynchorizedLiveness in
    union Raft, { TestSingleClientMultipleServers };

test tcSingleClientMultipleServersWithDelay [main = TestSingleClientMultipleServersWithDelay]:
    assert SynchorizedSafety in
    union Raft, { TestSingleClientMultipleServersWithDelay };

test tcSingleClientMultipleServersWithDrop [main = TestSingleClientMultipleServersWithDrop]:
    assert SynchorizedSafety in
    union Raft, { TestSingleClientMultipleServersWithDrop };