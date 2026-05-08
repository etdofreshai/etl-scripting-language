# ETL v0 Draft Spec

ETL v0 is intentionally small. It is not the final language; it is the seed language needed to build the self-hosting compiler.

## Design constraints

- Few keywords.
- Regular grammar.
- Explicit types.
- No ambiguous syntax.
- Easy for LLMs to read, write, diff, and repair.
- Every compiler version must be buildable by the previous stable compiler.

## Tentative keywords

```text
function external let if elif else while return type use end true false and or not size pointer
```

The legacy spellings `fn`, `extern`, `ret`, `struct`, `i32`, `i8`, `bool`, `ptr`, and `sizeof` remain accepted as compatibility aliases for `function`, `external`, `return`, `structure`, `integer`, `byte`, `boolean`, `pointer`, and `size`.

## Block syntax decision

ETL source uses terminating keywords, not braces, for human- and LLM-readable structure.

- Function bodies terminate with `end`.
- Nested statement blocks terminate with `end` or a paired keyword form such as `elif ... else ... end`.
- Braces are not ETL source block syntax. They may still appear in emitted C or compiler implementation languages.

## Example syntax

```etl
function add(a integer, b integer) integer
  return a + b
end

function main() integer
  let x integer = add(2, 3)
  return x
end
```

Top-level declarations are function definitions, external function declarations, and type declarations:

```etl
external function etl_print_i32(value integer)
external function etl_read_i32() integer

type Point structure
  x integer
  y integer
end
```

## v0 feature set

- integers: `integer` (emitted as C `int32_t`; legacy spelling `i32`), `u32`, maybe `i64`, `u64`
- `byte` (legacy `i8`): 8-bit signed integer, emitted as C `int8_t`. Integer literals continue to default to `integer`/`i32` (there is no separate `byte` literal syntax in this phase). `byte` exists primarily so `byte[N]` arrays — i.e. strings — are typeable. Comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`) between two `byte` operands produce `boolean`. Arithmetic on `byte` (`+`, `-`, `*`, `/`, `%`) is **deferred** in v0; attempting it produces a clean diagnostic. Mixed `byte`/`integer` operands are rejected.
- booleans: `boolean` (legacy `bool`; literals `true` and `false`; emitted as C `stdbool.h` `bool`)
- `pointer` (legacy `ptr`): opaque byte pointer, emitted as C `int8_t *`. `pointer` may appear only in `external function` parameter/return types and in local bindings that store/pass extern pointer values, for example `let buf pointer = etl_alloc(64)`. ETL code cannot dereference, index, access fields on, do arithmetic with, or compare `pointer` values. Null checks go through an extern such as `etl_is_null(p pointer) boolean`.
- fixed-size arrays: `T[N]`, where `T` is `integer`, `boolean`, or `byte` and `N` is a positive integer literal. Arrays are declared as locals without initializer expressions:

```etl
let buf integer[16]
let flags boolean[8]
```

Array locals are zero-initialized. The C backend emits declarations such as `int32_t buf[16] = {0};`; bool arrays are initialized the same way, yielding `false` elements.

- arithmetic expressions initially support left-associative `+`, `-`, `*`, `/`, and `%`; `*`, `/`, and `%` bind tighter than `+` and `-`; negative integer literals use a leading `-`
- comparison operators `==`, `!=`, `<`, `<=`, `>`, `>=`; all produce `boolean`; comparisons sit below additive operators in precedence so `a + b < c + d` parses as `(a + b) < (c + d)`; `==` and `!=` accept matching types (integer-with-integer or boolean-with-boolean); `<`, `<=`, `>`, `>=` require integer operands
- logical operators `and`, `or`, `not` as keywords; all operands and results are `boolean`; `and` and `or` use short-circuit evaluation, emitted as C `&&` and `||`; `not` is a unary prefix operator emitted as C `!`
- unary minus `-` on `integer` expressions (names, calls, parenthesized expressions); negative integer literals continue to parse as literal values (distinct from unary minus on an expression)
- `if` / `elif` / `else` statements use keyword-terminated blocks. `elif` clauses and the `else` block are optional:

```etl
if a > b
  return a
elif a == b
  return 0
else
  return b
end
```

`if` and `elif` conditions must have type `boolean`; there is no implicit truthiness from `integer` or other types.

- `while` statements use a bool condition and an `end`-terminated body:

```etl
while i < 10
  i = i + 1
end
```

`while` conditions must have type `boolean`; there is no implicit truthiness. `break` and `continue` are explicitly not supported in v0.

- Assignment to an existing local uses `name = expr`. The name must already be declared in the current function by `let` or as a parameter, and the expression type must match the existing local type. Parameters are assignable because parameters are locals inside the function body.

```etl
function inc(x integer) integer
  x = x + 1
  return x
end
```

- Indexed array read uses `array[index]`, where `index` is an `i32` expression. The result type is the array element type. Indexed array write uses `array[index] = expr`; the assigned expression must match the element type.

```etl
let buf integer[5]
buf[0] = 7
return buf[0]
```

Phase 3a emits raw C indexing and performs no bounds checking. Arrays are not first-class values in v0: arrays cannot be passed as function parameters, returned from functions, assigned as whole values, or used directly in arithmetic, comparisons, logical operators, returns, calls, or scalar `let` initializers. Indexed read and indexed write are the only supported array operations.

- struct types use a top-level `type T structure ... end` declaration:

```etl
type Token structure
  kind integer
  value integer
  line integer
end
```

Struct fields may be `integer`, `boolean`, fixed-size arrays of those types (`integer[N]` or `boolean[N]`), or another previously declared struct type. Struct declarations are emitted as C `typedef struct { ... } T;` in source declaration order. Forward references and recursive structs are not supported. Empty structs, duplicate field names within one struct, and duplicate struct type names are errors.

Struct locals are value locals and are zero-initialized:

```etl
let t Token
let buf Token[10]
```

The C backend emits these as `Token t = {0};` and `Token buf[10] = {0};`. Field read and write use `.`:

```etl
t.kind = 1
return t.kind
```

Postfix indexing and field access compose for array fields and arrays of structs:

```etl
t.values[0] = 7
buf[i].kind = 2
```

Phase 3b intentionally keeps structs out of first-class operations. Structs cannot be passed as function parameters, returned from functions, assigned as whole values, or compared with `==` / `!=`. Field access on non-struct values and unknown field names are errors. Pointer, extern, struct parameter, and struct return support are deferred.

### String literals (Phase 3c)

ETL string literals use double quotes: `"hello"`. They desugar to static `byte[N]` arrays terminated with a null byte, exactly like C string literals. The effective length is `N = (number of characters in the literal) + 1`, where the trailing `+ 1` is for the null terminator.

The only supported binding form in v0 is:

```etl
let s byte[6] = "hello"
```

`N` must be at least `length-of-string + 1`, or the type-check fails with a clean diagnostic. Wider buffers are allowed and retain C's zero-initialization for the remaining elements. Using a string literal in any other position (returning it, passing it through general expressions, assigning it to non-`byte[N]` arrays, etc.) is a clean diagnostic; full string ergonomics arrive with Phase 4 `external` / FFI.

Supported escape sequences inside string literals:

| Escape | Meaning            |
|--------|--------------------|
| `\n`   | newline (0x0A)     |
| `\t`   | horizontal tab     |
| `\\`   | literal backslash  |
| `\"`   | literal `"`        |
| `\0`   | null byte          |

Any other escape (e.g. `\q`) is a clean lexer error. Unterminated string literals, raw newlines inside a string literal, and a bare backslash at end of line are all clean lexer errors. Only printable ASCII characters (and the escape sequences above) are accepted inside a string literal in v0.

### `size(T)` (Phase 3c)

`size(T)` (legacy spelling `sizeof`) is a compile-time `integer` constant whose value is the size in bytes of the C representation of `T`. `T` may be any non-`pointer` type usable in `let`:

- a primitive (`integer`, `boolean`, `byte`),
- a previously declared struct type,
- a fixed-size array type such as `integer[10]`.

It emits as `((int32_t)sizeof(T_in_C))` where `T_in_C` is the corresponding C type. Examples:

```etl
let n integer = size(integer)        // 4 on the targets we test
let m integer = size(Pt)            // struct size
let q integer = size(integer[10])   // 40 with natural alignment
```

`size` of `pointer` or an unknown type is a clean diagnostic. The expression form `size(expr)` is **not** supported in v0 — only `size(type)` — and is rejected at parse time.

### `external function` declarations (Phase 4a)

ETL can declare C functions supplied by the runtime or host program:

```etl
external function etl_print_i32(value integer)
external function etl_exit(code integer)
external function etl_read_i32() integer
```

`external function NAME(PARAMS) [RET_TYPE]` is a top-level declaration. It has no ETL body and is not terminated by `end`. Omitting the return type declares a `void` C function. External names share the same function namespace as ETL-defined functions, so duplicate extern/user function names are rejected.

Parameters may use any v0 type usable in extern signatures: primitives (`integer`, `boolean`, `byte`), opaque `pointer`, previously declared structs, and fixed-size arrays. The C backend emits fixed-size array parameters as pointers to the element type and `pointer` as `int8_t *`. Return types are restricted to primitives and `pointer` in v0; struct and array returns are rejected.

User-defined ETL functions cannot take or return `pointer`; it is an FFI boundary type only. Locals may be declared as `pointer` so an extern return can be saved and passed to another extern:

```etl
external function etl_alloc(bytes integer) pointer
external function etl_free(p pointer)
external function etl_is_null(p pointer) boolean

function main() integer
  let buf pointer = etl_alloc(64)
  if etl_is_null(buf)
    return 1
  end
  etl_free(buf)
  return 0
end
```

Calls to extern functions type-check like calls to user functions. A void extern call can be used as a statement:

```etl
external function etl_print_i32(value integer)

function main() integer
  etl_print_i32(42)
  return 0
end
```

When a program contains any `external function`, the C backend emits `#include "etl_runtime.h"` after the standard includes. Extern prototypes are emitted after struct typedefs and before user function prototypes/definitions.

The initial C runtime lives in `runtime/etl_runtime.h` and `runtime/etl_runtime.c`:

```c
void etl_print_i32(int32_t value);
void etl_print_bool(bool value);
void etl_print_str(const int8_t *s);
void etl_print_str_n(const int8_t *s, int32_t n);
void etl_exit(int32_t code);
int32_t etl_read_i32(void);
int8_t *etl_alloc(int32_t bytes);
void etl_free(int8_t *p);
bool etl_is_null(int8_t *p);
int32_t etl_read_file(int8_t *path, int8_t *buf, int32_t cap);
int32_t etl_write_file(int8_t *path, int8_t *buf, int32_t len);
void etl_panic(int8_t *msg);
```

These file and panic declarations intentionally use mutable `int8_t *` in v0 because ETL does not have a `const` qualifier yet; callers should still treat path and output buffers as read-only by convention where the runtime function does not mutate them.

For now, non-void functions use a simple final-return rule: the last statement must be `return`, or the last statement must be an `if` / `elif` / `else` chain where the `if` branch, every `elif` branch, and the `else` branch all end in `return`. An `if` / `elif` chain without `else` does not satisfy the function-body return check by itself; a later `return` is required. `while` loops never satisfy this return check by themselves because the loop body might not run. Full reachability analysis is intentionally out of scope for v0.

## Opaque types (M1 capabilities — v0)

M1 adds four opaque runtime types accessible exclusively through `external function` calls. They introduce no new ETL syntax; all operations go through the normal extern-call surface. Compiler-0 (Python) does not support these types; equivalence smoke tests for M1 types compare the compiler-1 C backend against the compiler-1 VM backend (not c0/C vs c1/C).

### `ptr` — opaque heap pointer

`ptr` (legacy spelling `pointer`) is an opaque handle to a heap allocation. In compiler-1 it is assigned `TY_PTR` and emitted as `void*` by the C backend.

Supported operations (via externs):

```etl
external function alloc(n integer) ptr
external function free(p ptr)
```

Limitations:
- No arithmetic, no dereference, no field access, no null comparison via operators. All such operations must go through extern functions.
- `ptr` is accepted in extern fn parameter and return positions and in local `let` bindings. It is not accepted in fixed-size array element types or struct fields in v0.

### `str` — heap-backed mutable string

`str` is an opaque handle to an `EtlString*` heap allocation (defined in `runtime/etl_string.h`). It is assigned `TY_STR` in compiler-1 and emitted as `EtlString*` by the C backend.

Supported extern surface:

| Extern | Signature | Notes |
|---|---|---|
| `str_new` | `(literal ptr) str` | C backend: copies bytes from the ptr. VM backend: ignores input ptr, creates empty string (see limitation below). |
| `str_len` | `(s str) integer` | Returns length in bytes. |
| `str_concat` | `(a str, b str) str` | Allocates a new concatenated string. |
| `str_at` | `(s str, i integer) byte` | Returns byte at index. |
| `str_eq` | `(a str, b str) boolean` | True if contents are identical. |
| `str_free` | `(s str)` | Frees the heap string. |

Limitations:
- **VM `str_new` ignores the input `ptr`**: the VM has no way to dereference arbitrary host pointers to read string literals. The VM creates an empty string. Programs that need meaningful string content in the VM backend must construct it via `str_concat` or other operations. The C backend does not have this limitation.
- `str` is accepted in extern fn parameter/return positions and in local `let` bindings. Not supported in compiler-0.

### `dynarr` — growable i32 array

`dynarr` is an opaque handle to an `EtlDynArr*` heap allocation (defined in `runtime/etl_dynarr.h`). It is assigned `TY_DYNARR` in compiler-1 and emitted as `EtlDynArr*` by the C backend.

Supported extern surface:

| Extern | Signature | Notes |
|---|---|---|
| `dynarr_new` | `() dynarr` | Allocates an empty dynamic array. |
| `dynarr_push` | `(a dynarr, v integer)` | Appends one element. |
| `dynarr_len` | `(a dynarr) integer` | Returns element count. |
| `dynarr_get` | `(a dynarr, i integer) integer` | Returns element at index. |
| `dynarr_set` | `(a dynarr, i integer, v integer)` | Sets element at index. |
| `dynarr_free` | `(a dynarr)` | Frees the array and its backing buffer. |

Limitations:
- Element type is `i32` only. Generic element types are not supported in v0.
- No iterator protocol, no map/filter, no ETL syntax additions.
- Not supported in compiler-0.

### `etlval` — tagged union over int/bool/ptr/str

`etlval` is an opaque handle to an `EtlVal*` heap allocation (defined in `runtime/etl_etlval.h`). It is a tagged union that can hold one of four variants: `int`, `bool`, `ptr`, or `str`. Tag constants: 0=int, 1=bool, 2=ptr, 3=str.

Supported extern surface:

| Extern | Signature | Notes |
|---|---|---|
| `etlval_int` | `(v integer) etlval` | Constructs an int variant. |
| `etlval_bool` | `(v boolean) etlval` | Constructs a bool variant. |
| `etlval_ptr` | `(v ptr) etlval` | Constructs a ptr variant. |
| `etlval_str` | `(v str) etlval` | Constructs a str variant; etlval owns the EtlString. |
| `etlval_tag` | `(v etlval) integer` | Returns the tag (0–3). |
| `etlval_as_int` | `(v etlval) integer` | Extracts the int payload. |
| `etlval_as_bool` | `(v etlval) boolean` | Extracts the bool payload. |
| `etlval_as_ptr` | `(v etlval) ptr` | Extracts the ptr payload. |
| `etlval_as_str` | `(v etlval) str` | Extracts the str payload (handle remains owned by etlval). |
| `etlval_free` | `(v etlval)` | Frees the EtlVal struct; also frees the inner EtlString if tag==3. |

Limitations:
- `etlval` is accepted in extern fn parameter/return positions and in local `let` bindings, and in regular user-function parameter and return positions (compiler-1 only).
- Not supported in compiler-0.
- The VM fixture for the `str` variant (etlval_str) is elided due to the 1024-byte bytecode buffer limit. The runtime and VM HV* opcodes for the str variant are implemented and tested indirectly.

### Common M1 limitations

- All four types are available via the extern-call surface only. No new ETL syntax was added.
- Compiler-0 (Python) does not support `str`, `dynarr`, or `etlval`. Equivalence smokes for these types run c1/C vs c1/VM only.
- The VM bytecode buffer is currently 1024 bytes, which limits fixture complexity for combined opaque-type programs. Tracked as tech debt; buffer expansion is required before VM-in-ETL (M2) is feasible.
- ASM and WAT backends do not yet support any M1 opaque type calls.


## Operator precedence (lowest to highest)

| Precedence | Operators                              | Associativity |
|------------|----------------------------------------|---------------|
| 1 (lowest) | `or`                                   | left          |
| 2          | `and`                                  | left          |
| 3          | `not`                                  | right (unary) |
| 4          | `==` `!=` `<` `<=` `>` `>=`           | left          |
| 5          | `+` `-`                                | left          |
| 6          | `*` `/` `%`                            | left          |
| 7          | unary `-`                              | right (unary) |
| 8 (highest)| primary (literal, name, call, parens)  | —             |

`not` has lower precedence than comparison operators, so `not a == b` parses as `not (a == b)`. Use parentheses to obtain `(not a) == b` if needed.

`and` and `or` use short-circuit evaluation: the right operand is not evaluated if the left operand determines the result. This is emitted directly as C `&&` and `||`, which have the same semantics.

- v0 division and modulo follow C99 semantics for negative operands.
- bytes
- functions
- local variables
- assignment to locals and parameters
- fixed-size local arrays with indexed read/write
- `if` / `elif` / `else`
- `while`
- `return`
- slices later if needed for compiler-1
- simple structs/records when needed for AST/IR
- string literals when needed for diagnostics

## Compiler-1 (in ETL)

Compiler-1 is the self-hosted ETL compiler, written in ETL itself. It lives in `compiler1/`. The goal is for compiler-0 (Python) to compile compiler-1, producing a native binary that can then compile itself — reaching a self-hosting fixed point.

### Current state

Compiler-1 is a **skeleton**. It contains:

- `compiler1/main.etl` — a trivial program that reads stdin, checks for the exact input `"hello\n"`, and writes the byte `'h'` to stdout if matched. This proves the full ETL → C → native pipeline end-to-end for a program written in `compiler1/`.
- `compiler1/lex.etl`, `compiler1/parse.etl`, `compiler1/sema.etl`, `compiler1/emit_c.etl` — placeholder modules with trivial functions, not yet linked into the build.

### Build path

```sh
compiler0/etl0.py compile compiler1/main.etl -o /tmp/c1.c
cc /tmp/c1.c runtime/etl_runtime.c -I runtime -o /tmp/c1
```

Or equivalently: `scripts/build_etl.sh compiler1/main.etl /tmp/c1`

### Smoke gate

`make selfhost` runs `scripts/c1_smoke.sh`, which builds compiler-1 via compiler-0 and verifies it produces correct output. This target will grow over Phase 5 to become the full self-host gate (c0 builds c1, c1 builds c2, behavior-equivalence check).

## Initial backend strategy

Start with:

```text
ETL source -> lexer -> parser -> AST -> type check -> IR -> C
```

Then add:

```text
IR -> WASM
IR -> LLVM/Cranelift/native
IR -> ASM experiments
IR -> ETL bytecode -> ETL VM
```

The VM path is experimental runtime behavior, not part of the stable v0
language contract yet. The intended model is an AOT-compiled ETL host program
that embeds the same ETL lexer, parser, semantic checks, and IR lowering used by
the bootstrap compiler, then compiles runtime-provided ETL source into portable
bytecode for the VM. Runtime ETL should share syntax and type rules with AOT
ETL; host programs may add sandboxing policy around what runtime modules can
import or call.
