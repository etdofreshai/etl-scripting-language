# Parallel Wave 0024 - anthropic/claude-opus-4.7

## Scope

Kept this wave intentionally small and low-conflict, focused on bootstrap verification rather than expanding ETL v0 syntax.

## Changes

- Hardened `scripts/bootstrap_smoke.sh` so the example-generated C must match `tests/fixtures/add_main.c` before compiling/running it.
- Updated `README.md` to document that `make smoke` includes the golden C fixture check in the bootstrap path.

## Verification

```bash
make check
```

Result:

```text
Ran 66 tests in 0.291s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add the next tiny parser/compiler feature only after deciding whether `if`/`while` or richer type support is more important for the first self-hosting compiler skeleton.
