use tests::assert;
use cli::args::{Command, Matches, ArgError, command, error_message, exit_code, distance};

fn v(string... xs) -> Vec<string> {
    return xs;
}

fn app() -> Command {
    return command("tool", "Does things")
        .version("1.2.3")
        .flag("verbose", "v", "More output")
        .flag("quiet", "q", "Less output")
        .option("output", "o", "FILE", "Write to FILE")
        .option_default("level", "l", "N", "Level", "3")
        .multi("include", "I", "DIR", "Add a directory")
        .positional("input", "Input file")
        .rest("extra", "Extra files", false);
}

fn ok(Result<Matches, ArgError> r) -> Matches {
    return match r {
        Result::Ok(m) => m,
        Result::Err(e) => panic error_message(app(), e),
    };
}

fn err(Result<Matches, ArgError> r) -> ArgError {
    return match r {
        Result::Ok(_) => panic "expected an error",
        Result::Err(e) => e,
    };
}

test("flags, options, positionals") {
    let m = ok(app().parse(v("-v", "--output", "out.txt", "in.txt", "a", "b")));
    assert!(m.flag("verbose"));
    assert!(!m.flag("quiet"));
    assert!((m.value("output") ?? "") == "out.txt");
    assert!((m.value("input") ?? "") == "in.txt");
    assert!(m.values("extra").len() == 2);
    assert!(m.value_or("level", "") == "3");
}

test("inline values and bundles") {
    let m = ok(app().parse(v("-vvq", "-ofile", "--level=7", "-I", "x", "-Iy", "in")));
    assert!(m.count("verbose") == 2);
    assert!(m.flag("quiet"));
    assert!((m.value("output") ?? "") == "file");
    assert!(m.value_or("level", "") == "7");
    let inc = m.values("include");
    assert!(inc.len() == 2);
    assert!(inc[0] == "x");
    assert!(inc[1] == "y");
}

test("double dash ends options") {
    let m = ok(app().parse(v("in", "--", "-v", "--x")));
    assert!(!m.flag("verbose"));
    assert!(m.values("extra").len() == 2);
    assert!(m.values("extra")[0] == "-v");
}

test("errors") {
    assert!(
        match err(app().parse(v("--verbos", "in"))) {
            ArgError::UnknownOption(o, s) => o == "--verbos" && s == "verbose",
            default => false,
        },
    );
    assert!(
        match err(app().parse(v("in", "--output"))) {
            ArgError::MissingValue(n) => n == "output",
            default => false,
        },
    );
    assert!(
        match err(app().parse(v("-v"))) {
            ArgError::Missing(n) => n == "<input>",
            default => false,
        },
    );
    assert!(
        match err(app().parse(v("--verbose=yes", "in"))) {
            ArgError::FlagValue(n) => n == "verbose",
            default => false,
        },
    );
    assert!(exit_code(err(app().parse(v("-z", "in")))) == 2);
}

test("help and version") {
    let h = err(app().parse(v("--help")));
    assert!(exit_code(h) == 0);
    let text = error_message(app(), h);
    assert!(text.contains("Usage: tool [options] <input> [extra]..."));
    assert!(text.contains("-o, --output <FILE>"));
    assert!(text.contains("[default: 3]"));
    assert!(text.contains("-V, --version"));
    assert!(
        match err(app().parse(v("-V"))) {
            ArgError::Version(v) => v == "tool 1.2.3",
            default => false,
        },
    );
}

fn git() -> Command {
    return command("git", "")
        .flag("verbose", "v", "")
        .subcommand(
            command("commit", "Record changes")
                .option("message", "m", "MSG", "Message")
                .flag("all", "a", ""),
        )
        .subcommand(command("push", "Update remote").positional("remote", ""));
}

test("subcommands") {
    let m = match git().parse(v("-v", "commit", "-am", "fix")) {
        Result::Ok(m) => m,
        Result::Err(e) => panic error_message(git(), e),
    };
    assert!(m.flag("verbose"));
    assert!(m.subcommand_name() == "commit");
    let c = match m.subcommand() {
        Option::Some(s) => s,
        Option::None => panic "no subcommand",
    };
    assert!(c.flag("all"));
    assert!((c.value("message") ?? "") == "fix");
    assert!(
        match git().parse(v("comit")) {
            Result::Err(ArgError::UnknownCommand(v, s)) => v == "comit" && s == "commit",
            default => false,
        },
    );
    let h = match git().parse(v("push", "--help")) {
        Result::Err(ArgError::Help(t)) => t,
        default => "",
    };
    assert!(h.contains("Usage: git push [options] <remote>"));
}

test("edit distance") {
    assert!(distance("kitten", "sitting") == 3);
    assert!(distance("", "ab") == 2);
}
