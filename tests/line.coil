use tests::assert;
use cli::line::Edit;
use cli::line::Outcome;
use cli::line::Editor;
use cli::line::History;
use cli::line::editor;
use cli::line::history;
use cli::line::units;
use cli::line::edit_for;
use cli::keys::decode_all;
use string::to_bytes;

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

/// Feed raw terminal bytes through the default bindings.
fn keyed(Editor e, string bytes) {
    for ev in decode_all(to_bytes(bytes)) {
        match edit_for(ev) {
            Option::Some(a) => {
                e.apply(a);
            },
            Option::None => {},
        }
    }
}

test("default key bindings") {
    let e = ed();
    keyed(e, "hello world");
    assert!(e.text() == "hello world");
    keyed(e, "\x17");
    assert!(e.text() == "hello ");
    keyed(e, "\x01X\x05!");
    assert!(e.text() == "Xhello !");
    keyed(e, "\e[D\e[D\x7f");
    assert!(e.text() == "Xhell !");
    keyed(e, "\x0b");
    assert!(e.text() == "Xhell");
    keyed(e, "\x19\x19");
    assert!(e.text() == "Xhell ! !");
    keyed(e, "\e[200~pasted\e[201~");
    assert!(e.text() == "Xhell ! !pasted");
}

test("binding outcomes") {
    let e = ed();
    let evs = decode_all(to_bytes("\r\x03\x04"));
    assert!(e.apply(edit_for(evs[0]) ?? Edit::Clear) == Outcome::Submit);
    assert!(e.apply(edit_for(evs[1]) ?? Edit::Clear) == Outcome::Cancel);
    assert!(e.apply(edit_for(evs[2]) ?? Edit::Clear) == Outcome::Eof);
    assert!(edit_for(decode_all(to_bytes("\e[I"))[0]).is_none());
}
