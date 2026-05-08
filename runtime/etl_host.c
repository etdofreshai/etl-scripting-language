/* mkstemp is in stdlib.h on POSIX 2008 systems; expose via the BSD/SUS macro. */
#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 700

#include "etl_host.h"
#include "etl_vm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/*
 * Implementation of the temporary C host bridge.
 *
 * etl_compile_module:
 *   -1  bad arguments (NULL ptr, negative length, etc.)
 *   -2  bytecode_cap too small for a useful module
 *   -3  ETL_BYTECODE_DRIVER environment variable not set
 *   -4  could not create source temp file
 *   -5  could not write source temp file
 *   -6  could not create bytecode temp file
 *   -7  child process failed (driver exited non-zero)
 *   -8  could not read back emitted bytecode
 *   -9  emitted bytecode larger than bytecode_cap
 *
 * etl_run_main_i32:
 *   forwards the return code of etl_vm_run_main_i32 (negative on
 *   error, 0 on success).
 */

static int write_all(int fd, const int8_t *buf, int32_t len) {
    int32_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, (const char *)buf + off, (size_t)(len - off));
        if (n < 0) return -1;
        if (n == 0) return -1;
        off += (int32_t)n;
    }
    return 0;
}

int32_t etl_compile_module(const int8_t *source,
                           int32_t source_len,
                           int8_t *bytecode_out,
                           int32_t bytecode_cap) {
    if (source == NULL || bytecode_out == NULL) return -1;
    if (source_len < 0 || bytecode_cap < 32) return -2;

    const char *driver = getenv("ETL_BYTECODE_DRIVER");
    if (driver == NULL || driver[0] == '\0') return -3;

    char src_path[] = "/tmp/etl_host_src_XXXXXX";
    int sfd = mkstemp(src_path);
    if (sfd < 0) return -4;
    if (write_all(sfd, source, source_len) != 0) {
        close(sfd);
        unlink(src_path);
        return -5;
    }
    close(sfd);

    char bc_path[] = "/tmp/etl_host_bc_XXXXXX";
    int bfd = mkstemp(bc_path);
    if (bfd < 0) {
        unlink(src_path);
        return -6;
    }
    close(bfd);

    /* Build the command: <driver> < <src> > <bc> 2>/dev/null */
    char cmd[2048];
    int written = snprintf(cmd, sizeof(cmd),
                           "%s < %s > %s 2>/dev/null",
                           driver, src_path, bc_path);
    if (written < 0 || (size_t)written >= sizeof(cmd)) {
        unlink(src_path);
        unlink(bc_path);
        return -3;
    }

    int rc = system(cmd);
    if (rc != 0) {
        unlink(src_path);
        unlink(bc_path);
        return -7;
    }

    FILE *bf = fopen(bc_path, "rb");
    if (bf == NULL) {
        unlink(src_path);
        unlink(bc_path);
        return -8;
    }
    size_t n = fread(bytecode_out, 1, (size_t)bytecode_cap, bf);
    int eof_ok = feof(bf);
    fclose(bf);
    unlink(src_path);
    unlink(bc_path);
    if (!eof_ok) return -9;
    return (int32_t)n;
}

int32_t etl_run_main_i32(const int8_t *bytecode,
                         int32_t bytecode_len,
                         int32_t *result_out) {
    int32_t local_result = 0;
    int32_t status = etl_vm_run_main_i32(bytecode,
                                          bytecode_len,
                                          (result_out != NULL) ? result_out : &local_result);
    return status;
}
