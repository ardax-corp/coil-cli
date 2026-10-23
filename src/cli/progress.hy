// Progress bars and spinners for stderr. Rendering is pure (`render_*`);
// `Bar` and `Spinner` redraw one line in place, throttled, and stay quiet
// when not enabled (not a terminal), so piped logs are not filled with
// carriage returns.
use io::stderr;
use io::Stream;
use io::sync::write_all;
use string::{format, to_bytes};
use clock::mono_nanos;
use cli::width::{width, truncate};

fn strs(string... xs) -> Vec<string> {
    return xs;
}

/// Bar glyphs. `partials` are the fractional cells from 1/n to (n-1)/n
/// (may be empty for whole-cell bars).
class BarStyle {
    pub left: string,
    pub right: string,
    pub fill: string,
    pub empty: string,
    pub partials: Vec<string>,
}

/// Smooth Unicode blocks: `▕██████▍     ▏`.
fn blocks() -> BarStyle {
    return new BarStyle(
        "▕",
        "▏",
        "█",
        " ",
        strs("▏", "▎", "▍", "▌", "▋", "▊", "▉"),
    );
}

/// Plain ASCII: `[=====>    ]`.
fn ascii() -> BarStyle {
    return new BarStyle("[", "]", "=", " ", strs(">"));
}

fn repeat(string s, int n) -> string {
    let out = "";
    let i = 0;
    while i < n {
        out = out + s;
        i++;
    }
    return out;
}

/// The bar itself, `cells` wide inside its ends, for `current` of `total`.
fn render_bar(BarStyle st, int current, int total, int cells) -> string {
    if cells <= 0 {
        return st.left + st.right;
    }
    let c = current;
    if c < 0 {
        c = 0;
    }
    if total > 0 && c > total {
        c = total;
    }
    let steps = st.partials.len() + 1;
    let units = 0;
    if total > 0 {
        units = c * cells * steps / total;
    }
    let full = units / steps;
    let part = units % steps;
    let s = st.left + repeat(st.fill, full);
    let used = full;
    if used < cells && part > 0 {
        s = s + st.partials[part - 1];
        used++;
    }
    return s + repeat(st.empty, cells - used) + st.right;
}

/// `1.5 KiB`, `12 B`, `3.2 GiB`.
fn human_bytes(int n) -> string {
    if n < 1024 {
        return format("%i B", n);
    }
    let units = ["KiB", "MiB", "GiB", "TiB", "PiB"];
    let v = n as float / 1024.0;
    let i = 0;
    while v >= 1024.0 && i < 4 {
        v = v / 1024.0;
        i++;
    }
    return one_decimal(v) + " " + units[i];
}

/// `v` with one decimal place, `10.0` and up without.
fn one_decimal(float v) -> string {
    if v >= 10.0 {
        return format("%i", (v + 0.5) as int);
    }
    let tenths = (v * 10.0 + 0.5) as int;
    return format("%i.%i", tenths / 10, tenths % 10);
}

/// `950ms`, `12s`, `3m05s`, `1h02m`.
fn human_duration(int ms) -> string {
    if ms < 1000 {
        return format("%ims", ms);
    }
    let s = ms / 1000;
    if s < 60 {
        return format("%is", s);
    }
    let m = s / 60;
    if m < 60 {
        return format("%im%s", m, two(s % 60)) + "s";
    }
    return format("%ih%s", m / 60, two(m % 60)) + "m";
}

fn two(int n) -> string {
    if n < 10 {
        return format("0%i", n);
    }
    return format("%i", n);
}

/// `12.3k/s`-style count per second; `""` before any time passed.
fn human_rate(int count, int elapsed_ms) -> string {
    if elapsed_ms <= 0 {
        return "";
    }
    let per = count as float * 1000.0 / elapsed_ms as float;
    if per >= 1000000.0 {
        return one_decimal(per / 1000000.0) + "M/s";
    }
    if per >= 1000.0 {
        return one_decimal(per / 1000.0) + "k/s";
    }
    return one_decimal(per) + "/s";
}

/// Remaining time estimate in ms, or -1 when it cannot be told yet.
fn eta_ms(int current, int total, int elapsed_ms) -> int {
    if current <= 0 || total <= 0 || current >= total || elapsed_ms <= 0 {
        return -1;
    }
    return (elapsed_ms * (total - current)) / current;
}

/// A whole progress line, at most `cols` columns:
/// `label ▕████▍    ▏ 45% 450/1000 1.2k/s ETA 3s`. The bar takes what
/// the text leaves (at least 10 cells, else it is left out).
fn render_line(
    BarStyle st,
    string label,
    int current,
    int total,
    int elapsed_ms,
    int cols,
) -> string {
    let pct = 0;
    if total > 0 {
        pct = current * 100 / total;
        if pct > 100 {
            pct = 100;
        }
    }
    let info = format("%i%% %i/%i", pct, current, total);
    let rate = human_rate(current, elapsed_ms);
    if rate != "" {
        info = info + " " + rate;
    }
    let eta = eta_ms(current, total, elapsed_ms);
    if eta >= 0 {
        info = info + " ETA " + human_duration(eta);
    }
    let head = "";
    if label != "" {
        head = label + " ";
    }
    let fixed = width(head) + width(info) + 1 + width(st.left) + width(st.right);
    let cells = cols - fixed;
    if cells < 10 {
        return truncate(head + info, cols, "…");
    }
    if cells > 60 {
        cells = 60;
    }
    return head + render_bar(st, current, total, cells) + " " + info;
}

/// Braille spinner frames.
fn dots() -> Vec<string> {
    return strs("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏");
}

/// ASCII spinner frames.
fn line_frames() -> Vec<string> {
    return strs("-", "\\", "|", "/");
}

fn render_spinner(Vec<string> frames, int tick, string label, int elapsed_ms) -> string {
    let f = frames[tick % frames.len()];
    let s = f + " " + label;
    if elapsed_ms >= 1000 {
        s = s + " (" + human_duration(elapsed_ms) + ")";
    }
    return s;
}

const REDRAW_NS = 80000000;

fn now_ms(int start_ns) -> int {
    return (mono_nanos() - start_ns) / 1000000;
}

fn emit(Stream out, string s) {
    match write_all(out, to_bytes(s)) {
        Result::Ok(_) => {},
        Result::Err(_) => {},
    }
}

/// A redrawing progress bar.
class Bar {
    pub total: int,
    pub current: int,
    pub label: string,
    pub style: BarStyle,
    /// Columns to fit in (the terminal width).
    pub cols: int,
    /// Draw at all. Pass whether stderr is a terminal.
    pub enabled: bool,
    out: Stream,
    start_ns: int,
    last_ns: int,
    drawn: bool,
}

/// A bar for `total` steps on stderr, `cols` wide. `enabled` should be
/// whether stderr is a terminal.
fn bar(int total, int cols, bool enabled) -> Bar {
    let now = mono_nanos();
    return new Bar(total, 0, "", blocks(), cols, enabled, stderr(), now, 0, false);
}

impl Bar {
    pub fn set_label(string label) {
        self.label = label;
        self.draw(false);
    }

    pub fn inc(int n) {
        self.current = self.current + n;
        self.draw(false);
    }

    pub fn set(int n) {
        self.current = n;
        self.draw(false);
    }

    pub fn elapsed_ms() -> int {
        return now_ms(self.start_ns);
    }

    pub fn line() -> string {
        return render_line(
            self.style,
            self.label,
            self.current,
            self.total,
            self.elapsed_ms(),
            self.cols - 1,
        );
    }

    /// Redraw now if enough time passed (or `force`).
    pub fn draw(bool force) {
        if !self.enabled {
            return;
        }
        let now = mono_nanos();
        if !force && self.drawn && now - self.last_ns < REDRAW_NS {
            return;
        }
        self.last_ns = now;
        self.drawn = true;
        emit(self.out, "\r" + self.line() + "\e[K");
    }

    /// Final draw and newline; `message` replaces the bar when not "".
    pub fn finish(string message) {
        if !self.enabled {
            return;
        }
        if message != "" {
            emit(self.out, "\r" + message + "\e[K\n");
            return;
        }
        self.draw(true);
        emit(self.out, "\n");
    }

    /// Remove the bar's line.
    pub fn clear() {
        if self.enabled && self.drawn {
            emit(self.out, "\r\e[K");
        }
    }
}

/// A redrawing spinner; call `tick` from the work loop.
class Spinner {
    pub label: string,
    pub frames: Vec<string>,
    pub enabled: bool,
    out: Stream,
    start_ns: int,
    last_ns: int,
    frame: int,
}

fn spinner(string label, bool enabled) -> Spinner {
    return new Spinner(label, dots(), enabled, stderr(), mono_nanos(), 0, 0);
}

impl Spinner {
    pub fn set_label(string label) {
        self.label = label;
    }

    /// Advance and redraw, at most every 80ms.
    pub fn tick() {
        if !self.enabled {
            return;
        }
        let now = mono_nanos();
        if self.frame > 0 && now - self.last_ns < REDRAW_NS {
            return;
        }
        self.last_ns = now;
        emit(
            self.out,
            "\r" + render_spinner(self.frames, self.frame, self.label, now_ms(self.start_ns)) +
            "\e[K",
        );
        self.frame++;
    }

    /// Replace the spinner with `message` (or clear it when "").
    pub fn finish(string message) {
        if !self.enabled {
            return;
        }
        if message == "" {
            emit(self.out, "\r\e[K");
            return;
        }
        emit(self.out, "\r" + message + "\e[K\n");
    }
}
