#include "etl_vm.h"

/*
 * ETL VM bootstrap interpreter (temporary C implementation).
 *
 * Bytecode format (readable ASCII; ';' is the universal separator):
 *
 *   ETLB1;            magic + version (always first)
 *   I<int>;           push i32 literal (decimal, non-negative)
 *   +;  -;  *;  /;  %;
 *                     pop right, pop left, push (left OP right)
 *                     (/ and % trap on right == 0 -> error code -12)
 *   L<idx>;           load_local slot <idx>: push locals[idx]
 *   L<idx>=;          store_local slot <idx>: pop top, locals[idx] = value
 *   R;                pop top of stack and return as exit value
 *
 * Locals slots are zero-initialised before execution; valid indices are
 * 0..ETL_VM_LOCAL_MAX-1. Stack is bounded at ETL_VM_STACK_MAX. All limits
 * produce deterministic negative error codes; see header comments.
 */

#define ETL_VM_STACK_MAX 64
#define ETL_VM_LOCAL_MAX 32

static int etl_vm_is_digit(int8_t ch) {
    return ch >= '0' && ch <= '9';
}

static int32_t etl_vm_pop_i32(int32_t *stack, int32_t *sp, int32_t *out) {
    if (*sp <= 0) {
        return -10;
    }
    *sp = *sp - 1;
    *out = stack[*sp];
    return 0;
}

static int32_t etl_vm_push_i32(int32_t *stack, int32_t *sp, int32_t value) {
    if (*sp >= ETL_VM_STACK_MAX) {
        return -11;
    }
    stack[*sp] = value;
    *sp = *sp + 1;
    return 0;
}

int32_t etl_vm_run_main_i32(const int8_t *bytecode, int32_t len, int32_t *result) {
    if (bytecode == 0 || result == 0) {
        return -1;
    }
    if (len < 8) {
        return -2;
    }
    if (bytecode[0] != 'E' || bytecode[1] != 'T' || bytecode[2] != 'L' ||
        bytecode[3] != 'B' || bytecode[4] != '1') {
        return -3;
    }
    if (bytecode[5] != ';') {
        return -5;
    }

    int32_t stack[ETL_VM_STACK_MAX];
    int32_t locals[ETL_VM_LOCAL_MAX];
    for (int32_t li = 0; li < ETL_VM_LOCAL_MAX; li = li + 1) {
        locals[li] = 0;
    }
    int32_t sp = 0;
    int32_t i = 6;
    while (i < len) {
        int8_t op = bytecode[i];
        i = i + 1;

        if (op == 'I') {
            if (i >= len || !etl_vm_is_digit(bytecode[i])) {
                return -6;
            }
            int32_t value = 0;
            while (i < len && etl_vm_is_digit(bytecode[i])) {
                value = value * 10 + (bytecode[i] - '0');
                i = i + 1;
            }
            if (i >= len || bytecode[i] != ';') {
                return -7;
            }
            i = i + 1;
            int32_t pushed = etl_vm_push_i32(stack, &sp, value);
            if (pushed < 0) {
                return pushed;
            }
        } else if (op == '+' || op == '-' || op == '*' || op == '/' || op == '%') {
            if (i >= len || bytecode[i] != ';') {
                return -8;
            }
            i = i + 1;
            int32_t right = 0;
            int32_t left = 0;
            int32_t popped = etl_vm_pop_i32(stack, &sp, &right);
            if (popped < 0) {
                return popped;
            }
            popped = etl_vm_pop_i32(stack, &sp, &left);
            if (popped < 0) {
                return popped;
            }
            int32_t value = 0;
            if (op == '+') {
                value = left + right;
            } else if (op == '-') {
                value = left - right;
            } else if (op == '*') {
                value = left * right;
            } else if (op == '/') {
                if (right == 0) {
                    return -12;
                }
                value = left / right;
            } else {
                if (right == 0) {
                    return -12;
                }
                value = left % right;
            }
            int32_t pushed = etl_vm_push_i32(stack, &sp, value);
            if (pushed < 0) {
                return pushed;
            }
        } else if (op == 'L') {
            if (i >= len || !etl_vm_is_digit(bytecode[i])) {
                return -16;
            }
            int32_t slot = 0;
            while (i < len && etl_vm_is_digit(bytecode[i])) {
                slot = slot * 10 + (bytecode[i] - '0');
                i = i + 1;
            }
            if (slot < 0 || slot >= ETL_VM_LOCAL_MAX) {
                return -17;
            }
            if (i >= len) {
                return -18;
            }
            if (bytecode[i] == '=') {
                i = i + 1;
                if (i >= len || bytecode[i] != ';') {
                    return -18;
                }
                i = i + 1;
                int32_t value = 0;
                int32_t popped = etl_vm_pop_i32(stack, &sp, &value);
                if (popped < 0) {
                    return popped;
                }
                locals[slot] = value;
            } else if (bytecode[i] == ';') {
                i = i + 1;
                int32_t pushed = etl_vm_push_i32(stack, &sp, locals[slot]);
                if (pushed < 0) {
                    return pushed;
                }
            } else {
                return -18;
            }
        } else if (op == 'R') {
            if (i >= len || bytecode[i] != ';') {
                return -9;
            }
            i = i + 1;
            int32_t value = 0;
            int32_t popped = etl_vm_pop_i32(stack, &sp, &value);
            if (popped < 0) {
                return popped;
            }
            if (sp != 0) {
                return -13;
            }
            if (i != len) {
                return -14;
            }
            *result = value;
            return 0;
        } else {
            return -5;
        }
    }

    return -15;
}
