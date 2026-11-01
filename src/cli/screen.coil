// A grid of styled cells and a renderer that writes only what changed
// between two frames. The base a TUI draws on: draw a frame into a
// `Buffer`, hand it to `Screen.present`, write the returned string.
use string::{format, to_bytes, slice_bytes};
use cli::style::Style;
use cli::style::plain;
use cli::style::sgr;
use cli::color::ColorLevel;
use cli::width::char_width;
use cli::width::decode_at;
use cli::width::seq_len;

/// One cell: the text drawn there (one character plus any zero-width
/// marks) and its style. A wide character's second cell holds "".
class Cell {
    /// The character drawn in this cell, with any zero-width marks after it;
    /// "" for the right half of a wide character.
    pub text: string,
    /// How the cell is drawn.
    pub style: Style,
}

fn blank() -> Cell {
    return new Cell(" ", plain());
}

fn same_cell(Cell a, Cell b) -> bool {
    return a.text == b.text && a.style.eq(b.style);
}

/// Box-drawing characters for `Buffer.draw_box`.
class BoxChars {
    /// Top-left corner.
    pub tl: string,
    /// Top-right corner.
    pub tr: string,
    /// Bottom-left corner.
    pub bl: string,
    /// Bottom-right corner.
    pub br: string,
    /// Horizontal edge.
    pub h: string,
    /// Vertical edge.
    pub v: string,
}

/// Thin lines with square corners: `┌─┐`.
fn light_box() -> BoxChars {
    return new BoxChars("┌", "┐", "└", "┘", "─", "│");
}

/// Thin lines with rounded corners: `╭─╮`.
fn rounded_box() -> BoxChars {
    return new BoxChars("╭", "╮", "╰", "╯", "─", "│");
}

/// Thick lines: `┏━┓`.
fn heavy_box() -> BoxChars {
    return new BoxChars("┏", "┓", "┗", "┛", "━", "┃");
}

/// Double lines: `╔═╗`.
fn double_box() -> BoxChars {
    return new BoxChars("╔", "╗", "╚", "╝", "═", "║");
}

/// Plain ASCII for terminals without box drawing: `+-+`.
fn ascii_box() -> BoxChars {
    return new BoxChars("+", "+", "+", "+", "-", "|");
}

fn piece(string s, int from, int to) -> string {
    return match slice_bytes(s, from, to) {
        Result::Ok(t) => t,
        Result::Err(_) => "",
    };
}

/// A grid of styled cells, `cols` by `rows`, addressed by 0-based column
/// `x` and row `y`. Drawing outside the grid is clipped, so callers can
/// draw without bounds checks. Render it with `render_full` /
/// `render_diff`, or let a `Screen` keep two of them.
///
/// # Examples
///
/// ```
/// use cli::screen::{buffer, light_box};
/// use cli::style::plain;
/// # use tests::assert;
/// let b = buffer(8, 3);
/// b.draw_box(0, 0, 8, 3, light_box(), plain());
/// b.put(2, 1, "hi", plain());
/// assert!(b.row_text(0) == "┌──────┐");
/// assert!(b.row_text(1) == "│ hi   │");
/// assert!(b.text().split("\n").len() == 3);
/// ```
shared class Buffer {
    /// Width in cells.
    pub cols: int,
    /// Height in cells.
    pub rows: int,
    cells: Vec<Cell>,
}

/// A `cols` by `rows` buffer of blank cells.
fn buffer(int cols, int rows) -> Buffer {
    let cells: Vec<Cell> = Vec::new();
    let i = 0;
    while i < cols * rows {
        cells.push(blank());
        i++;
    }
    return new Buffer(cols, rows, cells);
}

impl Buffer {
    /// Whether (`x`, `y`) is inside the grid.
    pub fn in_bounds(int x, int y) -> bool {
        return x >= 0 && y >= 0 && x < self.cols && y < self.rows;
    }

    /// Cell at 0-based column `x`, row `y` (a blank outside the grid).
    pub fn get(int x, int y) -> Cell {
        if !self.in_bounds(x, y) {
            return blank();
        }
        return self.cells[y * self.cols + x];
    }

    /// Set one cell. Outside the grid it is ignored.
    pub fn set(int x, int y, string text, Style style) {
        if self.in_bounds(x, y) {
            self.cells[y * self.cols + x] = new Cell(text, style);
        }
    }

    /// Reset every cell to a blank.
    pub fn clear() {
        let i = 0;
        while i < self.cells.len() {
            self.cells[i] = blank();
            i++;
        }
    }

    /// Write `s` from (`x`, `y`) on one row, clipped at the right edge.
    /// Wide characters take two cells; zero-width marks join the cell
    /// before them. Returns the column after the text.
    pub fn put(int x, int y, string s, Style style) -> int {
        let b = to_bytes(s);
        let col = x;
        let i = 0;
        let last = -1;
        while i < b.len() {
            let n = seq_len(b[i] as int);
            let cp = decode_at(b, i);
            let ch = piece(s, i, i + n);
            let w = char_width(cp);
            if w == 0 {
                if last >= 0 && self.in_bounds(last, y) {
                    let prev = self.get(last, y);
                    self.set(last, y, prev.text + ch, prev.style);
                }
            } else {
                if col + w > self.cols {
                    break;
                }
                self.set(col, y, ch, style);
                if w == 2 {
                    self.set(col + 1, y, "", style);
                }
                last = col;
                col = col + w;
            }
            i = i + n;
        }
        return col;
    }

    /// Fill a rectangle with `ch` (one column wide).
    pub fn fill(int x, int y, int w, int h, string ch, Style style) {
        let r = y;
        while r < y + h {
            let c = x;
            while c < x + w {
                self.set(c, r, ch, style);
                c++;
            }
            r++;
        }
    }

    /// A horizontal line of `w` cells of `ch` starting at (`x`, `y`).
    pub fn hline(int x, int y, int w, string ch, Style style) {
        self.fill(x, y, w, 1, ch, style);
    }

    /// A vertical line of `h` cells of `ch` starting at (`x`, `y`).
    pub fn vline(int x, int y, int h, string ch, Style style) {
        self.fill(x, y, 1, h, ch, style);
    }

    /// A box outline; `w`, `h` include the border.
    pub fn draw_box(int x, int y, int w, int h, BoxChars bc, Style style) {
        if w < 2 || h < 2 {
            return;
        }
        self.set(x, y, bc.tl, style);
        self.set(x + w - 1, y, bc.tr, style);
        self.set(x, y + h - 1, bc.bl, style);
        self.set(x + w - 1, y + h - 1, bc.br, style);
        self.hline(x + 1, y, w - 2, bc.h, style);
        self.hline(x + 1, y + h - 1, w - 2, bc.h, style);
        self.vline(x, y + 1, h - 2, bc.v, style);
        self.vline(x + w - 1, y + 1, h - 2, bc.v, style);
    }

    /// Row `y` as plain text (styles dropped), for tests and snapshots.
    pub fn row_text(int y) -> string {
        let s = "";
        let x = 0;
        while x < self.cols {
            s = s + self.get(x, y).text;
            x++;
        }
        return s;
    }

    /// Every row's text joined with "\n".
    pub fn text() -> string {
        let s = "";
        let y = 0;
        while y < self.rows {
            if y > 0 {
                s = s + "\n";
            }
            s = s + self.row_text(y);
            y++;
        }
        return s;
    }
}

fn style_switch(Style s, ColorLevel level) -> string {
    return "\e[0m" + sgr(s, level);
}

/// Escapes that turn a terminal showing `prev` into `next` (same size):
/// only changed cells are written, with cursor moves between runs and an
/// SGR change only when the style changes. Ends with attributes reset.
/// Empty when nothing changed.
///
/// # Examples
///
/// ```
/// use cli::screen::{buffer, render_diff};
/// use cli::style::plain;
/// use cli::color::ColorLevel;
/// # use tests::assert;
/// let a = buffer(10, 2);
/// let b = buffer(10, 2);
/// b.put(3, 1, "x", plain());
/// assert!(render_diff(a, a, ColorLevel::None) == "");
/// assert!(render_diff(a, b, ColorLevel::None) == "\e[2;4H\e[0mx\e[0m");
/// ```
fn render_diff(Buffer prev, Buffer next, ColorLevel level) -> string {
    let out = "";
    let cur = plain();
    let styled = false;
    let y = 0;
    while y < next.rows {
        let x = 0;
        let cursor_x = -1;
        while x < next.cols {
            let c = next.get(x, y);
            if c.text == "" || same_cell(prev.get(x, y), c) {
                x++;
                continue;
            }
            if cursor_x != x {
                out = out + format("\e[%i;%iH", y + 1, x + 1);
            }
            if !styled || !cur.eq(c.style) {
                out = out + style_switch(c.style, level);
                cur = c.style;
                styled = true;
            }
            out = out + c.text;
            let w = 1;
            if x + 1 < next.cols && next.get(x + 1, y).text == "" {
                w = 2;
            }
            x = x + w;
            cursor_x = x;
        }
        y++;
    }
    if styled {
        out = out + "\e[0m";
    }
    return out;
}

/// The whole buffer: clear, then every row.
fn render_full(Buffer next, ColorLevel level) -> string {
    return "\e[H\e[2J" + render_diff(buffer(next.cols, next.rows), next, level);
}

/// Double-buffered presenter. Draw into `frame()`, then write what
/// `present()` returns: the first frame in full, later frames as the
/// difference from the one before.
///
/// # Examples
///
/// ```
/// use cli::screen::screen;
/// use cli::style::plain;
/// use cli::color::ColorLevel;
/// # use tests::assert;
/// let s = screen(20, 5, ColorLevel::Basic);
/// s.frame().put(0, 0, "hello", plain());
/// let first = s.present();
/// assert!(first.starts_with("\e[H\e[2J"));
/// s.frame().put(0, 0, "hello", plain());
/// assert!(s.present() == "");
/// ```
class Screen {
    front: Buffer,
    back: Buffer,
    /// The colour level frames are rendered at.
    pub level: ColorLevel,
    full: bool,
}

/// A `cols` by `rows` screen rendering at `level`; the first `present`
/// redraws everything.
fn screen(int cols, int rows, ColorLevel level) -> Screen {
    return new Screen(buffer(cols, rows), buffer(cols, rows), level, true);
}

impl Screen {
    /// The buffer to draw the next frame into (cleared).
    pub fn frame() -> Buffer {
        self.back.clear();
        return self.back;
    }

    /// Escapes for the drawn frame (the full screen the first time and
    /// after `resize`/`invalidate`, else only the changes).
    pub fn present() -> string {
        let out = "";
        if self.full {
            out = render_full(self.back, self.level);
            self.full = false;
        } else {
            out = render_diff(self.front, self.back, self.level);
        }
        let t = self.front;
        self.front = self.back;
        self.back = t;
        return out;
    }

    /// Redraw everything on the next `present` (after the terminal was
    /// cleared by someone else).
    pub fn invalidate() {
        self.full = true;
    }

    /// New size: both buffers are replaced and the next `present` redraws
    /// everything.
    pub fn resize(int cols, int rows) {
        self.front = buffer(cols, rows);
        self.back = buffer(cols, rows);
        self.full = true;
    }

    /// Current width in cells.
    pub fn cols() -> int {
        return self.back.cols;
    }

    /// Current height in cells.
    pub fn rows() -> int {
        return self.back.rows;
    }
}
