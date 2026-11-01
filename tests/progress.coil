use tests::assert;
use cli::progress::render_bar;
use cli::progress::render_line;
use cli::progress::render_spinner;
use cli::progress::blocks;
use cli::progress::ascii;
use cli::progress::human_bytes;
use cli::progress::human_duration;
use cli::progress::human_rate;
use cli::progress::eta_ms;
use cli::progress::dots;
use cli::progress::bar;
use cli::progress::spinner;
use cli::width::width;

test("ascii bar") {
    assert!(render_bar(ascii(), 0, 10, 10) == "[          ]");
    assert!(render_bar(ascii(), 5, 10, 10) == "[=====     ]");
    assert!(render_bar(ascii(), 10, 10, 10) == "[==========]");
    assert!(render_bar(ascii(), 15, 10, 10) == "[==========]");
    assert!(render_bar(ascii(), 1, 4, 10) == "[==>       ]");
}

test("smooth bar") {
    let b = render_bar(blocks(), 7, 16, 2);
    assert!(b == "▕▉ ▏");
    assert!(width(render_bar(blocks(), 7, 13, 20)) == 22);
}

test("human units") {
    assert!(human_bytes(12) == "12 B");
    assert!(human_bytes(1536) == "1.5 KiB");
    assert!(human_bytes(10 * 1024 * 1024) == "10 MiB");
    assert!(human_duration(950) == "950ms");
    assert!(human_duration(12000) == "12s");
    assert!(human_duration(185000) == "3m05s");
    assert!(human_duration(3720000) == "1h02m");
    assert!(human_rate(500, 1000) == "500/s");
    assert!(human_rate(1500, 1000) == "1.5k/s");
    assert!(human_rate(5, 0) == "");
    assert!(eta_ms(25, 100, 1000) == 3000);
    assert!(eta_ms(0, 100, 1000) == -1);
}

test("progress line fits its width") {
    let l = render_line(ascii(), "copy", 50, 100, 2000, 60);
    assert!(width(l) <= 60);
    assert!(l == "copy [===============               ] 50% 50/100 25/s ETA 2s");
    let narrow = render_line(ascii(), "copy", 50, 100, 0, 16);
    assert!(narrow == "copy 50% 50/100");
}

test("spinner frames") {
    assert!(render_spinner(dots(), 0, "working", 0) == "⠋ working");
    assert!(render_spinner(dots(), 11, "working", 2500) == "⠙ working (2s)");
}

test("disabled bars draw nothing") {
    let b = bar(10, 80, false);
    b.inc(3);
    b.finish("");
    assert!(b.current == 3);
    let s = spinner("x", false);
    s.tick();
    s.finish("done");
}
