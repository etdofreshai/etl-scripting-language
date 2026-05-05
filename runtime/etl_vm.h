#ifndef ETL_VM_H
#define ETL_VM_H

#include <stdint.h>

/*
 * etl_vm_run_main_i32:
 *   Execute an ETL bytecode buffer and return its i32 result.
 *
 *   bytecode  - pointer to readable-ASCII ETL bytecode (begins "ETLB1;").
 *   len       - number of bytes in bytecode (excluding trailing nul).
 *   result    - on success (return 0), receives the value popped by R;.
 *
 *   Returns 0 on success or a negative error code:
 *     -1   bad pointer
 *     -2   bytecode too short to contain a header
 *     -3   bad magic
 *     -5   bad header separator or unrecognised opcode
 *     -6   I missing digit
 *     -7   I missing ';'
 *     -8   arithmetic op missing ';'
 *     -9   R missing ';'
 *     -10  pop on empty stack
 *     -11  push on full stack (limit 64 slots)
 *     -12  div/mod by zero
 *     -13  R with non-empty stack remainder
 *     -14  reserved (older VM rejected trailing bytes after R;)
 *     -15  ran off end without R;
 *     -16  L missing slot digit
 *     -17  L slot index out of range (limit 32 slots)
 *     -18  L malformed: missing ';' after load or '=;' after store
 *     -19  label/jump missing label digit
 *     -20  label/jump missing ';'
 *     -21  jump target label not found
 *     -22  execution step bound exceeded
 *
 * The interpreter is intentionally bounded and deterministic; it does not
 * allocate, perform any I/O, or access memory outside its parameters.
 */
int32_t etl_vm_run_main_i32(const int8_t *bytecode, int32_t len, int32_t *result);

#endif
