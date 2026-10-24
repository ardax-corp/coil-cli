// Prompts and a small REPL. Pipe answers in to see the line fallbacks:
//
//   coil --root <stdlib>/src --root src examples/ask.hy
//   printf 'y\nAda\n2\n1 3\nquit\n' | coil ... examples/ask.hy
use io::stdout;
use io::sync::write_all;
use string::{format, to_bytes};
use cli::prompt::confirm;
use cli::prompt::input;
use cli::prompt::select;
use cli::prompt::multi_select;
use cli::line::LineInput;
use cli::line::editor;
use cli::line::history;
use cli::line::read_line;

fn say(string s) {
    let _ = write_all(stdout(), to_bytes(s));
}

fn strs(string... xs) -> Vec<string> {
    return xs;
}

fn main() {
    let go = confirm("Start the survey?", true) ?? Option::None;
    if !(go ?? false) {
        say("Maybe later.\n");
        return;
    }
    let name = (input("Your name?", "anonymous") ?? Option::None) ?? "anonymous";
    let langs = strs("Coil", "Rust", "Zig", "Go", "OCaml");
    let fav = (select("Favourite language?", langs) ?? Option::None) ?? 0;
    let tools = strs("editor", "debugger", "profiler", "formatter");
    let used = (multi_select("Which tools do you use?", tools) ?? Option::None) ?? Vec::new();
    say(format("%s likes %s and uses %i tool(s).\n", name, langs[fav], used.len()));

    say("Type lines to echo; `quit` or Ctrl-D ends.\n");
    let ed = editor(history(50));
    while true {
        let got = read_line(ed, "echo> ") ?? LineInput::Eof;
        match got {
            LineInput::Line(l) => {
                if l == "quit" {
                    return;
                }
                say(l + "\n");
            },
            LineInput::Cancelled => {},
            LineInput::Eof => {
                return;
            },
        }
    }
}
