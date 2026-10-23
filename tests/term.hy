use tests::assert;
use cli::term::{ColorLevel, Size, detect_color_level, is_tty, is_raw, raw_mode, read_bytes, resized, size, size_or, TermError};

fn none() -> Option<string> {
    return Option::None;
}

fn some(string s) -> Option<string> {
    return Option::Some(s);
}

test("not raw until asked") {
    assert!(!is_raw());
}

test("size_or falls back without a terminal") {
    let s = size_or(80, 24);
    assert!(s.cols > 0);
    assert!(s.rows > 0);
}

test("raw mode needs a terminal") {
    if is_tty(0) {
        return;
    }
    let r = raw_mode();
    assert!(
        match r {
            Result::Err(TermError::NotATty) => true,
            default => false,
        },
    );
}

test("read_bytes at end of input") {
    let r = read_bytes(10)?;
    assert!(match r {
        Option::None => true,
        Option::Some(b) => b.len() == 0,
    });
}

test("resized is false without a resize") {
    assert!(!resized());
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
