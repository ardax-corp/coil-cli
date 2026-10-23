use tests::assert;
use cli::color::{ColorLevel, detect_color_level};

fn none() -> Option<string> {
    return Option::None;
}

fn some(string s) -> Option<string> {
    return Option::Some(s);
}

test("NO_COLOR wins") {
    assert!(
        detect_color_level(true, some("1"), some("3"), some("truecolor"), some("xterm-256color")) ==
        ColorLevel::None,
    );
}

test("empty NO_COLOR is ignored") {
    assert!(detect_color_level(true, some(""), none(), none(), some("xterm")) == ColorLevel::Basic);
}

test("not a tty means no colour unless forced") {
    assert!(
        detect_color_level(false, none(), none(), some("truecolor"), some("xterm-256color")) ==
        ColorLevel::None,
    );
    assert!(
        detect_color_level(false, none(), some("1"), none(), some("xterm")) == ColorLevel::Basic,
    );
    assert!(detect_color_level(false, none(), some("3"), none(), none()) == ColorLevel::TrueColor);
    assert!(
        detect_color_level(true, none(), some("0"), some("truecolor"), none()) == ColorLevel::None,
    );
}

test("COLORTERM and TERM refine the level") {
    assert!(
        detect_color_level(true, none(), none(), some("truecolor"), some("xterm")) ==
        ColorLevel::TrueColor,
    );
    assert!(
        detect_color_level(true, none(), none(), some("24bit"), none()) == ColorLevel::TrueColor,
    );
    assert!(
        detect_color_level(true, none(), none(), none(), some("xterm-256color")) ==
        ColorLevel::Ansi256,
    );
    assert!(detect_color_level(true, none(), none(), none(), some("xterm")) == ColorLevel::Basic);
    assert!(detect_color_level(true, none(), none(), none(), some("dumb")) == ColorLevel::None);
}
