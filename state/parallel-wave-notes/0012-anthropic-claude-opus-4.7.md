# Parallel Wave 0012 — anthropic/claude-opus-4.7

## Scope

Small parser diagnostic hardening in compiler-0, chosen to avoid merge-hot state and broad implementation churn.

## Changes

- Added an explicit parser error for unterminated function bodies that reach EOF before `}`.
- Added unittest coverage for the unterminated-function diagnostic.

## Verification

```bash
make check
```

Result:

```text
Ran 37 tests in 0.128s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add the next smallest syntax/diagnostic guard around parameter lists or argument lists reaching EOF, then keep routing through `make check`.
