# Parallel Wave 0024 - zai/glm-5.1

## Focus

Small compiler-0 CLI diagnostics hardening, staying away from merge-hot autopilot state and language-surface expansion.

## Changes

- Made `python3 -m compiler0 compile <missing-input> -o -` report the user-supplied input label before the OS error.
- Kept output-path `OSError` handling on the general CLI path so output failures are not mislabeled as source failures.
- Added regression coverage for missing input diagnostics.

## Verification

```bash
make check
```

Result: 67 parser/compiler tests passed, then all bootstrap smoke paths passed (`bootstrap_smoke.sh`, `stdout_smoke.sh`, `stdin_smoke.sh`).

## Blockers

None.

## Next suggestion

Add dedicated regression coverage for output-path failures so input-read diagnostics and output-write diagnostics stay clearly separated.
