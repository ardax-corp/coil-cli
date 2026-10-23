// Colours and text attributes as SGR escapes, downgraded to what the
// terminal supports (`cli::term::ColorLevel`), and `strip` to remove them.
use string::{format, to_bytes, from_bytes};
use cli::term::{ColorLevel, color_level};

enum Color {
    /// The terminal's own foreground / background.
    Default,
    /// One of the 16 standard colours: 0-7 normal, 8-15 bright.
    Ansi(int),
    /// xterm 256-colour palette index.
    Indexed(int),
    /// 24-bit colour, each channel 0-255.
    Rgb(int, int, int),
}

fn black() -> Color {
    return Color::Ansi(0);
}

fn red() -> Color {
    return Color::Ansi(1);
}

fn green() -> Color {
    return Color::Ansi(2);
}

fn yellow() -> Color {
    return Color::Ansi(3);
}

fn blue() -> Color {
    return Color::Ansi(4);
}

fn magenta() -> Color {
    return Color::Ansi(5);
}

fn cyan() -> Color {
    return Color::Ansi(6);
}

fn white() -> Color {
    return Color::Ansi(7);
}

fn bright_black() -> Color {
    return Color::Ansi(8);
}

fn bright_red() -> Color {
    return Color::Ansi(9);
}

fn bright_green() -> Color {
    return Color::Ansi(10);
}

fn bright_yellow() -> Color {
    return Color::Ansi(11);
}

fn bright_blue() -> Color {
    return Color::Ansi(12);
}

fn bright_magenta() -> Color {
    return Color::Ansi(13);
}

fn bright_cyan() -> Color {
    return Color::Ansi(14);
}

fn bright_white() -> Color {
    return Color::Ansi(15);
}

fn rgb(int r, int g, int b) -> Color {
    return Color::Rgb(clamp(r), clamp(g), clamp(b));
}

fn clamp(int v) -> int {
    if v < 0 {
        return 0;
    }
    if v > 255 {
        return 255;
    }
    return v;
}

fn hex_digit(byte c) -> int {
    let n = c as int;
    if n >= 48 && n <= 57 {
        return n - 48;
    }
    if n >= 97 && n <= 102 {
        return n - 87;
    }
    if n >= 65 && n <= 70 {
        return n - 55;
    }
    return -1;
}

/// `#rrggbb`, `rrggbb`, `#rgb` or `rgb`.
fn hex(string s) -> Option<Color> {
    let b = to_bytes(s);
    let start = 0;
    if b.len() > 0 && b[0] as int == 35 {
        start = 1;
    }
    let n = b.len() - start;
    let d: Vec<int> = Vec::new();
    let i = start;
    while i < b.len() {
        let v = hex_digit(b[i]);
        if v < 0 {
            return Option::None;
        }
        d.push(v);
        i++;
    }
    if n == 6 {
        return Option::Some(Color::Rgb(d[0] * 16 + d[1], d[2] * 16 + d[3], d[4] * 16 + d[5]));
    }
    if n == 3 {
        return Option::Some(Color::Rgb(d[0] * 17, d[1] * 17, d[2] * 17));
    }
    return Option::None;
}

const BOLD = 1;

const DIM = 2;

const ITALIC = 4;

const UNDERLINE = 8;

const BLINK = 16;

const REVERSE = 32;

const HIDDEN = 64;

const STRIKE = 128;

/// Foreground, background and attributes. Builder methods return a new
/// `Style`, so a shared style is never changed under its users.
class Style {
    pub fg: Color,
    pub bg: Color,
    pub attrs: int,
}

fn plain() -> Style {
    return new Style(Color::Default, Color::Default, 0);
}

fn fg(Color c) -> Style {
    return new Style(c, Color::Default, 0);
}

fn bg(Color c) -> Style {
    return new Style(Color::Default, c, 0);
}

impl Style {
    pub fn with_attr(int bit) -> Style {
        return new Style(self.fg, self.bg, self.attrs | bit);
    }

    pub fn fg(Color c) -> Style {
        return new Style(c, self.bg, self.attrs);
    }

    pub fn bg(Color c) -> Style {
        return new Style(self.fg, c, self.attrs);
    }

    pub fn bold() -> Style {
        return self.with_attr(BOLD);
    }

    pub fn dim() -> Style {
        return self.with_attr(DIM);
    }

    pub fn italic() -> Style {
        return self.with_attr(ITALIC);
    }

    pub fn underline() -> Style {
        return self.with_attr(UNDERLINE);
    }

    pub fn blink() -> Style {
        return self.with_attr(BLINK);
    }

    pub fn reverse() -> Style {
        return self.with_attr(REVERSE);
    }

    pub fn hidden() -> Style {
        return self.with_attr(HIDDEN);
    }

    pub fn strike() -> Style {
        return self.with_attr(STRIKE);
    }

    pub fn has(int bit) -> bool {
        return (self.attrs & bit) != 0;
    }

    pub fn is_plain() -> bool {
        return self.attrs == 0 && is_default(self.fg) && is_default(self.bg);
    }

    /// `self` with `other`'s colours where `other` sets them, and both
    /// sets of attributes.
    pub fn merge(Style other) -> Style {
        let f = self.fg;
        if !is_default(other.fg) {
            f = other.fg;
        }
        let b = self.bg;
        if !is_default(other.bg) {
            b = other.bg;
        }
        return new Style(f, b, self.attrs | other.attrs);
    }

    pub fn eq(Style other) -> bool {
        return self.attrs == other.attrs &&
               color_eq(self.fg, other.fg) &&
               color_eq(self.bg, other.bg);
    }
}

fn is_default(Color c) -> bool {
    return match c {
        Color::Default => true,
        default => false,
    };
}

fn color_eq(Color a, Color b) -> bool {
    return match a {
        Color::Default => is_default(b),
        Color::Ansi(x) => match b {
            Color::Ansi(y) => x == y,
            default => false,
        },
        Color::Indexed(x) => match b {
            Color::Indexed(y) => x == y,
            default => false,
        },
        Color::Rgb(r, g, bl) => match b {
            Color::Rgb(r2, g2, b2) => r == r2 && g == g2 && bl == b2,
            default => false,
        },
    };
}

// RGB of the 16 standard colours (xterm defaults), for downgrading.
fn ansi_rgb(int i) -> (int, int, int) {
    return match i {
        0 => (0, 0, 0),
        1 => (205, 0, 0),
        2 => (0, 205, 0),
        3 => (205, 205, 0),
        4 => (0, 0, 238),
        5 => (205, 0, 205),
        6 => (0, 205, 205),
        7 => (229, 229, 229),
        8 => (127, 127, 127),
        9 => (255, 0, 0),
        10 => (0, 255, 0),
        11 => (255, 255, 0),
        12 => (92, 92, 255),
        13 => (255, 0, 255),
        14 => (0, 255, 255),
        default => (255, 255, 255),
    };
}

fn cube_level(int i) -> int {
    if i == 0 {
        return 0;
    }
    return 55 + i * 40;
}

/// RGB of a 256-palette index.
fn indexed_rgb(int i) -> (int, int, int) {
    if i < 16 {
        return ansi_rgb(i);
    }
    if i >= 232 {
        let v = 8 + (i - 232) * 10;
        return (v, v, v);
    }
    let n = i - 16;
    return (cube_level(n / 36), cube_level((n / 6) % 6), cube_level(n % 6));
}

fn dist(int r, int g, int b, (int, int, int) c) -> int {
    let (r2, g2, b2) = c;
    let dr = r - r2;
    let dg = g - g2;
    let db = b - b2;
    return dr * dr + dg * dg + db * db;
}

fn cube_index(int v) -> int {
    if v < 48 {
        return 0;
    }
    if v < 115 {
        return 1;
    }
    return (v - 35) / 40;
}

/// Nearest 256-palette index (6x6x6 cube or grey ramp).
fn rgb_to_indexed(int r, int g, int b) -> int {
    let ri = cube_index(r);
    let gi = cube_index(g);
    let bi = cube_index(b);
    let cube = 16 + 36 * ri + 6 * gi + bi;
    let avg = (r + g + b) / 3;
    let gi2 = 23;
    if avg < 238 {
        gi2 = (avg - 3) / 10;
    }
    if gi2 < 0 {
        gi2 = 0;
    }
    let grey = 232 + gi2;
    if dist(r, g, b, indexed_rgb(grey)) < dist(r, g, b, indexed_rgb(cube)) {
        return grey;
    }
    return cube;
}

/// Nearest of the 16 standard colours.
fn rgb_to_ansi(int r, int g, int b) -> int {
    let best = 0;
    let best_d = dist(r, g, b, ansi_rgb(0));
    let i = 1;
    while i < 16 {
        let d = dist(r, g, b, ansi_rgb(i));
        if d < best_d {
            best = i;
            best_d = d;
        }
        i++;
    }
    return best;
}

/// `c` reduced to what `level` can show. `ColorLevel::None` gives `Default`.
fn downgrade(Color c, ColorLevel level) -> Color {
    if level == ColorLevel::None {
        return Color::Default;
    }
    return match c {
        Color::Indexed(i) => {
            if level == ColorLevel::Basic && i >= 16 {
                let (r, g, b) = indexed_rgb(i);
                return Color::Ansi(rgb_to_ansi(r, g, b));
            }
            if i < 16 {
                return Color::Ansi(i);
            }
            return c;
        },
        Color::Rgb(r, g, b) => {
            if level == ColorLevel::Basic {
                return Color::Ansi(rgb_to_ansi(r, g, b));
            }
            if level == ColorLevel::Ansi256 {
                return Color::Indexed(rgb_to_indexed(r, g, b));
            }
            return c;
        },
        default => c,
    };
}

fn color_params(Color c, bool bg) -> string {
    let base = 30;
    if bg {
        base = 40;
    }
    return match c {
        Color::Default => format("%i", base + 9),
        Color::Ansi(i) => {
            if i >= 8 {
                return format("%i", base + 60 + i - 8);
            }
            return format("%i", base + i);
        },
        Color::Indexed(i) => format("%i;5;%i", base + 8, i),
        Color::Rgb(r, g, b) => format("%i;2;%i;%i;%i", base + 8, r, g, b),
    };
}

fn push_param(string acc, string p) -> string {
    if acc == "" {
        return p;
    }
    return acc + ";" + p;
}

/// SGR escape that switches to `s` from the default attributes, at
/// `level`. Empty when there is nothing to set.
fn sgr(Style s, ColorLevel level) -> string {
    let p = "";
    if s.has(BOLD) {
        p = push_param(p, "1");
    }
    if s.has(DIM) {
        p = push_param(p, "2");
    }
    if s.has(ITALIC) {
        p = push_param(p, "3");
    }
    if s.has(UNDERLINE) {
        p = push_param(p, "4");
    }
    if s.has(BLINK) {
        p = push_param(p, "5");
    }
    if s.has(REVERSE) {
        p = push_param(p, "7");
    }
    if s.has(HIDDEN) {
        p = push_param(p, "8");
    }
    if s.has(STRIKE) {
        p = push_param(p, "9");
    }
    let f = downgrade(s.fg, level);
    if !is_default(f) {
        p = push_param(p, color_params(f, false));
    }
    let b = downgrade(s.bg, level);
    if !is_default(b) {
        p = push_param(p, color_params(b, true));
    }
    if p == "" {
        return "";
    }
    return "\e[" + p + "m";
}

/// `text` in style `s`, followed by a reset. At `ColorLevel::None`, or
/// with nothing to set, `text` is returned as is, so piped output stays
/// clean.
fn paint_at(Style s, string text, ColorLevel level) -> string {
    if level == ColorLevel::None {
        return text;
    }
    let on = sgr(s, level);
    if on == "" {
        return text;
    }
    return on + text + "\e[0m";
}

/// Paints at a fixed colour level. `Painter::detect()` reads the
/// environment once (needs `--allow-env`).
class Painter {
    pub level: ColorLevel,
}

impl Painter {
    pub static fn at(ColorLevel level) -> Painter {
        return new Painter(level);
    }

    pub static fn detect() -> Painter {
        return new Painter(color_level());
    }

    pub fn enabled() -> bool {
        return self.level != ColorLevel::None;
    }

    pub fn paint(Style s, string text) -> string {
        return paint_at(s, text, self.level);
    }

    // Not `fg`: a 2-arg method named like the free `fg` breaks calls to
    // it (coil-lang#1981).
    pub fn color(Color c, string text) -> string {
        return paint_at(fg(c), text, self.level);
    }

    pub fn bold(string text) -> string {
        return paint_at(plain().bold(), text, self.level);
    }

    pub fn dim(string text) -> string {
        return paint_at(plain().dim(), text, self.level);
    }
}

/// `text` without escape sequences (CSI, OSC, and two-byte ESC forms).
fn strip(string text) -> string {
    let b = to_bytes(text);
    let out: Vec<byte> = Vec::new();
    let n = b.len();
    let i = 0;
    while i < n {
        let c = b[i] as int;
        if c != 27 {
            out.push(b[i]);
            i++;
            continue;
        }
        if i + 1 >= n {
            break;
        }
        let k = b[i + 1] as int;
        if k == 91 {
            // CSI: parameters and intermediates, then a final byte 0x40-0x7e.
            i = i + 2;
            while i < n && !((b[i] as int) >= 64 && (b[i] as int) <= 126) {
                i++;
            }
            i++;
        } else if k == 93 || k == 80 || k == 95 {
            // OSC / DCS / APC: up to BEL or ST.
            i = i + 2;
            while i < n {
                let d = b[i] as int;
                if d == 7 {
                    i++;
                    break;
                }
                if d == 27 && i + 1 < n && (b[i + 1] as int) == 92 {
                    i = i + 2;
                    break;
                }
                i++;
            }
        } else {
            i = i + 2;
        }
    }
    return match from_bytes(out) {
        Result::Ok(s) => s,
        Result::Err(_) => text,
    };
}
