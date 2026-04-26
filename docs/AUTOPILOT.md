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

1. Migrate compiler-0 and examples from brace-delimited function bodies to `end`-terminated function bodies.
2. Finalize ETL v0 lexical grammar and syntax choices.
3. Create compiler-0 skeleton in a pragmatic host language.
4. Implement lexer/parser for a tiny function subset.
5. Emit C for a tiny program and run it.
5. Grow v0 only enough to write the compiler in ETL.
6. Begin compiler-1 in ETL.
7. Bootstrap: compiler-0 builds compiler-1; compiler-1 builds future compiler.

## Preferred verification

Use the smallest relevant check available, for example:

```bash
make test
python3 -m pytest
cargo test
go test ./...
```

If no build system exists yet, add one before expanding the language.
