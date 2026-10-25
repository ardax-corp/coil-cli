// Input events from a terminal: timed reads over `cli::term`, decoded by
// `cli::keys`, with the Esc timeout and window resizes folded in. The
// seam full-screen programs and the interactive prompts read from.
use io::Stream;
use io::stdin;
use io::stdout;
use io::tty::TtyError;
use clock::mono_nanos;
use cli::keys::Decoder;
use cli::keys::Event;
use cli::keys::decoder;
use cli::term::read_bytes;
use cli::term::size_or;
use cli::term::was_resized;

/// How long a lone Esc waits for the rest of a sequence (ms).
const ESC_TIMEOUT_MS = 30;

const READ_CHUNK = 1024;

class Events {
    /// Where bytes come from (a raw-mode terminal, or any stream).
    pub input: Stream,
    /// Whose size a resize reports.
    pub output: Stream,
    pub esc_ms: int,
    /// The input ended; `next` returns `None` from now on.
    pub eof: bool,
    dec: Decoder,
    queue: Vec<Event>,
}

/// Events from `input`; resizes report the size of `output`'s terminal.
fn events_from(Stream input, Stream output) -> Events {
    // The first `resized()` call only starts watching.
    was_resized();
    return new Events(input, output, ESC_TIMEOUT_MS, false, decoder(), Vec::new());
}

/// Events from stdin, resizes measured on stdout.
fn events() -> Events {
    return events_from(stdin(), stdout());
}

fn ms_since(int start_ns) -> int {
    return (mono_nanos() - start_ns) / 1000000;
}

impl Events {
    /// Expect a cursor position report next (after writing
    /// `cli::ansi::query_cursor()`).
    pub fn expect_cursor() {
        self.dec.expect_cursor = true;
    }

    fn take_queued() -> Option<Event> {
        if self.queue.len() == 0 {
            return Option::None;
        }
        let e = self.queue[0];
        let rest: Vec<Event> = Vec::new();
        let i = 1;
        while i < self.queue.len() {
            rest.push(self.queue[i]);
            i++;
        }
        self.queue = rest;
        return Option::Some(e);
    }

    fn push_all(Vec<Event> evs) {
        for e in evs {
            self.queue.push(e);
        }
    }

    /// The next event, waiting up to `timeout_ms` (negative: for ever).
    /// `None` when the time passed with nothing to report, or at the end
    /// of input (then `eof` is set).
    pub fn next(int timeout_ms) -> Result<Option<Event>, TtyError> {
        let start = mono_nanos();
        while true {
            match self.take_queued() {
                Option::Some(e) => {
                    return Option::Some(e);
                },
                Option::None => {},
            }
            if self.eof {
                return Option::None;
            }
            if was_resized() {
                let sz = size_or(self.output, 80, 24);
                let (c, r) = sz;
                return Option::Some(Event::Resize(c, r));
            }
            let wait = -1;
            if timeout_ms >= 0 {
                wait = timeout_ms - ms_since(start);
                if wait < 0 {
                    wait = 0;
                }
            }
            let pending = self.dec.pending() > 0;
            if pending && (wait < 0 || wait > self.esc_ms) {
                wait = self.esc_ms;
            }
            let got = read_bytes(self.input, READ_CHUNK, wait)?;
            match got {
                Option::None => {
                    self.eof = true;
                    self.push_all(self.dec.flush());
                },
                Option::Some(bytes) => {
                    if bytes.len() > 0 {
                        self.dec.feed(bytes);
                        self.push_all(self.dec.drain());
                    } else if pending {
                        // Quiet after a partial sequence: a lone Esc, or junk.
                        self.push_all(self.dec.flush());
                    } else if timeout_ms >= 0 && ms_since(start) >= timeout_ms {
                        return Option::None;
                    }
                },
            }
        }
    }

    /// Every event available now, without waiting.
    pub fn poll() -> Result<Vec<Event>, TtyError> {
        let out: Vec<Event> = Vec::new();
        while let Option::Some(e) = self.next(0)? {
            out.push(e);
        }
        return out;
    }
}
