#include "etl_vm.h"

/*
 * ETL VM bootstrap interpreter (temporary C implementation).
 *
 * Bytecode format (readable ASCII; ';' is the universal separator):
 *
 *   ETLB1;            magic + version (always first)
 *   T<count>;         function table count
 *   D<name>,<argc>;   function table entry. The loader resolves the matching
 *                     @<name>; body marker into a byte offset.
 *   C<name>;          call function. Args are popped into callee locals.
 *   @<name>;          body marker (no-op when reached by linear scanning)
 *   I<int>;           push i32 literal (decimal, non-negative)
 *   +;  -;  *;  /;  %;
 *                     pop right, pop left, push (left OP right)
 *                     (/ and % trap on right == 0 -> error code -12)
 *   q;  n;  <;  l;  >;  g;
 *                     comparisons: ==, !=, <, <=, >, >=. Push 1 or 0.
 *   !;                logical not: pop value, push value == 0.
 *   L<idx>;           load_local slot <idx>: push locals[idx]
 *   L<idx>=;          store_local slot <idx>: pop top, locals[idx] = value
 *   :<label>;         label definition (no-op at runtime)
 *   F<label>;         pop condition; jump to label if condition == 0
 *   J<label>;         unconditional jump to label
 *   R;                pop top of stack and return as exit value
 *                     at frame depth 0, or return to caller otherwise.
 *
 * Locals slots are zero-initialised before execution; valid indices are
 * 0..ETL_VM_LOCAL_MAX-1. Stack is bounded at ETL_VM_STACK_MAX. All limits
 * produce deterministic negative error codes; see header comments.
 */

#define ETL_VM_STACK_MAX 64
#define ETL_VM_LOCAL_MAX 32
#define ETL_VM_FUNC_MAX 32
#define ETL_VM_NAME_MAX 32
#define ETL_VM_FRAME_MAX 32
#define ETL_VM_STEP_MAX 100000

typedef struct {
    int8_t name[ETL_VM_NAME_MAX];
    int32_t name_len;
    int32_t argc;
    int32_t ip;
} EtlVmFunction;

typedef struct {
    int32_t return_ip;
    int32_t locals[ETL_VM_LOCAL_MAX];
} EtlVmFrame;

static int etl_vm_is_digit(int8_t ch) {
    return ch >= '0' && ch <= '9';
}

static int32_t etl_vm_parse_i32(const int8_t *bytecode, int32_t len, int32_t *i, int32_t *out) {
    if (*i >= len || !etl_vm_is_digit(bytecode[*i])) {
        return -6;
    }
    int32_t value = 0;
    while (*i < len && etl_vm_is_digit(bytecode[*i])) {
        value = value * 10 + (bytecode[*i] - '0');
        *i = *i + 1;
    }
    *out = value;
    return 0;
}

static int32_t etl_vm_find_label(const int8_t *bytecode, int32_t len, int32_t label) {
    int32_t i = 6;
    while (i < len) {
        if (bytecode[i] == ':') {
            i = i + 1;
            int32_t parsed = 0;
            int32_t rc = etl_vm_parse_i32(bytecode, len, &i, &parsed);
            if (rc < 0) {
                return -19;
            }
            if (i >= len || bytecode[i] != ';') {
                return -20;
            }
            i = i + 1;
            if (parsed == label) {
                return i;
            }
        } else {
            i = i + 1;
        }
    }
    return -21;
}

static int32_t etl_vm_name_equals(const int8_t *a, int32_t a_len, const int8_t *b, int32_t b_len) {
    if (a_len != b_len) {
        return 0;
    }
    for (int32_t i = 0; i < a_len; i = i + 1) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}

static int32_t etl_vm_skip_to_sep(const int8_t *bytecode, int32_t len, int32_t *i) {
    while (*i < len && bytecode[*i] != ';') {
        *i = *i + 1;
    }
    if (*i >= len || bytecode[*i] != ';') {
        return -23;
    }
    *i = *i + 1;
    return 0;
}

static int32_t etl_vm_find_body(const int8_t *bytecode, int32_t len, const int8_t *name, int32_t name_len) {
    int32_t i = 6;
    while (i < len) {
        if (bytecode[i] == '@') {
            i = i + 1;
            int32_t start = i;
            while (i < len && bytecode[i] != ';') {
                i = i + 1;
            }
            if (i >= len || bytecode[i] != ';') {
                return -23;
            }
            if (etl_vm_name_equals(bytecode + start, i - start, name, name_len)) {
                return i + 1;
            }
            i = i + 1;
        } else {
            i = i + 1;
        }
    }
    return -24;
}

static int32_t etl_vm_parse_functions(const int8_t *bytecode, int32_t len, int32_t *i,
                                      EtlVmFunction *funcs, int32_t *func_count) {
    *func_count = 0;
    if (*i >= len || bytecode[*i] != 'T') {
        return 0;
    }
    *i = *i + 1;
    int32_t count = 0;
    int32_t rc = etl_vm_parse_i32(bytecode, len, i, &count);
    if (rc < 0) {
        return -25;
    }
    if (count < 0 || count > ETL_VM_FUNC_MAX) {
        return -26;
    }
    if (*i >= len || bytecode[*i] != ';') {
        return -27;
    }
    *i = *i + 1;
    for (int32_t fi = 0; fi < count; fi = fi + 1) {
        if (*i >= len || bytecode[*i] != 'D') {
            return -28;
        }
        *i = *i + 1;
        int32_t name_len = 0;
        while (*i < len && bytecode[*i] != ',') {
            if (name_len >= ETL_VM_NAME_MAX) {
                return -29;
            }
            funcs[fi].name[name_len] = bytecode[*i];
            name_len = name_len + 1;
            *i = *i + 1;
        }
        if (*i >= len || bytecode[*i] != ',' || name_len <= 0) {
            return -30;
        }
        funcs[fi].name_len = name_len;
        *i = *i + 1;
        rc = etl_vm_parse_i32(bytecode, len, i, &funcs[fi].argc);
        if (rc < 0) {
            return -31;
        }
        if (funcs[fi].argc < 0 || funcs[fi].argc > ETL_VM_LOCAL_MAX) {
            return -32;
        }
        if (*i >= len || bytecode[*i] != ';') {
            return -33;
        }
        *i = *i + 1;
        funcs[fi].ip = etl_vm_find_body(bytecode, len, funcs[fi].name, funcs[fi].name_len);
        if (funcs[fi].ip < 0) {
            return funcs[fi].ip;
        }
    }
    *func_count = count;
    return 0;
}

static int32_t etl_vm_find_function(EtlVmFunction *funcs, int32_t func_count, const int8_t *name, int32_t name_len) {
    for (int32_t fi = 0; fi < func_count; fi = fi + 1) {
        if (etl_vm_name_equals(funcs[fi].name, funcs[fi].name_len, name, name_len)) {
            return fi;
        }
    }
    return -34;
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
    EtlVmFunction funcs[ETL_VM_FUNC_MAX];
    EtlVmFrame frames[ETL_VM_FRAME_MAX];
    int32_t frame_depth = 0;
    int32_t *locals = frames[0].locals;
    for (int32_t li = 0; li < ETL_VM_LOCAL_MAX; li = li + 1) {
        locals[li] = 0;
    }
    int32_t sp = 0;
    int32_t i = 6;
    int32_t func_count = 0;
    int32_t parsed_funcs = etl_vm_parse_functions(bytecode, len, &i, funcs, &func_count);
    if (parsed_funcs < 0) {
        return parsed_funcs;
    }
    int32_t steps = 0;
    while (i < len) {
        steps = steps + 1;
        if (steps > ETL_VM_STEP_MAX) {
            return -22;
        }
        int8_t op = bytecode[i];
        i = i + 1;

        if (op == 'I') {
            int32_t value = 0;
            int32_t parsed = etl_vm_parse_i32(bytecode, len, &i, &value);
            if (parsed < 0) {
                return parsed;
            }
            if (i >= len || bytecode[i] != ';') {
                return -7;
            }
            i = i + 1;
            int32_t pushed = etl_vm_push_i32(stack, &sp, value);
            if (pushed < 0) {
                return pushed;
            }
        } else if (op == '+' || op == '-' || op == '*' || op == '/' || op == '%' ||
                   op == 'q' || op == 'n' || op == '<' || op == 'l' || op == '>' || op == 'g') {
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
                if (op == 'q') {
                    value = left == right;
                } else if (op == 'n') {
                    value = left != right;
                } else if (op == '<') {
                    value = left < right;
                } else if (op == 'l') {
                    value = left <= right;
                } else if (op == '>') {
                    value = left > right;
                } else if (op == 'g') {
                    value = left >= right;
                } else {
                if (right == 0) {
                    return -12;
                }
                value = left % right;
                }
            }
            int32_t pushed = etl_vm_push_i32(stack, &sp, value);
            if (pushed < 0) {
                return pushed;
            }
        } else if (op == '!') {
            if (i >= len || bytecode[i] != ';') {
                return -8;
            }
            i = i + 1;
            int32_t value = 0;
            int32_t popped = etl_vm_pop_i32(stack, &sp, &value);
            if (popped < 0) {
                return popped;
            }
            int32_t pushed = etl_vm_push_i32(stack, &sp, value == 0);
            if (pushed < 0) {
                return pushed;
            }
        } else if (op == 'L') {
            int32_t slot = 0;
            int32_t parsed = etl_vm_parse_i32(bytecode, len, &i, &slot);
            if (parsed < 0) {
                return -16;
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
        } else if (op == ':') {
            int32_t label = 0;
            int32_t parsed = etl_vm_parse_i32(bytecode, len, &i, &label);
            if (parsed < 0) {
                return -19;
            }
            (void)label;
            if (i >= len || bytecode[i] != ';') {
                return -20;
            }
            i = i + 1;
        } else if (op == 'F' || op == 'J') {
            int32_t label = 0;
            int32_t parsed = etl_vm_parse_i32(bytecode, len, &i, &label);
            if (parsed < 0) {
                return -19;
            }
            if (i >= len || bytecode[i] != ';') {
                return -20;
            }
            i = i + 1;
            int32_t should_jump = 1;
            if (op == 'F') {
                int32_t value = 0;
                int32_t popped = etl_vm_pop_i32(stack, &sp, &value);
                if (popped < 0) {
                    return popped;
                }
                should_jump = value == 0;
            }
            if (should_jump) {
                int32_t target = etl_vm_find_label(bytecode, len, label);
                if (target < 0) {
                    return target;
                }
                i = target;
            }
        } else if (op == '@') {
            int32_t skipped = etl_vm_skip_to_sep(bytecode, len, &i);
            if (skipped < 0) {
                return skipped;
            }
        } else if (op == 'C') {
            int32_t name_start = i;
            while (i < len && bytecode[i] != ';') {
                i = i + 1;
            }
            if (i >= len || bytecode[i] != ';') {
                return -35;
            }
            int32_t name_len = i - name_start;
            i = i + 1;
            int32_t fn_index = etl_vm_find_function(funcs, func_count, bytecode + name_start, name_len);
            if (fn_index < 0) {
                return fn_index;
            }
            if (frame_depth + 1 >= ETL_VM_FRAME_MAX) {
                return -36;
            }
            frame_depth = frame_depth + 1;
            frames[frame_depth].return_ip = i;
            locals = frames[frame_depth].locals;
            for (int32_t li = 0; li < ETL_VM_LOCAL_MAX; li = li + 1) {
                locals[li] = 0;
            }
            for (int32_t ai = funcs[fn_index].argc - 1; ai >= 0; ai = ai - 1) {
                int32_t value = 0;
                int32_t popped = etl_vm_pop_i32(stack, &sp, &value);
                if (popped < 0) {
                    return popped;
                }
                locals[ai] = value;
            }
            i = funcs[fn_index].ip;
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
            if (frame_depth > 0) {
                i = frames[frame_depth].return_ip;
                frame_depth = frame_depth - 1;
                locals = frames[frame_depth].locals;
                int32_t pushed = etl_vm_push_i32(stack, &sp, value);
                if (pushed < 0) {
                    return pushed;
                }
            } else {
                if (sp != 0) {
                    return -13;
                }
                *result = value;
                return 0;
            }
        } else {
            return -5;
        }
    }

    return -15;
}
