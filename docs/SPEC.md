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
fn let if elif else while ret type use end true false and or not
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

## v0 feature set

- integers: `i32`, `u32`, maybe `i64`, `u64`
- booleans: `bool` (literals `true` and `false`; emitted as C `stdbool.h` `bool`)
- fixed-size arrays: `T[N]`, where `T` is `i32` or `bool` and `N` is a positive integer literal. Arrays are declared as locals without initializer expressions:

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
