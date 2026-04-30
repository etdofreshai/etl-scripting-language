# ETL Autopilot

Purpose: build ETL, a minimal LLM-oriented language and self-hosting compiler, through small verified increments.

## Standing rules

- Keep ETL v0 minimal. Avoid clever features until the compiler can self-host.
- Prefer explicit, regular syntax over compact ambiguity.
- Use terminating keywords for ETL source blocks. Function bodies should use `end`, not `{ ... }` braces.
- Optimize compiler diagnostics for AI repair loops.
- First working backend should be C.
- Do not start ASM, WASM, and mobile simultaneously; sequence them after the C bootstrap path is solid.
- Every cycle should leave durable state in docs, tests, commits, or `state/autopilot.md`.
- Every meaningful implementation step needs a small verification command.
- Do not ask ET routine questions; choose the safest small next step.

## Near-term milestones

1. Keep compiler-0 frozen except for fixes needed to preserve the existing v0 corpus.
2. Expand compiler-1's C emitter beyond the initial `main returns i32 literal` smoke.
3. Connect compiler-1 lex/parse/sema/emit into a real source-to-C command path.
4. Run compiler-1 against `tests/etl_corpus/` and compare behavior with compiler-0.
5. Bootstrap: compiler-0 builds compiler-1; compiler-1 builds future compiler.

## Preferred verification

Use the smallest relevant check available, for example:

```bash
make test
python3 -m pytest
cargo test
go test ./...
```

If no build system exists yet, add one before expanding the language.
