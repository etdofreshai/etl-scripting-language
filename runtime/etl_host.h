#ifndef ETL_HOST_H
#define ETL_HOST_H

#include <stdint.h>

/*
 * etl_host bridge — temporary C-side runtime host bridge.
 *
 * An AOT-compiled ETL host program can use these two entry points to
 * compile a small ETL source buffer into bytecode and run it through
 * the embedded ETL VM. This is the host-bridge slice for D3.d in the
 * supervisor plan and the Phase 6 milestone in docs/runtime-vm-plan.md.
 *
 * The bridge is intentionally minimal:
 *   - etl_compile_module spawns a child process of a c1-built bytecode
 *     driver binary (path supplied via the ETL_BYTECODE_DRIVER env var)
 *     and pipes the source through it. The driver writes bytecode to
 *     stdout; we capture it into bytecode_out.
 *   - etl_run_main_i32 is a thin wrapper around etl_vm_run_main_i32.
 *
 * Long-term plan: when compiler-1 supports the runtime structures it
 * needs, both entry points will be implemented in ETL itself. Today
 * this C-side implementation is the bootstrap aid that lets us prove
 * the runtime-compile architecture end-to-end.
 *
 * Returns negative error codes on failure; see comments in etl_host.c
 * for the meaning of each code.
 */
int32_t etl_compile_module(const int8_t *source,
                           int32_t source_len,
                           int8_t *bytecode_out,
                           int32_t bytecode_cap);

int32_t etl_run_main_i32(const int8_t *bytecode,
                         int32_t bytecode_len,
                         int32_t *result_out);

#endif
