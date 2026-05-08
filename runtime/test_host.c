#include "etl_host.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

/*
 * test_host — tiny harness that exercises the runtime host bridge.
 *
 * Compiles a small ETL source via etl_compile_module, runs it through
 * etl_run_main_i32, and returns the result via process exit code.
 *
 * The ETL source to compile is read from argv[1] if provided;
 * otherwise a default integer-expression program is used.
 */

int main(int argc, char **argv) {
    const char *default_src = "fn main() i32 ret 1 + 2 * (9 - 4) end";
    const char *src_arg = (argc > 1) ? argv[1] : default_src;
    int32_t src_len = (int32_t)strlen(src_arg);

    static int8_t bytecode[1024];
    int32_t bc_len = etl_compile_module((const int8_t *)src_arg, src_len, bytecode, sizeof(bytecode));
    if (bc_len < 0) {
        fprintf(stderr, "test_host: etl_compile_module failed (%d)\n", bc_len);
        return 200;
    }

    int32_t result = 0;
    int32_t status = etl_run_main_i32(bytecode, bc_len, &result);
    if (status != 0) {
        fprintf(stderr, "test_host: etl_run_main_i32 failed (%d)\n", status);
        return 201;
    }
    if (result < 0 || result > 255) {
        fprintf(stderr, "test_host: result %d out of u8 exit-code range\n", result);
        return 202;
    }
    return (int)result;
}
