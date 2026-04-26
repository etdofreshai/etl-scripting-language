# Parallel wave 0001 — zai/glm-5.1

## Scope

Added a minimal compiler-0 CLI entrypoint without changing merge-hot `state/autopilot.md`.

## Changes

- Added `python3 -m compiler0.etl0 compile <input.etl> -o <output.c>`.
- Added a reusable `main(argv)` path for tests.
- Added CLI smoke coverage that compiles the sample through the CLI, builds the emitted C with `cc`, and verifies the exit code.
- Documented the CLI command in `README.md`.

## Verification

```bash
make test
```

Result:

```text
Ran 8 tests in 0.053s
OK
```

Additional manual smoke:

```bash
python3 -m compiler0.etl0 compile examples/add_main.etl -o /tmp/etl-wave-0001-add_main.c
cc /tmp/etl-wave-0001-add_main.c -o /tmp/etl-wave-0001-add_main
/tmp/etl-wave-0001-add_main
```

Expected process exit code: `5`.

## Next suggestion

Add source locations to AST nodes or semantic diagnostics next, so AI repair loops can point users at the exact function/name that failed without growing the language surface.
