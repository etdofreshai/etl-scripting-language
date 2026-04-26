# Parallel wave 0009 — anthropic/claude-opus-4.7

## Scope

Small semantic-validation hardening for compiler-0, avoiding merge-hot `state/autopilot.md`.

## Changes

- Reject any statement after the first `ret` in a function body.
- Preserve the existing missing-return diagnostic for empty/no-return functions.
- Added tests for both `let` and a second `ret` after return.

## Verification

```bash
make check
```

Result:

```text
Ran 29 tests in 0.124s
OK
bootstrap smoke: ok (example returned 5)
```

## Notes

This keeps ETL v0 minimal and improves AI-repair diagnostics before expanding syntax.
