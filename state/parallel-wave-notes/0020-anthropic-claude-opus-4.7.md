# Parallel Wave 0020 - anthropic/claude-opus-4.7

## Scope

Kept this wave intentionally small and low-conflict: C backend semantic hardening plus tests.

## Changes

- Reserved backend-provided stdint typedef identifiers (`int32_t`, `uint64_t`, etc.) in compiler-0 semantic validation.
- Added regression tests proving ETL function/local names cannot collide with emitted C typedef names.

## Verification

```bash
make check
```

Result:

```text
Ran 58 tests in 0.281s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny expression-precedence test/implementation boundary next (e.g. decide whether `*` exists now or explicitly reject it with a targeted diagnostic) before expanding statements.
