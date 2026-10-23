use tests::assert;
use cli::term::ColorLevel;
use cli::style::Color;
use cli::style::Style;
use cli::style::Painter;
use cli::style::plain;
use cli::style::fg;
use cli::style::bg;
use cli::style::rgb;
use cli::style::hex;
use cli::style::red;
use cli::style::bright_blue;
use cli::style::sgr;
use cli::style::paint_at;
use cli::style::downgrade;
use cli::style::strip;
use cli::style::rgb_to_indexed;
use cli::style::rgb_to_ansi;
use cli::style::color_eq;
use cli::ansi::move_to;
use cli::ansi::hyperlink;
use cli::ansi::set_title;
use cli::ansi::clear_line;
use cli::ansi::cursor_shape;
use cli::ansi::CursorShape;
use cli::ansi::up;

test("sgr for attributes and basic colours") {
    assert!(sgr(plain().bold().underline(), ColorLevel::TrueColor) == "\e[1;4m");
    assert!(sgr(fg(red()), ColorLevel::Basic) == "\e[31m");
    assert!(sgr(bg(bright_blue()), ColorLevel::Basic) == "\e[104m");
    assert!(sgr(plain(), ColorLevel::TrueColor) == "");
}

test("sgr for 256 and rgb") {
    assert!(sgr(fg(Color::Indexed(208)), ColorLevel::Ansi256) == "\e[38;5;208m");
    assert!(
        sgr(fg(rgb(1, 2, 3)).bg(rgb(4, 5, 300)), ColorLevel::TrueColor) ==
        "\e[38;2;1;2;3;48;2;4;5;255m",
    );
}

test("rgb downgrades by level") {
    let c = rgb(255, 0, 0);
    assert!(color_eq(downgrade(c, ColorLevel::TrueColor), c));
    assert!(color_eq(downgrade(c, ColorLevel::Ansi256), Color::Indexed(196)));
    assert!(color_eq(downgrade(c, ColorLevel::Basic), Color::Ansi(9)));
    assert!(color_eq(downgrade(c, ColorLevel::None), Color::Default));
    assert!(color_eq(downgrade(Color::Indexed(3), ColorLevel::Basic), Color::Ansi(3)));
    assert!(color_eq(downgrade(Color::Indexed(232), ColorLevel::Basic), Color::Ansi(0)));
}

test("grey picks the grey ramp") {
    assert!(rgb_to_indexed(128, 128, 128) == 244);
    assert!(rgb_to_indexed(0, 0, 0) == 16);
    assert!(rgb_to_indexed(255, 255, 255) == 231);
    assert!(rgb_to_ansi(250, 250, 250) == 15);
}

test("hex colours") {
    assert!(
        match hex("#ff8800") {
            Option::Some(Color::Rgb(255, 136, 0)) => true,
            default => false,
        },
    );
    assert!(
        match hex("0f0") {
            Option::Some(Color::Rgb(0, 255, 0)) => true,
            default => false,
        },
    );
    assert!(match hex("#12345") {
        Option::None => true,
        default => false,
    });
    assert!(match hex("zzzzzz") {
        Option::None => true,
        default => false,
    });
}

test("paint resets and stays clean without colour") {
    assert!(paint_at(fg(red()).bold(), "hi", ColorLevel::Basic) == "\e[1;31mhi\e[0m");
    assert!(paint_at(fg(red()), "hi", ColorLevel::None) == "hi");
    assert!(paint_at(plain(), "hi", ColorLevel::TrueColor) == "hi");
    let p = Painter::at(ColorLevel::Basic);
    assert!(p.bold("x") == "\e[1mx\e[0m");
    assert!(!Painter::at(ColorLevel::None).enabled());
}

test("styles are values") {
    let base = fg(red());
    let b = base.bold();
    assert!(!base.has(1));
    assert!(b.has(1));
    let m = base.merge(bg(rgb(1, 1, 1)).italic());
    assert!(m.has(4));
    assert!(color_eq(m.fg, red()));
    assert!(base.eq(fg(red())));
    assert!(!base.eq(b));
}

test("strip removes escapes") {
    assert!(strip("\e[1;31mred\e[0m plain") == "red plain");
    assert!(strip(hyperlink("https://x", "link")) == "link");
    assert!(strip(set_title("t") + "a") == "a");
    assert!(strip(move_to(1, 2) + clear_line() + "é") == "é");
    assert!(strip("a\e7b") == "ab");
}

test("ansi builders") {
    assert!(move_to(3, 4) == "\e[3;4H");
    assert!(cursor_shape(CursorShape::Bar) == "\e[6 q");
    assert!(up(0) == "");
    assert!(up(2) == "\e[2A");
}
