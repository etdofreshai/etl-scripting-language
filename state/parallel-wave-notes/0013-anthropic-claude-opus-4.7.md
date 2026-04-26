# Parallel Wave 0013 — anthropic/claude-opus-4.7

## Scope

Small compiler-0 CLI regression coverage, focused on safe failure behavior and avoiding merge-hot autopilot state.

## Changes

- Added a CLI regression test proving a failed compile does not overwrite an existing output file.
- Kept implementation unchanged because `compile_file` already compiles/validates before writing, so the new test documents and protects the desired behavior.

## Verification

```bash
make check
```

Result:

```text
Ran 39 tests in 0.160s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny fixture-driven smoke test helper for example programs, then use it for both successful examples and expected-failure CLI cases without duplicating subprocess setup.
