// Escape-sequence builders. Pure strings: write them with `io::sync::print`
// or collect them in a buffer and write once per frame.
use string::format;

const ESC = "\e";

const CSI = "\e[";

const OSC = "\e]";

const ST = "\e\\";

/// Move the cursor to 1-based `row`, `col`.
fn move_to(int row, int col) -> string {
    return format("\e[%i;%iH", row, col);
}

/// Move to 1-based `col` in the current row.
fn column(int col) -> string {
    return format("\e[%iG", col);
}

fn up(int n) -> string {
    if n <= 0 {
        return "";
    }
    return format("\e[%iA", n);
}

fn down(int n) -> string {
    if n <= 0 {
        return "";
    }
    return format("\e[%iB", n);
}

fn right(int n) -> string {
    if n <= 0 {
        return "";
    }
    return format("\e[%iC", n);
}

fn left(int n) -> string {
    if n <= 0 {
        return "";
    }
    return format("\e[%iD", n);
}

/// Start of the line `n` lines down / up.
fn next_line(int n) -> string {
    return format("\e[%iE", n);
}

fn prev_line(int n) -> string {
    return format("\e[%iF", n);
}

fn home() -> string {
    return "\e[H";
}

fn save_cursor() -> string {
    return "\e7";
}

fn restore_cursor() -> string {
    return "\e8";
}

fn hide_cursor() -> string {
    return "\e[?25l";
}

fn show_cursor() -> string {
    return "\e[?25h";
}

/// Ask the terminal for the cursor position; it answers `ESC [ row ; col R`
/// on stdin (decoded by `cli::keys` as `Event::CursorPos`).
fn query_cursor() -> string {
    return "\e[6n";
}

/// Cursor shapes for `cursor_shape`.
#[repr(int)]
enum CursorShape {
    Default = 0,
    BlinkingBlock = 1,
    Block = 2,
    BlinkingUnderline = 3,
    Underline = 4,
    BlinkingBar = 5,
    Bar = 6,
}

fn cursor_shape(CursorShape shape) -> string {
    return format("\e[%i q", shape);
}

/// Clear the whole screen (cursor does not move).
fn clear_screen() -> string {
    return "\e[2J";
}

/// Clear from the cursor to the end of the screen.
fn clear_below() -> string {
    return "\e[J";
}

fn clear_above() -> string {
    return "\e[1J";
}

/// Clear the whole current line.
fn clear_line() -> string {
    return "\e[2K";
}

/// Clear from the cursor to the end of the line.
fn clear_to_eol() -> string {
    return "\e[K";
}

fn clear_to_bol() -> string {
    return "\e[1K";
}

/// Scroll the region up / down by `n` lines.
fn scroll_up(int n) -> string {
    return format("\e[%iS", n);
}

fn scroll_down(int n) -> string {
    return format("\e[%iT", n);
}

/// Limit scrolling to 1-based rows `top`..=`bottom`.
fn scroll_region(int top, int bottom) -> string {
    return format("\e[%i;%ir", top, bottom);
}

fn reset_scroll_region() -> string {
    return "\e[r";
}

/// Switch to the alternate screen (full-screen programs) and back.
fn enter_alt_screen() -> string {
    return "\e[?1049h";
}

fn leave_alt_screen() -> string {
    return "\e[?1049l";
}

/// Mouse reporting: clicks, drags and wheel in SGR encoding (1006).
fn enable_mouse() -> string {
    return "\e[?1000h\e[?1002h\e[?1006h";
}

/// Also report motion with no button held (1003).
fn enable_mouse_motion() -> string {
    return "\e[?1000h\e[?1003h\e[?1006h";
}

fn disable_mouse() -> string {
    return "\e[?1006l\e[?1003l\e[?1002l\e[?1000l";
}

/// Bracketed paste: pasted text arrives between markers, as one event.
fn enable_paste() -> string {
    return "\e[?2004h";
}

fn disable_paste() -> string {
    return "\e[?2004l";
}

/// Focus in / out reports.
fn enable_focus() -> string {
    return "\e[?1004h";
}

fn disable_focus() -> string {
    return "\e[?1004l";
}

/// Line wrapping at the right margin (on by default).
fn enable_wrap() -> string {
    return "\e[?7h";
}

fn disable_wrap() -> string {
    return "\e[?7l";
}

/// Synchronized output (2026): the terminal shows the frame at once.
fn begin_sync() -> string {
    return "\e[?2026h";
}

fn end_sync() -> string {
    return "\e[?2026l";
}

/// Window title.
fn set_title(string title) -> string {
    return OSC + "2;" + title + ST;
}

/// A clickable link (OSC 8). Terminals without support show `text`.
fn hyperlink(string url, string text) -> string {
    return OSC + "8;;" + url + ST + text + OSC + "8;;" + ST;
}

/// Ring the bell.
fn bell() -> string {
    return "\x07";
}

/// Reset all attributes (colour, bold, …).
fn reset() -> string {
    return "\e[0m";
}
