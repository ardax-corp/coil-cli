// Terminal input decoding: bytes from a raw-mode terminal to key, mouse,
// paste, focus and cursor-report events. Incremental: feed what was read,
// take complete events, and `flush()` after a short quiet time so a lone
// Esc is told apart from the start of a sequence.
use string::{format, from_bytes};

enum Key {
    /// A typed character (code point). Ctrl+letter arrives as the
    /// lower-case letter with `CTRL`.
    Char(int),
    Enter,
    Tab,
    BackTab,
    Backspace,
    Esc,
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    PageUp,
    PageDown,
    Insert,
    Delete,
    /// Function key F1-F24.
    F(int),
}

/// Modifier bits, as in xterm's `1 + mods` parameter.
const SHIFT = 1;

const ALT = 2;

const CTRL = 4;

const META = 8;

class KeyEvent {
    pub key: Key,
    pub mods: int,
}

impl KeyEvent {
    pub fn shift() -> bool {
        return (self.mods & SHIFT) != 0;
    }

    pub fn alt() -> bool {
        return (self.mods & ALT) != 0;
    }

    pub fn ctrl() -> bool {
        return (self.mods & CTRL) != 0;
    }

    /// The character, when this is a plain or shifted character key.
    pub fn char() -> Option<int> {
        return match self.key {
            Key::Char(c) => {
                if (self.mods & (CTRL | ALT | META)) == 0 {
                    return Option::Some(c);
                }
                return Option::None;
            },
            default => Option::None,
        };
    }
}

enum MouseButton {
    Left,
    Middle,
    Right,
    WheelUp,
    WheelDown,
    WheelLeft,
    WheelRight,
    /// Motion with no button held.
    NoButton,
}

enum MouseKind {
    Press,
    Release,
    Drag,
    Move,
}

/// A mouse report; `col` and `row` are 1-based.
class MouseEvent {
    pub kind: MouseKind,
    pub button: MouseButton,
    pub col: int,
    pub row: int,
    pub mods: int,
}

enum Event {
    Key(KeyEvent),
    Mouse(MouseEvent),
    /// Bracketed paste contents.
    Paste(string),
    FocusIn,
    FocusOut,
    /// A cursor position report (`row`, `col`), the answer to
    /// `cli::ansi::query_cursor()`.
    CursorPos(int, int),
    /// A terminal resize (`cols`, `rows`). Not decoded from bytes; event
    /// loops produce it.
    Resize(int, int),
    /// A sequence this decoder does not know, kept as bytes.
    Unknown(Vec<byte>),
}

fn key(Key k, int mods) -> Event {
    return Event::Key(new KeyEvent(k, mods));
}

/// Bytes `b[from..to]`.
fn bytes_between(Vec<byte> b, int from, int to) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    let i = from;
    while i < to {
        out.push(b[i]);
        i++;
    }
    return out;
}

fn utf8_len(int lead) -> int {
    if lead < 192 {
        return 1;
    }
    if lead >= 240 {
        return 4;
    }
    if lead >= 224 {
        return 3;
    }
    return 2;
}

fn decode_cp(Vec<byte> b, int i, int n) -> int {
    let c = b[i] as int;
    if n == 1 {
        return c;
    }
    let cp = 0;
    if n == 2 {
        cp = c & 31;
    } else if n == 3 {
        cp = c & 15;
    } else {
        cp = c & 7;
    }
    let k = 1;
    while k < n {
        cp = (cp << 6) | ((b[i + k] as int) & 63);
        k++;
    }
    return cp;
}

/// Key for a single control or printable byte / code point.
fn plain_key(int cp, int mods) -> Event {
    if cp == 13 || cp == 10 {
        return key(Key::Enter, mods);
    }
    if cp == 9 {
        return key(Key::Tab, mods);
    }
    if cp == 127 || cp == 8 {
        return key(Key::Backspace, mods);
    }
    if cp == 27 {
        return key(Key::Esc, mods);
    }
    if cp == 0 {
        return key(Key::Char(32), mods | CTRL);
    }
    if cp >= 1 && cp <= 26 {
        return key(Key::Char(cp + 96), mods | CTRL);
    }
    if cp >= 28 && cp <= 31 {
        return key(Key::Char(cp + 64), mods | CTRL);
    }
    return key(Key::Char(cp), mods);
}

/// Numeric parameters of a CSI body (`1;5` -> [1, 5]); empty fields are 0.
fn params(Vec<byte> body) -> Vec<int> {
    let out: Vec<int> = Vec::new();
    let cur = 0;
    let any = false;
    for c in body {
        let n = c as int;
        if n >= 48 && n <= 57 {
            cur = cur * 10 + (n - 48);
            any = true;
        } else if n == 59 || n == 58 {
            out.push(cur);
            cur = 0;
            any = true;
        }
    }
    if any {
        out.push(cur);
    }
    return out;
}

fn param_or(Vec<int> p, int i, int fallback) -> int {
    if i < p.len() {
        return p[i];
    }
    return fallback;
}

/// Modifier bits from xterm's `1 + bits` parameter.
fn mods_of(int p) -> int {
    if p <= 1 {
        return 0;
    }
    return p - 1;
}

fn tilde_key(int n) -> Option<Key> {
    return match n {
        1 => Option::Some(Key::Home),
        2 => Option::Some(Key::Insert),
        3 => Option::Some(Key::Delete),
        4 => Option::Some(Key::End),
        5 => Option::Some(Key::PageUp),
        6 => Option::Some(Key::PageDown),
        7 => Option::Some(Key::Home),
        8 => Option::Some(Key::End),
        11 => Option::Some(Key::F(1)),
        12 => Option::Some(Key::F(2)),
        13 => Option::Some(Key::F(3)),
        14 => Option::Some(Key::F(4)),
        15 => Option::Some(Key::F(5)),
        17 => Option::Some(Key::F(6)),
        18 => Option::Some(Key::F(7)),
        19 => Option::Some(Key::F(8)),
        20 => Option::Some(Key::F(9)),
        21 => Option::Some(Key::F(10)),
        23 => Option::Some(Key::F(11)),
        24 => Option::Some(Key::F(12)),
        25 => Option::Some(Key::F(13)),
        26 => Option::Some(Key::F(14)),
        28 => Option::Some(Key::F(15)),
        29 => Option::Some(Key::F(16)),
        31 => Option::Some(Key::F(17)),
        32 => Option::Some(Key::F(18)),
        33 => Option::Some(Key::F(19)),
        34 => Option::Some(Key::F(20)),
        default => Option::None,
    };
}

/// Key for a letter final byte (CSI or SS3).
fn letter_key(int f) -> Option<Key> {
    return match f {
        65 => Option::Some(Key::Up),
        66 => Option::Some(Key::Down),
        67 => Option::Some(Key::Right),
        68 => Option::Some(Key::Left),
        72 => Option::Some(Key::Home),
        70 => Option::Some(Key::End),
        80 => Option::Some(Key::F(1)),
        81 => Option::Some(Key::F(2)),
        82 => Option::Some(Key::F(3)),
        83 => Option::Some(Key::F(4)),
        default => Option::None,
    };
}

fn mouse_button(int cb) -> MouseButton {
    let low = cb & 3;
    if (cb & 64) != 0 {
        return match low {
            0 => MouseButton::WheelUp,
            1 => MouseButton::WheelDown,
            2 => MouseButton::WheelLeft,
            default => MouseButton::WheelRight,
        };
    }
    return match low {
        0 => MouseButton::Left,
        1 => MouseButton::Middle,
        2 => MouseButton::Right,
        default => MouseButton::NoButton,
    };
}

fn mouse_mods(int cb) -> int {
    let m = 0;
    if (cb & 4) != 0 {
        m = m | SHIFT;
    }
    if (cb & 8) != 0 {
        m = m | ALT;
    }
    if (cb & 16) != 0 {
        m = m | CTRL;
    }
    return m;
}

/// A mouse event from the button byte `cb`, position and release flag.
fn mouse_event(int cb, int col, int row, bool release) -> Event {
    let button = mouse_button(cb);
    let kind = MouseKind::Press;
    if release {
        kind = MouseKind::Release;
    } else if (cb & 32) != 0 {
        kind = match button {
            MouseButton::NoButton => MouseKind::Move,
            default => MouseKind::Drag,
        };
    }
    return Event::Mouse(new MouseEvent(kind, button, col, row, mouse_mods(cb)));
}

/// Event for a complete CSI sequence: `body` is between `ESC [` and the
/// final byte `f`.
fn csi_event(Vec<byte> body, int f, Vec<byte> raw, bool expect_cursor) -> Event {
    let first = -1;
    if body.len() > 0 {
        first = body[0] as int;
    }
    if first == 60 && (f == 77 || f == 109) {
        // SGR mouse: ESC [ < b ; x ; y M|m
        let p = params(bytes_between(body, 1, body.len()));
        if p.len() == 3 {
            return mouse_event(p[0], p[1], p[2], f == 109);
        }
        return Event::Unknown(raw);
    }
    if first == 63 || first == 62 || first == 61 {
        // Private replies (DA, DECRQM, …): not keys.
        return Event::Unknown(raw);
    }
    let p = params(body);
    if f == 126 {
        let k = tilde_key(param_or(p, 0, 0));
        return match k {
            Option::Some(kk) => key(kk, mods_of(param_or(p, 1, 1))),
            Option::None => Event::Unknown(raw),
        };
    }
    if f == 117 {
        // CSI code ; mods u (fixterms / kitty basic).
        let code = param_or(p, 0, 0);
        let mods = mods_of(param_or(p, 1, 1));
        return plain_key(code, mods);
    }
    if f == 73 && body.len() == 0 {
        return Event::FocusIn;
    }
    if f == 79 && body.len() == 0 {
        return Event::FocusOut;
    }
    if f == 90 {
        return key(Key::BackTab, mods_of(param_or(p, 1, 1)) | SHIFT);
    }
    if f == 82 && expect_cursor && p.len() == 2 {
        return Event::CursorPos(p[0], p[1]);
    }
    if param_or(p, 0, 1) != 1 {
        // Letter keys only carry modifiers as `1;mods`; anything else
        // (a stray cursor report, say) is not a key.
        return Event::Unknown(raw);
    }
    return match letter_key(f) {
        Option::Some(k) => key(k, mods_of(param_or(p, 1, 1))),
        Option::None => Event::Unknown(raw),
    };
}

const PASTE_END_LEN = 6;

/// Incremental decoder. `feed` bytes, then call `next` until it returns
/// `None`; after a quiet time with bytes still pending call `flush`.
class Decoder {
    buf: Vec<byte>,
    pos: int,
    /// Treat `CSI row ; col R` as a cursor report instead of F3. Set it
    /// while a `query_cursor()` answer is pending.
    pub expect_cursor: bool,
}

fn decoder() -> Decoder {
    return new Decoder(Vec::new(), 0, false);
}

/// Index of the paste end marker `ESC [ 2 0 1 ~` at or after `from`, or -1.
fn find_paste_end(Vec<byte> b, int from) -> int {
    let i = from;
    while i + PASTE_END_LEN <= b.len() {
        if (b[i] as int) == 27 &&
           (b[i + 1] as int) == 91 &&
           (b[i + 2] as int) == 50 &&
           (b[i + 3] as int) == 48 &&
           (b[i + 4] as int) == 49 &&
           (b[i + 5] as int) == 126 {
            return i;
        }
        i++;
    }
    return -1;
}

fn is_paste_start(Vec<byte> body, int f) -> bool {
    return f == 126 &&
           body.len() == 3 &&
           (body[0] as int) == 50 &&
           (body[1] as int) == 48 &&
           (body[2] as int) == 48;
}

fn text_of(Vec<byte> b) -> string {
    return match from_bytes(b) {
        Result::Ok(s) => s,
        Result::Err(_) => "",
    };
}

impl Decoder {
    pub fn feed(Vec<byte> bytes) {
        for c in bytes {
            self.buf.push(c);
        }
    }

    /// Bytes fed but not decoded yet.
    pub fn pending() -> int {
        return self.buf.len() - self.pos;
    }

    fn consume(int n) {
        self.pos = self.pos + n;
        if self.pos >= self.buf.len() {
            self.buf = Vec::new();
            self.pos = 0;
        }
    }

    fn at(int i) -> int {
        return self.buf[self.pos + i] as int;
    }

    /// The next complete event, or `None` when more bytes are needed.
    pub fn next() -> Option<Event> {
        let n = self.pending();
        if n == 0 {
            return Option::None;
        }
        let c = self.at(0);
        if c != 27 {
            let len = utf8_len(c);
            if len > n {
                return Option::None;
            }
            let cp = decode_cp(self.buf, self.pos, len);
            self.consume(len);
            return Option::Some(plain_key(cp, 0));
        }
        if n == 1 {
            return Option::None;
        }
        let k = self.at(1);
        if k == 91 {
            return self.next_csi(n);
        }
        if k == 79 {
            if n < 3 {
                return Option::None;
            }
            let f = self.at(2);
            self.consume(3);
            return match letter_key(f) {
                Option::Some(kk) => Option::Some(key(kk, 0)),
                Option::None => Option::Some(
                    Event::Unknown(bytes_between(self.buf, self.pos - 3, self.pos)),
                ),
            };
        }
        // ESC + key: the key with Alt.
        let len = utf8_len(k);
        if len + 1 > n {
            return Option::None;
        }
        let cp = decode_cp(self.buf, self.pos + 1, len);
        self.consume(len + 1);
        return Option::Some(plain_key(cp, ALT));
    }

    fn next_csi(int n) -> Option<Event> {
        // Legacy X10 mouse: ESC [ M cb cx cy.
        if n >= 3 && self.at(2) == 77 {
            if n < 6 {
                return Option::None;
            }
            let cb = self.at(3) - 32;
            let col = self.at(4) - 32;
            let row = self.at(5) - 32;
            self.consume(6);
            return Option::Some(mouse_event(cb, col, row, (cb & 3) == 3 && (cb & 32) == 0));
        }
        let i = 2;
        while i < n {
            let b = self.at(i);
            if b >= 64 && b <= 126 {
                break;
            }
            i++;
        }
        if i >= n {
            return Option::None;
        }
        let start = self.pos;
        let body = bytes_between(self.buf, start + 2, start + i);
        let f = self.at(i);
        if is_paste_start(body, f) {
            let end = find_paste_end(self.buf, start + i + 1);
            if end < 0 {
                return Option::None;
            }
            let text = text_of(bytes_between(self.buf, start + i + 1, end));
            self.consume(end + PASTE_END_LEN - start);
            return Option::Some(Event::Paste(text));
        }
        let raw = bytes_between(self.buf, start, start + i + 1);
        self.consume(i + 1);
        let ev = csi_event(body, f, raw, self.expect_cursor);
        match ev {
            Event::CursorPos(_, _) => {
                self.expect_cursor = false;
            },
            default => {},
        }
        return Option::Some(ev);
    }

    /// After a quiet time: whatever is pending as events. A lone Esc is
    /// `Esc`; an unfinished sequence is `Unknown`.
    pub fn flush() -> Vec<Event> {
        let out: Vec<Event> = self.drain();
        if self.pending() == 0 {
            return out;
        }
        if self.pending() == 1 && self.at(0) == 27 {
            self.consume(1);
            out.push(key(Key::Esc, 0));
            return out;
        }
        let rest = bytes_between(self.buf, self.pos, self.buf.len());
        self.consume(self.pending());
        out.push(Event::Unknown(rest));
        return out;
    }

    /// Every complete event decoded so far.
    pub fn drain() -> Vec<Event> {
        let out: Vec<Event> = Vec::new();
        while let Option::Some(e) = self.next() {
            out.push(e);
        }
        return out;
    }
}

/// Decode a whole buffer at once (tests, scripted input): `feed`, `drain`
/// and `flush`.
fn decode_all(Vec<byte> bytes) -> Vec<Event> {
    let d = decoder();
    d.feed(bytes);
    return d.flush();
}

/// UTF-8 text of code point `cp`.
fn cp_string(int cp) -> string {
    let b: Vec<byte> = Vec::new();
    if cp < 128 {
        b.push(cp as byte);
    } else if cp < 2048 {
        b.push((192 | (cp >> 6)) as byte);
        b.push((128 | (cp & 63)) as byte);
    } else if cp < 65536 {
        b.push((224 | (cp >> 12)) as byte);
        b.push((128 | ((cp >> 6) & 63)) as byte);
        b.push((128 | (cp & 63)) as byte);
    } else {
        b.push((240 | (cp >> 18)) as byte);
        b.push((128 | ((cp >> 12) & 63)) as byte);
        b.push((128 | ((cp >> 6) & 63)) as byte);
        b.push((128 | (cp & 63)) as byte);
    }
    return text_of(b);
}

fn key_name(Key k) -> string {
    return match k {
        Key::Char(c) => {
            if c == 32 {
                return "space";
            }
            return cp_string(c);
        },
        Key::Enter => "enter",
        Key::Tab => "tab",
        Key::BackTab => "backtab",
        Key::Backspace => "backspace",
        Key::Esc => "esc",
        Key::Up => "up",
        Key::Down => "down",
        Key::Left => "left",
        Key::Right => "right",
        Key::Home => "home",
        Key::End => "end",
        Key::PageUp => "pageup",
        Key::PageDown => "pagedown",
        Key::Insert => "insert",
        Key::Delete => "delete",
        Key::F(n) => format("f%i", n),
    };
}

/// `ctrl+alt+shift+name`, the form `KeyEvent` bindings use: `"ctrl+c"`,
/// `"alt+enter"`, `"shift+f5"`, `"up"`, `"a"`, `"space"`.
fn describe_key(KeyEvent e) -> string {
    let s = "";
    if e.ctrl() {
        s = s + "ctrl+";
    }
    if e.alt() {
        s = s + "alt+";
    }
    if e.shift() {
        s = s + "shift+";
    }
    return s + key_name(e.key);
}

fn kind_name(MouseKind k) -> string {
    return match k {
        MouseKind::Press => "press",
        MouseKind::Release => "release",
        MouseKind::Drag => "drag",
        MouseKind::Move => "move",
    };
}

fn button_name(MouseButton b) -> string {
    return match b {
        MouseButton::Left => "left",
        MouseButton::Middle => "middle",
        MouseButton::Right => "right",
        MouseButton::WheelUp => "wheel-up",
        MouseButton::WheelDown => "wheel-down",
        MouseButton::WheelLeft => "wheel-left",
        MouseButton::WheelRight => "wheel-right",
        MouseButton::NoButton => "none",
    };
}

/// Short text for any event, for logs and tests.
fn describe(Event e) -> string {
    return match e {
        Event::Key(k) => describe_key(k),
        Event::Mouse(m) => format(
            "mouse(%s %s %i,%i)",
            kind_name(m.kind),
            button_name(m.button),
            m.col,
            m.row,
        ),
        Event::Paste(t) => "paste(" + t + ")",
        Event::FocusIn => "focus-in",
        Event::FocusOut => "focus-out",
        Event::CursorPos(r, c) => format("cursor(%i,%i)", r, c),
        Event::Resize(c, r) => format("resize(%ix%i)", c, r),
        Event::Unknown(b) => format("unknown(%i bytes)", b.len()),
    };
}

/// Whether `e` is the key `spec` (as `describe_key` writes it).
fn is_key(Event e, string spec) -> bool {
    return match e {
        Event::Key(k) => describe_key(k) == spec,
        default => false,
    };
}
