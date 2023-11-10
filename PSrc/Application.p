type Command = (key: string, value: int);
type State = map[string, int];

fun initialState(): State {
    return default(State);
}

fun apply(s: State, command: Command) {
    s[command.key] = command.value;
}

type Query = (key: string);
type QueryResult = (keyExists: bool, value: int);

fun query(s: State, q: Query): QueryResult {
    var value: int;
    if (q.key in s) {
        return (keyExists = true, value = s[q.key]);
    } else {
        return (keyExists = false, value = 0);
    }
}