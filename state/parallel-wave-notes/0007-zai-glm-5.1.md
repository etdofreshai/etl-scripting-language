# Parallel Wave 0007 — zai/glm-5.1

## Scope

Small parser/compiler increment for compiler-0, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added parenthesized expression parsing in `compiler0/etl0.py`.
- Added parser and compile/run regression tests for `ret (1 + 2) + 3`.
- Documented parenthesized expressions in the current compiler-0 README feature list.

## Verification

```bash
make check
```

Result:

```text
Ran 22 tests in 0.102s
OK
bootstrap smoke: ok (example returned 5)
```

Note: one expected CLI error-path test prints `etl0: error: ... unsupported type 'u32' ...` to stderr while still passing.

## Blockers

None.

## Next suggestion

Add a tiny expression type inference/checking helper next, even while all current expressions are `i32`, so return expressions, let initializers, binary operands, and call arguments have a clear validation path before introducing `bool` or additional integer types.
