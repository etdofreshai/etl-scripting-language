# ETL Runtime VM Plan

This plan extends ETL from a purely ahead-of-time compiled language into an
AOT language that can also host runtime-compiled ETL modules.

The core rule is that runtime ETL must share the same language implementation
as AOT ETL. The lexer, parser, semantic checks, and typed AST or IR lowering
should be common. Runtime execution diverges only at the backend: instead of
emitting C, WASM, or assembly, the runtime path emits portable ETL bytecode for
an embedded VM.

## Target Architecture

```text
ETL source
  -> lexer
  -> parser
  -> sema
  -> typed AST / IR
      -> emit_c        -> native AOT build
      -> emit_wasm     -> web / portable runtime target
      -> emit_asm      -> native backend experiments
      -> emit_bytecode -> ETL VM
```

An AOT-built ETL host program may link the compiler frontend, bytecode emitter,
and VM:

```text
host.etl -> C -> native host binary

inside host binary:
  runtime ETL source -> shared compiler frontend -> bytecode -> VM execution
```

This gives ETL both compatibility and runtime flexibility without creating a
second scripting dialect.

## Phase 1: Bytecode Backend Scaffold

Goal: establish a compiler-1 backend slot for bytecode without changing normal
AOT behavior.

- Add `compiler1/emit_bytecode.etl`.
- Add a smoke test for `fn main() i32 ret 42 end`.
- Emit a small versioned bytecode header plus integer push, arithmetic, and
  return instructions. The first scaffold uses a readable ASCII bytecode form
  such as `ETLB1;I1;I2;+;R;` so the current compiler subset can write it into
  `i8` buffers without needing arbitrary binary byte assignment.
- Keep unsupported AST shapes returning `EMIT_ERR_UNSUPPORTED()`.
- Do not add a VM interpreter yet.

Gate:

```sh
scripts/c1_emit_bytecode_smoke.sh
```

## Phase 2: Minimal VM Interpreter

Goal: execute the first bytecode program from a C or ETL runtime harness.

- Define bytecode constants in shared compiler/runtime documentation.
- Add `runtime/etl_vm.h` and `runtime/etl_vm.c` as the temporary C runtime VM
  baseline until compiler-1 supports the needed runtime shapes for an ETL VM.
- Execute the scaffold stack bytecode form.
- Add a smoke that emits bytecode and verifies VM result `42`.

Gate:

```sh
scripts/c1_vm_return_smoke.sh
```

## Phase 3: Expression Bytecode

Goal: reach parity with the earliest expression corpus.

- `push_i32`, arithmetic ops, and `return` are now the first bytecode shape.
- Compile simple integer expression returns.
- Run a small c0/C, c1/C, and c1/VM equivalence matrix.

Gate:

```sh
scripts/c1_vm_expr_smoke.sh
```

## Phase 4: Locals and Control Flow

Goal: execute the same minimal control-flow subset as the backend subset gate.

- Add local slots.
- Add load/store local.
- Add branches and labels or relative jumps.
- Support `if`, `elif`, `else`, and `while`.

Gate:

```sh
scripts/c1_vm_control_flow_smoke.sh
```

### Bytecode format reference (current)

The bytecode is a readable ASCII byte stream so that the current compiler
subset can build it inside `i8` buffers without arbitrary-byte assignment.
`;` is the universal separator. Implemented by `compiler1/emit_bytecode.etl`
and consumed by `runtime/etl_vm.c`.

| Form         | Meaning                                                |
| ------------ | ------------------------------------------------------ |
| `ETLB1;`     | Module header. Always first.                           |
| `I<int>;`    | Push i32 literal (decimal, non-negative).              |
| `+; -; *; /; %;` | Pop right, pop left, push (left OP right).        |
| `L<idx>;`    | Load local: push `locals[idx]` onto the stack.         |
| `L<idx>=;`   | Store local: pop top-of-stack into `locals[idx]`.      |
| `R;`         | Pop top of stack, return it as the program exit value. |

Limits in the bootstrap C VM: 64-slot operand stack, 32 local slots,
deterministic negative error codes. Local slots are zero-initialised at
entry. Stack must be empty after `R;`. Trailing bytes after `R;` are an
error. See `runtime/etl_vm.h` for the full error code table.

## Phase 5: Functions and Calls

Goal: support runtime modules with multiple ETL functions.

- Add function table metadata.
- Add direct intra-module calls.
- Add parameter passing and return values.
- Keep stack and call-frame limits explicit.

Gate:

```sh
scripts/c1_vm_function_smoke.sh
```

## Phase 6: Runtime Host Bridge

Goal: let AOT ETL programs load and execute runtime ETL modules safely.

- Add host APIs such as `etl_compile_module`, `etl_run_main_i32`, and explicit
  import binding.
- Keep imports allowlisted by the host.
- Preserve opaque pointer and runtime-string limitations unless deliberately
  expanded by a separate language feature.

Gate:

```sh
scripts/c1_runtime_compile_smoke.sh
```

## Phase 7: JIT

Goal: optional performance path after bytecode semantics are stable.

- Treat native JIT as an optimization over bytecode or typed IR.
- Keep bytecode VM as the portable baseline.
- Require VM/JIT equivalence tests for every supported bytecode feature.

Native JIT is not the first runtime target.
