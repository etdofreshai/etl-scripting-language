# Parallel Wave 0021 — zai/glm-5.1

## Focus

Kept this wave small and parser/compiler-adjacent. I avoided the merge-hot `state/autopilot.md` and worked only inside this isolated worktree.

## Changes

- Tightened compiler-0 lexing so ETL identifiers are ASCII-only (`A-Z`, `a-z`, `_`, then digits).
- Added regression coverage for rejecting non-ASCII identifier starts and continuations before they can reach the C backend.

## Why

Python's `str.isalpha()` / `str.isalnum()` accepts Unicode letters, which allowed source like `fn café() ...` to parse as an ETL identifier but emit invalid/unportable C. ETL v0 is C-backend-first, so the lexer now uses explicit ASCII identifier rules.

## Verification

```bash
make check
```

Result:

```text
Ran 61 tests in 0.290s
OK
bootstrap smoke: ok (example returned 5)
stdout smoke: ok (example returned 5)
stdin smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add a short identifier grammar note to `docs/SPEC.md` once parallel docs/spec edits cool down, matching the implementation's ASCII-only v0 rule.
