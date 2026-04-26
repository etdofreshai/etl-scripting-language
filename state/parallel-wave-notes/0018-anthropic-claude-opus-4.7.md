# Parallel Wave 0018 — anthropic-claude-opus-4.7

## Scope

Small parser/codegen regression coverage, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added a compiler regression covering nested call arguments combined with left-associative subtraction.
- The regression verifies emitted C shape, compiles it with `cc -Wall -Werror`, runs the executable, and checks the expected exit code.

## Verification

```bash
make check
```

Result:

```text
Ran 52 tests in 0.238s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add the smallest explicit statement-separator decision to the v0 spec before implementing `if`/`while`, because the current parser intentionally accepts compact adjacent statements without semicolons or newlines.
