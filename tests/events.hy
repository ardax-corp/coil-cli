use tests::assert;
use io::open;
use io::close;
use io::file::write_text;
use io::fs::remove_file;
use io::stdout;
use cli::events::events_from;
use cli::keys::describe;
use cli::term::read_bytes;
use cli::term::raw_mode;
use cli::term::size_or;
use cli::term::tty;

test("events from a stream") {
    write_text("events_in.txt", "a\e[A\e[1;5C\e[200~hi\e[201~\e")?;
    let f = open("events_in.txt", "r")?;
    let ev = events_from(f, stdout());
    let seen = "";
    while let Option::Some(e) = ev.next(100)? {
        seen = seen + describe(e) + " ";
    }
    assert!(seen == "a up ctrl+right paste(hi) esc ");
    assert!(ev.eof);
    assert!((ev.next(0)?).is_none());
    close(f)?;
    remove_file("events_in.txt")?;
}

test("term on a file") {
    write_text("term_in.txt", "hello")?;
    let f = open("term_in.txt", "r")?;
    assert!(!tty(f));
    let sz = size_or(f, 81, 25);
    let (c, r) = sz;
    assert!(c > 0 && r > 0);
    assert!(raw_mode(f).is_err());
    let got = read_bytes(f, 3, 50)? ?? Vec::new();
    assert!(got.len() == 3);
    let rest = read_bytes(f, 10, 50)? ?? Vec::new();
    assert!(rest.len() == 2);
    assert!((read_bytes(f, 10, 50)?).is_none());
    close(f)?;
    remove_file("term_in.txt")?;
}
