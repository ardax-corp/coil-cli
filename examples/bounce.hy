// A full-screen program: the alternate screen, the cell buffer with diff
// rendering, timed events and resizes. Arrows steer, space pauses, q quits.
//
//   coil --allow-env --root <stdlib>/src --root src examples/bounce.hy
use io::stdin;
use io::stdout;
use io::tty::TtyError;
use string::format;
use cli::ansi::enter_alt_screen;
use cli::ansi::leave_alt_screen;
use cli::ansi::hide_cursor;
use cli::ansi::show_cursor;
use cli::color::color_level_from_env;
use cli::events::events;
use cli::keys::Event;
use cli::keys::is_key;
use cli::screen::Screen;
use cli::screen::screen;
use cli::screen::rounded_box;
use cli::style::fg;
use cli::style::plain;
use cli::style::cyan;
use cli::style::yellow;
use cli::term::RawMode;
use cli::term::raw_mode;
use cli::term::put;
use cli::term::size_or;

fn run(Screen scr) -> Result<(), TtyError> {
    let out = stdout();
    let ev = events();
    let x = 2;
    let y = 2;
    let dx = 1;
    let dy = 1;
    let paused = false;
    let frames = 0;
    while true {
        let got = ev.next(50)?;
        match got {
            Option::Some(Event::Resize(c, r)) => scr.resize(c, r),
            Option::Some(e) => {
                if is_key(e, "q") || is_key(e, "ctrl+c") || is_key(e, "esc") {
                    return;
                }
                if is_key(e, "space") {
                    paused = !paused;
                }
                if is_key(e, "left") {
                    dx = -1;
                }
                if is_key(e, "right") {
                    dx = 1;
                }
                if is_key(e, "up") {
                    dy = -1;
                }
                if is_key(e, "down") {
                    dy = 1;
                }
            },
            Option::None => {
                if ev.eof {
                    return;
                }
            },
        }
        let w = scr.cols();
        let h = scr.rows();
        if !paused {
            x = x + dx;
            y = y + dy;
            if x <= 1 || x >= w - 3 {
                dx = -dx;
            }
            if y <= 1 || y >= h - 2 {
                dy = -dy;
            }
            frames++;
        }
        let b = scr.frame();
        b.draw_box(0, 0, w, h, rounded_box(), fg(cyan()));
        b.put(2, 0, format(" bounce · frame %i · q quits ", frames), plain());
        b.put(x, y, "●", fg(yellow()).bold());
        put(out, scr.present())?;
    }
}

fn main() -> Result<(), TtyError> {
    let out = stdout();
    let raw = raw_mode(stdin())?;
    let sz = size_or(out, 80, 24);
    let (c, r) = sz;
    let scr = screen(c, r, color_level_from_env(true));
    put(out, enter_alt_screen() + hide_cursor())?;
    let result = run(scr);
    put(out, show_cursor() + leave_alt_screen())?;
    raw.leave()?;
    return result?;
}
