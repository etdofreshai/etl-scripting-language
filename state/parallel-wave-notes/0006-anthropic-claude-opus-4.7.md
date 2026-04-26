# Parallel Wave 0006 - anthropic/claude-opus-4.7

## Scope

Small semantic diagnostic improvement for compiler-0, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added lightweight source locations to parser AST nodes.
- Updated semantic validation errors to include `line:col` prefixes for duplicate functions/names, unsupported types, missing final returns, unknown names/functions, and call arity mismatches.
- Added regression tests for semantic error locations on unknown names, bad call arity, and unsupported local types.

## Verification

```bash
make test && make smoke
```

Result:

```text
Ran 20 tests in 0.076s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny expression type inference/checking pass next, so return expressions and call arguments are validated as `i32` before introducing any second type.
