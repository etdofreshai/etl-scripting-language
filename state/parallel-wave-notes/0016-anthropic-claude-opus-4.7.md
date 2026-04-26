# Parallel Wave 0016 — anthropic-claude-opus-4.7

## Scope

Small parser/compiler verification hardening, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added a compiler/codegen regression for the minimum supported `i32` literal (`-2147483648`).
- The regression now compiles generated C with `cc -Wall -Werror` and runs it, covering the C backend edge case suggested by the previous wave.

## Verification

```bash
make check
```

Result:

```text
Ran 49 tests in 0.188s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny statement-boundary regression around the current newline-free grammar behavior, then decide whether v0 should keep whitespace-insensitive statement parsing or require explicit separators before the language grows control flow.
