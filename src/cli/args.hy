// Declarative command-line parsing: flags, options, positionals,
// subcommands, `--`, bundled short flags, `--opt=value`, defaults, help
// and usage errors with suggestions.
use collections::map::HashMap;
use string::{format, to_bytes, slice_bytes};
use text::Searchable;
use cli::width::{pad_right, width};

const FLAG = 0;

const OPTION = 1;

const MULTI = 2;

const POSITIONAL = 3;

const REST = 4;

/// One declared argument.
class Arg {
    pub name: string,
    /// Short letter without `-`, or "".
    pub short: string,
    pub value_name: string,
    pub help: string,
    pub kind: int,
    pub default: string,
    pub has_default: bool,
    pub required: bool,
}

enum ArgError {
    /// `-h` / `--help`: the help text to print (exit 0).
    Help(string),
    /// `-V` / `--version`: the version line (exit 0).
    Version(string),
    /// An option nobody declared, with a suggestion or "".
    UnknownOption(string, string),
    /// An option that needs a value got none.
    MissingValue(string),
    /// A required argument was not given.
    Missing(string),
    /// A positional argument nobody asked for.
    Unexpected(string),
    /// A subcommand nobody declared, with a suggestion or "".
    UnknownCommand(string, string),
    /// A value was given to a flag (`--verbose=yes`).
    FlagValue(string),
}

/// The parse result for one command (and its chosen subcommand).
class Matches {
    pub command: string,
    counts: HashMap<string, int>,
    values: HashMap<string, Vec<string>>,
    pub sub_name: string,
    pub sub: Vec<Matches>,
}

impl Matches {
    /// Times a flag was given (0 when absent).
    pub fn count(string name) -> int {
        return self.counts.get_or(name, 0);
    }

    /// Whether a flag (or an option) was given.
    pub fn flag(string name) -> bool {
        return self.count(name) > 0;
    }

    /// Last value of an option or a positional, the default when not
    /// given, or `None`.
    pub fn value(string name) -> Option<string> {
        let vs = self.values.get_or(name, Vec::new());
        if vs.len() == 0 {
            return Option::None;
        }
        return Option::Some(vs[vs.len() - 1]);
    }

    pub fn value_or(string name, string fallback) -> string {
        return self.value(name) ?? fallback;
    }

    /// Every value of a repeatable option or a rest positional.
    pub fn values(string name) -> Vec<string> {
        return self.values.get_or(name, Vec::new());
    }

    /// The chosen subcommand's name, or "".
    pub fn subcommand_name() -> string {
        return self.sub_name;
    }

    /// The chosen subcommand's matches.
    pub fn subcommand() -> Option<Matches> {
        if self.sub.len() == 0 {
            return Option::None;
        }
        return Option::Some(self.sub[0]);
    }

    pub fn add_count(string name) {
        self.counts.insert(name, self.count(name) + 1);
    }

    pub fn add_value(string name, string v) {
        let vs = self.values.get_or(name, Vec::new());
        vs.push(v);
        self.values.insert(name, vs);
    }
}

fn new_matches(string command) -> Matches {
    return new Matches(command, HashMap::new(), HashMap::new(), "", Vec::new());
}

/// A command: its arguments, subcommands, and help text.
class Command {
    pub name: string,
    pub about: string,
    pub version: string,
    pub args: Vec<Arg>,
    pub commands: Vec<Command>,
    /// The program name shown in usage lines ("tool sub").
    pub path: string,
}

fn command(string name, string about) -> Command {
    return new Command(name, about, "", Vec::new(), Vec::new(), name);
}

fn new_arg(string name, string short, string value_name, string help, int kind) -> Arg {
    return new Arg(name, short, value_name, help, kind, "", false, false);
}

/// Levenshtein distance, for "did you mean".
fn distance(string a, string b) -> int {
    let x = to_bytes(a);
    let y = to_bytes(b);
    let prev: Vec<int> = Vec::new();
    let j = 0;
    while j <= y.len() {
        prev.push(j);
        j++;
    }
    let i = 1;
    while i <= x.len() {
        let cur: Vec<int> = Vec::new();
        cur.push(i);
        let k = 1;
        while k <= y.len() {
            let cost = 1;
            if x[i - 1] == y[k - 1] {
                cost = 0;
            }
            let best = prev[k] + 1;
            if cur[k - 1] + 1 < best {
                best = cur[k - 1] + 1;
            }
            if prev[k - 1] + cost < best {
                best = prev[k - 1] + cost;
            }
            cur.push(best);
            k++;
        }
        prev = cur;
        i++;
    }
    return prev[y.len()];
}

/// The closest of `names` to `word`, if close enough to suggest.
fn suggest(string word, Vec<string> names) -> string {
    let best = "";
    let best_d = 3;
    for n in names {
        let d = distance(word, n);
        if d < best_d {
            best = n;
            best_d = d;
        }
    }
    return best;
}

fn rest_of(string s, int from) -> string {
    return match slice_bytes(s, from, s.len()) {
        Result::Ok(t) => t,
        Result::Err(_) => "",
    };
}

fn first_char(string s) -> string {
    return match slice_bytes(s, 0, 1) {
        Result::Ok(t) => t,
        Result::Err(_) => "",
    };
}

fn arg_label(Arg a) -> string {
    if a.kind == POSITIONAL {
        if a.required {
            return "<" + a.name + ">";
        }
        return "[" + a.name + "]";
    }
    if a.kind == REST {
        if a.required {
            return "<" + a.name + ">...";
        }
        return "[" + a.name + "]...";
    }
    let s = "";
    if a.short != "" {
        s = "-" + a.short + ", ";
    } else {
        s = "    ";
    }
    s = s + "--" + a.name;
    if a.kind != FLAG {
        s = s + " <" + a.value_name + ">";
    }
    return s;
}

fn help_line(string label, string help, int col) -> string {
    if help == "" {
        return "  " + label + "\n";
    }
    if width(label) + 2 > col {
        return "  " + label + "\n" + pad_right("", col + 2) + help + "\n";
    }
    return "  " + pad_right(label, col) + help + "\n";
}

fn option_help(Arg a) -> string {
    let h = a.help;
    if a.has_default {
        h = h + " [default: " + a.default + "]";
    }
    if a.kind == MULTI {
        h = h + " (repeatable)";
    }
    return h;
}

impl Command {
    /// Enables `-V` / `--version`.
    pub fn version(string v) -> Command {
        self.version = v;
        return self;
    }

    fn add(Arg a) -> Command {
        self.args.push(a);
        return self;
    }

    /// A boolean flag (`--name`, `-s`), counted when repeated.
    pub fn flag(string name, string short, string help) -> Command {
        return self.add(new_arg(name, short, "", help, FLAG));
    }

    /// An option taking a value (`--name VALUE`, `--name=VALUE`, `-sVALUE`).
    pub fn option(string name, string short, string value_name, string help) -> Command {
        return self.add(new_arg(name, short, value_name, help, OPTION));
    }

    /// An option with a default value.
    pub fn option_default(
        string name,
        string short,
        string value_name,
        string help,
        string default,
    ) -> Command {
        let a = new_arg(name, short, value_name, help, OPTION);
        a.default = default;
        a.has_default = true;
        return self.add(a);
    }

    /// An option that must be given.
    pub fn required_option(string name, string short, string value_name, string help) -> Command {
        let a = new_arg(name, short, value_name, help, OPTION);
        a.required = true;
        return self.add(a);
    }

    /// A repeatable option; `Matches.values` has every value.
    pub fn multi(string name, string short, string value_name, string help) -> Command {
        return self.add(new_arg(name, short, value_name, help, MULTI));
    }

    /// A required positional argument, filled in declaration order.
    pub fn positional(string name, string help) -> Command {
        let a = new_arg(name, "", name, help, POSITIONAL);
        a.required = true;
        return self.add(a);
    }

    pub fn optional_positional(string name, string help) -> Command {
        return self.add(new_arg(name, "", name, help, POSITIONAL));
    }

    /// Every remaining positional (and everything after `--`).
    pub fn rest(string name, string help, bool required) -> Command {
        let a = new_arg(name, "", name, help, REST);
        a.required = required;
        return self.add(a);
    }

    /// A subcommand; its usage lines show this command's name first.
    pub fn subcommand(Command c) -> Command {
        c.path = self.path + " " + c.name;
        self.commands.push(c);
        return self;
    }

    pub fn find_long(string name) -> Option<Arg> {
        for a in self.args {
            if a.kind <= MULTI && a.name == name {
                return Option::Some(a);
            }
        }
        return Option::None;
    }

    pub fn find_short(string s) -> Option<Arg> {
        for a in self.args {
            if a.kind <= MULTI && a.short == s {
                return Option::Some(a);
            }
        }
        return Option::None;
    }

    pub fn long_names() -> Vec<string> {
        let out: Vec<string> = Vec::new();
        for a in self.args {
            if a.kind <= MULTI {
                out.push(a.name);
            }
        }
        out.push("help");
        if self.version != "" {
            out.push("version");
        }
        return out;
    }

    pub fn command_names() -> Vec<string> {
        let out: Vec<string> = Vec::new();
        for c in self.commands {
            out.push(c.name);
        }
        return out;
    }

    pub fn has_options() -> bool {
        for a in self.args {
            if a.kind <= MULTI {
                return true;
            }
        }
        return false;
    }

    /// One-line usage: `tool [options] <input> [files]...`.
    pub fn usage() -> string {
        let s = "Usage: " + self.path;
        s = s + " [options]";
        for a in self.args {
            if a.kind == OPTION && a.required {
                s = s + " --" + a.name + " <" + a.value_name + ">";
            }
        }
        if self.commands.len() > 0 {
            s = s + " <command>";
        }
        for a in self.args {
            if a.kind >= POSITIONAL {
                s = s + " " + arg_label(a);
            }
        }
        return s;
    }

    /// Full help text.
    pub fn help() -> string {
        let out = "";
        if self.about != "" {
            out = self.about + "\n\n";
        }
        out = out + self.usage() + "\n";
        let col = 24;
        let pos = "";
        for a in self.args {
            if a.kind >= POSITIONAL {
                pos = pos + help_line(arg_label(a), a.help, col);
            }
        }
        if pos != "" {
            out = out + "\nArguments:\n" + pos;
        }
        if self.commands.len() > 0 {
            out = out + "\nCommands:\n";
            for c in self.commands {
                out = out + help_line(c.name, c.about, col);
            }
        }
        out = out + "\nOptions:\n";
        for a in self.args {
            if a.kind <= MULTI {
                out = out + help_line(arg_label(a), option_help(a), col);
            }
        }
        out = out + help_line("-h, --help", "Print help", col);
        if self.version != "" {
            out = out + help_line("-V, --version", "Print version", col);
        }
        return out;
    }

    pub fn take_option(
        Arg a,
        Matches m,
        Vec<string> argv,
        int i,
        string inline,
        bool has_inline,
    ) -> Result<int, ArgError> {
        if a.kind == FLAG {
            if has_inline {
                raise ArgError::FlagValue(a.name);
            }
            m.add_count(a.name);
            return i + 1;
        }
        if has_inline {
            m.add_value(a.name, inline);
            m.add_count(a.name);
            return i + 1;
        }
        if i + 1 >= argv.len() {
            raise ArgError::MissingValue(a.name);
        }
        m.add_value(a.name, argv[i + 1]);
        m.add_count(a.name);
        return i + 2;
    }

    pub fn accepts_positionals() -> bool {
        for a in self.args {
            if a.kind >= POSITIONAL {
                return true;
            }
        }
        return false;
    }

    pub fn fill_positionals(Matches m, Vec<string> positionals) -> Result<(), ArgError> {
        let k = 0;
        for a in self.args {
            if a.kind == POSITIONAL {
                if k < positionals.len() {
                    m.add_value(a.name, positionals[k]);
                    k++;
                } else if a.required {
                    raise ArgError::Missing(arg_label(a));
                }
            }
            if a.kind == REST {
                let n = 0;
                while k < positionals.len() {
                    m.add_value(a.name, positionals[k]);
                    k++;
                    n++;
                }
                if n == 0 && a.required {
                    raise ArgError::Missing(arg_label(a));
                }
            }
        }
        if k < positionals.len() {
            if self.commands.len() > 0 && !self.accepts_positionals() {
                raise ArgError::UnknownCommand(
                    positionals[k],
                    suggest(positionals[k], self.command_names()),
                );
            }
            raise ArgError::Unexpected(positionals[k]);
        }
        return;
    }

    pub fn finish(Matches m) -> Result<(), ArgError> {
        for a in self.args {
            if a.kind == OPTION && m.count(a.name) == 0 {
                if a.required {
                    raise ArgError::Missing("--" + a.name);
                }
                if a.has_default {
                    m.add_value(a.name, a.default);
                }
            }
        }
        return;
    }
}

// A free function: a method calling itself on another `Command` sees its
// return type unqualified (coil-lang#1980).
fn parse_args(Command cmd, Vec<string> argv) -> Result<Matches, ArgError> {
    let m = new_matches(cmd.name);
    let positionals: Vec<string> = Vec::new();
    let only_positional = false;
    let i = 0;
    while i < argv.len() {
        let a = argv[i];
        if only_positional || a == "-" || !a.starts_with("-") {
            if !only_positional && cmd.commands.len() > 0 && positionals.len() == 0 {
                let found = false;
                for c in cmd.commands {
                    if c.name == a {
                        found = true;
                        let rest: Vec<string> = Vec::new();
                        let k = i + 1;
                        while k < argv.len() {
                            rest.push(argv[k]);
                            k++;
                        }
                        let sm = parse_args(c, rest)?;
                        m.sub_name = c.name;
                        m.sub.push(sm);
                    }
                }
                if found {
                    i = argv.len();
                    break;
                }
                if !cmd.accepts_positionals() {
                    raise ArgError::UnknownCommand(a, suggest(a, cmd.command_names()));
                }
            }
            positionals.push(a);
            i++;
            continue;
        }
        if a == "--" {
            only_positional = true;
            i++;
            continue;
        }
        if a.starts_with("--") {
            let body = rest_of(a, 2);
            let name = body;
            let inline = "";
            let has_inline = false;
            match body.find("=") {
                Option::Some(sp) => {
                    name = match slice_bytes(body, 0, sp.start) {
                        Result::Ok(t) => t,
                        Result::Err(_) => body,
                    };
                    inline = rest_of(body, sp.start + 1);
                    has_inline = true;
                },
                Option::None => {},
            }
            if name == "help" {
                raise ArgError::Help(cmd.help());
            }
            if name == "version" && cmd.version != "" {
                raise ArgError::Version(cmd.name + " " + cmd.version);
            }
            let spec = match cmd.find_long(name) {
                Option::Some(s) => s,
                Option::None => raise ArgError::UnknownOption(
                    "--" + name,
                    suggest(name, cmd.long_names()),
                ),
            };
            i = cmd.take_option(spec, m, argv, i, inline, has_inline)?;
            continue;
        }
        // Short flags, possibly bundled: -abc, -ovalue, -o value.
        let j = 1;
        let advanced = false;
        while j < a.len() {
            let s = match slice_bytes(a, j, j + 1) {
                Result::Ok(t) => t,
                Result::Err(_) => "",
            };
            if s == "h" {
                raise ArgError::Help(cmd.help());
            }
            if s == "V" && cmd.version != "" {
                raise ArgError::Version(cmd.name + " " + cmd.version);
            }
            let spec = match cmd.find_short(s) {
                Option::Some(sp) => sp,
                Option::None => raise ArgError::UnknownOption("-" + s, ""),
            };
            if spec.kind == FLAG {
                m.add_count(spec.name);
                j++;
                continue;
            }
            if j + 1 < a.len() {
                i = cmd.take_option(spec, m, argv, i, rest_of(a, j + 1), true)?;
            } else {
                i = cmd.take_option(spec, m, argv, i, "", false)?;
            }
            advanced = true;
            break;
        }
        if !advanced {
            i++;
        }
    }
    cmd.fill_positionals(m, positionals)?;
    cmd.finish(m)?;
    return m;
}

impl Command {
    /// Parse `argv` (without the program name).
    pub fn parse(Vec<string> argv) -> Result<Matches, ArgError> {
        return parse_args(self, argv)?;
    }
}

/// Text for an error, with the usage line and a pointer to `--help`.
fn error_message(Command c, ArgError e) -> string {
    let msg = match e {
        ArgError::Help(t) => t,
        ArgError::Version(t) => t,
        ArgError::UnknownOption(o, s) => {
            if s != "" {
                return format(
                    "error: unexpected option '%s' (did you mean '--%s'?)\n\n%s\n\nFor more information, try '--help'.",
                    o,
                    s,
                    c.usage(),
                );
            }
            return format(
                "error: unexpected option '%s'\n\n%s\n\nFor more information, try '--help'.",
                o,
                c.usage(),
            );
        },
        ArgError::MissingValue(n) => format("error: '--%s' needs a value", n),
        ArgError::Missing(n) => format("error: missing required argument %s", n),
        ArgError::Unexpected(v) => format("error: unexpected argument '%s'", v),
        ArgError::UnknownCommand(v, s) => {
            if s != "" {
                return format(
                    "error: unknown command '%s' (did you mean '%s'?)\n\n%s\n\nFor more information, try '--help'.",
                    v,
                    s,
                    c.usage(),
                );
            }
            return format(
                "error: unknown command '%s'\n\n%s\n\nFor more information, try '--help'.",
                v,
                c.usage(),
            );
        },
        ArgError::FlagValue(n) => format("error: '--%s' takes no value", n),
    };
    return match e {
        ArgError::Help(_) => msg,
        ArgError::Version(_) => msg,
        default => msg + "\n\n" + c.usage() + "\n\nFor more information, try '--help'.",
    };
}

/// Exit status for an error: 0 for help/version, 2 for usage errors.
fn exit_code(ArgError e) -> int {
    return match e {
        ArgError::Help(_) => 0,
        ArgError::Version(_) => 0,
        default => 2,
    };
}
