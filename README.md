# coil-cli

Building blocks for command-line and terminal programs in [Coil](https://github.com/ardax-corp/coil-lang): terminal state and size, raw mode, colour detection, styled output, key and mouse input, a line editor and prompts, argument parsing, progress bars, and a diffing cell buffer for full-screen programs. Package name: `cli`.

Pure Coil, no native code: terminal state (isatty, raw mode, size, timed reads, resize) comes from coil-lang's `io::tty` host natives, so no `--allow-dload` is needed. See [docs/design.md](docs/design.md) for the layout and plan.

## Requirements

- coil-lang (edge) and coil-stdlib

## Use it

With [spool](https://github.com/ardax-corp/spool):

```bash
spool add cli --git https://github.com/ardax-corp/coil-cli.git --rev <commit SHA>
```

There are no tags yet, so pin a commit with `--rev`. Without spool, clone this repo (and coil-stdlib) next to your project and pass `--root ../coil-cli/src` to `coil`, as below.

## Quick start

```coil
use cli::style::{Painter, fg, red};
use cli::color::ColorLevel;
use cli::width::truncate;
use io::stdout;
use io::sync::write_all;
use string::to_bytes;

fn main() {
    let p = Painter::at(ColorLevel::Basic);
    let line = p.paint(fg(red()).bold(), truncate("something went wrong", 12, "…"));
    let _ = write_all(stdout(), to_bytes(line + "\n"));
}
```

```bash
coil --root ../coil-stdlib/src --root ../coil-cli/src main.hy
```

Every public item has `///` docs with examples; the pure modules' examples run as doc tests.

## Modules

| Module | Status |
|--------|--------|
| `cli::term` | `tty`, `size_or`, `columns`, `RawMode` (`raw_mode`, `leave`), `read_bytes` with a timeout, `was_resized` |
| `cli::events` | `Events.next(timeout)`: decoded input with the Esc timeout and `Resize` events, from stdin or any stream |
| `cli::color` | `ColorLevel` and detection from `NO_COLOR`, `FORCE_COLOR`, `COLORTERM`, `TERM` |
| `cli::ansi` | cursor, clear, scroll, alt screen, mouse/paste/focus modes, title, hyperlinks |
| `cli::style` | `Color` (16 / 256 / RGB), `Style`, `Painter`, downgrade by colour level, `strip` |
| `cli::width` | display width (wide, combining, emoji), `truncate`, `pad_*`, `center`, `wrap` |
| `cli::args` | declarative parser: flags (counted), options, defaults, repeatable options, positionals, rest, subcommands, `--`, bundles, generated help, "did you mean" |
| `cli::progress` | progress bar (smooth or ASCII, rate, ETA) and spinner, redrawn in place and throttled; `human_bytes`, `human_duration` |
| `cli::keys` | `Event` (keys with modifiers, SGR mouse, bracketed paste, focus, cursor reports) and an incremental `Decoder` for CSI / SS3 / xterm / kitty-basic input |
| `cli::line` | line editor: `Edit` model (kill/yank, word moves, transpose, history with draft, scrolled and masked `view`), `edit_for` key bindings, and `read_line` in raw mode (plain stdin when piped) |
| `cli::prompt` | `confirm`, `input`, `password`, `select`, `multi_select` on a terminal; the fuzzy-filtered `Select` model and `select_key_for`; line-based `*_line` runners used when stdin is piped |
| `cli::screen` | cell `Buffer` (wide chars, boxes, fills), `render_diff` / `render_full`, double-buffered `Screen` |

## Examples

| File | Shows |
|------|-------|
| [examples/hello.hy](examples/hello.hy) | `cli::args` with help and errors, `Painter` colours, a progress bar |
| [examples/ask.hy](examples/ask.hy) | `confirm`, `input`, `select`, `multi_select` and a `read_line` REPL; pipe answers in to see the fallbacks |
| [examples/bounce.hy](examples/bounce.hy) | a full-screen program: alternate screen, `Screen` diff rendering, timed `Events`, resizes |

```bash
coil --allow-env --allow-exit --root ../coil-stdlib/src --root src examples/hello.hy -- --name Ada -n 3
make examples COIL_ROOTS='--root ../coil-stdlib/src'   # compile them all
```

A component framework (layout, widgets, focus) built on `cli::screen` and `cli::events` is [coil-tui](https://github.com/ardax-corp/coil-tui), package `tui`.

## Development

```bash
make test COIL_ROOTS='--root ../coil-stdlib/src'          # tests/ and the doc examples of the modules they import; writes scratch files
coil test --doc-tests-only src --root ../coil-stdlib/src  # only the doc examples under src/
make fmt                                                  # format check
```

## License

MIT — see [LICENSE](LICENSE).
