module Raft = union { Server }, { Client }, { ElectionTimer }, { Wrapper }, {PeriodicTimer};

test tcSingleClientSingleServer [main = TestSingleClientSingleServer]:
    assert SynchorizedSafety, LivenessMonitor in
    union Raft, { TestSingleClientSingleServer };

test tcSingleClientMultipleServers [main = TestSingleClientMultipleServers]:
    assert SynchorizedSafety, LivenessMonitor in
    union Raft, { TestSingleClientMultipleServers };

test tcSingleClientMultipleServersWithDelay [main = TestSingleClientMultipleServersWithDelay]:
    assert SynchorizedSafety in
    union Raft, { TestSingleClientMultipleServersWithDelay };

test tcSingleClientMultipleServersWithDrop [main = TestSingleClientMultipleServersWithDrop]:
    assert SynchorizedSafety in
    union Raft, { TestSingleClientMultipleServersWithDrop };

test tcMultipleClientsMultipleServers [main = TestMultipleClientsMultipleServers]:
    assert Safety, LivenessMonitor in
    union Raft, { TestMultipleClientsMultipleServers };