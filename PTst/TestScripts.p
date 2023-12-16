module Raft = union { Server }, { Client }, { ElectionTimer }, { Wrapper };

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

test tcSingleClientMultipleServersUnreliable [main = TestSingleClientMultipleServersUnreliable]:
    assert SynchorizedSafety in
    union Raft, {TestSingleClientMultipleServersUnreliable};

test tcMultipleClientsMultipleServers [main = TestMultipleClientsMultipleServers]:
    assert Safety, Linearizability, LivenessMonitor in
    union Raft, { TestMultipleClientsMultipleServers };

test tcMultipleClientsMultipleServersUnreliable [main = TestMultipleClientsMultipleServersUnreliable]:
    assert Safety, Linearizability in
    union Raft, {TestMultipleClientsMultipleServersUnreliable};