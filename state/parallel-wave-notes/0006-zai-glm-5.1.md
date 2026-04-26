# Parallel wave 0006 - zai/glm-5.1

## Scope

Focused on low-conflict build/verification ergonomics for compiler-0.

## Changes

- Added `make check` as a combined verification gate that runs both parser/compiler unit tests and the bootstrap smoke test.
- Documented `make check` in `README.md` next to the existing `make test` and `make smoke` commands.

## Verification

```bash
make check
```

Result:

```text
Ran 17 tests in 0.078s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Make future autopilot/CI entrypoints use `make check` so parser/compiler tests and the ETL -> C -> native smoke stay tied together.
