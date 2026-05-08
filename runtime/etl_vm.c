#include "etl_vm.h"
#include "etl_string.h"
#include "etl_dynarr.h"
#include "etl_etlval.h"
#include <stdlib.h>

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
#define ETL_VM_ALLOC_MAX 64

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
    void *etl_alloc_table[ETL_VM_ALLOC_MAX];
    int32_t etl_alloc_count = 0;
    for (int32_t ai = 0; ai < ETL_VM_ALLOC_MAX; ai = ai + 1) { etl_alloc_table[ai] = 0; }
    /* String table for HS* opcodes */
    EtlString *str_table[ETL_VM_ALLOC_MAX];
    int32_t str_count = 0;
    for (int32_t si = 0; si < ETL_VM_ALLOC_MAX; si = si + 1) { str_table[si] = 0; }
    /* DynArr table for HD* opcodes */
    EtlDynArr *dynarr_table[ETL_VM_ALLOC_MAX];
    int32_t dynarr_count = 0;
    for (int32_t di = 0; di < ETL_VM_ALLOC_MAX; di = di + 1) { dynarr_table[di] = 0; }
    /* EtlVal table for HV* opcodes */
    EtlVal *etlval_table[ETL_VM_ALLOC_MAX];
    int32_t etlval_count = 0;
    for (int32_t vi = 0; vi < ETL_VM_ALLOC_MAX; vi = vi + 1) { etlval_table[vi] = 0; }
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
                for (int32_t ci = 0; ci < etl_alloc_count; ci = ci + 1) {
                    if (etl_alloc_table[ci] != 0) { free(etl_alloc_table[ci]); etl_alloc_table[ci] = 0; }
                }
                for (int32_t si = 0; si < str_count; si = si + 1) {
                    if (str_table[si] != 0) { str_free(str_table[si]); str_table[si] = 0; }
                }
                for (int32_t di = 0; di < dynarr_count; di = di + 1) {
                    if (dynarr_table[di] != 0) { dynarr_free(dynarr_table[di]); dynarr_table[di] = 0; }
                }
                for (int32_t vi = 0; vi < etlval_count; vi = vi + 1) {
                    if (etlval_table[vi] != 0) { etlval_free(etlval_table[vi]); etlval_table[vi] = 0; }
                }
                *result = value;
                return 0;
            }
        } else if (op == 'H') {
            if (i >= len) { return -5; }
            int8_t sub = bytecode[i];
            i = i + 1;
            if (sub == 'S') {
                /* HS* string opcodes: next char is sub-op, then ';' */
                if (i >= len) { return -5; }
                int8_t sub2 = bytecode[i];
                i = i + 1;
                if (i >= len || bytecode[i] != ';') { return -5; }
                i = i + 1;
                if (sub2 == 'N') {
                    /* str_new: pop ptr handle (ignored in VM) → create empty string */
                    int32_t _ptr_h = 0;
                    int32_t popped = etl_vm_pop_i32(stack, &sp, &_ptr_h);
                    if (popped < 0) { return popped; }
                    if (str_count >= ETL_VM_ALLOC_MAX) { return -37; }
                    EtlString *ns = str_new((void *)"");
                    if (!ns) { return -38; }
                    str_table[str_count] = ns;
                    int32_t handle = str_count + 1;
                    str_count = str_count + 1;
                    int32_t pushed = etl_vm_push_i32(stack, &sp, handle);
                    if (pushed < 0) { return pushed; }
                } else if (sub2 == 'L') {
                    /* str_len: pop handle, push len */
                    int32_t h = 0;
                    int32_t popped = etl_vm_pop_i32(stack, &sp, &h);
                    if (popped < 0) { return popped; }
                    int32_t slen = 0;
                    if (h > 0 && h <= str_count && str_table[h-1] != 0) {
                        slen = str_len(str_table[h-1]);
                    }
                    int32_t pushed = etl_vm_push_i32(stack, &sp, slen);
                    if (pushed < 0) { return pushed; }
                } else if (sub2 == 'C') {
                    /* str_concat: pop b handle then a handle, push new handle */
                    int32_t hb = 0, ha = 0;
                    int32_t popped = etl_vm_pop_i32(stack, &sp, &hb);
                    if (popped < 0) { return popped; }
                    popped = etl_vm_pop_i32(stack, &sp, &ha);
                    if (popped < 0) { return popped; }
                    if (str_count >= ETL_VM_ALLOC_MAX) { return -37; }
                    EtlString *sa = (ha > 0 && ha <= str_count) ? str_table[ha-1] : 0;
                    EtlString *sb = (hb > 0 && hb <= str_count) ? str_table[hb-1] : 0;
                    EtlString *sc = 0;
                    if (sa && sb) { sc = str_concat(sa, sb); }
                    else { sc = str_new((void *)""); }
                    if (!sc) { return -38; }
                    str_table[str_count] = sc;
                    int32_t handle = str_count + 1;
                    str_count = str_count + 1;
                    int32_t pushed = etl_vm_push_i32(stack, &sp, handle);
                    if (pushed < 0) { return pushed; }
                } else if (sub2 == 'A') {
                    /* str_at: pop i then handle, push byte */
                    int32_t idx = 0, h = 0;
                    int32_t popped = etl_vm_pop_i32(stack, &sp, &idx);
                    if (popped < 0) { return popped; }
                    popped = etl_vm_pop_i32(stack, &sp, &h);
                    if (popped < 0) { return popped; }
                    int32_t byte_val = 0;
                    if (h > 0 && h <= str_count && str_table[h-1] != 0) {
                        byte_val = (int32_t)str_at(str_table[h-1], idx);
                    }
                    int32_t pushed = etl_vm_push_i32(stack, &sp, byte_val);
                    if (pushed < 0) { return pushed; }
                } else if (sub2 == 'E') {
                    /* str_eq: pop b handle then a handle, push bool */
                    int32_t hb2 = 0, ha2 = 0;
                    int32_t popped = etl_vm_pop_i32(stack, &sp, &hb2);
                    if (popped < 0) { return popped; }
                    popped = etl_vm_pop_i32(stack, &sp, &ha2);
                    if (popped < 0) { return popped; }
                    int32_t eq_result = 0;
                    EtlString *sa2 = (ha2 > 0 && ha2 <= str_count) ? str_table[ha2-1] : 0;
                    EtlString *sb2 = (hb2 > 0 && hb2 <= str_count) ? str_table[hb2-1] : 0;
                    if (sa2 && sb2) { eq_result = str_eq(sa2, sb2); }
                    int32_t pushed = etl_vm_push_i32(stack, &sp, eq_result);
                    if (pushed < 0) { return pushed; }
                } else if (sub2 == 'F') {
                    /* str_free: pop handle, free string */
                    int32_t h = 0;
                    int32_t popped = etl_vm_pop_i32(stack, &sp, &h);
                    if (popped < 0) { return popped; }
                    if (h > 0 && h <= str_count && str_table[h-1] != 0) {
                        str_free(str_table[h-1]);
                        str_table[h-1] = 0;
                    }
                } else {
                    return -5;
                }
            } else if (sub == 'D') {
                /* HD* dynarr opcodes: next char is sub-op, then ';' */
                if (i >= len) { return -5; }
                int8_t sub2d = bytecode[i];
                i = i + 1;
                if (i >= len || bytecode[i] != ';') { return -5; }
                i = i + 1;
                if (sub2d == 'N') {
                    /* HDN; dynarr_new: no args, push handle */
                    if (dynarr_count >= ETL_VM_ALLOC_MAX) { return -37; }
                    EtlDynArr *nd = dynarr_new();
                    if (!nd) { return -38; }
                    dynarr_table[dynarr_count] = nd;
                    int32_t dh = dynarr_count + 1;
                    dynarr_count = dynarr_count + 1;
                    int32_t pushed_n = etl_vm_push_i32(stack, &sp, dh);
                    if (pushed_n < 0) { return pushed_n; }
                } else if (sub2d == 'P') {
                    /* HDP; dynarr_push: pop v, pop handle */
                    int32_t v = 0;
                    int32_t popped_v = etl_vm_pop_i32(stack, &sp, &v);
                    if (popped_v < 0) { return popped_v; }
                    int32_t dh_p = 0;
                    int32_t popped_h = etl_vm_pop_i32(stack, &sp, &dh_p);
                    if (popped_h < 0) { return popped_h; }
                    if (dh_p > 0 && dh_p <= dynarr_count && dynarr_table[dh_p-1] != 0) {
                        dynarr_push(dynarr_table[dh_p-1], v);
                    }
                } else if (sub2d == 'L') {
                    /* HDL; dynarr_len: pop handle, push len */
                    int32_t dh_l = 0;
                    int32_t popped_hl = etl_vm_pop_i32(stack, &sp, &dh_l);
                    if (popped_hl < 0) { return popped_hl; }
                    int32_t dlen = 0;
                    if (dh_l > 0 && dh_l <= dynarr_count && dynarr_table[dh_l-1] != 0) {
                        dlen = dynarr_len(dynarr_table[dh_l-1]);
                    }
                    int32_t pushed_l = etl_vm_push_i32(stack, &sp, dlen);
                    if (pushed_l < 0) { return pushed_l; }
                } else if (sub2d == 'G') {
                    /* HDG; dynarr_get: pop i, pop handle, push element */
                    int32_t gi = 0;
                    int32_t popped_gi = etl_vm_pop_i32(stack, &sp, &gi);
                    if (popped_gi < 0) { return popped_gi; }
                    int32_t dh_g = 0;
                    int32_t popped_hg = etl_vm_pop_i32(stack, &sp, &dh_g);
                    if (popped_hg < 0) { return popped_hg; }
                    int32_t gval = 0;
                    if (dh_g > 0 && dh_g <= dynarr_count && dynarr_table[dh_g-1] != 0) {
                        gval = dynarr_get(dynarr_table[dh_g-1], gi);
                    }
                    int32_t pushed_g = etl_vm_push_i32(stack, &sp, gval);
                    if (pushed_g < 0) { return pushed_g; }
                } else if (sub2d == 'S') {
                    /* HDS; dynarr_set: pop v, pop i, pop handle */
                    int32_t sv = 0;
                    int32_t popped_sv = etl_vm_pop_i32(stack, &sp, &sv);
                    if (popped_sv < 0) { return popped_sv; }
                    int32_t si2 = 0;
                    int32_t popped_si2 = etl_vm_pop_i32(stack, &sp, &si2);
                    if (popped_si2 < 0) { return popped_si2; }
                    int32_t dh_s = 0;
                    int32_t popped_hs = etl_vm_pop_i32(stack, &sp, &dh_s);
                    if (popped_hs < 0) { return popped_hs; }
                    if (dh_s > 0 && dh_s <= dynarr_count && dynarr_table[dh_s-1] != 0) {
                        dynarr_set(dynarr_table[dh_s-1], si2, sv);
                    }
                } else if (sub2d == 'F') {
                    /* HDF; dynarr_free: pop handle */
                    int32_t dh_f = 0;
                    int32_t popped_hf = etl_vm_pop_i32(stack, &sp, &dh_f);
                    if (popped_hf < 0) { return popped_hf; }
                    if (dh_f > 0 && dh_f <= dynarr_count && dynarr_table[dh_f-1] != 0) {
                        dynarr_free(dynarr_table[dh_f-1]);
                        dynarr_table[dh_f-1] = 0;
                    }
                } else {
                    return -5;
                }
            } else if (sub == 'V') {
                /* HV* etlval opcodes: next 1-2 chars is sub-op, then ';' */
                if (i >= len) { return -5; }
                int8_t sub2v = bytecode[i];
                i = i + 1;
                if (sub2v == 'I') {
                    /* HVI; etlval_int: pop i32, push handle */
                    if (i >= len || bytecode[i] != ';') { return -5; }
                    i = i + 1;
                    int32_t vv = 0;
                    int32_t pv = etl_vm_pop_i32(stack, &sp, &vv);
                    if (pv < 0) { return pv; }
                    if (etlval_count >= ETL_VM_ALLOC_MAX) { return -37; }
                    EtlVal *nv = etlval_int(vv);
                    if (!nv) { return -38; }
                    etlval_table[etlval_count] = nv;
                    int32_t vh = etlval_count + 1;
                    etlval_count = etlval_count + 1;
                    int32_t psh = etl_vm_push_i32(stack, &sp, vh);
                    if (psh < 0) { return psh; }
                } else if (sub2v == 'B') {
                    /* HVB; etlval_bool: pop i32, push handle */
                    if (i >= len || bytecode[i] != ';') { return -5; }
                    i = i + 1;
                    int32_t vb = 0;
                    int32_t pvb = etl_vm_pop_i32(stack, &sp, &vb);
                    if (pvb < 0) { return pvb; }
                    if (etlval_count >= ETL_VM_ALLOC_MAX) { return -37; }
                    EtlVal *nb = etlval_bool(vb);
                    if (!nb) { return -38; }
                    etlval_table[etlval_count] = nb;
                    int32_t vhb = etlval_count + 1;
                    etlval_count = etlval_count + 1;
                    int32_t pshb = etl_vm_push_i32(stack, &sp, vhb);
                    if (pshb < 0) { return pshb; }
                } else if (sub2v == 'P') {
                    /* HVP; etlval_ptr: pop i32 handle (ptr), push etlval handle */
                    if (i >= len || bytecode[i] != ';') { return -5; }
                    i = i + 1;
                    int32_t vph = 0;
                    int32_t pvph = etl_vm_pop_i32(stack, &sp, &vph);
                    if (pvph < 0) { return pvph; }
                    if (etlval_count >= ETL_VM_ALLOC_MAX) { return -37; }
                    /* ptr handle -> raw pointer (may be NULL for handle 0) */
                    void *rawp = (vph > 0 && vph <= etl_alloc_count) ? etl_alloc_table[vph-1] : (void*)0;
                    EtlVal *np = etlval_ptr(rawp);
                    if (!np) { return -38; }
                    etlval_table[etlval_count] = np;
                    int32_t vhp = etlval_count + 1;
                    etlval_count = etlval_count + 1;
                    int32_t pshp = etl_vm_push_i32(stack, &sp, vhp);
                    if (pshp < 0) { return pshp; }
                } else if (sub2v == 'S') {
                    /* HVS; etlval_str: pop str handle, push etlval handle */
                    if (i >= len || bytecode[i] != ';') { return -5; }
                    i = i + 1;
                    int32_t vsh = 0;
                    int32_t pvsh = etl_vm_pop_i32(stack, &sp, &vsh);
                    if (pvsh < 0) { return pvsh; }
                    if (etlval_count >= ETL_VM_ALLOC_MAX) { return -37; }
                    EtlString *raws = (vsh > 0 && vsh <= str_count) ? str_table[vsh-1] : (EtlString*)0;
                    EtlVal *ns = etlval_str(raws);
                    if (!ns) { return -38; }
                    etlval_table[etlval_count] = ns;
                    int32_t vhs = etlval_count + 1;
                    etlval_count = etlval_count + 1;
                    int32_t pshs = etl_vm_push_i32(stack, &sp, vhs);
                    if (pshs < 0) { return pshs; }
                } else if (sub2v == 'T') {
                    /* HVT; etlval_tag: pop etlval handle, push tag */
                    if (i >= len || bytecode[i] != ';') { return -5; }
                    i = i + 1;
                    int32_t vth = 0;
                    int32_t pvt = etl_vm_pop_i32(stack, &sp, &vth);
                    if (pvt < 0) { return pvt; }
                    int32_t vtag = -1;
                    if (vth > 0 && vth <= etlval_count && etlval_table[vth-1] != 0) {
                        vtag = etlval_tag(etlval_table[vth-1]);
                    }
                    int32_t psht = etl_vm_push_i32(stack, &sp, vtag);
                    if (psht < 0) { return psht; }
                } else if (sub2v == 'F') {
                    /* HVF; etlval_free: pop handle */
                    if (i >= len || bytecode[i] != ';') { return -5; }
                    i = i + 1;
                    int32_t vfh = 0;
                    int32_t pvf = etl_vm_pop_i32(stack, &sp, &vfh);
                    if (pvf < 0) { return pvf; }
                    if (vfh > 0 && vfh <= etlval_count && etlval_table[vfh-1] != 0) {
                        etlval_free(etlval_table[vfh-1]);
                        etlval_table[vfh-1] = 0;
                    }
                } else {
                    /* HVAI; HVAB; HVAP; HVAS; — two-char sub-ops */
                    if (i >= len) { return -5; }
                    int8_t sub3v = bytecode[i];
                    i = i + 1;
                    if (i >= len || bytecode[i] != ';') { return -5; }
                    i = i + 1;
                    if (sub2v == 'A' && sub3v == 'I') {
                        /* HVAI; etlval_as_int: pop handle, push i32 */
                        int32_t aih = 0;
                        int32_t pai = etl_vm_pop_i32(stack, &sp, &aih);
                        if (pai < 0) { return pai; }
                        int32_t aiv = 0;
                        if (aih > 0 && aih <= etlval_count && etlval_table[aih-1] != 0) {
                            aiv = etlval_as_int(etlval_table[aih-1]);
                        }
                        int32_t pshai = etl_vm_push_i32(stack, &sp, aiv);
                        if (pshai < 0) { return pshai; }
                    } else if (sub2v == 'A' && sub3v == 'B') {
                        /* HVAB; etlval_as_bool: pop handle, push i32 */
                        int32_t abh = 0;
                        int32_t pab = etl_vm_pop_i32(stack, &sp, &abh);
                        if (pab < 0) { return pab; }
                        int32_t abv = 0;
                        if (abh > 0 && abh <= etlval_count && etlval_table[abh-1] != 0) {
                            abv = etlval_as_bool(etlval_table[abh-1]);
                        }
                        int32_t pshab = etl_vm_push_i32(stack, &sp, abv);
                        if (pshab < 0) { return pshab; }
                    } else if (sub2v == 'A' && sub3v == 'P') {
                        /* HVAP; etlval_as_ptr: pop handle, push ptr handle (or 0) */
                        int32_t aph = 0;
                        int32_t pap = etl_vm_pop_i32(stack, &sp, &aph);
                        if (pap < 0) { return pap; }
                        int32_t apv = 0;
                        if (aph > 0 && aph <= etlval_count && etlval_table[aph-1] != 0) {
                            void *rawap = etlval_as_ptr(etlval_table[aph-1]);
                            /* find handle in alloc table */
                            int32_t found_ap = 0;
                            for (int32_t ai2 = 0; ai2 < etl_alloc_count; ai2 = ai2 + 1) {
                                if (etl_alloc_table[ai2] == rawap) { found_ap = ai2 + 1; }
                            }
                            apv = found_ap;
                        }
                        int32_t pshap = etl_vm_push_i32(stack, &sp, apv);
                        if (pshap < 0) { return pshap; }
                    } else if (sub2v == 'A' && sub3v == 'S') {
                        /* HVAS; etlval_as_str: pop handle, push str handle (or 0) */
                        int32_t ash = 0;
                        int32_t pas = etl_vm_pop_i32(stack, &sp, &ash);
                        if (pas < 0) { return pas; }
                        int32_t asv = 0;
                        if (ash > 0 && ash <= etlval_count && etlval_table[ash-1] != 0) {
                            EtlString *rawas = etlval_as_str(etlval_table[ash-1]);
                            /* find handle in str table */
                            int32_t found_as = 0;
                            for (int32_t si2 = 0; si2 < str_count; si2 = si2 + 1) {
                                if (str_table[si2] == rawas) { found_as = si2 + 1; }
                            }
                            asv = found_as;
                        }
                        int32_t pshas = etl_vm_push_i32(stack, &sp, asv);
                        if (pshas < 0) { return pshas; }
                    } else {
                        return -5;
                    }
                }
            } else {
                /* HA; and HF; */
                if (i >= len || bytecode[i] != ';') { return -5; }
                i = i + 1;
                if (sub == 'A') {
                    int32_t sz = 0;
                    int32_t popped = etl_vm_pop_i32(stack, &sp, &sz);
                    if (popped < 0) { return popped; }
                    int32_t handle = 0;
                    if (sz > 0) {
                        if (etl_alloc_count >= ETL_VM_ALLOC_MAX) { return -37; }
                        void *ptr = calloc((size_t)sz, 1);
                        etl_alloc_table[etl_alloc_count] = ptr;
                        handle = etl_alloc_count + 1;
                        etl_alloc_count = etl_alloc_count + 1;
                    }
                    int32_t pushed = etl_vm_push_i32(stack, &sp, handle);
                    if (pushed < 0) { return pushed; }
                } else if (sub == 'F') {
                    int32_t handle = 0;
                    int32_t popped = etl_vm_pop_i32(stack, &sp, &handle);
                    if (popped < 0) { return popped; }
                    if (handle > 0 && handle <= etl_alloc_count) {
                        free(etl_alloc_table[handle - 1]);
                        etl_alloc_table[handle - 1] = 0;
                    }
                } else {
                    return -5;
                }
            }
        } else {
            return -5;
        }
    }

    return -15;
}
