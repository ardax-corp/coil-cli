// How many colours output may use, from the conventional environment
// variables. The terminal check itself is the caller's (`tty`).
use env::var;
use text::Searchable;

/// How many colours output may use.
#[repr(int)]
#[derive(Eq, Ord)]
enum ColorLevel {
    /// No colour: plain text only.
    None = 0,
    /// The 16 standard ANSI colours.
    Basic = 1,
    /// The xterm 256-colour palette.
    Ansi256 = 2,
    /// 24-bit RGB.
    TrueColor = 3,
}

/// Colour level for a stream that is (`tty`) or is not a terminal, from
/// the given values of the colour environment variables (`None` when a
/// variable is unset).
///
/// `NO_COLOR` (any non-empty value) turns colour off; `FORCE_COLOR` turns
/// it on even off a terminal (`0` or `false` off, `1` basic, `2` 256, `3`
/// truecolor); `COLORTERM=truecolor|24bit`, a `TERM` ending in
/// `-256color` or `-direct`, or `TERM=dumb` refine the guess. Use
/// `color_level_from_env` to read the real environment.
///
/// # Examples
///
/// ```
/// use cli::color::{ColorLevel, detect_color_level};
/// # use tests::assert;
/// let none: Option<string> = Option::None;
/// let piped = detect_color_level(false, none, none, none, Option::Some("xterm"));
/// assert!(piped == ColorLevel::None);
/// let term = detect_color_level(true, none, none, Option::Some("truecolor"), none);
/// assert!(term == ColorLevel::TrueColor);
/// let off = detect_color_level(true, Option::Some("1"), none, none, none);
/// assert!(off == ColorLevel::None);
/// ```
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
    if t.ends_with("-256color") || t.ends_with("-direct") {
        return ColorLevel::Ansi256;
    }
    return ColorLevel::Basic;
}

fn env_opt(string name) -> Option<string> {
    return match var(name) {
        Result::Ok(v) => Option::Some(v),
        Result::Err(_) => Option::None,
    };
}

/// `detect_color_level` with the real environment. Needs `--allow-env`.
/// Pass `stdout_is_tty()` (from `cli::term`) for ordinary output.
fn color_level_from_env(bool tty) -> ColorLevel {
    return detect_color_level(
        tty,
        env_opt("NO_COLOR"),
        env_opt("FORCE_COLOR"),
        env_opt("COLORTERM"),
        env_opt("TERM"),
    );
}
