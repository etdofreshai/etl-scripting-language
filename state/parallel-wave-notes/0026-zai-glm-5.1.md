# Parallel Wave 0026 - zai/glm-5.1

## Scope

Small parser diagnostic hardening for compiler-0, focused on AI-repairable errors without expanding ETL v0 syntax.

## Changes

- Added targeted parse errors when parameter lists are missing a comma before the next parameter.
- Added targeted parse errors when call argument lists are missing a comma before the next argument.
- Updated parser tests for both diagnostics.

## Verification

```bash
make check
```

Result:

```text
Ran 69 tests in 0.293s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
expression smoke: ok (program returned 10)
```

## Blockers

None.

## Next suggestion

Add similarly targeted diagnostics for trailing commas in parameter and call argument lists, or start the smallest `if`/`else` parser boundary tests before implementing control flow.
