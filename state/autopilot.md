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
