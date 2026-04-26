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
fn let if else while ret type use
```

## Example syntax

```etl
fn add(a i32, b i32) i32 {
  ret a + b
}

fn main() i32 {
  let x i32 = add(2, 3)
  ret x
}
```

## v0 feature set

- integers: `i32`, `u32`, maybe `i64`, `u64`
- bytes and booleans
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
