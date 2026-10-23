# coil-cli design

coil-cli is the terminal foundation for Coil programs: everything a
command-line tool needs to talk to a terminal well, and the lower layer a
full TUI package builds on. Package name: `cli`.

## Goals

- Plain CLI tools: parse arguments, print styled output that degrades on
  pipes and `NO_COLOR`, show progress, ask questions.
- Interactive programs: raw mode, decoded key/mouse/paste/resize events,
  a line editor with history, cursor and screen control.
- A seam for a TUI: a cell buffer that renders by diffing frames, so a
  widget library only has to draw into cells.

Non-goals for this package: a widget set, focus management and layout
trees. Those belong in a separate TUI package on top of `cli::screen`
(see "Scope split" below).

## What Coil gives us, and what it does not

Coil has `io::stdin/stdout/stderr` streams, `env::args`/`env::var`,
`clock::mono_nanos`/`sleep_ms`, and `string`/`text` helpers. It has no
`isatty`, no termios, no window size and no signals. Those cannot be
written in Coil: they are OS calls, and `extern "c"` (libc) is denied by
the dload gate on purpose. So, like coil-process, coil-cli ships a small C
library, `native/libcli`, and everything above it is pure Coil.

The C side is kept to what only the OS can do:

| Native | Purpose |
|--------|---------|
| `coil_cli_isatty(fd)` | Is the fd a terminal |
| `coil_cli_size(fd)` | Columns and rows (`TIOCGWINSZ` / console info) |
| `coil_cli_raw_enter(flags)` / `coil_cli_raw_leave()` | Save termios, enter raw mode; restore. Also restored `atexit` |
| `coil_cli_read(buf, cap, timeout_ms)` | Read stdin bytes with a timeout (`poll` / `WaitForSingleObject`) |
| `coil_cli_resized()` | SIGWINCH seen since the last call (Windows: size changed) |
| `coil_cli_enable_vt()` | Windows: turn on VT output processing; no-op elsewhere |
| `coil_cli_last_error()` | Text of the last OS error |

Escape sequences, key decoding, widths and everything else are Coil code
and are unit tested without a terminal. The C library has a smoke test
that drives raw mode and sizes through a pseudo-terminal (`posix_openpt`).

Writing goes through Coil's `io::stdout()` stream with `io::sync::write_all`;
reading in raw mode goes through the native read, because it needs a
timeout (to tell a lone Esc from the start of a sequence) and must not mix
with a buffered reader.

## Modules

| Module | Contents | Native? |
|--------|----------|---------|
| `cli::term` | `is_tty`, `size`, `RawMode` guard, `read_bytes(timeout)`, `resized`, colour-level detection (`NO_COLOR`, `FORCE_COLOR`, `COLORTERM`, `TERM`) | yes |
| `cli::ansi` | Escape-sequence builders: cursor moves, save/restore, show/hide, clear line/screen, alt screen, scroll region, mouse/paste/focus modes, title, hyperlinks (OSC 8) | no |
| `cli::style` | `Color` (16 / 256 / RGB), `Style` (fg, bg, bold, dim, italic, underline, reverse, strike), `paint`, downgrading RGB to 256/16 by colour level, `strip` | no |
| `cli::width` | Display width of text (East Asian wide, combining marks, zero-width), truncation and padding by columns | no |
| `cli::keys` | `Event` (key, mouse, paste, focus, resize), `Key`, `Mods`; an incremental `Decoder` for CSI/SS3/xterm/kitty-basic sequences, SGR mouse and bracketed paste | no |
| `cli::events` | Blocking/timed `next_event` over `term` + `keys.Decoder`, Esc timeout, resize events | yes (via term) |
| `cli::line` | Line editor model (buffer, cursor, kill ring, history, word moves) driven by key events, and `read_line(prompt)` that runs it in raw mode, falling back to plain stdin when not a tty | model no, runner yes |
| `cli::prompt` | `confirm`, `input` (with default/validation), `password`, `select`, `multi_select` | runner yes |
| `cli::args` | Declarative argument parser: flags, options, positionals, subcommands, `--`, `-abc` bundles, `--opt=value`, defaults, generated help and usage errors | no |
| `cli::progress` | Progress bar and spinner with rate/ETA, redraw throttling, quiet when not a tty | output only |
| `cli::screen` | Cell buffer (`Cell` = text + style), drawing helpers (text, fill, box), diffing renderer that emits the minimum escapes between frames | no |

Each pure module takes and returns strings/bytes, so it can be tested with
plain asserts. Modules that touch the terminal take an output `Stream` (by
default `stdout()`) so tests can point them at a file.

## Behaviour on non-terminals

- `style::paint` checks the colour level once: no colour when stdout is
  not a tty, when `NO_COLOR` is set, or when `TERM=dumb`; `FORCE_COLOR`
  overrides. Programs can also set the level explicitly.
- `progress` draws nothing when stderr is not a tty (only a final line, if
  asked).
- `line::read_line` and `prompt` read plain lines from stdin when stdin is
  not a tty, so scripts can pipe answers in.

## Safety

`RawMode` restores the terminal in its `drop` and the native library
restores it `atexit` as well, so a panic or `env::exit` does not leave the
shell in raw mode. Programs should still `defer` `leave()`, because `drop`
is a GC finaliser and runs late.

## Scope split with a TUI package

Proposed: a later `coil-tui` package depends on `cli` and adds layout
(rows/columns/constraints), widgets (list, table, text area, tabs, gauge),
focus and an application loop. coil-cli provides `cli::screen` and
`cli::events` as the stable seam. If we decide to keep everything in one
package instead, the TUI layer would live here as `cli::tui::*` and nothing
below it changes.

## Platforms

Linux and macOS are first class (termios, SIGWINCH). Windows builds with
the MSYS2 toolchain: VT output and VT input modes give the same escape
sequences, so the Coil layer is shared; resize is detected by polling the
console size.

## Plan

1. Scaffolding, CI, native library + smoke, `cli::term`, this doc.
2. `cli::ansi`, `cli::style`, `cli::width`.
3. `cli::keys` decoder and `cli::events`.
4. `cli::args`.
5. `cli::progress`.
6. `cli::line` and `cli::prompt`.
7. `cli::screen`.
8. Examples and API docs.

Each step is one PR into `main`, merged when CI is green. Compiler or
stdlib bugs found along the way are filed in coil-lang / coil-stdlib with
a repro rather than worked around silently.
