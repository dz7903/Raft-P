event eSafetyMonitorInit: map[int, Server];
event eSafetyBecomeLeader: (id: int, term: int);
event eSafetyLogChange: (id: int, isLeader: bool, leaderTerm: int, newLog: seq[LogEntry]);
event eSafetyLeaderCommitEntry: (logEntry: LogEntry);
event eSafetyApplyEntry: (id: int, index: int, logEntry: LogEntry);

spec Safety observes eSafetyMonitorInit, eSafetyBecomeLeader, eSafetyLogChange, eSafetyLeaderCommitEntry, eSafetyApplyEntry {
    var leaders: map[int, int]; // term -> leader id
    var logs: map[int, seq[LogEntry]]; // id -> log
    var allLogs: set[seq[LogEntry]];
    var commitedEntries: set[LogEntry];
    var appliedEntries: map[int, map[int, LogEntry]]; // id -> index -> entry
    
    start state Init {
        on eSafetyMonitorInit do (payload: map[int, Server]) {
            var k: int;
            foreach (k in keys(payload)) {
                logs += (k, default(seq[LogEntry]));
                appliedEntries += (k, default(map[int, LogEntry]));
            }
            allLogs += (default(seq[LogEntry]));
        }
        
        on eSafetyBecomeLeader do (payload: (id: int, term: int)) {
            if (payload.term in leaders) {
                assert (payload.id == leaders[payload.term]), format("Election Safety violated: term {0} has two leaders {1}, {2}", payload.term, leaders[payload.term], payload.id);
            }
            leaders += (payload.term, payload.id);
        }
        
        on eSafetyLogChange do (payload: (id: int, isLeader: bool, leaderTerm: int, newLog: seq[LogEntry])) {
            if (payload.isLeader) {
                checkAppendOnly(payload.id, logs[payload.id], payload.newLog);
            }
            logs[payload.id] = payload.newLog;
            
            if (!(payload.newLog in allLogs)) {
                checkLogMatching(payload.newLog);
                allLogs += (payload.newLog);
                checkLeaderCompleteness(payload.leaderTerm, payload.newLog);
            }
        }
        
        on eSafetyLeaderCommitEntry do (payload: (logEntry: LogEntry)) {
            commitedEntries += (payload.logEntry);
        }
        
        on eSafetyApplyEntry do (payload: (id: int, index: int, logEntry: LogEntry)) {
            var k: int;
            assert !(payload.index in appliedEntries[payload.id]), format("State Machine Safety violated: entry is already applied, id = {0}, index = {1}", payload.id, payload.index);
            foreach (k in keys(appliedEntries)) {
                if (payload.index in appliedEntries[k]) {
                    assert (payload.logEntry == appliedEntries[k][payload.index]), format("State Machine Safety violated: id = {0}, index = {1}, logEntry = {2}, but a different entry is applied at the same index, with id = {3}, logEntry = {4}", payload.id, payload.index, payload.logEntry, k, appliedEntries[k][payload.index]);
                }
            }
            appliedEntries[payload.id] += (payload.index, payload.logEntry);
        }
    }
        
    fun checkAppendOnly(id: int, oldLog: seq[LogEntry], newLog: seq[LogEntry]) {
        var i: int;
        
        assert (sizeof(oldLog) <= sizeof(newLog)), format("Leader Append Only violated: leader id = {0}, old log = {1}, new log = {2}", id, oldLog, newLog);
        i = 0;
        while (i < sizeof(oldLog)) {
            assert (oldLog[i] == newLog[i]), format("Leader Append Only violated: leader id = {0}, old log = {1}, new log = {2}", id, oldLog, newLog);
            i = i + 1;
        }
    }
    
    fun checkLogMatching(newLog: seq[LogEntry]) {
        var commonLen: int;
        var log: seq[LogEntry];
        var i: int;
        var j: int;
        
        foreach(log in allLogs) {
            commonLen = Min(sizeof(log), sizeof(newLog));
            i = commonLen - 1;
            while (i >= 0 && log[i] != newLog[i]) { i = i - 1; }
            if (i > 0) {
                j = i - 1;
                while (j >= 0) {
                    assert (log[j] == newLog[j]), format("Log Matching violated: old log = {0}, new log = {1}, they are identical at {2}, but different at {3}", log, newLog, i, j);
                    j = j - 1;
                }
            }
        }
    }
    
    fun checkLeaderCompleteness(term: int, log: seq[LogEntry]) {
        var logEntry: LogEntry;
        foreach (logEntry in commitedEntries) {
            if (logEntry.term < term) {
                assert (logEntry in log), format("Leader Completeness violated: committed entry = {0}, leader term = {1}, leader log = {2}", logEntry, term, log);
            }
        }
    }
}