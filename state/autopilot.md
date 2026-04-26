# ETL Autopilot State

## Current objective

Create the initial ETL repository structure, pin down ETL v0, and build compiler-0 toward the first ETL-to-C smoke test.

## Current decision

Start with a C backend. Treat WASM, ASM, and mobile as later targets after the v0 compiler pipeline exists.

ETL source syntax should use terminating keywords instead of braces. Function bodies should be written as `fn ...` followed by statements and closed with `end`. Future autopilot waves should migrate compiler-0, examples, tests, and docs away from `{ ... }` ETL source blocks.

## Next best steps

1. Migrate compiler-0 syntax from brace-delimited functions to `end`-terminated functions.
2. Update examples and tests to use `end`.
3. Preserve C backend output; braces remain fine in emitted C.
4. Add/adjust parser diagnostics for missing `end`.

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

## Cycle 2026-04-25 22:20 CDT

Action taken:

- Added the first semantic validation pass to compiler-0 before C emission.
- Validation now rejects duplicate function names, unsupported types, duplicate local/parameter names, unknown names/functions, and call arity mismatches.
- Added unittest coverage for duplicate functions, unsupported return types, call arity mismatch, and unknown names.
- Updated README and this state file with the new validation boundary.

Verification:

```bash
make test
```

Result:

```text
Ran 7 tests
OK
```

Next likely move:

- Add a minimal CLI entrypoint for compiler-0 (`etl0 compile input.etl -o out.c`) and verify the example through the CLI path.

Blockers: none.

## Syntax steering 2026-04-26 00:01 CDT

ET requested ETL source blocks use terminating keywords instead of braces.

Decision:

- ETL functions should be written as `fn ...` followed by statements and closed with `end`.
- Braces are not ETL source block syntax.
- Braces remain acceptable in emitted C and host compiler implementation code.

Immediate next autopilot task:

- Migrate compiler-0 lexer/parser/examples/tests from `{ ... }` function bodies to `end`-terminated function bodies while keeping existing C output and smoke tests passing.
