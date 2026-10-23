use tests::assert;
use io::open;
use io::close;
use io::file::write_text;
use io::file::read_text;
use io::fs::remove_file;
use cli::prompt::parse_confirm;
use cli::prompt::confirm_label;
use cli::prompt::fuzzy_match;
use cli::prompt::Select;
use cli::prompt::SelectKey;
use cli::prompt::SelectOutcome;
use cli::prompt::select_model;
use cli::prompt::confirm_line;
use cli::prompt::input_line;
use cli::prompt::select_line;
use cli::prompt::select_key_for;
use cli::prompt::parse_choices;
use cli::prompt::multi_select_line;
use cli::prompt::select_block;
use cli::keys::decode_all;
use string::to_bytes;

fn strs(string... xs) -> Vec<string> {
    return xs;
}

test("confirm answers") {
    assert!((parse_confirm("Y", false) ?? false) == true);
    assert!((parse_confirm(" no ", true) ?? true) == false);
    assert!((parse_confirm("", true) ?? false) == true);
    assert!(
        match parse_confirm("maybe", true) {
            Option::None => true,
            default => false,
        },
    );
    assert!(confirm_label("Go?", true) == "Go? [Y/n] ");
}

test("fuzzy filter") {
    assert!(fuzzy_match("cmt", "commit"));
    assert!(fuzzy_match("CO", "commit"));
    assert!(!fuzzy_match("tc", "commit"));
    assert!(fuzzy_match("", "x"));
}

test("select moves, wraps and scrolls") {
    let s = select_model(strs("a", "b", "c", "d", "e"), false, 2);
    assert!(s.lines(20).len() == 2);
    assert!(s.lines(20)[0] == "❯ a");
    s.apply(SelectKey::Down);
    s.apply(SelectKey::Down);
    assert!(s.current() == 2);
    assert!(s.offset == 1);
    assert!(s.lines(20)[1] == "❯ c");
    s.apply(SelectKey::End);
    assert!(s.current() == 4);
    s.apply(SelectKey::Down);
    assert!(s.current() == 0);
    s.apply(SelectKey::Up);
    assert!(s.current() == 4);
    s.apply(SelectKey::PageUp);
    assert!(s.current() == 2);
    assert!(s.apply(SelectKey::Submit) == SelectOutcome::Submit);
    assert!(s.chosen()[0] == 2);
}

test("select filter") {
    let s = select_model(strs("commit", "push", "checkout"), false, 5);
    s.apply(SelectKey::FilterChar("c"));
    s.apply(SelectKey::FilterChar("h"));
    assert!(s.visible.len() == 1);
    assert!(s.current() == 2);
    s.apply(SelectKey::FilterChar("z"));
    assert!(s.current() == -1);
    assert!(s.apply(SelectKey::Submit) == SelectOutcome::Continue);
    s.apply(SelectKey::FilterBackspace);
    s.apply(SelectKey::FilterBackspace);
    assert!(s.visible.len() == 2);
    assert!(s.apply(SelectKey::Cancel) == SelectOutcome::Cancel);
}

test("multi select toggles") {
    let s = select_model(strs("a", "b", "c"), true, 5);
    s.apply(SelectKey::Toggle);
    s.apply(SelectKey::Down);
    s.apply(SelectKey::Down);
    s.apply(SelectKey::Toggle);
    let c = s.chosen();
    assert!(c.len() == 2);
    assert!(c[1] == 2);
    assert!(s.lines(20)[0] == "  ◉ a");
    assert!(s.lines(20)[1] == "  ○ b");
    s.apply(SelectKey::ToggleAll);
    assert!(s.chosen().len() == 3);
    s.apply(SelectKey::ToggleAll);
    assert!(s.chosen().len() == 0);
}

test("line runners read answers from a stream") {
    write_text("prompt_in.txt", "maybe\ny\n\nsecond\n9\n2\n")?;
    write_text("prompt_out.txt", "")?;
    let input = open("prompt_in.txt", "r")?;
    let out = open("prompt_out.txt", "w")?;
    assert!(confirm_line(input, out, "Go?", false));
    assert!((input_line(input, out, "Name?", "anon") ?? "") == "anon");
    assert!((input_line(input, out, "Name?", "anon") ?? "") == "second");
    assert!((select_line(input, out, "Pick", strs("x", "y")) ?? -1) == 1);
    assert!(
        match input_line(input, out, "More?", "") {
            Option::None => true,
            default => false,
        },
    );
    close(input)?;
    close(out)?;
    let shown = read_text("prompt_out.txt")?;
    assert!(shown.len() > 0);
    remove_file("prompt_in.txt")?;
    remove_file("prompt_out.txt")?;
}

test("select key bindings") {
    let s = select_model(strs("apple", "banana", "cherry"), true, 5);
    let out = SelectOutcome::Continue;
    for ev in decode_all(to_bytes("\e[B \e[B \e[A\r")) {
        match select_key_for(ev) {
            Option::Some(k) => {
                out = s.apply(k);
            },
            Option::None => {},
        }
    }
    assert!(out == SelectOutcome::Submit);
    let c = s.chosen();
    assert!(c.len() == 2 && c[0] == 1 && c[1] == 2);
    let f = select_model(strs("apple", "banana", "cherry"), false, 5);
    for ev in decode_all(to_bytes("chr")) {
        f.apply(select_key_for(ev) ?? SelectKey::Cancel);
    }
    assert!(f.current() == 2);
    assert!(
        f.apply(select_key_for(decode_all(to_bytes("\e"))[0]) ?? SelectKey::Submit) ==
        SelectOutcome::Cancel,
    );
}

test("multi-select answers") {
    let v = parse_choices("1 3,2", 3) ?? Vec::new();
    assert!(v.len() == 3 && v[0] == 0 && v[1] == 2 && v[2] == 1);
    assert!(parse_choices("4", 3).is_none());
    assert!(parse_choices("x", 3).is_none());
    assert!((parse_choices("", 3) ?? strs_int()).len() == 0);
    write_text("multi_in.txt", "0\n2, 1\n")?;
    write_text("multi_out.txt", "")?;
    let input = open("multi_in.txt", "r")?;
    let out = open("multi_out.txt", "w")?;
    let got = multi_select_line(input, out, "Many", strs("a", "b"))? ?? strs_int();
    assert!(got.len() == 2 && got[0] == 1 && got[1] == 0);
    assert!((multi_select_line(input, out, "Many", strs("a", "b"))?).is_none());
    close(input)?;
    close(out)?;
    remove_file("multi_in.txt")?;
    remove_file("multi_out.txt")?;
}

fn strs_int() -> Vec<int> {
    return Vec::new();
}

test("select block") {
    let s = select_model(strs("apple", "banana"), false, 5);
    let b = select_block("Pick", s, 20);
    assert!(b.len() == 3 && b[0] == "Pick" && b[1] == "❯ apple");
    s.apply(SelectKey::FilterChar("zz"));
    let e = select_block("Pick", s, 20);
    assert!(e.len() == 2 && e[0] == "Pick  zz" && e[1] == "  (no matches)");
}
