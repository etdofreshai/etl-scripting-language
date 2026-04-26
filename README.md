# ETL Scripting Language

ETL is a minimal LLM-oriented scripting/systems language designed to bootstrap into a self-hosting compiler.

Early goals:

- tiny, regular syntax
- explicit types
- easy parsing and AST generation
- compiler errors optimized for AI repair loops
- first backend: C for fast bootstrap and portability
- future backends: WASM, native/ASM, mobile build pipelines

Bootstrap path:

1. Write compiler-0 in a practical host language.
2. Compile ETL v0 programs to C.
3. Rewrite the compiler in ETL.
4. Use compiler-0 to build compiler-1.
5. Use compiler-1+ to build future ETL compilers.

## compiler-0

The first compiler is a small Python implementation under `compiler0/`.
It currently supports the tiny v0 subset needed for the bootstrap smoke:

- `fn` definitions with explicit parameter and return types
- `let` locals
- `ret`
- integer literals (including negative literals), names, calls, parenthesized expressions, `+`, and `-`
- C emission for `i32`

Compile an ETL file to C with:

```bash
python3 -m compiler0.etl0 compile examples/add_main.etl -o /tmp/add_main.c
```

Use `-` for stdin and/or stdout when piping compiler-0:

```bash
cat examples/add_main.etl | python3 -m compiler0 compile - -o -
```

CLI diagnostics include the input path, or `<stdin>` for piped input, before the compiler source location.

Run parser/compiler tests with:

```bash
make test
```

Run the bootstrap smoke paths (ETL example -> C file -> native executable, stdout piped directly into `cc`, and stdin input) with:

```bash
make smoke
```

Run both gates with:

```bash
make check
```

## semantic checks

Compiler-0 now validates the tiny v0 subset before C emission:

- duplicate function names are rejected
- only supported v0 types are accepted (`i32` for now)
- duplicate local/parameter names are rejected
- unknown names and unknown calls are rejected
- function call arity is checked
- integer literals must fit the supported `i32` range
- the minimum `i32` literal is emitted with a portable C expression instead of relying on an out-of-range positive token
