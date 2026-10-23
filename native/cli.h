// coil-cli C ABI — terminal state, size, timed reads. Not HostInvoke.
#pragma once

#include <stdint.h>

#define COIL_CLI_ERR_IO (-2)
#define COIL_CLI_ERR_NOTTY (-3)
#define COIL_CLI_EOF (-1)

// Raw-mode flags.
#define COIL_CLI_RAW_KEEP_SIGNALS 1  // leave ISIG on: Ctrl-C / Ctrl-Z still signal
#define COIL_CLI_RAW_KEEP_OUTPUT 2   // leave OPOST on: "\n" still moves to column 0

int64_t coil_cli_isatty(int64_t fd);
// (cols << 32) | rows, or a negative error.
int64_t coil_cli_size(int64_t fd);
int64_t coil_cli_raw_enter(int64_t flags);
int64_t coil_cli_raw_leave(void);
int64_t coil_cli_is_raw(void);
// Bytes read (> 0), 0 on timeout, COIL_CLI_EOF at end of input, or an error.
// timeout_ms < 0 waits forever.
int64_t coil_cli_read(uint8_t *buf, int64_t cap, int64_t timeout_ms);
// 1 once per resize since the last call, else 0.
int64_t coil_cli_resized(void);
int64_t coil_cli_enable_vt(void);
const char *coil_cli_last_error(void);
