# ETL Scripting Language

ETL is a minimal LLM-oriented scripting/systems language designed to bootstrap into a self-hosting compiler.

See [docs/support-matrix.md](docs/support-matrix.md) for the works/experimental/unsupported matrix.

This repository absorbed the companion `etl-scripting` repo. Earlier
design documents and example programs from that line of work are
preserved under `docs/legacy/` and `examples/legacy/` for reference.

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

- `function` definitions with explicit parameter and return types
- `let` locals
- `return`
- integer literals (including negative literals), names, calls, parenthesized expressions, `+`, and `-`
- explicit v0 diagnostics for operators that are intentionally not implemented yet, such as `*`, `/`, and `%`
- C emission for `integer` (`i32`)

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

Run the bootstrap smoke paths (ETL example -> golden C fixture check -> native executable, stdout piped directly into `cc`, stdin input, and a nested-call/parenthesized-expression native run) with:

```bash
make smoke
```

Run both gates with:

```bash
make check
```

Run the current headless-server readiness gate with:

```bash
make headless-ready
```

This runs the baseline checks, compiler-1 self-host smoke, backend plan,
shared backend subset, WAT/WASM smoke, and full headless self-evaluation.
See `docs/selfeval.md` for the exact readiness contract and optional
tooling notes.

## semantic checks

Compiler-0 now validates the tiny v0 subset before C emission:

- duplicate function names are rejected
- only supported v0 types are accepted (`integer`/`i32` for now)
- duplicate local/parameter names are rejected
- unknown names and unknown calls are rejected
- function call arity is checked
- integer literals must fit the supported `i32` range
- the minimum `i32` literal is emitted with a portable C expression instead of relying on an out-of-range positive token

Legacy spellings (`fn`, `ret`, `extern`, `struct`, `i32`, `i8`, `bool`, `ptr`, `sizeof`) remain accepted as compatibility aliases. See `docs/platform-vocabulary.md` for the full canonical vocabulary and platform compatibility tiers.

See `docs/self-improvement-roadmap.md` for the path from the current headless-ready state to a self-improving language loop.
