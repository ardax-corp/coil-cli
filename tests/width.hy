use tests::assert;
use cli::width::{width, visible_width, char_width, truncate, take, pad_right, pad_left, center, wrap, code_points};

test("ascii and control") {
    assert!(width("hello") == 5);
    assert!(width("") == 0);
    assert!(width("a\tb") == 2);
}

test("wide and zero-width") {
    assert!(width("日本") == 4);
    assert!(width("é") == 1);
    assert!(width("e\u{301}") == 1);
    assert!(width("👍") == 2);
    assert!(width("👨\u{200d}👩") == 2);
    assert!(char_width(0x4e00) == 2);
    assert!(char_width(0x301) == 0);
    assert!(char_width(0xff21) == 2);
    assert!(char_width(0x41) == 1);
}

test("code points") {
    let cps = code_points("aé日👍");
    assert!(cps.len() == 4);
    assert!(cps[1] == 233);
    assert!(cps[2] == 0x65e5);
    assert!(cps[3] == 0x1f44d);
}

test("styled width ignores escapes") {
    assert!(visible_width("\e[1;31m日本\e[0m!") == 5);
}

test("take and truncate by columns") {
    assert!(take("日本語", 3) == "日");
    assert!(take("abc", 10) == "abc");
    assert!(truncate("hello world", 8, "…") == "hello w…");
    assert!(truncate("short", 8, "…") == "short");
    assert!(truncate("日本語", 5, "…") == "日本…");
    assert!(truncate("abcdef", 2, "...") == "..");
}

test("padding") {
    assert!(pad_right("ab", 4) == "ab  ");
    assert!(pad_left("ab", 4) == "  ab");
    assert!(pad_right("日本語", 5) == "日本 ");
    assert!(center("ab", 6) == "  ab  ");
    assert!(center("ab", 5) == " ab  ");
}

test("wrap") {
    let lines = wrap("the quick brown fox jumps", 10);
    assert!(lines.len() == 3);
    assert!(lines[0] == "the quick");
    assert!(lines[1] == "brown fox");
    assert!(lines[2] == "jumps");
    let long = wrap("abcdefghij xy", 4);
    assert!(long.len() == 4);
    assert!(long[0] == "abcd");
    assert!(long[2] == "ij");
    assert!(long[3] == "xy");
    let paras = wrap("a\n\nb", 10);
    assert!(paras.len() == 3);
    assert!(paras[1] == "");
}
