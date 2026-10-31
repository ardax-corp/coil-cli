// Escape-sequence builders. Pure strings: write them with `io::sync::print`
// or collect them in a buffer and write once per frame.
use string::format;

/// The escape character that starts every sequence.
const ESC = "\e";

/// Control Sequence Introducer, `ESC [`.
const CSI = "\e[";

/// Operating System Command introducer, `ESC ]`.
const OSC = "\e]";

/// String Terminator, `ESC \`, which ends an OSC sequence.
const ST = "\e\\";

/// Move the cursor to 1-based `row`, `col`.
///
/// # Examples
///
/// ```
/// use cli::ansi::{move_to, clear_line, up};
/// # use tests::assert;
/// assert!(move_to(3, 10) == "\e[3;10H");
/// assert!(up(2) + clear_line() == "\e[2A\e[2K");
/// assert!(up(0) == "");
/// ```
fn move_to(int row, int col) -> string {
    return format("\e[%i;%iH", row, col);
}

/// Move to 1-based `col` in the current row.
fn column(int col) -> string {
    return format("\e[%iG", col);
}

/// Move the cursor up `n` rows; empty when `n <= 0`.
fn up(int n) -> string {
    if n <= 0 {
        return "";
    }
    return format("\e[%iA", n);
}

/// Move the cursor down `n` rows; empty when `n <= 0`.
fn down(int n) -> string {
    if n <= 0 {
        return "";
    }
    return format("\e[%iB", n);
}

/// Move the cursor right `n` columns; empty when `n <= 0`.
fn right(int n) -> string {
    if n <= 0 {
        return "";
    }
    return format("\e[%iC", n);
}

/// Move the cursor left `n` columns; empty when `n <= 0`.
fn left(int n) -> string {
    if n <= 0 {
        return "";
    }
    return format("\e[%iD", n);
}

/// Move to the start of the line `n` lines down.
fn next_line(int n) -> string {
    return format("\e[%iE", n);
}

/// Move to the start of the line `n` lines up.
fn prev_line(int n) -> string {
    return format("\e[%iF", n);
}

/// Move the cursor to the top-left corner.
fn home() -> string {
    return "\e[H";
}

/// Save the cursor position (and attributes); `restore_cursor` goes back.
fn save_cursor() -> string {
    return "\e7";
}

/// Return to the position saved by `save_cursor`.
fn restore_cursor() -> string {
    return "\e8";
}

/// Hide the cursor.
fn hide_cursor() -> string {
    return "\e[?25l";
}

/// Show the cursor again.
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
    /// The terminal's configured shape.
    Default = 0,
    /// A blinking block.
    BlinkingBlock = 1,
    /// A steady block.
    Block = 2,
    /// A blinking underline.
    BlinkingUnderline = 3,
    /// A steady underline.
    Underline = 4,
    /// A blinking vertical bar.
    BlinkingBar = 5,
    /// A steady vertical bar (the usual insert-mode cursor).
    Bar = 6,
}

/// Set the cursor shape (DECSCUSR).
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

/// Clear from the start of the screen to the cursor.
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

/// Clear from the start of the line to the cursor.
fn clear_to_bol() -> string {
    return "\e[1K";
}

/// Scroll the region up by `n` lines (new blank lines at the bottom).
fn scroll_up(int n) -> string {
    return format("\e[%iS", n);
}

/// Scroll the region down by `n` lines (new blank lines at the top).
fn scroll_down(int n) -> string {
    return format("\e[%iT", n);
}

/// Limit scrolling to 1-based rows `top`..=`bottom`.
fn scroll_region(int top, int bottom) -> string {
    return format("\e[%i;%ir", top, bottom);
}

/// Scroll the whole screen again (undo `scroll_region`).
fn reset_scroll_region() -> string {
    return "\e[r";
}

/// Switch to the alternate screen, as full-screen programs do; the
/// normal screen and its scrollback come back with `leave_alt_screen`.
fn enter_alt_screen() -> string {
    return "\e[?1049h";
}

/// Switch back from the alternate screen.
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

/// Turn off every mouse reporting mode turned on above.
fn disable_mouse() -> string {
    return "\e[?1006l\e[?1003l\e[?1002l\e[?1000l";
}

/// Bracketed paste: pasted text arrives between markers, as one event.
fn enable_paste() -> string {
    return "\e[?2004h";
}

/// Turn bracketed paste off.
fn disable_paste() -> string {
    return "\e[?2004l";
}

/// Report focus in / out (`Event::Focus`).
fn enable_focus() -> string {
    return "\e[?1004h";
}

/// Stop focus reports.
fn disable_focus() -> string {
    return "\e[?1004l";
}

/// Line wrapping at the right margin (on by default).
fn enable_wrap() -> string {
    return "\e[?7h";
}

/// Turn line wrapping off: text past the right margin overwrites the last
/// column.
fn disable_wrap() -> string {
    return "\e[?7l";
}

/// Begin synchronized output (mode 2026): the terminal holds the screen
/// until `end_sync`, then shows the frame at once. Ignored where
/// unsupported.
fn begin_sync() -> string {
    return "\e[?2026h";
}

/// End synchronized output and show the frame.
fn end_sync() -> string {
    return "\e[?2026l";
}

/// Window title.
fn set_title(string title) -> string {
    return OSC + "2;" + title + ST;
}

/// A clickable link (OSC 8). Terminals without support show `text`.
///
/// # Examples
///
/// ```
/// use cli::ansi::hyperlink;
/// use cli::style::strip;
/// # use tests::assert;
/// let link = hyperlink("https://example.com", "docs");
/// assert!(strip(link) == "docs");
/// ```
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
