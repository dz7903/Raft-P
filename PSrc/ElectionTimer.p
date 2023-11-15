type tTimerTicks = int;
event eStartTimer: tTimerTicks;
event eTick;
event eElectionTimeOut;
event eCancelTimer;

machine ElectionTimer {
    var timerTicks: int;
    var client: Server;

    start state Init {
        entry (clientInput: Server){
            client = clientInput;
            goto WaitForTimerRequests;
        }
    }

    state WaitForTimerRequests {
        on eStartTimer do (inputTimerTicks: tTimerTicks){
            timerTicks = inputTimerTicks;
            goto TimerStarted;
        }
        ignore eCancelTimer, eTick;
    }

    state TimerStarted{
        entry {
            if(timerTicks > 0){
                timerTicks = timerTicks - 1;
                send this, eTick;
            } else {
                send client, eElectionTimeOut;
                goto WaitForTimerRequests;
            }
        }
        
        on eTick goto TimerStarted;
        on eCancelTimer goto WaitForTimerRequests;
        ignore eStartTimer;
    }

}