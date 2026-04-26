# Parallel Wave 0019 — anthropic/claude-opus-4.7

## Scope

Small compiler-0 semantic hardening in the isolated wave worktree. Avoided merge-hot `state/autopilot.md`.

## Changes

- Reject parameter names that conflict with any function name.
- Reject local `let` names that conflict with any function name.
- Added regression tests for both cases.

## Why

The C backend emits functions and locals into C scopes where a parameter/local can shadow a function. ETL code such as `let helper i32 = 1; ret helper()` could pass semantic validation but produce invalid C. The validator now catches this before codegen.

## Verification

```bash
make test && scripts/bootstrap_smoke.sh
```

Result:

```text
Ran 56 tests in 0.285s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a narrow negative compiler smoke test that asserts invalid ETL never leaves or overwrites generated C outputs beyond the existing CLI preservation case, or begin the first minimal type-check boundary if more expression types are introduced.
