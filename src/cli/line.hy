// Line editor: a terminal-free model (a text buffer with a cursor,
// kill/yank, word moves and history, driven by `Edit` actions), default
// key bindings (`edit_for`), and `read_line`, which runs it in raw mode.
use string::{to_bytes, slice_bytes};
use cli::width::char_width;
use cli::width::decode_at;
use cli::width::seq_len;
use cli::width::width;
use cli::keys::Event;
use cli::keys::Key;
use cli::keys::KeyEvent;
use cli::keys::describe_key;
use cli::ansi::enable_paste;
use cli::ansi::disable_paste;
use cli::ansi::right;
use cli::term::RawMode;
use cli::term::raw_mode;
use cli::term::put;
use cli::term::tty_io;
use cli::term::size_or;
use cli::events::Events;
use cli::events::events;
use io::Stream;
use io::tty::TtyError;
use io::stdin;
use io::stdout;
use io::tty::is_tty;
use cli::keys::cp_string;

enum Edit {
    /// Insert text at the cursor (typed characters or a paste).
    Insert(string),
    Left,
    Right,
    Home,
    End,
    WordLeft,
    WordRight,
    /// Delete the character before / under the cursor.
    Backspace,
    Delete,
    /// Delete the word before / after the cursor into the kill buffer.
    KillWordBack,
    KillWordForward,
    /// Delete to the end / start of the line into the kill buffer.
    KillToEnd,
    KillToStart,
    /// Insert the kill buffer.
    Yank,
    /// Swap the two characters around the cursor.
    Transpose,
    HistoryPrev,
    HistoryNext,
    /// Accept the line.
    Submit,
    /// Abandon the line (Ctrl-C).
    Cancel,
    /// End of input on an empty line (Ctrl-D).
    Eof,
    Clear,
}

/// What the caller should do after an action.
#[repr(int)]
#[derive(Eq)]
enum Outcome {
    Continue = 0,
    Submit = 1,
    Cancel = 2,
    Eof = 3,
}

fn piece(string s, int from, int to) -> string {
    return match slice_bytes(s, from, to) {
        Result::Ok(t) => t,
        Result::Err(_) => "",
    };
}

/// `s` split into display units: one character plus any zero-width marks.
fn units(string s) -> Vec<string> {
    let b = to_bytes(s);
    let out: Vec<string> = Vec::new();
    let i = 0;
    while i < b.len() {
        let n = seq_len(b[i] as int);
        let ch = piece(s, i, i + n);
        if char_width(decode_at(b, i)) == 0 && out.len() > 0 && (b[i] as int) >= 128 {
            out[out.len() - 1] = out[out.len() - 1] + ch;
        } else {
            out.push(ch);
        }
        i = i + n;
    }
    return out;
}

fn join_units(Vec<string> u, int from, int to) -> string {
    let s = "";
    let i = from;
    while i < to {
        s = s + u[i];
        i++;
    }
    return s;
}

fn is_word(string u) -> bool {
    let b = to_bytes(u);
    let c = b[0] as int;
    if c >= 128 {
        return true;
    }
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
}

shared class History {
    pub entries: Vec<string>,
    /// Most entries kept (oldest dropped first).
    pub limit: int,
}

fn history(int limit) -> History {
    return new History(Vec::new(), limit);
}

impl History {
    /// Add an entry; blanks and repeats of the last entry are skipped.
    pub fn add(string line) {
        if line == "" {
            return;
        }
        let n = self.entries.len();
        if n > 0 && self.entries[n - 1] == line {
            return;
        }
        self.entries.push(line);
        if self.entries.len() > self.limit {
            let kept: Vec<string> = Vec::new();
            let i = self.entries.len() - self.limit;
            while i < self.entries.len() {
                kept.push(self.entries[i]);
                i++;
            }
            self.entries = kept;
        }
    }

    pub fn len() -> int {
        return self.entries.len();
    }
}

class Editor {
    buf: Vec<string>,
    /// Cursor position in display units (0..=len).
    pub cursor: int,
    pub kill: string,
    pub history: History,
    /// Index into history while browsing; `history.len()` = the draft.
    hpos: int,
    draft: string,
}

fn editor(History h) -> Editor {
    return new Editor(Vec::new(), 0, "", h, h.len(), "");
}

impl Editor {
    pub fn text() -> string {
        return join_units(self.buf, 0, self.buf.len());
    }

    pub fn len() -> int {
        return self.buf.len();
    }

    /// Replace the line and put the cursor at its end.
    pub fn set_text(string s) {
        self.buf = units(s);
        self.cursor = self.buf.len();
    }

    fn insert(string s) {
        let add = units(s);
        let out: Vec<string> = Vec::new();
        let i = 0;
        while i < self.cursor {
            out.push(self.buf[i]);
            i++;
        }
        for u in add {
            out.push(u);
        }
        while i < self.buf.len() {
            out.push(self.buf[i]);
            i++;
        }
        self.buf = out;
        self.cursor = self.cursor + add.len();
    }

    /// Remove units `from..to`; returns the removed text.
    fn cut(int from, int to) -> string {
        let removed = join_units(self.buf, from, to);
        let out: Vec<string> = Vec::new();
        let i = 0;
        while i < self.buf.len() {
            if i < from || i >= to {
                out.push(self.buf[i]);
            }
            i++;
        }
        self.buf = out;
        self.cursor = from;
        return removed;
    }

    fn word_start() -> int {
        let i = self.cursor;
        while i > 0 && !is_word(self.buf[i - 1]) {
            i--;
        }
        while i > 0 && is_word(self.buf[i - 1]) {
            i--;
        }
        return i;
    }

    fn word_end() -> int {
        let i = self.cursor;
        let n = self.buf.len();
        while i < n && !is_word(self.buf[i]) {
            i++;
        }
        while i < n && is_word(self.buf[i]) {
            i++;
        }
        return i;
    }

    fn show_history(int pos) {
        if pos == self.history.len() {
            self.set_text(self.draft);
        } else {
            self.set_text(self.history.entries[pos]);
        }
        self.hpos = pos;
    }

    /// Apply one action.
    pub fn apply(Edit e) -> Outcome {
        match e {
            Edit::Insert(s) => self.insert(s),
            Edit::Left => {
                if self.cursor > 0 {
                    self.cursor--;
                }
            },
            Edit::Right => {
                if self.cursor < self.buf.len() {
                    self.cursor++;
                }
            },
            Edit::Home => {
                self.cursor = 0;
            },
            Edit::End => {
                self.cursor = self.buf.len();
            },
            Edit::WordLeft => {
                self.cursor = self.word_start();
            },
            Edit::WordRight => {
                self.cursor = self.word_end();
            },
            Edit::Backspace => {
                if self.cursor > 0 {
                    self.cut(self.cursor - 1, self.cursor);
                }
            },
            Edit::Delete => {
                if self.cursor < self.buf.len() {
                    self.cut(self.cursor, self.cursor + 1);
                }
            },
            Edit::KillWordBack => {
                let s = self.word_start();
                if s < self.cursor {
                    self.kill = self.cut(s, self.cursor);
                }
            },
            Edit::KillWordForward => {
                let at = self.cursor;
                let end = self.word_end();
                if end > at {
                    self.kill = self.cut(at, end);
                }
            },
            Edit::KillToEnd => {
                if self.cursor < self.buf.len() {
                    self.kill = self.cut(self.cursor, self.buf.len());
                }
            },
            Edit::KillToStart => {
                if self.cursor > 0 {
                    self.kill = self.cut(0, self.cursor);
                }
            },
            Edit::Yank => {
                if self.kill != "" {
                    self.insert(self.kill);
                }
            },
            Edit::Transpose => {
                let n = self.buf.len();
                if n >= 2 && self.cursor > 0 {
                    let at = self.cursor;
                    if at == n {
                        at = n - 1;
                    }
                    let t = self.buf[at - 1];
                    self.buf[at - 1] = self.buf[at];
                    self.buf[at] = t;
                    self.cursor = at + 1;
                }
            },
            Edit::HistoryPrev => {
                if self.hpos > 0 {
                    if self.hpos == self.history.len() {
                        self.draft = self.text();
                    }
                    self.show_history(self.hpos - 1);
                }
            },
            Edit::HistoryNext => {
                if self.hpos < self.history.len() {
                    self.show_history(self.hpos + 1);
                }
            },
            Edit::Submit => {
                return Outcome::Submit;
            },
            Edit::Cancel => {
                return Outcome::Cancel;
            },
            Edit::Eof => {
                if self.buf.len() == 0 {
                    return Outcome::Eof;
                }
                if self.cursor < self.buf.len() {
                    self.cut(self.cursor, self.cursor + 1);
                }
            },
            Edit::Clear => {
                self.buf = Vec::new();
                self.cursor = 0;
            },
        }
        return Outcome::Continue;
    }

    /// Accept the line: add it to the history, reset, and return it.
    pub fn take() -> string {
        let s = self.text();
        self.history.add(s);
        self.buf = Vec::new();
        self.cursor = 0;
        self.draft = "";
        self.hpos = self.history.len();
        return s;
    }

    /// Columns from the start of the text to the cursor.
    pub fn cursor_col() -> int {
        return width(join_units(self.buf, 0, self.cursor));
    }

    /// The visible part of the line for a field `cols` wide, scrolled so
    /// the cursor shows, and the cursor's column within it. `mask` (e.g.
    /// "*") replaces each character when not "" (passwords).
    pub fn view(int cols, string mask) -> (string, int) {
        let shown: Vec<string> = Vec::new();
        for u in self.buf {
            if mask != "" {
                shown.push(mask);
            } else {
                shown.push(u);
            }
        }
        let start = 0;
        let ccol = width(join_units(shown, 0, self.cursor));
        while ccol >= cols && start < self.cursor {
            ccol = ccol - width(shown[start]);
            start++;
        }
        let out = "";
        let used = 0;
        let i = start;
        while i < shown.len() {
            let w = width(shown[i]);
            if used + w > cols {
                break;
            }
            out = out + shown[i];
            used = used + w;
            i++;
        }
        return (out, ccol);
    }
}

/// The default (Emacs / readline-style) binding for an input event, or
/// `None` when it means nothing to the editor. Pastes insert their text.
fn edit_for(Event e) -> Option<Edit> {
    return match e {
        Event::Paste(t) => Option::Some(Edit::Insert(t)),
        Event::Key(k) => edit_for_key(k),
        default => Option::None,
    };
}

fn edit_for_key(KeyEvent k) -> Option<Edit> {
    match k.char() {
        Option::Some(c) => {
            return Option::Some(Edit::Insert(cp_string(c)));
        },
        Option::None => {},
    }
    let spec = describe_key(k);
    if spec == "enter" || spec == "ctrl+j" || spec == "ctrl+m" {
        return Option::Some(Edit::Submit);
    }
    if spec == "ctrl+c" || spec == "esc" {
        return Option::Some(Edit::Cancel);
    }
    if spec == "ctrl+d" {
        return Option::Some(Edit::Eof);
    }
    if spec == "left" || spec == "ctrl+b" {
        return Option::Some(Edit::Left);
    }
    if spec == "right" || spec == "ctrl+f" {
        return Option::Some(Edit::Right);
    }
    if spec == "home" || spec == "ctrl+a" {
        return Option::Some(Edit::Home);
    }
    if spec == "end" || spec == "ctrl+e" {
        return Option::Some(Edit::End);
    }
    if spec == "alt+b" || spec == "ctrl+left" || spec == "alt+left" {
        return Option::Some(Edit::WordLeft);
    }
    if spec == "alt+f" || spec == "ctrl+right" || spec == "alt+right" {
        return Option::Some(Edit::WordRight);
    }
    if spec == "backspace" || spec == "ctrl+h" || spec == "shift+backspace" {
        return Option::Some(Edit::Backspace);
    }
    if spec == "delete" {
        return Option::Some(Edit::Delete);
    }
    if spec == "ctrl+w" || spec == "alt+backspace" || spec == "ctrl+backspace" {
        return Option::Some(Edit::KillWordBack);
    }
    if spec == "alt+d" || spec == "ctrl+delete" {
        return Option::Some(Edit::KillWordForward);
    }
    if spec == "ctrl+k" {
        return Option::Some(Edit::KillToEnd);
    }
    if spec == "ctrl+u" {
        return Option::Some(Edit::KillToStart);
    }
    if spec == "ctrl+y" {
        return Option::Some(Edit::Yank);
    }
    if spec == "ctrl+t" {
        return Option::Some(Edit::Transpose);
    }
    if spec == "up" || spec == "ctrl+p" {
        return Option::Some(Edit::HistoryPrev);
    }
    if spec == "down" || spec == "ctrl+n" {
        return Option::Some(Edit::HistoryNext);
    }
    if spec == "ctrl+l" {
        return Option::Some(Edit::Clear);
    }
    if spec == "tab" {
        return Option::Some(Edit::Insert("\t"));
    }
    return Option::None;
}

/// What `read_line` got.
enum LineInput {
    Line(string),
    /// Ctrl-C (or Esc).
    Cancelled,
    /// End of input (Ctrl-D on an empty line, or stdin closed).
    Eof,
}

fn draw_line(Stream out, Editor ed, string prompt, string mask, int cols) -> Result<(), TtyError> {
    let pw = width(prompt);
    let avail = cols - pw - 1;
    if avail < 1 {
        avail = 1;
    }
    let v = ed.view(avail, mask);
    let (text, ccol) = v;
    put(out, "\r" + prompt + text + "\e[K\r" + right(pw + ccol))?;
    return;
}

fn edit_loop(Editor ed, string prompt, string mask) -> Result<LineInput, TtyError> {
    let out = stdout();
    let ev = events();
    let sz = size_or(out, 80, 24);
    let (cols, _) = sz;
    put(out, enable_paste())?;
    draw_line(out, ed, prompt, mask, cols)?;
    while true {
        let got = ev.next(-1)?;
        match got {
            Option::None => {
                if ev.eof {
                    put(out, disable_paste() + "\r\n")?;
                    return LineInput::Eof;
                }
            },
            Option::Some(Event::Resize(c, _)) => {
                cols = c;
                draw_line(out, ed, prompt, mask, cols)?;
            },
            Option::Some(e) => {
                match edit_for(e) {
                    Option::Some(action) => {
                        let o = ed.apply(action);
                        if o == Outcome::Submit {
                            put(out, disable_paste() + "\r\n")?;
                            return LineInput::Line(ed.take());
                        }
                        if o == Outcome::Cancel {
                            ed.apply(Edit::Clear);
                            put(out, disable_paste() + "^C\r\n")?;
                            return LineInput::Cancelled;
                        }
                        if o == Outcome::Eof {
                            put(out, disable_paste() + "\r\n")?;
                            return LineInput::Eof;
                        }
                        draw_line(out, ed, prompt, mask, cols)?;
                    },
                    Option::None => {},
                }
            },
        }
    }
}

/// Read a line with `prompt`, editing it in raw mode (Emacs keys,
/// history, paste) with each character shown as `mask` when it is not "".
/// When stdin is not a terminal the line is read plainly, so piped input
/// works. Accepted lines go into the editor's history.
fn read_line_masked(Editor ed, string prompt, string mask) -> Result<LineInput, TtyError> {
    if !is_tty(stdin()) {
        put(stdout(), prompt)?;
        let got = io::sync::read_line(stdin()).map_err(tty_io)?;
        return match got {
            Option::Some(l) => {
                ed.history.add(l);
                return LineInput::Line(l);
            },
            Option::None => LineInput::Eof,
        };
    }
    let raw = raw_mode(stdin())?;
    let r = edit_loop(ed, prompt, mask);
    raw.leave()?;
    return r?;
}

/// `read_line_masked` with the text shown.
fn read_line(Editor ed, string prompt) -> Result<LineInput, TtyError> {
    return read_line_masked(ed, prompt, "")?;
}
