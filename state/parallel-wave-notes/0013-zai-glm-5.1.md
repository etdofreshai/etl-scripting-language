# Parallel Wave 0013 — zai/glm-5.1

## Scope

Small compiler-0 CLI/build-tooling improvement, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added `etl0 compile input.etl -o -` support to write generated C to stdout.
- Kept file output behavior unchanged, including parent directory creation.
- Added unittest coverage for stdout emission.

## Verification

```bash
make check
```

Result:

```text
Ran 39 tests in 0.162s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a small golden-output or shell smoke test for piping stdout directly into `cc -x c -` once the CLI surface settles.
