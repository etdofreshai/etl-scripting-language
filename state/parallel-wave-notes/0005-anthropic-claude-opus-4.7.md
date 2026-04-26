# Parallel Wave 0005 - anthropic/claude-opus-4.7

## Scope

Small parser/compiler verification hardening, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added regression tests that lexer and parser diagnostics include useful line/column and expected-token details.
- Tightened the bootstrap smoke C build to compile emitted C with `-Wall -Werror`.

## Verification

```bash
make test && make smoke
```

Result:

```text
Ran 17 tests in 0.076s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None so far.

## Next suggestion

Add source spans to semantic errors next, so unknown names/functions and arity failures can point directly at the failing ETL source location.
