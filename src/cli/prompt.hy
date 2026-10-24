// Prompts: confirm, input with validation, and single / multi select.
// The models are terminal-free (`Select` + `SelectKey`, answer parsers);
// the `*_line` runners read whole lines from a stream, which works on
// pipes and scripts, and are what interactive runners fall back to when
// stdin is not a terminal.
use io::Stream;
use io::sync::write_all;
use io::sync::read_line;
use string::{format, to_bytes, slice_bytes};
use conv::parse_int;
use text::{trim, to_lower};
use cli::width::truncate;
use cli::width::width;
use cli::keys::Event;
use cli::keys::KeyEvent;
use cli::keys::describe_key;
use cli::keys::cp_string;

/// `y`/`yes`/`n`/`no` (any case); an empty answer is `fallback`; anything
/// else is `None` (ask again).
fn parse_confirm(string answer, bool fallback) -> Option<bool> {
    let a = to_lower(trim(answer) ?? "") ?? "";
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
    let p = to_bytes(to_lower(pattern) ?? pattern);
    let t = to_bytes(to_lower(text) ?? text);
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
                    self.filter = slice_bytes(self.filter, 0, cut) ?? "";
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
    return fallback;
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
        let n = parse_int(trim(line) ?? "") ?? 0;
        if n >= 1 && n <= items.len() {
            return Option::Some(n - 1);
        }
    }
    return Option::None;
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
