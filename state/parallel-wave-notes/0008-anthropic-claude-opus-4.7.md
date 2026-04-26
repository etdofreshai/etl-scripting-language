# Parallel Wave 0008 - anthropic-claude-opus-4.7

## Scope

Small parser/compiler increment for the ETL v0 arithmetic subset, staying within compiler-0 and parser tests.

## Changes

- Added `-` as a lexer token and binary expression operator with the same left-associative precedence as `+`.
- Added negative integer literal parsing for forms like `-2` and `-2147483648`.
- Added tests for subtraction, negative literals, min-i32 acceptance, and rejecting unary `-` before non-integers.
- Updated README and draft spec to document the supported arithmetic subset.

## Verification

```bash
make check
```

Result:

```text
Ran 27 tests in 0.125s
OK
bootstrap smoke: ok (example returned 5)
```

## Blockers

None.

## Next suggestion

Add minimal typed expression checking so `let` initializers and `ret` expressions are validated against declared `i32` types before adding `if`/`while`.
