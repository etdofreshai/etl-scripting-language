# Parallel wave 0015 - zai/glm-5.1

## Focus

Small compiler-0 hardening in a low-conflict semantic validation area.

## Change

- Added validation for C-backend-reserved underscore identifier forms:
  - names beginning with `__`
  - names beginning with `_` followed by an uppercase letter
- Kept lowercase single-underscore identifiers valid for now (for example `_tmp`).
- Added regression tests for rejected and accepted underscore identifier forms.

## Verification

```bash
make check
```

Result: 46 unittest cases passed, then both bootstrap smoke scripts passed.

## Blockers

None.

## Next suggestion

Add the next minimal expression/codegen feature only after preserving the `make check` gate; a small comparison/branch subset for `if` would be a useful step toward compiler-1, but should be isolated behind parser + C smoke tests.
