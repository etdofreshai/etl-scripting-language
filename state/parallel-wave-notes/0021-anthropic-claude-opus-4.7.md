# Parallel Wave 0021 - anthropic/claude-opus-4.7

## Scope

Kept this wave small and parser/diagnostic-focused: make ETL v0's current arithmetic boundary clearer without expanding the language.

## Changes

- Added `*` token recognition so multiplication reaches the parser instead of failing as an unknown lexer character.
- Added a targeted parser diagnostic for unsupported multiplication: `operator '*' is not supported in ETL v0`.
- Added regression coverage for the diagnostic.
- Documented the explicit unsupported-operator diagnostic boundary in `README.md`.

## Verification

```bash
make check
```

Result:

```text
Ran 60 tests in 0.289s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a similar explicit v0 diagnostic for `/` when it is not a line comment, or start a tiny type-check boundary that verifies `ret` expression types once new primitive types are introduced.
