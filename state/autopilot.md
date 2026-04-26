# ETL Autopilot State

## Current objective

Create the initial ETL repository structure, pin down ETL v0, and build compiler-0 toward the first ETL-to-C smoke test.

## Current decision

Start with a C backend. Treat WASM, ASM, and mobile as later targets after the v0 compiler pipeline exists.

## Next best steps

1. Choose compiler-0 implementation language.
2. Add lexer/parser tests for the sample `add/main` program.
3. Implement the smallest parser/codegen path that emits C.
4. Add a smoke test that compiles and runs emitted C.

## Blockers

None yet.

## Cycle 2026-04-25 22:18 CDT

Action taken:

- Chose Python for compiler-0 because it keeps the first parser/codegen loop small and easy to verify.
- Added `compiler0/etl0.py` with lexer, parser, AST dataclasses, and a minimal C backend for the v0 `add/main` subset.
- Added `examples/add_main.etl` as the first bootstrap-style sample.
- Added `tests/test_compiler0.py` covering lexing, parsing, C emission, compiling emitted C with `cc`, and running the result.
- Updated `Makefile` so `make test` runs the real compiler-0 tests.

Verification:

```bash
make test
```

Result:

```text
Ran 3 tests
OK
```

Next likely move:

- Add the smallest semantic validation pass for duplicate functions, unsupported types, and call arity before growing syntax.

Blockers: none.
