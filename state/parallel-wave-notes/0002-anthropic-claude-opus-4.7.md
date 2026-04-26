# Parallel Wave 0002 - anthropic-claude-opus-4.7

## Scope

Added a small bootstrap smoke target without touching merge-hot `state/autopilot.md`.

## Changes

- Added `scripts/bootstrap_smoke.sh` to compile `examples/add_main.etl` through compiler-0, build the emitted C with `cc`, run it, and assert the expected exit code.
- Added `make smoke` as a durable command for the ETL -> C -> native executable path.
- Documented the smoke command in `README.md`.

## Verification

```bash
make test && make smoke
```

Result:

```text
Ran 9 tests in 0.052s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add source locations to AST nodes or semantic errors so compiler-0 diagnostics become easier for LLM repair loops before expanding the language syntax.
