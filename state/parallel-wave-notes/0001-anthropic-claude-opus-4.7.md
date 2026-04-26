# Parallel Wave 0001 - anthropic-claude-opus-4.7

## Scope

Added the smallest compiler-0 CLI path, matching the prior autopilot next step, without touching merge-hot `state/autopilot.md`.

## Changes

- Added `python3 -m compiler0.etl0 compile <input.etl> -o <out.c>`.
- Added CLI smoke coverage that compiles the sample through the CLI, builds emitted C with `cc`, and verifies the exit code.
- Added a CLI error-path test for invalid source.
- Documented the CLI command in `README.md`.

## Verification

```bash
make test
```

Result:

```text
Ran 9 tests in 0.053s
OK
```

```bash
tmpdir=$(mktemp -d) && python3 -m compiler0.etl0 compile examples/add_main.etl -o "$tmpdir/add_main.c" && cc "$tmpdir/add_main.c" -o "$tmpdir/add_main" && "$tmpdir/add_main"; code=$?; echo "exit=$code"; test "$code" -eq 5
```

Result:

```text
exit=5
```

## Next suggestion

Add minimal diagnostic location coverage for semantic errors, or add a parser fixture for the next syntax feature only after the C bootstrap CLI remains stable.
