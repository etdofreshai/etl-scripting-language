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
| `emit_c.etl` | C emitter for the current selfhost corpus subset: multi-function `i32`, typed `bool`/`i8` locals, local arrays/structs, byte strings, extern byte buffers, extern scalar bool/i8/byte params, narrow user-defined byte-array params, and narrow by-value struct params. |
| `backend_defs.etl` | Shared backend error codes (EMIT_OK, EMIT_ERR_*). Not linked into build. |
| `emit_asm.etl` | ASM backend emitter (x86-64 System V active smoke subset). Not linked into default build. |
| `emit_wasm.etl` | WASM backend emitter (WAT text active subset). Not linked into default build. |
| `emit_bytecode.etl` | Bytecode backend emitter for the runtime ETL VM (`runtime/etl_vm.{c,h}`). See [Bytecode format](#bytecode-format) below. Not linked into default build. |

## Bytecode format

`compiler1/emit_bytecode.etl` produces a readable ASCII bytecode for the
embedded ETL VM. The format is intentionally text-friendly so the
compiler-1 subset can build it from `i8` buffers without needing arbitrary
binary byte assignment, and so a human can hand-inspect the stream.

Header (always the first six bytes):

```
ETLB1;
```

Instructions (each instruction ends with a `;` separator):

| Form        | Name           | Behavior |
|-------------|----------------|----------|
| `I<int>;`   | `push_i32`     | Push the decimal i32 immediate onto the stack. Negative immediates are not supported by the emitter. |
| `+;`        | `add`          | Pop right, pop left, push `left + right`. |
| `-;`        | `sub`          | Pop right, pop left, push `left - right`. |
| `*;`        | `mul`          | Pop right, pop left, push `left * right`. |
| `/;`        | `div`          | Pop right, pop left, push `left / right` (errors if `right == 0`). |
| `%;`        | `mod`          | Pop right, pop left, push `left % right` (errors if `right == 0`). |
| `L<idx>;`   | `load_local`   | Push the value of local slot `<idx>` onto the stack. |
| `L<idx>=;`  | `store_local`  | Pop top of stack and store it into local slot `<idx>`. |
| `R;`        | `return_i32`   | Pop top of stack and use it as the i32 return value of `main`. |

The `store_local` form reuses the `L` opcode plus an `=` marker so that a
single decoder lookahead disambiguates load vs. store after reading the
slot digits. Slots are numbered from 0 in declaration order within a
function body and are bounded by the VM (see
`runtime/etl_vm.h`, `ETL_VM_MAX_LOCALS`).

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
scalar `bool`/`i8`/`byte` parameters, extern scalar `bool`/`i8`/`byte`
parameter emission, and user-defined byte-array parameters.
