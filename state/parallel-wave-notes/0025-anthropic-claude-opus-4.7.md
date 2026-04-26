# Parallel Wave 0025 - anthropic/claude-opus-4.7

Worktree: `/home/node/.openclaw/tmp/etl-scripting-language/.worktrees/etl-wave-0025-anthropic-claude-opus-4.7`

## Change

- Added `%` to the lexer as an explicit tokenized arithmetic operator.
- Kept ETL v0 minimal by rejecting `%` in the parser with the same targeted unsupported-operator diagnostic used for `*` and `/`.
- Added parser/boundary tests for the `%` diagnostic.
- Updated README operator-boundary docs.

## Verification

```bash
make check
```

Result:

```text
Ran 68 tests in 0.291s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Continue tightening v0 parser boundaries before adding features: add explicit diagnostics for comparison/logical operators once their tokens are introduced, or add a tiny semantic smoke around return-expression type once non-i32 values exist.
