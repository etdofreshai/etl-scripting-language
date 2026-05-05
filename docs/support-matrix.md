# ETL Support Matrix

## Summary

ETL is currently a bootstrap-stage, ahead-of-time compiled language with C as
the primary durable backend. Compiler-1 can lex, parse, type-check, and emit C
for a 32-fixture self-host equivalence corpus; ASM and WAT/WASM cover active
validation subsets; the VM executes a narrow expression and local-slot bytecode
subset through the same frontend path. Full compiler fixed point, runtime-loaded
ETL modules, graphical examples, release packaging, and broad application
support remain in progress or not implemented.

## Language feature support

| Feature | c0/C | c1/C | ASM | WAT/WASM | VM | Notes / proving smoke |
|---|---|---|---|---|---|---|
| integer arithmetic (i32 +,-,*,/,%) | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | EXPERIMENTAL | `make check`, `scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh`, `scripts/c1_vm_expr_smoke.sh` |
| comparisons | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `make check`, `scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh` |
| logical and/or/not | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `make check`, `scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh` |
| if/elif/else | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `make check`, `scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh` |
| while | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `make check`, `scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh` |
| fn declaration | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `scripts/c1_equiv_smoke.sh`, `scripts/c1_asm_function_call_smoke.sh`, `scripts/c1_wat_function_call_smoke.sh` |
| fn params i32 | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `scripts/c1_equiv_smoke.sh`, `scripts/c1_asm_function_call_smoke.sh`, `scripts/c1_wat_function_call_smoke.sh` |
| fn params bool/i8/byte | SUPPORTED | SUPPORTED | EXPERIMENTAL | EXPERIMENTAL | UNSUPPORTED | `scripts/c1_source_to_c_scalar_param_smoke.sh`, `scripts/c1_source_to_c_byte_array_param_smoke.sh`, `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh` |
| recursion | SUPPORTED | SUPPORTED | UNSUPPORTED | UNSUPPORTED | UNSUPPORTED | `scripts/c1_equiv_smoke.sh` |
| local i32 | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | EXPERIMENTAL | `scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh`, `scripts/c1_vm_expr_smoke.sh` |
| local bool/i8 | SUPPORTED | SUPPORTED | EXPERIMENTAL | EXPERIMENTAL | UNSUPPORTED | `scripts/c1_equiv_smoke.sh`, `scripts/c1_source_to_c_bool_param_smoke.sh`, `scripts/c1_wat_array_smoke.sh`, `scripts/c1_asm_array_smoke.sh` |
| local i32 array constant index | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `scripts/c1_source_to_c_array_smoke.sh`, `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh` |
| local i32 array variable index | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `scripts/c1_source_to_c_array_var_index_smoke.sh`, `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh` |
| local i8 array | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `scripts/c1_equiv_smoke.sh`, `scripts/c1_source_to_c_byte_array_assign_smoke.sh`, `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh` |
| local string i8[N]="..." | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `scripts/c1_source_to_c_byte_string_smoke.sh`, `scripts/c1_source_to_c_byte_string_var_index_smoke.sh`, `scripts/c1_source_to_c_byte_string_multi_buffer_smoke.sh`, `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh` |
| struct decl + field | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `scripts/c1_equiv_smoke.sh`, `scripts/c1_source_to_c_struct_field_smoke.sh`, `scripts/c1_asm_struct_field_smoke.sh`, `scripts/c1_wat_struct_field_smoke.sh` |
| struct array field | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | UNSUPPORTED | `scripts/c1_equiv_smoke.sh`, `scripts/c1_source_to_c_struct_array_smoke.sh`, `scripts/c1_asm_struct_array_smoke.sh`, `scripts/c1_wat_struct_array_smoke.sh` |
| by-value struct param | SUPPORTED | SUPPORTED | UNSUPPORTED | UNSUPPORTED | UNSUPPORTED | `scripts/c1_source_to_c_struct_param_smoke.sh` |
| extern fn void return | SUPPORTED | SUPPORTED | EXPERIMENTAL | EXPERIMENTAL | UNSUPPORTED | `scripts/extern_smoke.sh`, `scripts/c1_extern_call_smoke.sh`, `scripts/c1_asm_extern_call_smoke.sh`, `scripts/c1_wat_extern_call_smoke.sh` |
| extern fn i32 return | SUPPORTED | SUPPORTED | EXPERIMENTAL | EXPERIMENTAL | UNSUPPORTED | `scripts/c1_extern_call_smoke.sh`, `scripts/c1_asm_extern_call_smoke.sh`, `scripts/c1_wat_extern_import_smoke.sh` |
| extern bool/i8/byte param | SUPPORTED | SUPPORTED | EXPERIMENTAL | UNSUPPORTED | UNSUPPORTED | `scripts/c1_extern_scalar_param_smoke.sh`, `scripts/c1_asm_extern_scalar_param_smoke.sh` |
| extern byte-array pointer param | SUPPORTED | SUPPORTED | UNSUPPORTED | UNSUPPORTED | UNSUPPORTED | `scripts/c1_source_to_c_byte_string_extern_smoke.sh` |
| sizeof | SUPPORTED | SUPPORTED | UNSUPPORTED | UNSUPPORTED | UNSUPPORTED | `scripts/sizeof_smoke.sh`, `make check` |
| unary minus | SUPPORTED | SUPPORTED | EXPERIMENTAL | EXPERIMENTAL | UNSUPPORTED | `scripts/c1_equiv_smoke.sh` |
| return | SUPPORTED | SUPPORTED | SUPPORTED | SUPPORTED | EXPERIMENTAL | `scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh`, `scripts/c1_vm_return_smoke.sh` |

## Runtime / tooling

CLI subcommands:

| Tooling surface | Status | Notes / gate |
|---|---|---|
| `etl check FILE.etl` | EXPERIMENTAL | Uses the c1 lex+parse+sema path; `docs/cli.md`; `make examples-cli` |
| `etl compile FILE.etl -o OUT` | SUPPORTED | Uses the durable c0 -> C -> cc AOT path; `docs/cli.md`; `make examples-cli` |
| `etl run FILE.etl` | SUPPORTED | Compiles through c0/C to a temporary native executable and forwards its exit code; `make examples-cli` |

Makefile gates:

| Gate | Status | Notes |
|---|---|---|
| `make check` | GREEN | Unit tests, core smokes, compiler-1 focused smokes, bytecode emit smoke, runtime C tests. |
| `make selfhost` | GREEN | `c1-pipeline`, `selfhost-equiv`, and `scripts/c1_smoke.sh`. |
| `make selfhost-equiv` | GREEN | 32-fixture c0/C vs c1/C equivalence corpus. |
| `make selfhost-selfcompile` | IN-PROGRESS | Probe exists and records the current blocker; expected to fail until c1 has a real stdin-driven compile driver. |
| `make selfhost-bootstrap` | NOT-IMPLEMENTED | No Makefile target yet. |
| `make backend-vm` | GREEN | Bytecode emit, VM return, and VM expression/local equivalence smokes. |
| `make backend-subset` | GREEN | 18 shared C/ASM/WAT cases. |
| `make backend-asm` | GREEN | Focused x86-64 System V assembly smokes. |
| `make backend-wasm` | GREEN | Focused WAT/WASM text smokes; execution depends on optional tools. |
| `make examples-cli` | GREEN | Runs `scripts/examples_cli_smoke.sh`. |
| `make headless-ready` | GREEN | Integration target wired through current readiness gates. |
| `make visual` | NOT-IMPLEMENTED | No Makefile target yet. |
| `make examples` | NOT-IMPLEMENTED | No Makefile target yet. |
| `make release-check` | NOT-IMPLEMENTED | No Makefile target yet. |

## Optional dependencies

- SDL3 is needed for the SDL3 headless path exercised by
  `scripts/sdl3_headless_smoke.sh` through `make headless-ready`. When SDL3
  development headers or libraries are missing, the SDL3-specific smoke is
  expected to skip rather than fail the whole readiness gate.
- `wat2wasm` from WABT is needed to convert emitted WAT text into WASM. Without
  it, WAT/WASM smokes validate emitted text only.
- `wasmtime` or `wasmer` is needed to execute generated WASM. Without a runtime,
  WAT/WASM smokes stop after text validation or `wat2wasm` validation.
- The ASM backend assumes x86-64 System V tooling (`as`, `cc`, and a compatible
  host/linker). It is an active validation backend, not the primary portability
  path.

## Limitations

- ETL remains single-file from the compiler's perspective. Compiler-1 smoke
  scripts concatenate modules into one temporary compilation unit.
- C is the stable AOT production path. Compiler-1 fixed point is not complete;
  compiler-0 is not frozen yet.
- Runtime ETL must use the same frontend and semantic rules as AOT ETL, but
  runtime-loaded ETL modules are not implemented yet. The current VM is a
  bootstrap C helper for a small ASCII bytecode subset.
- No broad pointer arithmetic, dereference, field access through pointers, or
  pointer comparison exists. `pointer` is an opaque FFI boundary type.
- Strings are fixed-size `byte[N]` or `i8[N]` buffers with a null terminator.
  There is no heap string type or large standard library.
- Arrays are fixed-size locals or narrow parameter forms in the proven subsets.
  There is no dynamic array type and no bounds checking in the current C path.
- Structs are value types for the proven subsets. Struct returns, extern struct
  parameters, recursive structs, and broad nested struct shapes remain outside
  the supported surface.
- The CLI has no REPL, package manager, project manifest, incremental cache, or
  release packaging flow.
- Diagnostics are improving but remain uneven across c0, c1, and backend smoke
  harnesses; unsupported features should be documented and tested as such before
  being treated as user-facing contracts.
