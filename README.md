# coil-cli

Building blocks for command-line and terminal programs in [Coil](https://github.com/ardax-corp/coil-lang): terminal state and size, raw mode, colour detection, styled output, key and mouse input, a line editor and prompts, argument parsing, progress bars, and a diffing cell buffer for full-screen programs. Package name: `cli`.

The terminal calls Coil cannot make itself (isatty, termios, window size, timed reads, resize signals) live in a small C library, `native/libcli`. Everything else is pure Coil. See [docs/design.md](docs/design.md) for the layout and plan.

## Requirements

- coil-lang (edge) and coil-stdlib
- libffi (for coil FFI)
- A C11 toolchain (`cc`)

## Quick start

```bash
make          # native/libcli.{so,dylib,dll}
make smoke    # C ABI smoke test over a pseudo-terminal
make test     # coil test harness (needs coil on PATH)
```

```coil
use cli::term::{stdout_is_tty, size_or, raw_mode};

let s = size_or(80, 24);
if stdout_is_tty() {
    let raw = raw_mode()?;
    defer use (raw) {
        let _ = raw.leave();
    }
    // read keys …
}
```

Run a program that uses it:

```bash
coil --root ../coil-stdlib/src --root ../coil-cli/src --ffi-search-path ../coil-cli/native \
  --allow-dload cli --dload-trusted cli main.hy
```

## Modules

| Module | Status |
|--------|--------|
| `cli::term` | tty checks, size, raw mode, timed reads, resize, colour level |
| `cli::ansi` | cursor, clear, scroll, alt screen, mouse/paste/focus modes, title, hyperlinks |
| `cli::style` | `Color` (16 / 256 / RGB), `Style`, `Painter`, downgrade by colour level, `strip` |
| `cli::width` | display width (wide, combining, emoji), `truncate`, `pad_*`, `center`, `wrap` |

More are on the way; the plan is in [docs/design.md](docs/design.md).

## License

MIT — see [LICENSE](LICENSE).
