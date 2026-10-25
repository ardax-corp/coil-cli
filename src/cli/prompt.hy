// Prompts: confirm, input, password, and single / multi select.
// The models are terminal-free (`Select` + `SelectKey`, answer parsers);
// the `*_line` runners read whole lines from a stream, which works on
// pipes and scripts; `confirm`, `input`, `password`, `select` and
// `multi_select` run in raw mode on a terminal and fall back to the line
// runners when stdin is not one.
use io::Stream;
use io::sync::write_all;
use io::sync::read_line;
use string::{format, to_bytes, slice_bytes};
use conv::parse_int;
use text::Text;
use cli::width::truncate;
use cli::width::width;
use cli::keys::Event;
use cli::keys::is_key;
use cli::line::LineInput;
use cli::line::editor;
use cli::line::history;
use cli::line::read_line_masked;
use cli::term::raw_mode;
use cli::term::put;
use cli::term::size_or;
use cli::events::events;
use cli::ansi::clear_below;
use cli::ansi::hide_cursor;
use cli::ansi::show_cursor;
use cli::ansi::up;
use io::IoError;
use io::stdin;
use io::stdout;
use io::tty::is_tty;
use cli::keys::{KeyEvent, describe_key, cp_string};

/// `y`/`yes`/`n`/`no` (any case); an empty answer is `fallback`; anything
/// else is `None` (ask again).
fn parse_confirm(string answer, bool fallback) -> Option<bool> {
    let a = answer.trim().to_lower();
    if a == "" {
        return Option::Some(fallback);
    }
    if a == "y" || a == "yes" {
        return Option::Some(true);
    }
    if a == "n" || a == "no" {
        return Option::Some(false);
    }
    return Option::None;
}

/// `question [Y/n] ` or `question [y/N] `.
fn confirm_label(string question, bool fallback) -> string {
    if fallback {
        return question + " [Y/n] ";
    }
    return question + " [y/N] ";
}

/// Case-insensitive subsequence match: "cmt" matches "commit".
fn fuzzy_match(string pattern, string text) -> bool {
    let p = to_bytes(pattern.to_lower());
    let t = to_bytes(text.to_lower());
    let i = 0;
    for c in t {
        if i < p.len() && p[i] == c {
            i++;
        }
    }
    return i == p.len();
}

enum SelectKey {
    Up,
    Down,
    PageUp,
    PageDown,
    Home,
    End,
    /// Toggle the item under the cursor (multi-select).
    Toggle,
    ToggleAll,
    /// Type into the filter.
    FilterChar(string),
    FilterBackspace,
    Submit,
    Cancel,
}

#[repr(int)]
#[derive(Eq)]
enum SelectOutcome {
    Continue = 0,
    Submit = 1,
    Cancel = 2,
}

/// A scrolling, filterable list. `cursor` and `offset` index the
/// filtered list (`visible`).
class Select {
    pub items: Vec<string>,
    pub multi: bool,
    pub checked: Vec<bool>,
    pub filter: string,
    pub visible: Vec<int>,
    pub cursor: int,
    pub offset: int,
    /// Rows the list may use.
    pub height: int,
}

fn select_model(Vec<string> items, bool multi, int height) -> Select {
    let checked: Vec<bool> = Vec::new();
    let visible: Vec<int> = Vec::new();
    let i = 0;
    while i < items.len() {
        checked.push(false);
        visible.push(i);
        i++;
    }
    let h = height;
    if h < 1 {
        h = 1;
    }
    return new Select(items, multi, checked, "", visible, 0, 0, h);
}

impl Select {
    fn refilter() {
        let v: Vec<int> = Vec::new();
        let i = 0;
        while i < self.items.len() {
            if self.filter == "" || fuzzy_match(self.filter, self.items[i]) {
                v.push(i);
            }
            i++;
        }
        self.visible = v;
        self.cursor = 0;
        self.offset = 0;
    }

    fn clamp() {
        let n = self.visible.len();
        if self.cursor >= n {
            self.cursor = n - 1;
        }
        if self.cursor < 0 {
            self.cursor = 0;
        }
        if self.cursor < self.offset {
            self.offset = self.cursor;
        }
        if self.cursor >= self.offset + self.height {
            self.offset = self.cursor - self.height + 1;
        }
    }

    /// Index into `items` under the cursor, or -1 when the filter hides
    /// everything.
    pub fn current() -> int {
        if self.visible.len() == 0 {
            return -1;
        }
        return self.visible[self.cursor];
    }

    /// Indices of the checked items (multi) or the current one (single).
    pub fn chosen() -> Vec<int> {
        let out: Vec<int> = Vec::new();
        if !self.multi {
            let c = self.current();
            if c >= 0 {
                out.push(c);
            }
            return out;
        }
        let i = 0;
        while i < self.items.len() {
            if self.checked[i] {
                out.push(i);
            }
            i++;
        }
        return out;
    }

    pub fn apply(SelectKey k) -> SelectOutcome {
        let n = self.visible.len();
        match k {
            SelectKey::Up => {
                if self.cursor > 0 {
                    self.cursor--;
                } else if n > 0 {
                    self.cursor = n - 1;
                }
            },
            SelectKey::Down => {
                if self.cursor + 1 < n {
                    self.cursor++;
                } else {
                    self.cursor = 0;
                }
            },
            SelectKey::PageUp => {
                self.cursor = self.cursor - self.height;
            },
            SelectKey::PageDown => {
                self.cursor = self.cursor + self.height;
            },
            SelectKey::Home => {
                self.cursor = 0;
            },
            SelectKey::End => {
                self.cursor = n - 1;
            },
            SelectKey::Toggle => {
                let c = self.current();
                if self.multi && c >= 0 {
                    self.checked[c] = !self.checked[c];
                }
            },
            SelectKey::ToggleAll => {
                if self.multi {
                    let all = true;
                    for i in self.visible {
                        if !self.checked[i] {
                            all = false;
                        }
                    }
                    for i in self.visible {
                        self.checked[i] = !all;
                    }
                }
            },
            SelectKey::FilterChar(s) => {
                self.filter = self.filter + s;
                self.refilter();
            },
            SelectKey::FilterBackspace => {
                let b = to_bytes(self.filter);
                if b.len() > 0 {
                    let cut = b.len() - 1;
                    while cut > 0 && ((b[cut] as int) & 192) == 128 {
                        cut--;
                    }
                    self.filter = slice_bytes(self.filter, 0, cut).ok() ?? "";
                    self.refilter();
                }
            },
            SelectKey::Submit => {
                if self.multi || self.current() >= 0 {
                    return SelectOutcome::Submit;
                }
            },
            SelectKey::Cancel => {
                return SelectOutcome::Cancel;
            },
        }
        self.clamp();
        return SelectOutcome::Continue;
    }

    /// The list rows to draw, each at most `cols` columns: a `❯` marker on
    /// the cursor row and `◉`/`○` boxes for multi-select.
    pub fn lines(int cols) -> Vec<string> {
        let out: Vec<string> = Vec::new();
        let r = self.offset;
        while r < self.visible.len() && r < self.offset + self.height {
            let idx = self.visible[r];
            let mark = "  ";
            if r == self.cursor {
                mark = "❯ ";
            }
            let box = "";
            if self.multi {
                if self.checked[idx] {
                    box = "◉ ";
                } else {
                    box = "○ ";
                }
            }
            out.push(truncate(mark + box + self.items[idx], cols, "…"));
            r++;
        }
        return out;
    }
}

fn say(Stream out, string s) -> bool {
    return match write_all(out, to_bytes(s)) {
        Result::Ok(_) => true,
        Result::Err(_) => false,
    };
}

/// Ask `question` on `out`, reading answers from `input` until one parses.
/// End of input gives `fallback`.
fn confirm_line(Stream input, Stream out, string question, bool fallback) -> bool {
    while true {
        say(out, confirm_label(question, fallback));
        let line = match read_line(input) {
            Result::Ok(Option::Some(l)) => l,
            default => {
                say(out, "\n");
                return fallback;
            },
        };
        match parse_confirm(line, fallback) {
            Option::Some(v) => {
                return v;
            },
            Option::None => {
                say(out, "Please answer y or n.\n");
            },
        }
    }
}

/// Ask for a line; an empty answer is `fallback`. `None` at end of input.
fn input_line(Stream input, Stream out, string question, string fallback) -> Option<string> {
    let label = question + " ";
    if fallback != "" {
        label = question + " (" + fallback + ") ";
    }
    say(out, label);
    return match read_line(input) {
        Result::Ok(Option::Some(l)) => {
            if l == "" {
                return Option::Some(fallback);
            }
            return Option::Some(l);
        },
        default => Option::None,
    };
}

/// Pick one of `items` by number. `None` at end of input.
fn select_line(Stream input, Stream out, string question, Vec<string> items) -> Option<int> {
    say(out, question + "\n");
    let i = 0;
    while i < items.len() {
        say(out, format("  %i) %s\n", i + 1, items[i]));
        i++;
    }
    while true {
        say(out, format("Choose 1-%i: ", items.len()));
        let line = match read_line(input) {
            Result::Ok(Option::Some(l)) => l,
            default => {
                return Option::None;
            },
        };
        let n = parse_int(line.trim()).ok() ?? 0;
        if n >= 1 && n <= items.len() {
            return Option::Some(n - 1);
        }
    }
}

/// The default binding for an input event in a `Select`: arrows, j/k
/// style Ctrl-N/P, space toggles, Ctrl-A toggles all, typing filters.
fn select_key_for(Event e) -> Option<SelectKey> {
    return match e {
        Event::Paste(t) => Option::Some(SelectKey::FilterChar(t)),
        Event::Key(k) => select_key_for_key(k),
        default => Option::None,
    };
}

fn select_key_for_key(KeyEvent k) -> Option<SelectKey> {
    let spec = describe_key(k);
    if spec == "space" {
        return Option::Some(SelectKey::Toggle);
    }
    match k.char() {
        Option::Some(c) => {
            return Option::Some(SelectKey::FilterChar(cp_string(c)));
        },
        Option::None => {},
    }
    if spec == "up" || spec == "ctrl+p" || spec == "shift+backtab" {
        return Option::Some(SelectKey::Up);
    }
    if spec == "down" || spec == "ctrl+n" || spec == "tab" {
        return Option::Some(SelectKey::Down);
    }
    if spec == "pageup" {
        return Option::Some(SelectKey::PageUp);
    }
    if spec == "pagedown" {
        return Option::Some(SelectKey::PageDown);
    }
    if spec == "home" {
        return Option::Some(SelectKey::Home);
    }
    if spec == "end" {
        return Option::Some(SelectKey::End);
    }
    if spec == "ctrl+a" {
        return Option::Some(SelectKey::ToggleAll);
    }
    if spec == "backspace" || spec == "ctrl+h" {
        return Option::Some(SelectKey::FilterBackspace);
    }
    if spec == "enter" {
        return Option::Some(SelectKey::Submit);
    }
    if spec == "esc" || spec == "ctrl+c" {
        return Option::Some(SelectKey::Cancel);
    }
    return Option::None;
}

/// Ask a yes/no question. On a terminal one key answers (y / n, Enter for
/// `fallback`); otherwise a line is read. `None` when cancelled (Ctrl-C,
/// Esc) or at end of input.
fn confirm(string question, bool fallback) -> Result<Option<bool>, IoError> {
    if !is_tty(stdin()) {
        return Option::Some(confirm_line(stdin(), stdout(), question, fallback));
    }
    let out = stdout();
    let raw = raw_mode(stdin())?;
    let r = confirm_keys(out, question, fallback);
    raw.leave()?;
    return r?;
}

fn confirm_keys(Stream out, string question, bool fallback) -> Result<Option<bool>, IoError> {
    put(out, confirm_label(question, fallback))?;
    let ev = events();
    while true {
        let got = ev.next(-1)?;
        match got {
            Option::None => {
                if ev.eof {
                    put(out, "\r\n")?;
                    return Option::None;
                }
            },
            Option::Some(e) => {
                if is_key(e, "y") || is_key(e, "shift+y") || is_key(e, "Y") {
                    put(out, "yes\r\n")?;
                    return Option::Some(true);
                }
                if is_key(e, "n") || is_key(e, "shift+n") || is_key(e, "N") {
                    put(out, "no\r\n")?;
                    return Option::Some(false);
                }
                if is_key(e, "enter") {
                    if fallback {
                        put(out, "yes\r\n")?;
                    } else {
                        put(out, "no\r\n")?;
                    }
                    return Option::Some(fallback);
                }
                if is_key(e, "ctrl+c") || is_key(e, "esc") || is_key(e, "ctrl+d") {
                    put(out, "^C\r\n")?;
                    return Option::None;
                }
            },
        }
    }
}

fn ask(string question, string fallback, string mask) -> Result<Option<string>, IoError> {
    let label = question + " ";
    if fallback != "" && mask == "" {
        label = question + " (" + fallback + ") ";
    }
    let got = read_line_masked(editor(history(0)), label, mask)?;
    return match got {
        LineInput::Line(l) => {
            if l == "" {
                return Option::Some(fallback);
            }
            return Option::Some(l);
        },
        default => Option::None,
    };
}

/// Ask for a line, edited in place on a terminal; an empty answer is
/// `fallback`. `None` when cancelled or at end of input.
fn input(string question, string fallback) -> Result<Option<string>, IoError> {
    return ask(question, fallback, "")?;
}

/// Ask for a secret; each character shows as `*`. `None` when cancelled
/// or at end of input.
fn password(string question) -> Result<Option<string>, IoError> {
    return ask(question, "", "*")?;
}

/// Lines for the whole select block: the question (with the filter) and
/// the list, or a note when the filter hides everything.
fn select_block(string question, Select s, int cols) -> Vec<string> {
    let out: Vec<string> = Vec::new();
    let head = question;
    if s.filter != "" {
        head = question + "  " + s.filter;
    }
    out.push(truncate(head, cols, "…"));
    let rows = s.lines(cols);
    if rows.len() == 0 {
        out.push("  (no matches)");
    }
    for r in rows {
        out.push(r);
    }
    return out;
}

fn draw_block(Stream out, Vec<string> lines, int drawn) -> Result<int, IoError> {
    let s = "\r";
    if drawn > 1 {
        s = s + up(drawn - 1);
    }
    s = s + clear_below();
    let i = 0;
    while i < lines.len() {
        if i > 0 {
            s = s + "\r\n";
        }
        s = s + lines[i];
        i++;
    }
    put(out, s)?;
    return lines.len();
}

fn run_select(Stream out, string question, Select s) -> Result<bool, IoError> {
    let sz = size_or(out, 80, 24);
    let (cols, rows) = sz;
    if s.height > rows - 2 {
        s.height = rows - 2;
    }
    if s.height < 1 {
        s.height = 1;
    }
    put(out, hide_cursor())?;
    let drawn = draw_block(out, select_block(question, s, cols - 1), 0)?;
    let ev = events();
    let done = false;
    let ok = false;
    while !done {
        let got = ev.next(-1)?;
        match got {
            Option::None => {
                if ev.eof {
                    done = true;
                }
            },
            Option::Some(Event::Resize(c, _)) => {
                cols = c;
            },
            Option::Some(e) => {
                match select_key_for(e) {
                    Option::Some(k) => {
                        let o = s.apply(k);
                        if o == SelectOutcome::Submit {
                            done = true;
                            ok = true;
                        } else if o == SelectOutcome::Cancel {
                            done = true;
                        }
                    },
                    Option::None => {},
                }
            },
        }
        if !done {
            drawn = draw_block(out, select_block(question, s, cols - 1), drawn)?;
        }
    }
    let summary = question + " ";
    if ok {
        let names = "";
        for i in s.chosen() {
            if names != "" {
                names = names + ", ";
            }
            names = names + s.items[i];
        }
        summary = summary + names;
    } else {
        summary = summary + "^C";
    }
    draw_block(out, strs1(truncate(summary, cols - 1, "…")), drawn)?;
    put(out, "\r\n" + show_cursor())?;
    return ok;
}

fn strs1(string x) -> Vec<string> {
    let v: Vec<string> = Vec::new();
    v.push(x);
    return v;
}

fn select_raw(string question, Select s) -> Result<bool, IoError> {
    let out = stdout();
    let raw = raw_mode(stdin())?;
    let r = run_select(out, question, s);
    if !r.is_ok() {
        let _ = put(out, show_cursor());
    }
    raw.leave()?;
    return r?;
}

/// Pick one of `items` with the arrow keys (type to filter). Falls back
/// to a numbered list when stdin is not a terminal. `None` when
/// cancelled or at end of input.
fn select(string question, Vec<string> items) -> Result<Option<int>, IoError> {
    if items.len() == 0 {
        return Option::None;
    }
    if !is_tty(stdin()) {
        return select_line(stdin(), stdout(), question, items);
    }
    let s = select_model(items, false, 10);
    if !select_raw(question, s)? {
        return Option::None;
    }
    return Option::Some(s.current());
}

/// Pick any of `items` (space toggles, Ctrl-A toggles all, Enter
/// accepts). Off a terminal, a line of numbers separated by spaces or
/// commas is read. `None` when cancelled or at end of input.
fn multi_select(string question, Vec<string> items) -> Result<Option<Vec<int>>, IoError> {
    if !is_tty(stdin()) {
        return multi_select_line(stdin(), stdout(), question, items);
    }
    let s = select_model(items, true, 10);
    if !select_raw(question, s)? {
        return Option::None;
    }
    return Option::Some(s.chosen());
}

/// Parse `1 3,4` into 0-based indices below `n`; `None` if any part is
/// not a number in 1..=n.
fn parse_choices(string answer, int n) -> Option<Vec<int>> {
    let out: Vec<int> = Vec::new();
    let cur = 0;
    let digits = 0;
    for b in to_bytes(answer + " ") {
        let c = b as int;
        if c >= 48 && c <= 57 {
            cur = cur * 10 + (c - 48);
            digits++;
        } else if c == 32 || c == 44 || c == 9 {
            if digits > 0 {
                if cur < 1 || cur > n {
                    return Option::None;
                }
                out.push(cur - 1);
                cur = 0;
                digits = 0;
            }
        } else {
            return Option::None;
        }
    }
    return Option::Some(out);
}

/// Pick several of `items` by number from a stream.
fn multi_select_line(
    Stream input,
    Stream out,
    string question,
    Vec<string> items,
) -> Result<Option<Vec<int>>, IoError> {
    say(out, question + "\n");
    let i = 0;
    while i < items.len() {
        say(out, format("  %i) %s\n", i + 1, items[i]));
        i++;
    }
    while true {
        say(out, format("Choose from 1-%i (space separated): ", items.len()));
        let got = read_line(input)?;
        match got {
            Option::None => {
                return Option::None;
            },
            Option::Some(l) => {
                match parse_choices(l, items.len()) {
                    Option::Some(v) => {
                        return Option::Some(v);
                    },
                    Option::None => {},
                }
            },
        }
    }
}
