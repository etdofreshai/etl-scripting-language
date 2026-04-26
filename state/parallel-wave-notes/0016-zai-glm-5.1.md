# Parallel Wave 0016 — zai/glm-5.1

## Scope

Small codegen regression coverage, avoiding merge-hot `state/autopilot.md`.

## Changes

- Added a golden C fixture for `examples/add_main.etl` at `tests/fixtures/add_main.c`.
- Added a unittest asserting compiler-0 emits exactly that fixture for the sample program, making formatting/codegen drift explicit before the backend grows.

## Verification

```bash
make check
```

Result:

```text
Ran 49 tests in 0.163s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add the first tiny control-flow parser/codegen slice (`if`/`else` returning `i32`) only after deciding the exact v0 brace/newline rules, with both parser assertions and a C smoke test.
