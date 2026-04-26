# Parallel Wave 0010 — anthropic-claude-opus-4.7

## Focus

Small compiler-0 hardening for the C backend, with parser/compiler tests and bootstrap smoke verification.

## Changes

- Added semantic validation that rejects ETL function, parameter, and local names that are reserved C keywords before code generation.
- Added regression tests for reserved C function, parameter, and local names.

## Verification

```bash
make check
```

Result:

```text
Ran 32 tests in 0.125s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a small source fixture for C-backend identifier edge cases once ETL grows beyond the current `i32` function subset, especially if backend-specific name mangling is introduced instead of rejecting reserved names.
