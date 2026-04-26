# Parallel Wave 0007 - anthropic/claude-opus-4.7

## Scope

Small compiler-0 semantic validation hardening, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added explicit `i32` integer literal range validation before C emission.
- Added regression coverage that rejects `2147483648` with a source location and still accepts `2147483647`.
- Documented the literal range check in `README.md`.

## Verification

```bash
make check
```

Result:

```text
Ran 22 tests in 0.077s
OK
bootstrap smoke: ok (example returned 5)
```

Note: one CLI error-path test intentionally prints `etl0: error: ...` to stderr while asserting the nonzero compiler result.

## Blockers

None.

## Next suggestion

Add minimal expression type inference next: track local/parameter types and function return types so return expressions, `let` initializers, and call arguments are checked structurally before adding a second supported scalar type.
