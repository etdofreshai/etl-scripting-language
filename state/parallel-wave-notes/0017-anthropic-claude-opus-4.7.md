# Parallel Wave 0017 — anthropic-claude-opus-4.7

## Scope

Small parser/compiler regression coverage, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added a compiler/codegen regression for compact adjacent statements in the current whitespace-insensitive grammar:
  `fn main() i32 { let x i32 = 2 let y i32 = 3 ret x + y }`.
- The regression checks emitted C for both locals and the return expression, then compiles with `cc -Wall -Werror` and runs the executable.

## Verification

```bash
make check
```

Result:

```text
Ran 51 tests in 0.217s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Decide whether ETL v0 should intentionally keep whitespace-insensitive statement boundaries (current behavior) or introduce explicit separators before adding `if`/`while` bodies, then document that choice in `docs/SPEC.md`.
