# Parallel Wave 0014 — zai/glm-5.1

## Scope

Small bootstrap/build-tooling verification improvement, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added `scripts/stdout_smoke.sh` to verify `etl0 compile -o -` can pipe generated C directly into `cc -x c -`.
- Extended `make smoke`/`make check` to run both the file-output bootstrap smoke and the stdout-pipe smoke.
- Updated README smoke wording to describe both smoke paths.

## Verification

```bash
make check
```

Result:

```text
Ran 40 tests in 0.163s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny golden C output fixture for `examples/add_main.etl` to make formatting/codegen drift explicit before compiler-0 grows more statements.
