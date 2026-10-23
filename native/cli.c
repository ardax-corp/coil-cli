// native/cli.c — terminal state, size and timed reads for coil-cli.

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#else
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cli.h"

static char g_last_error[256];
static int g_raw = 0;
static int g_atexit = 0;

static void set_error(const char *msg) {
    snprintf(g_last_error, sizeof(g_last_error), "%s", msg ? msg : "");
}

const char *coil_cli_last_error(void) {
    return g_last_error;
}

int64_t coil_cli_is_raw(void) {
    return g_raw;
}

#ifdef _WIN32

static DWORD g_in_mode;
static DWORD g_out_mode;
static int g_last_cols = -1;
static int g_last_rows = -1;

static void set_error_os(const char *prefix) {
    snprintf(g_last_error, sizeof(g_last_error), "%s: win32 %lu", prefix,
             (unsigned long)GetLastError());
}

static HANDLE fd_handle(int64_t fd) {
    if (fd == 0) return GetStdHandle(STD_INPUT_HANDLE);
    if (fd == 1) return GetStdHandle(STD_OUTPUT_HANDLE);
    if (fd == 2) return GetStdHandle(STD_ERROR_HANDLE);
    return INVALID_HANDLE_VALUE;
}

int64_t coil_cli_isatty(int64_t fd) {
    DWORD mode;
    HANDLE h = fd_handle(fd);
    return (h != INVALID_HANDLE_VALUE && GetConsoleMode(h, &mode)) ? 1 : 0;
}

static int console_size(int *cols, int *rows) {
    CONSOLE_SCREEN_BUFFER_INFO info;
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (!GetConsoleScreenBufferInfo(h, &info)) {
        h = GetStdHandle(STD_ERROR_HANDLE);
        if (!GetConsoleScreenBufferInfo(h, &info)) return 0;
    }
    *cols = info.srWindow.Right - info.srWindow.Left + 1;
    *rows = info.srWindow.Bottom - info.srWindow.Top + 1;
    return 1;
}

int64_t coil_cli_size(int64_t fd) {
    int cols, rows;
    (void)fd;
    if (!console_size(&cols, &rows)) {
        set_error_os("size");
        return COIL_CLI_ERR_NOTTY;
    }
    return ((int64_t)cols << 32) | (int64_t)rows;
}

int64_t coil_cli_enable_vt(void) {
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode;
    if (!GetConsoleMode(h, &mode)) {
        set_error_os("enable_vt");
        return COIL_CLI_ERR_NOTTY;
    }
    if (!SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING)) {
        set_error_os("enable_vt");
        return COIL_CLI_ERR_IO;
    }
    return 0;
}

int64_t coil_cli_raw_leave(void) {
    if (!g_raw) return 0;
    SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), g_in_mode);
    SetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), g_out_mode);
    g_raw = 0;
    return 0;
}

static void restore_at_exit(void) {
    coil_cli_raw_leave();
}

int64_t coil_cli_raw_enter(int64_t flags) {
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    if (g_raw) return 0;
    if (!GetConsoleMode(in, &g_in_mode) || !GetConsoleMode(out, &g_out_mode)) {
        set_error_os("raw_enter");
        return COIL_CLI_ERR_NOTTY;
    }
    DWORD in_mode = ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT;
    if (flags & COIL_CLI_RAW_KEEP_SIGNALS) in_mode |= ENABLE_PROCESSED_INPUT;
    DWORD out_mode = g_out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if (!(flags & COIL_CLI_RAW_KEEP_OUTPUT)) out_mode |= DISABLE_NEWLINE_AUTO_RETURN;
    if (!SetConsoleMode(in, in_mode) || !SetConsoleMode(out, out_mode)) {
        set_error_os("raw_enter");
        SetConsoleMode(in, g_in_mode);
        return COIL_CLI_ERR_IO;
    }
    g_raw = 1;
    if (!g_atexit) {
        atexit(restore_at_exit);
        g_atexit = 1;
    }
    return 0;
}

int64_t coil_cli_read(uint8_t *buf, int64_t cap, int64_t timeout_ms) {
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
    DWORD got = 0;
    if (cap <= 0) return 0;
    if (GetFileType(in) == FILE_TYPE_CHAR) {
        DWORD wait = timeout_ms < 0 ? INFINITE : (DWORD)timeout_ms;
        for (;;) {
            DWORD rc = WaitForSingleObject(in, wait);
            if (rc == WAIT_TIMEOUT) return 0;
            if (rc != WAIT_OBJECT_0) {
                set_error_os("read");
                return COIL_CLI_ERR_IO;
            }
            // Drop non-key records (focus, menu, resize) so ReadFile does not block.
            INPUT_RECORD rec;
            DWORD n = 0;
            if (PeekConsoleInputW(in, &rec, 1, &n) && n == 1 &&
                !(rec.EventType == KEY_EVENT && rec.Event.KeyEvent.bKeyDown)) {
                ReadConsoleInputW(in, &rec, 1, &n);
                continue;
            }
            break;
        }
    }
    if (!ReadFile(in, buf, (DWORD)cap, &got, NULL)) {
        if (GetLastError() == ERROR_BROKEN_PIPE) return COIL_CLI_EOF;
        set_error_os("read");
        return COIL_CLI_ERR_IO;
    }
    return got == 0 ? COIL_CLI_EOF : (int64_t)got;
}

int64_t coil_cli_resized(void) {
    int cols, rows;
    if (!console_size(&cols, &rows)) return 0;
    if (g_last_cols < 0) {
        g_last_cols = cols;
        g_last_rows = rows;
        return 0;
    }
    if (cols != g_last_cols || rows != g_last_rows) {
        g_last_cols = cols;
        g_last_rows = rows;
        return 1;
    }
    return 0;
}

#else

static struct termios g_saved;
static volatile sig_atomic_t g_winch = 0;
static int g_winch_installed = 0;

static void set_error_os(const char *prefix) {
    snprintf(g_last_error, sizeof(g_last_error), "%s: %s", prefix, strerror(errno));
}

int64_t coil_cli_isatty(int64_t fd) {
    return isatty((int)fd) ? 1 : 0;
}

int64_t coil_cli_size(int64_t fd) {
    struct winsize ws;
    int fds[3] = {(int)fd, 1, 2};
    for (int i = 0; i < 3; i++) {
        if (ioctl(fds[i], TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
            return ((int64_t)ws.ws_col << 32) | (int64_t)ws.ws_row;
        }
    }
    set_error_os("size");
    return COIL_CLI_ERR_NOTTY;
}

int64_t coil_cli_enable_vt(void) {
    return 0;
}

static void on_winch(int sig) {
    (void)sig;
    g_winch = 1;
}

static void install_winch(void) {
    if (g_winch_installed) return;
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_winch;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGWINCH, &sa, NULL);
    g_winch_installed = 1;
}

int64_t coil_cli_resized(void) {
    install_winch();
    if (g_winch) {
        g_winch = 0;
        return 1;
    }
    return 0;
}

int64_t coil_cli_raw_leave(void) {
    if (!g_raw) return 0;
    if (tcsetattr(0, TCSAFLUSH, &g_saved) != 0) {
        set_error_os("raw_leave");
        return COIL_CLI_ERR_IO;
    }
    g_raw = 0;
    return 0;
}

static void restore_at_exit(void) {
    coil_cli_raw_leave();
}

int64_t coil_cli_raw_enter(int64_t flags) {
    struct termios t;
    if (g_raw) return 0;
    if (!isatty(0)) {
        set_error("raw_enter: stdin is not a terminal");
        return COIL_CLI_ERR_NOTTY;
    }
    if (tcgetattr(0, &g_saved) != 0) {
        set_error_os("raw_enter");
        return COIL_CLI_ERR_IO;
    }
    t = g_saved;
    t.c_iflag &= ~(tcflag_t)(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    if (!(flags & COIL_CLI_RAW_KEEP_OUTPUT)) t.c_oflag &= ~(tcflag_t)OPOST;
    t.c_cflag |= CS8;
    t.c_lflag &= ~(tcflag_t)(ECHO | ICANON | IEXTEN);
    if (!(flags & COIL_CLI_RAW_KEEP_SIGNALS)) t.c_lflag &= ~(tcflag_t)ISIG;
    t.c_cc[VMIN] = 1;
    t.c_cc[VTIME] = 0;
    if (tcsetattr(0, TCSAFLUSH, &t) != 0) {
        set_error_os("raw_enter");
        return COIL_CLI_ERR_IO;
    }
    g_raw = 1;
    install_winch();
    if (!g_atexit) {
        atexit(restore_at_exit);
        g_atexit = 1;
    }
    return 0;
}

int64_t coil_cli_read(uint8_t *buf, int64_t cap, int64_t timeout_ms) {
    if (cap <= 0) return 0;
    for (;;) {
        struct pollfd p;
        p.fd = 0;
        p.events = POLLIN;
        p.revents = 0;
        int rc = poll(&p, 1, timeout_ms < 0 ? -1 : (int)timeout_ms);
        if (rc == 0) return 0;
        if (rc < 0) {
            // A resize interrupts the wait; report it as a timeout so the
            // caller can look at coil_cli_resized().
            if (errno == EINTR) return 0;
            set_error_os("read");
            return COIL_CLI_ERR_IO;
        }
        ssize_t n = read(0, buf, (size_t)cap);
        if (n > 0) return (int64_t)n;
        if (n == 0) return COIL_CLI_EOF;
        if (errno == EINTR || errno == EAGAIN) return 0;
        set_error_os("read");
        return COIL_CLI_ERR_IO;
    }
}

#endif
