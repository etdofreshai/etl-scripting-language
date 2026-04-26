# Parallel Wave 0012 - zai/glm-5.1

## Scope

Small build/CLI polish for compiler-0 without touching merge-hot `state/autopilot.md`.

## Changes

- Added `compiler0/__main__.py` so compiler-0 can be invoked as `python3 -m compiler0 compile ...`.
- Updated `scripts/bootstrap_smoke.sh` to exercise the package module entrypoint instead of the implementation module path.
- Added unittest coverage for the package module entrypoint compiling the sample program.

## Verification

```bash
make check
```

Result:

```text
Ran 37 tests in 0.164s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny fixture-driven compiler test helper for ETL examples once more examples appear, so smoke coverage can grow without duplicating subprocess/cc boilerplate.
