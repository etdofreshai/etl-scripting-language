# Parallel Wave 0015 — anthropic-claude-opus-4.7

## Scope

Small compiler-0 CLI/build-tooling improvement, avoiding merge-hot autopilot state.

## Changes

- Added `-` stdin support to `python3 -m compiler0 compile`.
- Split compiler file writing into `compile_text(...)` so stdin and file inputs share the same validation/emission path.
- Added unit coverage for stdin-to-file and stdin-to-stdout compile flows.
- Added `scripts/stdin_smoke.sh` and included it in `make smoke` / `make check`.
- Updated README usage notes for stdin/stdout piping.

## Verification

```bash
make check
```

Result:

```text
Ran 45 tests in 0.163s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny expression/semantic regression around C-safe emission for the minimum i32 literal (`-2147483648`) by compiling it with `cc -Wall -Werror`, then adjust emission if the host C compiler treats it awkwardly.
