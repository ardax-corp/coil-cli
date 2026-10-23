use tests::assert;
use cli::line::{Edit, Outcome, Editor, History, editor, history, units};

fn ed() -> Editor {
    return editor(history(100));
}

fn typed(string s) -> Editor {
    let e = ed();
    e.apply(Edit::Insert(s));
    return e;
}

test("insert and move") {
    let e = typed("helo");
    e.apply(Edit::Left);
    e.apply(Edit::Insert("l"));
    assert!(e.text() == "hello");
    assert!(e.cursor == 4);
    e.apply(Edit::Home);
    e.apply(Edit::Insert(">"));
    assert!(e.text() == ">hello");
    e.apply(Edit::End);
    assert!(e.cursor == 6);
    e.apply(Edit::Right);
    assert!(e.cursor == 6);
}

test("backspace and delete by character") {
    let e = typed("aé日");
    e.apply(Edit::Backspace);
    assert!(e.text() == "aé");
    e.apply(Edit::Home);
    e.apply(Edit::Delete);
    assert!(e.text() == "é");
    let c = typed("e\u{301}x");
    assert!(c.len() == 2);
    c.apply(Edit::Left);
    c.apply(Edit::Backspace);
    assert!(c.text() == "x");
}

test("words, kill and yank") {
    let e = typed("git commit -m fix");
    e.apply(Edit::WordLeft);
    assert!(e.cursor == 14);
    e.apply(Edit::WordLeft);
    e.apply(Edit::WordLeft);
    assert!(e.cursor == 4);
    e.apply(Edit::KillWordForward);
    assert!(e.text() == "git  -m fix");
    assert!(e.kill == "commit");
    e.apply(Edit::Yank);
    assert!(e.text() == "git commit -m fix");
    e.apply(Edit::End);
    e.apply(Edit::KillWordBack);
    assert!(e.text() == "git commit -m ");
    e.apply(Edit::Home);
    e.apply(Edit::KillToEnd);
    assert!(e.text() == "");
    e.apply(Edit::Yank);
    e.apply(Edit::WordLeft);
    e.apply(Edit::KillToStart);
    assert!(e.text() == "m ");
    assert!(e.kill == "git commit -");
}

test("transpose") {
    let e = typed("ab");
    e.apply(Edit::Transpose);
    assert!(e.text() == "ba");
    let f = typed("abc");
    f.apply(Edit::Left);
    f.apply(Edit::Transpose);
    assert!(f.text() == "acb");
    assert!(f.cursor == 3);
}

test("history browsing keeps the draft") {
    let h = history(2);
    let e = editor(h);
    e.apply(Edit::Insert("one"));
    assert!(e.take() == "one");
    e.apply(Edit::Insert("two"));
    e.take();
    e.apply(Edit::Insert("two"));
    e.take();
    e.apply(Edit::Insert("three"));
    e.take();
    assert!(h.len() == 2);
    assert!(h.entries[0] == "two");
    e.apply(Edit::Insert("dra"));
    e.apply(Edit::HistoryPrev);
    assert!(e.text() == "three");
    e.apply(Edit::HistoryPrev);
    assert!(e.text() == "two");
    e.apply(Edit::HistoryPrev);
    assert!(e.text() == "two");
    e.apply(Edit::HistoryNext);
    e.apply(Edit::HistoryNext);
    assert!(e.text() == "dra");
}

test("outcomes") {
    let e = ed();
    assert!(e.apply(Edit::Eof) == Outcome::Eof);
    e.apply(Edit::Insert("x"));
    assert!(e.apply(Edit::Eof) == Outcome::Continue);
    assert!(e.apply(Edit::Submit) == Outcome::Submit);
    assert!(e.apply(Edit::Cancel) == Outcome::Cancel);
    e.apply(Edit::Insert("abc"));
    e.apply(Edit::Clear);
    assert!(e.text() == "");
}

test("view scrolls to the cursor and masks") {
    let e = typed("abcdefghij");
    let (text, col) = e.view(5, "");
    assert!(text == "ghij");
    assert!(col == 4);
    e.apply(Edit::Home);
    let (t2, c2) = e.view(5, "");
    assert!(t2 == "abcde");
    assert!(c2 == 0);
    let p = typed("pw");
    let (t3, c3) = p.view(10, "*");
    assert!(t3 == "**");
    assert!(c3 == 2);
    let w = typed("日本語");
    assert!(w.cursor_col() == 6);
}

test("units") {
    assert!(units("ae\u{301}日").len() == 3);
}
