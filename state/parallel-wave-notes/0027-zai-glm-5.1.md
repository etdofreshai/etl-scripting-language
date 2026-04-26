# Parallel wave 0027 — zai/glm-5.1

## Scope

Small build/verification hardening change, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added `scripts/error_smoke.sh` to exercise the compiler CLI failure path with a semantic error.
- The smoke verifies three LLM-repair-critical properties:
  - bad source exits with status `1`
  - diagnostics include the input path plus ETL source location
  - a failed compile preserves an existing output file
- Wired the new smoke into `make smoke`, so `make check` covers it with parser/compiler tests and existing bootstrap smoke paths.

## Verification

```bash
make check
```

Result:

```text
Ran 69 tests in 0.291s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
expression smoke: ok (program returned 10)
error smoke: ok (bad source failed safely)
```

## Blockers

None.

## Next suggestion

Add the smallest expression type-checking boundary next, e.g. keep all expression values `i32` today and make that explicit in validation helpers before adding `bool`/conditions.
