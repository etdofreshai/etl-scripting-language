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
fn let if else while ret type use end true false
```

## Block syntax decision

ETL source uses terminating keywords, not braces, for human- and LLM-readable structure.

- Function bodies terminate with `end`.
- Future nested blocks also terminate with `end` or a paired keyword form such as `else ... end`.
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
- arithmetic expressions initially support left-associative `+`, `-`, `*`, `/`, and `%`; `*`, `/`, and `%` bind tighter than `+` and `-`; negative integer literals use a leading `-`
- comparison operators `==`, `!=`, `<`, `<=`, `>`, `>=`; all produce `bool`; comparisons sit below additive operators in precedence so `a + b < c + d` parses as `(a + b) < (c + d)`; `==` and `!=` accept matching types (i32-with-i32 or bool-with-bool); `<`, `<=`, `>`, `>=` require i32 operands
- v0 division and modulo follow C99 semantics for negative operands.
- bytes
- functions
- local variables
- `if` / `else`
- `while`
- `ret`
- arrays/slices later if needed for compiler-1
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
