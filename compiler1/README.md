# compiler-1 (in ETL)

compiler-1 is the self-hosted ETL compiler, written in ETL itself.
Currently a skeleton. Built by compiler-0; will grow toward self-hosting.

## File inventory

| File         | Purpose                                          |
|--------------|--------------------------------------------------|
| `main.etl`   | Entry point. Skeleton that reads stdin and emits one byte for one specific input. |
| `lex.etl`    | Lexer module (placeholder, not yet linked).      |
| `parse.etl`  | Parser module (placeholder, not yet linked).     |
| `sema.etl`   | Semantic analysis module (placeholder, not yet linked). |
| `emit_c.etl` | C code emission module (placeholder, not yet linked). |
| `backend_defs.etl` | Shared backend error codes (EMIT_OK, EMIT_ERR_*). Not linked into build. |
| `emit_asm.etl` | ASM backend scaffold (returns EMIT_ERR_UNSUPPORTED). Not linked into build. |
| `emit_wasm.etl` | WASM backend scaffold (returns EMIT_ERR_UNSUPPORTED). Not linked into build. |

## Build command

```sh
scripts/build_etl.sh compiler1/main.etl /tmp/c1
echo "hello" | /tmp/c1   # prints "h", exits 0
```

## Multi-file note

compiler-0 (`compiler0/etl0.py`) compiles a single `.etl` file at a time.
The placeholder modules (`lex.etl`, `parse.etl`, `sema.etl`, `emit_c.etl`)
exist to show the directory structure that compiler-1 will eventually have,
but they are not yet compiled or linked into the build. When compiler-1
grows to the point of needing its own modules, either:

1. compiler-0 will gain multi-file support, or
2. the modules will be concatenated into a single compilation unit.

The choice will be made when it's needed.

## Smoke test

```sh
make selfhost
```

This runs `scripts/c1_smoke.sh`, which builds compiler1/main.etl via
compiler-0, pipes "hello" into it, and asserts the output and exit code.
