// Terminal state: tty checks, size, raw mode, timed reads, resize, colour
// level. FFI shim over native/libcli; everything else in `cli` is pure Coil.
use ffi::dload;
use ffi::declare;
use ffi::invoke;
use ffi::Error;
use ffi::types::Bytes;
use ffi::types::Int;
use env::var;
use string::to_bytes;

extern "cli" {
    fn coil_cli_isatty(int fd) -> int;
    fn coil_cli_size(int fd) -> int;
    fn coil_cli_raw_enter(int flags) -> int;
    fn coil_cli_raw_leave() -> int;
    fn coil_cli_is_raw() -> int;
    fn coil_cli_resized() -> int;
    fn coil_cli_enable_vt() -> int;
    fn coil_cli_last_error() -> string;
}

enum TermError {
    /// The stream is not a terminal (piped, redirected, no console).
    NotATty,
    /// The OS call failed; `last_error()` has the text.
    Io,
}

/// Terminal size in character cells.
class Size {
    pub cols: int,
    pub rows: int,
}

/// Raw mode options. Defaults turn everything off, as a full-screen
/// program wants.
class RawOptions {
    /// Leave ISIG on: Ctrl-C and Ctrl-Z still send signals.
    pub keep_signals: bool,
    /// Leave output processing on: "\n" still returns to column 0.
    pub keep_output: bool,
}

/// An active raw mode. `leave()` restores the terminal; `drop` (GC time)
/// and the native `atexit` hook restore it too, so a panic or `exit` does
/// not leave the shell raw.
class RawMode {
    active: bool,
}

const STDIN_FD = 0;

const STDOUT_FD = 1;

const STDERR_FD = 2;

const ERR_NOTTY = -3;

const EOF = -1;

static let native_lib = 0;

static let fn_read = 0;

fn bound(Result<int, Error> r) -> int {
    return match r {
        Result::Ok(id) => id,
        Result::Err(e) => panic e.message,
    };
}

/// `coil_cli_read` takes an output buffer, which `extern` cannot express,
/// so it goes through `declare` / `invoke`.
fn native() -> int {
    if native_lib != 0 {
        return native_lib;
    }
    let lib = bound(dload("cli"));
    fn_read = bound(declare(lib, "coil_cli_read", (Bytes, Int, Int), Int));
    native_lib = lib;
    return lib;
}

fn err_of(int rc) -> TermError {
    if rc == ERR_NOTTY {
        return TermError::NotATty;
    }
    return TermError::Io;
}

/// Text of the last failing native call.
fn last_error() -> string {
    return coil_cli_last_error();
}

/// Whether file descriptor `fd` (0, 1 or 2) is a terminal.
fn is_tty(int fd) -> bool {
    return coil_cli_isatty(fd) == 1;
}

fn stdin_is_tty() -> bool {
    return is_tty(STDIN_FD);
}

fn stdout_is_tty() -> bool {
    return is_tty(STDOUT_FD);
}

fn stderr_is_tty() -> bool {
    return is_tty(STDERR_FD);
}

/// Size of the terminal behind stdout (falling back to stderr, stdin).
fn size() -> Result<Size, TermError> {
    let packed = coil_cli_size(STDOUT_FD);
    if packed < 0 {
        raise err_of(packed);
    }
    return new Size(packed >> 32, packed & 4294967295);
}

/// `size()`, or `cols` x `rows` when there is no terminal.
fn size_or(int cols, int rows) -> Size {
    return match size() {
        Result::Ok(s) => s,
        Result::Err(_) => new Size(cols, rows),
    };
}

/// Windows: turn on escape-sequence processing for stdout. No-op elsewhere.
/// Call once before writing escapes when stdout may be a Windows console.
fn enable_vt() -> bool {
    return coil_cli_enable_vt() == 0;
}

fn default_raw_options() -> RawOptions {
    return new RawOptions(false, false);
}

// Declared before `raw_mode`: coil-lang#1980.
fn raw_mode_with(RawOptions opts) -> Result<RawMode, TermError> {
    let flags = 0;
    if opts.keep_signals {
        flags = flags | 1;
    }
    if opts.keep_output {
        flags = flags | 2;
    }
    let rc = coil_cli_raw_enter(flags);
    if rc < 0 {
        raise err_of(rc);
    }
    return new RawMode(true);
}

/// Put stdin's terminal in raw mode: no echo, no line buffering, no
/// signals, no output processing.
fn raw_mode() -> Result<RawMode, TermError> {
    return raw_mode_with(default_raw_options())?;
}

/// Whether raw mode is on (from any `RawMode`).
fn is_raw() -> bool {
    return coil_cli_is_raw() == 1;
}

impl RawMode {
    /// Restore the terminal. Safe to call more than once.
    pub fn leave() -> Result<(), TermError> {
        if !self.active {
            return;
        }
        self.active = false;
        let rc = coil_cli_raw_leave();
        if rc < 0 {
            raise err_of(rc);
        }
        return;
    }

    pub fn is_active() -> bool {
        return self.active;
    }

    fn drop() {
        if self.active {
            self.active = false;
            coil_cli_raw_leave();
        }
    }
}

/// Read what stdin has, waiting at most `timeout_ms` (negative: forever).
/// `Some([])` is a timeout (or an interrupted wait: check `resized()`),
/// `None` is end of input.
fn read_bytes(int timeout_ms) -> Result<Option<Vec<byte>>, TermError> {
    return read_bytes_max(256, timeout_ms)?;
}

fn read_bytes_max(int cap, int timeout_ms) -> Result<Option<Vec<byte>>, TermError> {
    let lib = native();
    let f = fn_read;
    let buf: Vec<byte> = Vec::new();
    let zero: byte = 0;
    let i = 0;
    while i < cap {
        buf.push(zero);
        i++;
    }
    let n = match invoke(lib, f, (buf, cap, timeout_ms)) {
        Result::Ok(v) => v,
        Result::Err(_) => raise TermError::Io,
    };
    if n == EOF {
        return Option::None;
    }
    if n < 0 {
        raise err_of(n);
    }
    while buf.len() > n {
        buf.pop();
    }
    return Option::Some(buf);
}

/// True once per terminal resize since the last call.
fn resized() -> bool {
    return coil_cli_resized() == 1;
}

/// How many colours output may use.
#[repr(int)]
#[derive(Eq, Ord)]
enum ColorLevel {
    None = 0,
    /// The 16 standard ANSI colours.
    Basic = 1,
    /// The xterm 256-colour palette.
    Ansi256 = 2,
    /// 24-bit RGB.
    TrueColor = 3,
}

/// Colour level from the conventional variables, for a stream that is
/// (`tty`) or is not a terminal. `NO_COLOR` (any non-empty value) turns
/// colour off; `FORCE_COLOR` turns it on even off a terminal (`0` off,
/// `1` basic, `2` 256, `3` truecolor); `COLORTERM=truecolor|24bit`, a
/// `TERM` ending in `-256color`, or `TERM=dumb` refine the guess.
fn detect_color_level(
    bool tty,
    Option<string> no_color,
    Option<string> force_color,
    Option<string> colorterm,
    Option<string> term_name,
) -> ColorLevel {
    let nc = no_color ?? "";
    if nc != "" {
        return ColorLevel::None;
    }
    let fc = force_color ?? "-";
    if fc == "0" || fc == "false" {
        return ColorLevel::None;
    }
    let forced = fc != "-";
    if forced {
        if fc == "3" {
            return ColorLevel::TrueColor;
        }
        if fc == "2" {
            return ColorLevel::Ansi256;
        }
    }
    if !tty && !forced {
        return ColorLevel::None;
    }
    let t = term_name ?? "";
    if t == "dumb" && !forced {
        return ColorLevel::None;
    }
    let ct = colorterm ?? "";
    if ct == "truecolor" || ct == "24bit" {
        return ColorLevel::TrueColor;
    }
    if ends_with(t, "-256color") || ends_with(t, "-direct") {
        return ColorLevel::Ansi256;
    }
    return ColorLevel::Basic;
}

fn ends_with(string s, string suffix) -> bool {
    let n = s.len();
    let m = suffix.len();
    if m > n {
        return false;
    }
    let a = to_bytes(s);
    let b = to_bytes(suffix);
    let i = 0;
    while i < m {
        if a[n - m + i] != b[i] {
            return false;
        }
        i++;
    }
    return true;
}

fn env_opt(string name) -> Option<string> {
    return match var(name) {
        Result::Ok(v) => Option::Some(v),
        Result::Err(_) => Option::None,
    };
}

/// `detect_color_level` for stdout with the real environment. Needs
/// `--allow-env`.
fn color_level() -> ColorLevel {
    return detect_color_level(
        stdout_is_tty(),
        env_opt("NO_COLOR"),
        env_opt("FORCE_COLOR"),
        env_opt("COLORTERM"),
        env_opt("TERM"),
    );
}

/// The same for stderr (progress bars, diagnostics).
fn stderr_color_level() -> ColorLevel {
    return detect_color_level(
        stderr_is_tty(),
        env_opt("NO_COLOR"),
        env_opt("FORCE_COLOR"),
        env_opt("COLORTERM"),
        env_opt("TERM"),
    );
}
