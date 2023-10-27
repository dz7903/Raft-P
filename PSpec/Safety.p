event eSafetyMonitorInit: map[ServerId, machine];

spec Safety observes eSafetyMonitorInit {
    start state Init {}
}