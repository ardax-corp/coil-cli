// C ABI smoke test for libcli. On POSIX it drives a pseudo-terminal.
#ifndef _WIN32
#define _XOPEN_SOURCE 600
#define _DARWIN_C_SOURCE
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cli.h"

static void fail(const char *msg) {
    fprintf(stderr, "smoke: %s (%s)\n", msg, coil_cli_last_error());
    exit(1);
}

#ifdef _WIN32

int main(void) {
    // CI has no console: the calls must fail cleanly, not crash.
    int64_t tty = coil_cli_isatty(0);
    if (tty != 0 && tty != 1) fail("isatty");
    if (!tty && coil_cli_raw_enter(0) != COIL_CLI_ERR_NOTTY) fail("raw_enter without console");
    if (coil_cli_raw_leave() != 0) fail("raw_leave");
    coil_cli_enable_vt();
    coil_cli_resized();
    puts("smoke ok");
    return 0;
}

#else

#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

int main(void) {
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0) fail("openpt");
    int slave = open(ptsname(master), O_RDWR | O_NOCTTY);
    if (slave < 0) fail("open slave");

    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_col = 100;
    ws.ws_row = 30;
    if (ioctl(slave, TIOCSWINSZ, &ws) != 0) fail("TIOCSWINSZ");

    int saved_stdin = dup(0);
    if (dup2(slave, 0) < 0) fail("dup2");

    if (coil_cli_isatty(0) != 1) fail("isatty(pty)");
    int64_t sz = coil_cli_size(0);
    if (sz < 0 || (sz >> 32) != 100 || (sz & 0xffffffff) != 30) fail("size");

    if (coil_cli_raw_enter(0) != 0) fail("raw_enter");
    if (coil_cli_is_raw() != 1) fail("is_raw");
    struct termios t;
    tcgetattr(0, &t);
    if (t.c_lflag & (ECHO | ICANON | ISIG)) fail("raw lflag");
    if (t.c_oflag & OPOST) fail("raw oflag");

    uint8_t buf[16];
    if (coil_cli_read(buf, sizeof(buf), 20) != 0) fail("read timeout");
    if (write(master, "\x1b[A", 3) != 3) fail("write master");
    int64_t n = coil_cli_read(buf, sizeof(buf), 1000);
    if (n != 3 || memcmp(buf, "\x1b[A", 3) != 0) fail("read bytes");

    coil_cli_resized();
    raise(SIGWINCH);
    if (coil_cli_resized() != 1) fail("resized after SIGWINCH");
    if (coil_cli_resized() != 0) fail("resized clears");

    if (coil_cli_raw_leave() != 0) fail("raw_leave");
    tcgetattr(0, &t);
    if (!(t.c_lflag & ICANON)) fail("restored lflag");

    if (coil_cli_raw_enter(COIL_CLI_RAW_KEEP_SIGNALS | COIL_CLI_RAW_KEEP_OUTPUT) != 0) fail("raw_enter flags");
    tcgetattr(0, &t);
    if (!(t.c_lflag & ISIG) || !(t.c_oflag & OPOST)) fail("raw keep flags");
    coil_cli_raw_leave();

    dup2(saved_stdin, 0);
    int devnull = open("/dev/null", O_RDONLY);
    dup2(devnull, 0);
    if (coil_cli_isatty(0) != 0) fail("isatty(/dev/null)");
    if (coil_cli_raw_enter(0) != COIL_CLI_ERR_NOTTY) fail("raw_enter on non-tty");
    if (coil_cli_read(buf, sizeof(buf), 100) != COIL_CLI_EOF) fail("read eof");

    puts("smoke ok");
    return 0;
}

#endif
