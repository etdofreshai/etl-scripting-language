# Parallel Wave 0023 - zai/glm-5.1

## Scope

Kept this wave to low-conflict build/smoke tooling. I did not edit `state/autopilot.md`.

## Change

- Made all bootstrap smoke scripts `cd` to the repository root after resolving their own path.
- This keeps `python3 -m compiler0` importable when a smoke script is launched from outside the repo, while preserving the existing `make smoke` path.

## Verification

```bash
make check
(cd /tmp && /home/node/.openclaw/tmp/etl-scripting-language/.worktrees/etl-wave-0023-zai-glm-5.1/scripts/bootstrap_smoke.sh)
(cd /tmp && /home/node/.openclaw/tmp/etl-scripting-language/.worktrees/etl-wave-0023-zai-glm-5.1/scripts/stdout_smoke.sh)
(cd /tmp && /home/node/.openclaw/tmp/etl-scripting-language/.worktrees/etl-wave-0023-zai-glm-5.1/scripts/stdin_smoke.sh)
```

Result:

```text
Ran 64 tests in 0.287s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a small smoke fixture for a helper function called before its declaration so the script-level bootstrap path covers forward prototypes, not only the single `add/main` example.
