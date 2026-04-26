# Parallel Wave 0018 - zai/glm-5.1

Scope: kept this wave intentionally low-conflict by adding compiler/codegen regression coverage only.

Changes:

- Added compiler tests for zero-argument helper calls through the C backend.
- Added compiler tests for function calls used as operands in binary expressions.
- Both tests compile generated C with `cc -Wall -Werror` and execute the result.

Verification:

```bash
make check
```

Result: passed (`Ran 53 tests`, bootstrap/stdout/stdin smoke scripts all ok).

Blockers: none found.

Next suggestion: add the smallest statement-level control-flow subset (`if`/`else`) only after return/let/call diagnostics stay stable.
