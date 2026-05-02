# compiler-1 (in ETL)

compiler-1 is the self-hosted ETL compiler, written in ETL itself.
It is still early-stage, but compiler-0 can build the current compiler-1
stage harnesses and prove a small source-to-C path.

## File inventory

| File         | Purpose                                          |
|--------------|--------------------------------------------------|
| `main.etl`   | Entry point. Skeleton that reads stdin and emits one byte for one specific input. |
| `lex.etl`    | Lexer module for the compiler-1 subset.          |
| `parse.etl`  | Parser module for the compiler-1 subset.         |
| `sema.etl`   | Semantic analysis module for compiler-1 AST validation. |
| `emit_c.etl` | C emitter for the current selfhost corpus subset: multi-function `i32`, local arrays/structs, byte strings, extern byte buffers, narrow user-defined byte-array params, and narrow by-value struct params. |
| `backend_defs.etl` | Shared backend error codes (EMIT_OK, EMIT_ERR_*). Not linked into build. |
| `emit_asm.etl` | ASM backend emitter (x86-64 System V active smoke subset). Not linked into default build. |
| `emit_wasm.etl` | WASM backend emitter (WAT text active subset). Not linked into default build. |

## Build command

```sh
scripts/build_etl.sh compiler1/main.etl /tmp/c1
echo "hello" | /tmp/c1   # prints "h", exits 0
```

## Multi-file note

compiler-0 (`compiler0/etl0.py`) compiles a single `.etl` file at a time.
The compiler-1 smoke scripts concatenate `main.etl` declarations with the
stage modules into one temporary compilation unit. When compiler-1 grows
beyond this bootstrap shape, either:

1. compiler-0 will gain multi-file support, or
2. the modules will be concatenated into a single compilation unit.

The choice will be made when it's needed.

## Smoke test

```sh
make selfhost
```

This runs `scripts/c1_pipeline_smoke.sh`, `scripts/c1_equiv_smoke.sh`, and
`scripts/c1_smoke.sh`. The broader `make check` smoke set includes focused
source-to-C probes for arrays, structs, byte strings, extern byte buffers,
scalar `bool`/`i8`/`byte` parameters, and user-defined byte-array parameters.
