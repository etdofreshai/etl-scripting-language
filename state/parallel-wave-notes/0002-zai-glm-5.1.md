# Parallel Wave 0002 — zai/glm-5.1

## Scope

Small lexer/parser-adjacent increment for ETL compiler-0, avoiding merge-hot autopilot state.

## Changes

- Added lexer support for `//` line comments.
- Added tests that comments are skipped before code, after code, and inside compilable sample source.

## Verification

```bash
make test
```

Result: 11 unittest tests passed.

## Notes

This keeps ETL v0 minimal while allowing examples and compiler-1 source to carry explanatory comments without affecting parsing or C emission.

## Next suggestion

Add a tiny parse/semantic check that every function body eventually has a `ret`, so generated C does not silently omit returns for non-void v0 functions.
