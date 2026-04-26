# Parallel wave 0020 — zai/glm-5.1

## Focus

Verification-oriented CLI diagnostics for compiler-0.

## Changes

- Added source labels to `etl0 compile` semantic/parse/lex errors:
  - file input reports the input path before the source location
  - stdin input reports `<stdin>` before the source location
- Added unittest coverage for file-input and stdin diagnostic labels.
- Documented the CLI diagnostic shape in `README.md`.

## Verification

```bash
make check
```

Result: pass — 57 unittest cases plus bootstrap/stdout/stdin smoke scripts.

## Blockers

None.

## Next suggestion

Keep improving compiler-0 repair-loop diagnostics: consider source-line snippets/carets for parser and semantic errors once the minimal pipeline remains stable.
