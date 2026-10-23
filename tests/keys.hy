use tests::assert;
use string::to_bytes;
use cli::keys::{Event, Key, KeyEvent, MouseKind, MouseButton, Decoder, decoder, decode_all, describe, is_key, CTRL, ALT, SHIFT};

fn names(string input) -> string {
    let out = "";
    for e in decode_all(to_bytes(input)) {
        if out != "" {
            out = out + " ";
        }
        out = out + describe(e);
    }
    return out;
}

test("printable and control bytes") {
    assert!(names("aZ1 ") == "a Z 1 space");
    assert!(names("\x01\x1a\r\t\x7f\x08") == "ctrl+a ctrl+z enter tab backspace backspace");
    assert!(names("\x00") == "ctrl+space");
    assert!(names("é日") == "é 日");
}

test("arrows, home/end, ss3") {
    assert!(names("\e[A\e[B\e[C\e[D") == "up down right left");
    assert!(names("\e[H\e[F\eOH\eOF") == "home end home end");
    assert!(names("\eOA\eOP\eOS") == "up f1 f4");
}

test("modified keys") {
    assert!(names("\e[1;5A") == "ctrl+up");
    assert!(names("\e[1;2D") == "shift+left");
    assert!(names("\e[1;3C") == "alt+right");
    assert!(names("\e[1;6B") == "ctrl+shift+down");
    assert!(names("\e[Z") == "shift+backtab");
}

test("tilde keys") {
    assert!(names("\e[2~\e[3~\e[5~\e[6~\e[1~\e[4~") == "insert delete pageup pagedown home end");
    assert!(names("\e[15~\e[24~\e[3;5~") == "f5 f12 ctrl+delete");
}

test("alt prefix") {
    assert!(names("\ea\eé") == "alt+a alt+é");
    assert!(names("\e\x01") == "ctrl+alt+a");
    assert!(names("\e\r") == "alt+enter");
}

test("lone esc needs a flush") {
    let d = decoder();
    d.feed(to_bytes("\e"));
    assert!(d.drain().len() == 0);
    assert!(d.pending() == 1);
    let ev = d.flush();
    assert!(ev.len() == 1);
    assert!(is_key(ev[0], "esc"));
}

test("split sequences wait for the rest") {
    let d = decoder();
    d.feed(to_bytes("\e["));
    assert!(d.drain().len() == 0);
    d.feed(to_bytes("1;5"));
    assert!(d.drain().len() == 0);
    d.feed(to_bytes("Ax"));
    let ev = d.drain();
    assert!(ev.len() == 2);
    assert!(is_key(ev[0], "ctrl+up"));
    assert!(is_key(ev[1], "x"));
}

test("split utf-8 waits") {
    let d = decoder();
    let b = to_bytes("日");
    let first: Vec<byte> = Vec::new();
    first.push(b[0]);
    d.feed(first);
    assert!(d.drain().len() == 0);
    let rest: Vec<byte> = Vec::new();
    rest.push(b[1]);
    rest.push(b[2]);
    d.feed(rest);
    let ev = d.drain();
    assert!(ev.len() == 1);
    assert!(describe(ev[0]) == "日");
}

test("kitty / fixterms CSI u") {
    assert!(names("\e[97;5u") == "ctrl+a");
    assert!(names("\e[13;2u") == "shift+enter");
    assert!(names("\e[27u") == "esc");
}

test("sgr mouse") {
    assert!(names("\e[<0;10;5M\e[<0;10;5m") == "mouse(press left 10,5) mouse(release left 10,5)");
    assert!(
        names("\e[<64;1;1M\e[<65;1;1M") == "mouse(press wheel-up 1,1) mouse(press wheel-down 1,1)",
    );
    assert!(names("\e[<32;3;4M\e[<35;3;4M") == "mouse(drag left 3,4) mouse(move none 3,4)");
    let ev = decode_all(to_bytes("\e[<16;2;2M"));
    assert!(
        match ev[0] {
            Event::Mouse(m) => m.mods == CTRL,
            default => false,
        },
    );
}

test("x10 mouse") {
    let ev = decode_all(to_bytes("\e[M !!"));
    assert!(describe(ev[0]) == "mouse(press left 1,1)");
}

test("bracketed paste") {
    assert!(names("\e[200~hello\e[A world\e[201~x") == "paste(hello\e[A world) x");
    let d = decoder();
    d.feed(to_bytes("\e[200~par"));
    assert!(d.drain().len() == 0);
    d.feed(to_bytes("tial\e[201~"));
    let ev = d.drain();
    assert!(describe(ev[0]) == "paste(partial)");
}

test("focus and cursor reports") {
    assert!(names("\e[I\e[O") == "focus-in focus-out");
    assert!(names("\e[12;40R") == "unknown(8 bytes)");
    assert!(names("\e[1;2R") == "shift+f3");
    let d = decoder();
    d.expect_cursor = true;
    d.feed(to_bytes("\e[12;40R\e[1;2R"));
    let ev = d.drain();
    assert!(describe(ev[0]) == "cursor(12,40)");
    assert!(describe(ev[1]) == "shift+f3");
}

test("unfinished sequence flushes as unknown") {
    let d = decoder();
    d.feed(to_bytes("\e[12"));
    let ev = d.flush();
    assert!(ev.len() == 1);
    assert!(describe(ev[0]) == "unknown(4 bytes)");
    assert!(d.pending() == 0);
}

test("key event helpers") {
    let ev = decode_all(to_bytes("A\x03"));
    assert!(
        match ev[0] {
            Event::Key(k) => (k.char() ?? 0) == 65 && !k.ctrl(),
            default => false,
        },
    );
    assert!(
        match ev[1] {
            Event::Key(k) => k.ctrl() &&
                             match k.char() {
                Option::None => true,
                default => false,
            },
            default => false,
        },
    );
    assert!(is_key(ev[1], "ctrl+c"));
}
