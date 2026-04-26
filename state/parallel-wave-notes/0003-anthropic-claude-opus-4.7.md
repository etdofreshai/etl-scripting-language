# Parallel Wave 0003 - anthropic/claude-opus-4.7

## Scope

Focused on compiler-0 C backend correctness and parser/compiler verification, staying small and low-conflict.

## Changes

- Made semantic validation collect all function declarations before validating bodies, so calls can reference functions declared later in the file.
- Added C function prototype emission before function bodies, so forward calls compile cleanly under stricter C compiler flags.
- Strengthened compiler tests to build generated C with `-Wall -Werror`.
- Added a forward-call compile/run test for `main` calling `add` before `add` is declared.

## Verification

```bash
make test && make smoke
```

Result:

```text
Ran 12 tests in 0.077s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add the smallest return-path semantic check: require each `i32` function to contain a `ret` along every currently-supported body path (for the present straight-line subset, at least one final `ret` is enough), then keep compiling generated C under `-Wall -Werror`.
