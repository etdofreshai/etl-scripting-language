# Parallel Wave 0023 - anthropic/claude-opus-4.7

## Scope

Kept this wave intentionally small and test-focused. Followed the prior wave's suggestion to add a compact negative-test fixture style for v0 boundaries without expanding the language.

## Changes

- Added `tests/test_v0_boundaries.py` with table-driven regression coverage for unsupported-but-tokenized arithmetic operators (`*`, `/`).
- Added regression coverage that reserved draft keywords not implemented as statements yet (`if`, `while`, `type`, `use`) remain rejected at the parser boundary.

## Verification

```bash
make check
```

Result:

```text
Ran 66 tests in 0.293s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add the smallest expression-precedence step only when needed: either explicitly document/test that v0 currently has no `*`/`/`, or later introduce a precedence parser when multiplication is intentionally added.
