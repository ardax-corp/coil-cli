// The terminal itself, over coil-lang's `io::tty`: whether a stream is a
// terminal, its size, raw mode and timed reads. Everything that needs a
// real terminal goes through here; the other modules work on strings.
use io::Stream;
use io::IoError;
use io::tty::TtyError;
use io::stdin;
use io::stdout;
use io::stderr;
use io::sync::write_all;
use io::tty::enable_vt;
use io::tty::enter_raw;
use io::tty::is_raw;
use io::tty::is_tty;
use io::tty::leave_raw;
use io::tty::read_timeout;
use io::tty::resized;
use io::tty::size;
use string::to_bytes;

/// Whether `s` is a terminal.
///
/// # Examples
///
/// ```no_run
/// use cli::term::tty;
/// use io::stdout;
/// let styled = tty(stdout());
/// ```
fn tty(Stream s) -> bool {
    return is_tty(s);
}

/// Whether standard input is a terminal (`false` when it is piped or
/// redirected).
fn stdin_is_tty() -> bool {
    return is_tty(stdin());
}

/// Whether standard output is a terminal.
fn stdout_is_tty() -> bool {
    return is_tty(stdout());
}

/// Whether standard error is a terminal.
fn stderr_is_tty() -> bool {
    return is_tty(stderr());
}

/// `(cols, rows)` of the terminal behind `s` (or behind another standard
/// stream when `s` is piped), else `(cols, rows)` as given.
///
/// # Examples
///
/// ```no_run
/// use cli::term::size_or;
/// use io::stdout;
/// let (cols, rows) = size_or(stdout(), 80, 24);
/// ```
fn size_or(Stream s, int cols, int rows) -> (int, int) {
    return match size(s) {
        Result::Ok(sz) => sz,
        Result::Err(_) => (cols, rows),
    };
}

/// Terminal columns, 80 when there is no terminal.
fn columns() -> int {
    let (c, _) = size_or(stdout(), 80, 24);
    return c;
}

/// `true` once per window resize since the last call.
fn was_resized() -> bool {
    return resized();
}

/// Turn on ANSI escape handling for `s` (Windows consoles); `true` when
/// escapes can be written.
fn enable_ansi(Stream s) -> bool {
    return is_tty(s) && enable_vt(s);
}

/// Raw mode on a terminal. Leave it with `leave()`; the runtime also
/// restores the terminal if the program ends (exit, panic, signal) while
/// still raw.
class RawMode {
    /// The terminal stream that was put in raw mode.
    pub input: Stream,
    /// `true` until `leave` restores the terminal.
    pub active: bool,
}

/// Raw mode with the signal keys and output processing chosen.
fn raw_mode_with(Stream input, bool keep_signals, bool keep_output) -> Result<RawMode, TtyError> {
    enter_raw(input, keep_signals, keep_output)?;
    return new RawMode(input, true);
}

/// Raw mode on `input` with Ctrl-C/Ctrl-Z delivered as keys and output
/// sent as is (write "\r\n"), as full-screen programs and line editors
/// want. `Err(TtyError::NotATerminal)` when `input` is not a terminal.
///
/// # Examples
///
/// ```no_run
/// use cli::term::raw_mode;
/// use io::stdin;
/// use io::tty::TtyError;
/// fn main() -> Result<(), TtyError> {
///     let raw = raw_mode(stdin())?;
///     // ... read keys with cli::events ...
///     raw.leave()?;
///     return;
/// }
/// ```
fn raw_mode(Stream input) -> Result<RawMode, TtyError> {
    return raw_mode_with(input, false, false)?;
}

impl RawMode {
    /// Restore the terminal. Safe to call more than once.
    pub fn leave() -> Result<(), TtyError> {
        if self.active {
            self.active = false;
            leave_raw(self.input)?;
        }
        return;
    }

    /// Whether the terminal is still in raw mode through this handle.
    pub fn is_active() -> bool {
        return self.active && is_raw(self.input);
    }
}

/// Wait up to `timeout_ms` (negative: for ever) and read at most `max`
/// bytes. `Some([])` when the time passed or a resize cut the wait short,
/// `None` at end of input. Works on any stream, not only a terminal.
fn read_bytes(Stream s, int max, int timeout_ms) -> Result<Option<Vec<byte>>, TtyError> {
    let buf: Vec<byte> = Vec::new();
    let i = 0;
    while i < max {
        buf.push(0 as byte);
        i++;
    }
    let got = read_timeout(s, buf, timeout_ms)?;
    return match got {
        Option::None => Option::None,
        Option::Some(n) => {
            let out: Vec<byte> = Vec::new();
            let j = 0;
            while j < n {
                out.push(buf[j]);
                j++;
            }
            return Option::Some(out);
        },
    };
}

/// A stream error as a terminal error.
fn tty_io(IoError e) -> TtyError {
    return TtyError::Io(e);
}

/// Write `text` to `out`.
fn put(Stream out, string text) -> Result<(), TtyError> {
    write_all(out, to_bytes(text)).map_err(tty_io)?;
    return;
}
