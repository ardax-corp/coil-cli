// Arguments, colour and a progress bar.
//
//   coil --allow-env --allow-exit --root <stdlib>/src --root src examples/hello.hy -- --name Ada -n 3
use env::{args, exit};
use io::stdout;
use io::stderr;
use io::sync::write_all;
use string::{format, to_bytes};
use conv::parse_int;
use clock::sleep_ms;
use cli::args::Command;
use cli::args::command;
use cli::args::parse_args;
use cli::args::error_message;
use cli::args::Parsed;
use cli::style::Painter;
use cli::style::fg;
use cli::style::green;
use cli::progress::bar;
use cli::term::columns;
use cli::term::stderr_is_tty;
use cli::term::stdout_is_tty;

fn say(string s) {
    let _ = write_all(stdout(), to_bytes(s));
}

fn app() -> Command {
    return command("hello", "Greets someone, slowly.")
        .version("0.1.0")
        .option_default("name", "N", "NAME", "who to greet", "world")
        .option_default("times", "n", "COUNT", "how many greetings", "1")
        .flag("loud", "l", "shout");
}

fn main() {
    let argv = args().ok() ?? Vec::new();
    let rest: Vec<string> = Vec::new();
    let i = 1;
    while i < argv.len() {
        rest.push(argv[i]);
        i++;
    }
    let cmd = app();
    let m = match parse_args(cmd, rest) {
        Result::Ok(Parsed::Matches(m)) => m,
        Result::Ok(Parsed::Help(text)) => {
            say(text + "\n");
            exit(0);
            return;
        },
        Result::Ok(Parsed::Version(text)) => {
            say(text + "\n");
            exit(0);
            return;
        },
        Result::Err(e) => {
            let _ = write_all(stderr(), to_bytes(error_message(cmd, e) + "\n"));
            exit(2);
            return;
        },
    };
    let times = parse_int(m.value_or("times", "1")).ok() ?? 1;
    let p = Painter::from_env(stdout_is_tty());
    let b = bar(times, columns(), stderr_is_tty());
    b.set_label("greeting");
    let k = 0;
    while k < times {
        sleep_ms(200);
        b.inc(1);
        k++;
    }
    b.clear();
    let text = format("Hello, %s!", m.value_or("name", "world"));
    let style = fg(green());
    if m.flag("loud") {
        style = style.bold();
    }
    k = 0;
    while k < times {
        say(p.paint(style, text) + "\n");
        k++;
    }
}
