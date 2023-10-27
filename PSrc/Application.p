type Command = (key: string, value: int);
type State = map[string, int];

fun initialState(): State {
    return default(State);
}

fun applyCommand(s: State, command: Command) {
    s[command.key] = command.value;
}