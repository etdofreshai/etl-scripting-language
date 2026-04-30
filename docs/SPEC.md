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
fn extern let if elif else while ret type use end true false and or not sizeof ptr
```

## Block syntax decision

ETL source uses terminating keywords, not braces, for human- and LLM-readable structure.

- Function bodies terminate with `end`.
- Nested statement blocks terminate with `end` or a paired keyword form such as `elif ... else ... end`.
- Braces are not ETL source block syntax. They may still appear in emitted C or compiler implementation languages.

## Example syntax

```etl
fn add(a i32, b i32) i32
  ret a + b
end

fn main() i32
  let x i32 = add(2, 3)
  ret x
end
```

Top-level declarations are function definitions, external function declarations, and type declarations:

```etl
extern fn etl_print_i32(value i32)
extern fn etl_read_i32() i32

type Point struct
  x i32
  y i32
end
```

## v0 feature set

- integers: `i32`, `u32`, maybe `i64`, `u64`
- `i8`: 8-bit signed integer, emitted as C `int8_t`. Integer literals continue to default to `i32` (there is no separate `i8` literal syntax in this phase). `i8` exists primarily so `i8[N]` arrays — i.e. strings — are typeable. Comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`) between two `i8` operands produce `bool`. Arithmetic on `i8` (`+`, `-`, `*`, `/`, `%`) is **deferred** in v0; attempting it produces a clean diagnostic. Mixed `i8`/`i32` operands are rejected.
- booleans: `bool` (literals `true` and `false`; emitted as C `stdbool.h` `bool`)
- `ptr`: opaque byte pointer, emitted as C `int8_t *`. `ptr` may appear only in `extern fn` parameter/return types and in local bindings that store/pass extern pointer values, for example `let buf ptr = etl_alloc(64)`. ETL code cannot dereference, index, access fields on, do arithmetic with, or compare `ptr` values. Null checks go through an extern such as `etl_is_null(p ptr) bool`.
- fixed-size arrays: `T[N]`, where `T` is `i32`, `bool`, or `i8` and `N` is a positive integer literal. Arrays are declared as locals without initializer expressions:

```etl
let buf i32[16]
let flags bool[8]
```

Array locals are zero-initialized. The C backend emits declarations such as `int32_t buf[16] = {0};`; bool arrays are initialized the same way, yielding `false` elements.

- arithmetic expressions initially support left-associative `+`, `-`, `*`, `/`, and `%`; `*`, `/`, and `%` bind tighter than `+` and `-`; negative integer literals use a leading `-`
- comparison operators `==`, `!=`, `<`, `<=`, `>`, `>=`; all produce `bool`; comparisons sit below additive operators in precedence so `a + b < c + d` parses as `(a + b) < (c + d)`; `==` and `!=` accept matching types (i32-with-i32 or bool-with-bool); `<`, `<=`, `>`, `>=` require i32 operands
- logical operators `and`, `or`, `not` as keywords; all operands and results are `bool`; `and` and `or` use short-circuit evaluation, emitted as C `&&` and `||`; `not` is a unary prefix operator emitted as C `!`
- unary minus `-` on `i32` expressions (names, calls, parenthesized expressions); negative integer literals continue to parse as literal values (distinct from unary minus on an expression)
- `if` / `elif` / `else` statements use keyword-terminated blocks. `elif` clauses and the `else` block are optional:

```etl
if a > b
  ret a
elif a == b
  ret 0
else
  ret b
end
```

`if` and `elif` conditions must have type `bool`; there is no implicit truthiness from `i32` or other types.

- `while` statements use a bool condition and an `end`-terminated body:

```etl
while i < 10
  i = i + 1
end
```

`while` conditions must have type `bool`; there is no implicit truthiness. `break` and `continue` are explicitly not supported in v0.

- Assignment to an existing local uses `name = expr`. The name must already be declared in the current function by `let` or as a parameter, and the expression type must match the existing local type. Parameters are assignable because parameters are locals inside the function body.

```etl
fn inc(x i32) i32
  x = x + 1
  ret x
end
```

- Indexed array read uses `array[index]`, where `index` is an `i32` expression. The result type is the array element type. Indexed array write uses `array[index] = expr`; the assigned expression must match the element type.

```etl
let buf i32[5]
buf[0] = 7
ret buf[0]
```

Phase 3a emits raw C indexing and performs no bounds checking. Arrays are not first-class values in v0: arrays cannot be passed as function parameters, returned from functions, assigned as whole values, or used directly in arithmetic, comparisons, logical operators, returns, calls, or scalar `let` initializers. Indexed read and indexed write are the only supported array operations.

- struct types use a top-level `type T struct ... end` declaration:

```etl
type Token struct
  kind i32
  value i32
  line i32
end
```

Struct fields may be `i32`, `bool`, fixed-size arrays of those types (`i32[N]` or `bool[N]`), or another previously declared struct type. Struct declarations are emitted as C `typedef struct { ... } T;` in source declaration order. Forward references and recursive structs are not supported. Empty structs, duplicate field names within one struct, and duplicate struct type names are errors.

Struct locals are value locals and are zero-initialized:

```etl
let t Token
let buf Token[10]
```

The C backend emits these as `Token t = {0};` and `Token buf[10] = {0};`. Field read and write use `.`:

```etl
t.kind = 1
ret t.kind
```

Postfix indexing and field access compose for array fields and arrays of structs:

```etl
t.values[0] = 7
buf[i].kind = 2
```

Phase 3b intentionally keeps structs out of first-class operations. Structs cannot be passed as function parameters, returned from functions, assigned as whole values, or compared with `==` / `!=`. Field access on non-struct values and unknown field names are errors. Pointer, extern, struct parameter, and struct return support are deferred.

### String literals (Phase 3c)

ETL string literals use double quotes: `"hello"`. They desugar to static `i8[N]` arrays terminated with a null byte, exactly like C string literals. The effective length is `N = (number of characters in the literal) + 1`, where the trailing `+ 1` is for the null terminator.

The only supported binding form in v0 is:

```etl
let s i8[6] = "hello"
```

`N` must be at least `length-of-string + 1`, or the type-check fails with a clean diagnostic. Wider buffers are allowed and retain C's zero-initialization for the remaining elements. Using a string literal in any other position (returning it, passing it through general expressions, assigning it to non-`i8[N]` arrays, etc.) is a clean diagnostic; full string ergonomics arrive with Phase 4 `extern` / FFI.

Supported escape sequences inside string literals:

| Escape | Meaning            |
|--------|--------------------|
| `\n`   | newline (0x0A)     |
| `\t`   | horizontal tab     |
| `\\`   | literal backslash  |
| `\"`   | literal `"`        |
| `\0`   | null byte          |

Any other escape (e.g. `\q`) is a clean lexer error. Unterminated string literals, raw newlines inside a string literal, and a bare backslash at end of line are all clean lexer errors. Only printable ASCII characters (and the escape sequences above) are accepted inside a string literal in v0.

### `sizeof(T)` (Phase 3c)

`sizeof(T)` is a compile-time `i32` constant whose value is the size in bytes of the C representation of `T`. `T` may be any non-`ptr` type usable in `let`:

- a primitive (`i32`, `bool`, `i8`),
- a previously declared struct type,
- a fixed-size array type such as `i32[10]`.

It emits as `((int32_t)sizeof(T_in_C))` where `T_in_C` is the corresponding C type. Examples:

```etl
let n i32 = sizeof(i32)        // 4 on the targets we test
let m i32 = sizeof(Pt)         // struct size
let q i32 = sizeof(i32[10])    // 40 with natural alignment
```

`sizeof` of `ptr` or an unknown type is a clean diagnostic. The expression form `sizeof(expr)` is **not** supported in v0 — only `sizeof(type)` — and is rejected at parse time.

### `extern fn` declarations (Phase 4a)

ETL can declare C functions supplied by the runtime or host program:

```etl
extern fn etl_print_i32(value i32)
extern fn etl_exit(code i32)
extern fn etl_read_i32() i32
```

`extern fn NAME(PARAMS) [RET_TYPE]` is a top-level declaration. It has no ETL body and is not terminated by `end`. Omitting the return type declares a `void` C function. External names share the same function namespace as ETL-defined functions, so duplicate extern/user function names are rejected.

Parameters may use any v0 type usable in extern signatures: primitives (`i32`, `bool`, `i8`), opaque `ptr`, previously declared structs, and fixed-size arrays. The C backend emits fixed-size array parameters as pointers to the element type and `ptr` as `int8_t *`. Return types are restricted to primitives and `ptr` in v0; struct and array returns are rejected.

User-defined ETL functions cannot take or return `ptr`; it is an FFI boundary type only. Locals may be declared as `ptr` so an extern return can be saved and passed to another extern:

```etl
extern fn etl_alloc(bytes i32) ptr
extern fn etl_free(p ptr)
extern fn etl_is_null(p ptr) bool

fn main() i32
  let buf ptr = etl_alloc(64)
  if etl_is_null(buf)
    ret 1
  end
  etl_free(buf)
  ret 0
end
```

Calls to extern functions type-check like calls to user functions. A void extern call can be used as a statement:

```etl
extern fn etl_print_i32(value i32)

fn main() i32
  etl_print_i32(42)
  ret 0
end
```

When a program contains any `extern fn`, the C backend emits `#include "etl_runtime.h"` after the standard includes. Extern prototypes are emitted after struct typedefs and before user function prototypes/definitions.

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

For now, non-void functions use a simple final-return rule: the last statement must be `ret`, or the last statement must be an `if` / `elif` / `else` chain where the `if` branch, every `elif` branch, and the `else` branch all end in `ret`. An `if` / `elif` chain without `else` does not satisfy the function-body return check by itself; a later `ret` is required. `while` loops never satisfy this return check by themselves because the loop body might not run. Full reachability analysis is intentionally out of scope for v0.

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
- `ret`
- slices later if needed for compiler-1
- simple structs/records when needed for AST/IR
- string literals when needed for diagnostics

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
```
