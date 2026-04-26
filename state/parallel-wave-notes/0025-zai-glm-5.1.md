# Parallel wave 0025 - zai/glm-5.1

## Scope

Added a small compiler/bootstrap verification increment without touching merge-hot `state/autopilot.md`.

## Changes

- Added `scripts/expression_smoke.sh`, a native smoke test for nested function calls, multiple `let` statements, parenthesized expressions, `+`, and `-`.
- Wired the new smoke test into `make smoke` / `make check`.
- Updated README smoke-test wording to document the expanded coverage.

## Verification

```bash
make check
```

Result:

```text
Ran 67 tests in 0.290s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
expression smoke: ok (program returned 10)
```

## Blockers

None.

## Next suggestion

Add a small semantic/type-checking test seam before introducing non-`i32` types, so future bool/byte work has an obvious place to plug in expression type inference.
