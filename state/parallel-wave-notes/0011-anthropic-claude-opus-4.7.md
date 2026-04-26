# Parallel Wave 0011 — anthropic-claude-opus-4.7

## Focus

Compiler-0 semantic hardening for bootstrap entrypoint expectations, verified through parser/compiler tests and bootstrap smoke.

## Changes

- Added validation that every ETL program defines a `main` function.
- Enforced the current C bootstrap contract that `main` takes no parameters and returns `i32`.
- Added regression coverage for missing `main`, parameterized `main`, non-`i32` `main`, and preserved non-main unsupported-type diagnostics.
- Adjusted the reserved-parameter-name regression to avoid conflicting with the stricter `main` signature rule.

## Verification

```bash
make check
```

Result:

```text
Ran 35 tests in 0.125s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny negative bootstrap-smoke fixture (CLI compile should fail cleanly for a source file without `main`) once the test harness grows fixture-based smoke cases.
