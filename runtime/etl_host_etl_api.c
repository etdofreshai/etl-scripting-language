/*
 * etl_host_etl_api.c — ETL-callable wrappers around the host bridge.
 *
 * These thin C functions expose etl_compile_module and etl_run_main_i32
 * with signatures that map cleanly to ETL extern-fn declarations:
 *
 *   extern fn host_compile_module(src i8[256], src_len i32, bc i8[4096], bc_cap i32) i32
 *   extern fn host_run_main_i32(bc i8[4096], bc_len i32) i32
 *
 * host_run_main_i32 returns the i32 result value directly (not via a
 * pointer-out parameter) so that ETL programs can use it without needing
 * a raw i32 pointer.  It returns -200 if the VM itself signals an error.
 *
 * These wrappers are compiled into programs that link etl_host.c and allow
 * ETL source programs (e.g. tests/host/runtime_compile_run.etl) to call the
 * host bridge end-to-end.
 */

#include "etl_host.h"
#include <stdint.h>

int32_t host_compile_module(const int8_t *src, int32_t src_len,
                             int8_t *bc, int32_t bc_cap)
{
    return etl_compile_module(src, src_len, bc, bc_cap);
}

int32_t host_run_main_i32(const int8_t *bc, int32_t bc_len)
{
    int32_t result = 0;
    int32_t status = etl_run_main_i32(bc, bc_len, &result);
    if (status != 0) return -200;
    return result;
}
