/*
 * etl_vm_main.c — standalone driver for the C ETL VM oracle.
 *
 * Reads bytecode from stdin, executes via etl_vm_run_main_i32,
 * and exits with the program's i32 return value (clamped to 0..255).
 *
 * Used by scripts/vm_equivalence_smoke.sh to produce a reference result
 * against which bin/etl-vm-etl is compared.
 */

#include "etl_vm.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define BC_MAX 65536

int main(void) {
    static int8_t buf[BC_MAX];
    int32_t len = 0;
    int c;

    while ((c = fgetc(stdin)) != EOF) {
        if (len >= BC_MAX) {
            fprintf(stderr, "etl_vm_main: bytecode too large (>%d)\n", BC_MAX);
            return 1;
        }
        buf[len++] = (int8_t)c;
    }

    int32_t result = 0;
    int32_t status = etl_vm_run_main_i32(buf, len, &result);
    if (status != 0) {
        fprintf(stderr, "etl_vm_main: VM error %d\n", status);
        return 1;
    }

    /* Clamp to exit-code range 0..255 */
    int exit_code = (int)(result & 0xff);
    return exit_code;
}
