use tests::assert;
use cli::screen::Buffer;
use cli::screen::Screen;
use cli::screen::buffer;
use cli::screen::screen;
use cli::screen::render_diff;
use cli::screen::render_full;
use cli::screen::light_box;
use cli::screen::ascii_box;
use cli::style::plain;
use cli::style::fg;
use cli::style::red;
use cli::style::strip;
use cli::color::ColorLevel;

test("put clips and handles wide characters") {
    let b = buffer(6, 1);
    let end = b.put(0, 0, "ab日c", plain());
    assert!(end == 5);
    assert!(b.row_text(0) == "ab日c ");
    assert!(b.get(3, 0).text == "");
    let b2 = buffer(3, 1);
    assert!(b2.put(1, 0, "日本", plain()) == 3);
    assert!(b2.row_text(0) == " 日");
}

test("zero-width marks join their cell") {
    let b = buffer(3, 1);
    b.put(0, 0, "e\u{301}x", plain());
    assert!(b.get(0, 0).text == "e\u{301}");
    assert!(b.get(1, 0).text == "x");
}

test("boxes and fills") {
    let b = buffer(4, 3);
    b.draw_box(0, 0, 4, 3, ascii_box(), plain());
    assert!(b.text() == "+--+\n|  |\n+--+");
    b.fill(1, 1, 2, 1, "#", plain());
    assert!(b.row_text(1) == "|##|");
    b.clear();
    assert!(b.row_text(1) == "    ");
    b.set(9, 9, "x", plain());
}

test("diff writes only changed cells") {
    let a = buffer(5, 2);
    let b = buffer(5, 2);
    b.put(1, 0, "hi", plain());
    b.set(4, 1, "z", plain());
    let d = render_diff(a, b, ColorLevel::Basic);
    assert!(d == "\e[1;2H\e[0mhi\e[2;5Hz\e[0m");
    assert!(render_diff(b, b, ColorLevel::Basic) == "");
}

test("diff switches style only when it changes") {
    let a = buffer(4, 1);
    let b = buffer(4, 1);
    b.put(0, 0, "ab", fg(red()));
    b.put(2, 0, "c", plain());
    let d = render_diff(a, b, ColorLevel::Basic);
    assert!(d == "\e[1;1H\e[0m\e[31mab\e[0mc\e[0m");
}

test("screen presents full then diffs") {
    let s = screen(3, 1, ColorLevel::None);
    let f = s.frame();
    f.put(0, 0, "abc", plain());
    let first = s.present();
    assert!(first == "\e[H\e[2J\e[1;1H\e[0mabc\e[0m");
    let g = s.frame();
    g.put(0, 0, "abd", plain());
    assert!(s.present() == "\e[1;3H\e[0md\e[0m");
    let h = s.frame();
    h.put(0, 0, "abd", plain());
    assert!(s.present() == "");
    s.resize(2, 1);
    assert!(s.cols() == 2);
    let k = s.frame();
    k.put(0, 0, "x", plain());
    assert!(strip(s.present()) == "x");
}
