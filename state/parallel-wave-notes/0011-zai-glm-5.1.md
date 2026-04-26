# Parallel wave 0011 - zai/glm-5.1

## Scope

Kept this wave small and low-conflict: compiler-0 CLI/build-tooling behavior plus regression coverage.

## Changes

- Made `compile_file` create missing output parent directories before writing generated C.
- Added a CLI regression test that compiles to a nested output path.

## Verification

```bash
make check
```

Result:

```text
Ran 33 tests in 0.125s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a small negative CLI test that verifies syntax/semantic failures do not leave a partial output file when the target parent already exists, or begin the next minimal syntax milestone (`if`/`else`) behind focused parser/codegen tests.
