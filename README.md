# coil-cli

Building blocks for command-line and terminal programs in [Coil](https://github.com/ardax-corp/coil-lang): terminal state and size, raw mode, colour detection, styled output, key and mouse input, a line editor and prompts, argument parsing, progress bars, and a diffing cell buffer for full-screen programs. Package name: `cli`.

Pure Coil, no native code: terminal state (isatty, raw mode, size, timed reads, resize) comes from coil-lang's `io::tty` host natives (coil-lang issue 1982, in progress). See [docs/design.md](docs/design.md) for the layout and plan.

## Requirements

- coil-lang (edge) and coil-stdlib

## Quick start

```bash
make test     # coil test harness (needs coil on PATH; pass COIL_ROOTS='--root <stdlib>/src')
make fmt      # format check
```

```coil
use cli::style::{Painter, fg, red};
use cli::color::{ColorLevel};
use cli::width::{truncate};
use io::sync::{println};

fn main() {
    let p = Painter::at(ColorLevel::Basic);
    println(p.paint(fg(red()).bold(), truncate("something went wrong", 12, "…")))?;
}
```

```bash
coil --root ../coil-stdlib/src --root ../coil-cli/src main.hy
```

## Modules

| Module | Status |
|--------|--------|
| `cli::color` | `ColorLevel` and detection from `NO_COLOR`, `FORCE_COLOR`, `COLORTERM`, `TERM` |
| `cli::ansi` | cursor, clear, scroll, alt screen, mouse/paste/focus modes, title, hyperlinks |
| `cli::style` | `Color` (16 / 256 / RGB), `Style`, `Painter`, downgrade by colour level, `strip` |
| `cli::width` | display width (wide, combining, emoji), `truncate`, `pad_*`, `center`, `wrap` |
| `cli::args` | declarative parser: flags (counted), options, defaults, repeatable options, positionals, rest, subcommands, `--`, bundles, generated help, "did you mean" |

More are on the way; the plan is in [docs/design.md](docs/design.md).

## License

MIT — see [LICENSE](LICENSE).
