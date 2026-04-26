# Parallel wave 0017 — zai/glm-5.1

## Scope

Focused on a small compiler/codegen hardening change plus full parser/compiler/bootstrap verification.

## Change

- Hardened C emission for the minimum `i32` literal.
- `-2147483648` is now emitted as `(-2147483647 - 1)` so the generated C avoids relying on a positive integer token outside signed 32-bit range.
- Updated tests to assert and compile/run the portable emitted form.
- Documented the behavior in `README.md`.

## Verification

```bash
make check
```

Result:

```text
Ran 50 tests in 0.194s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a tiny expression/codegen regression fixture for nested call arguments and left-associative subtraction, then keep growing only validation/codegen behavior needed by the bootstrap sample.
