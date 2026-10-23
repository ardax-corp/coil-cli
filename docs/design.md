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

## Terminal access

Coil has `io::stdin/stdout/stderr` streams, `env::args`/`env::var`,
`clock::mono_nanos`/`sleep_ms`, and `string`/`text` helpers. It has no
`isatty`, no termios, no window size and no signals yet. Those are OS
calls, and they are being added to coil-lang itself as host natives
(`io::tty`, coil-lang issue 1982) so that this package stays pure
Coil and programs need no `--allow-dload`. coil-cli ships no native code.

`cli::term` is a thin wrapper over `io::tty` and lands once it exists.
Until then the pure modules (escapes, styles, widths, key decoding, the
line-editor model, argument parsing, progress rendering, the cell buffer)
are built and tested on their own; the parts that run against a real
terminal plug in afterwards.

Reading in raw mode uses a timed read (`io::tty::read_timeout`), because it
needs a timeout to tell a lone Esc from the start of a sequence.

## Modules

| Module | Contents | Needs `io::tty`? |
|--------|----------|---------|
| `cli::color` | `ColorLevel`, detection from `NO_COLOR`, `FORCE_COLOR`, `COLORTERM`, `TERM` | no |
| `cli::term` | `is_tty`, `size`, `RawMode` guard, `read_bytes(timeout)`, `resized`, over `io::tty` | io::tty |
| `cli::ansi` | Escape-sequence builders: cursor moves, save/restore, show/hide, clear line/screen, alt screen, scroll region, mouse/paste/focus modes, title, hyperlinks (OSC 8) | no |
| `cli::style` | `Color` (16 / 256 / RGB), `Style` (fg, bg, bold, dim, italic, underline, reverse, strike), `paint`, downgrading RGB to 256/16 by colour level, `strip` | no |
| `cli::width` | Display width of text (East Asian wide, combining marks, zero-width), truncation and padding by columns | no |
| `cli::keys` | `Event` (key, mouse, paste, focus, resize), `Key`, `Mods`; an incremental `Decoder` for CSI/SS3/xterm/kitty-basic sequences, SGR mouse and bracketed paste | no |
| `cli::events` | Blocking/timed `next_event` over `term` + `keys.Decoder`, Esc timeout, resize events | io::tty |
| `cli::line` | Line editor model (buffer, cursor, kill ring, history, word moves) driven by key events, and `read_line(prompt)` that runs it in raw mode, falling back to plain stdin when not a tty | model no, runner io::tty |
| `cli::prompt` | `confirm`, `input` (with default/validation), `password`, `select`, `multi_select` | runner io::tty |
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

The runtime restores a raw terminal when the program ends (exit, panic),
as that issue asks. `RawMode` also restores it in its `drop`, and programs
should `defer` `leave()`, because `drop` is a GC finaliser and runs late.

## Scope split with a TUI package

Proposed: a later `coil-tui` package depends on `cli` and adds layout
(rows/columns/constraints), widgets (list, table, text area, tabs, gauge),
focus and an application loop. coil-cli provides `cli::screen` and
`cli::events` as the stable seam. If we decide to keep everything in one
package instead, the TUI layer would live here as `cli::tui::*` and nothing
below it changes.

## Platforms

Whatever `io::tty` supports. On Windows the VT input/output console modes
give the same escape sequences, so the Coil layer is shared.

## Plan

1. Scaffolding, CI, this doc.
2. `cli::ansi`, `cli::color`, `cli::style`, `cli::width`.
3. `cli::keys` decoder.
4. `cli::args`.
5. `cli::progress` (rendering; tty check via a flag until `io::tty`).
6. `cli::line` model and `cli::prompt` models.
7. `cli::screen`.
8. Once `io::tty` lands: `cli::term`, `cli::events`, the line/prompt
   runners, examples and API docs.

Each step is one PR into `main`, merged when CI is green. Compiler or
stdlib bugs found along the way are filed in coil-lang / coil-stdlib with
a repro rather than worked around silently.
