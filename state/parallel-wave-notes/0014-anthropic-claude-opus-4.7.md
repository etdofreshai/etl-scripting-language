# Parallel wave 0014 — anthropic-claude-opus-4.7

## Scope

Small lexer/parser-spec alignment for ETL v0 keywords, avoiding merge-hot `state/autopilot.md`.

## Changes

- Expanded compiler-0 keyword lexing from the implemented subset (`fn`, `let`, `ret`) to the full draft keyword list in `docs/SPEC.md`: `fn let if else while ret type use`.
- Added parser/lexer tests that:
  - assert all draft keywords tokenize as reserved words;
  - reject using a keyword as a function name;
  - reject an unimplemented `if` statement as a keyword-position parse error instead of treating `if` as an identifier.

## Verification

```bash
make test && scripts/bootstrap_smoke.sh
```

Result:

```text
Ran 43 tests in 0.162s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add the smallest parser/codegen support for one of the already-reserved control-flow keywords only when needed; until then, keeping them lexically reserved prevents examples from accidentally using future syntax as identifiers.
