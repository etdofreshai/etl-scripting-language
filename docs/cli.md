# ETL CLI

The `etl` CLI is the user-facing entry point for ETL's compile/run/check
workflows. It is intentionally tiny and dependency-free: pure POSIX
shell plus `python3` (compiler-0) and a C compiler.

The wrapper lives at `bin/etl` and exec()s `scripts/etl_cli.sh`. The
implementation can change without changing the user-visible binary
path.

## Status

This CLI is a Level 2 readiness piece (see
`docs/language-goal-roadmap.md`). It wraps the durable c0 → C → cc AOT
pipeline plus a c1 lex+parse+sema check. Diagnostics today are
exit-code based; richer file/line/column reporting is on the roadmap.

## Quick start

```sh
# Lint a source file (lex + parse + sema, c1 pipeline).
bin/etl check examples/cli/hello.etl

# Build a native binary.
bin/etl compile examples/cli/hello.etl -o build/hello

# Compile and run, forwarding the program's exit code.
bin/etl run examples/cli/hello.etl
echo "exit=$?"
```

## Commands

### `etl check FILE.etl`

Runs the compiler-1 lex+parse+sema pipeline on `FILE.etl`. The CLI
builds a small c0-built compiler-1 binary (cached under
`build/etl_cli/c1_check`) the first time `check` is invoked, then pipes
the source file through it on stdin.

Exit codes:

| code | meaning                            |
| ---- | ---------------------------------- |
| 0    | accepted (lex + parse + sema OK)   |
| 10   | could not read source from stdin   |
| 11   | lex error                          |
| 12   | parse error                        |
| 13   | sema error                         |

The C output produced internally (if any) is discarded; `check` is a
linter, not a compile step.

### `etl compile FILE.etl -o OUT`

Compiles `FILE.etl` to a native binary at `OUT` using the durable
c0 → C → cc path:

1. `python3 -m compiler0 compile FILE.etl -o OUT.c` emits C.
2. `cc -std=c11 -Wall -Werror OUT.c runtime/etl_runtime.c -I runtime -o OUT`
   produces the binary, linked against the ETL runtime.

The `.c` file is left next to `OUT` for inspection. Override the C
compiler with `ETL_CC=...`.

### `etl run FILE.etl [ARGS...]`

Compiles `FILE.etl` to a temporary binary, executes it with `ARGS`, and
forwards the inner program's exit code. The temporary directory is
cleaned up before the wrapper exits.

## Environment

| variable        | default                  | meaning                                          |
| --------------- | ------------------------ | ------------------------------------------------ |
| `ETL_CC`        | `cc`                     | C compiler used by `compile` and `run`.          |
| `ETL_BUILD_DIR` | `<repo>/build/etl_cli`   | Cache directory for the c1 check binary.        |

## Examples

`examples/cli/hello.etl` returns 42 from `main`. The
`examples-cli` Makefile target invokes `scripts/examples_cli_smoke.sh`,
which exercises `etl check` and `etl run` against this fixture.

```sh
make examples-cli
```

## Notes and limits

- `compile` and `run` go through compiler-0 today, not the in-progress
  compiler-1, because c0 is the durable AOT path. `check` uses the c1
  pipeline so the CLI also exercises the self-hosted frontend.
- Diagnostics are exit-code based. File/line/column reporting will land
  with future c1 diagnostic plumbing.
- The compile path uses `/dev/stdin` semantics nowhere; arguments are
  ordinary file paths.
- The CLI does not provide a REPL, package manager, or build cache
  beyond the c1 check binary cache.

See `docs/language-goal-roadmap.md` Level 2 ("Practical AOT CLI
Language") for where this fits in the readiness ladder.
