ETL_RUNTIME = runtime/etl_runtime.c

.PHONY: test smoke runtime-test check selfhost autopilot-help

test:
	python3 -m unittest discover -s tests

smoke:
	scripts/bootstrap_smoke.sh
	scripts/stdout_smoke.sh
	scripts/stdin_smoke.sh
	scripts/expression_smoke.sh
	scripts/multiplication_smoke.sh
	scripts/error_smoke.sh
	scripts/logical_smoke.sh
	scripts/if_smoke.sh
	scripts/while_smoke.sh
	scripts/fib_smoke.sh
	scripts/array_smoke.sh
	scripts/struct_smoke.sh
	scripts/string_smoke.sh
	scripts/sizeof_smoke.sh
	scripts/extern_smoke.sh
	scripts/corpus_smoke.sh
	scripts/runtime_smoke.sh
	scripts/file_smoke.sh
	scripts/c1_lex_smoke.sh

runtime-test:
	$(CC) -std=c11 -Wall -Wextra -Werror -o runtime/test_runtime runtime/test_runtime.c $(ETL_RUNTIME)
	./runtime/test_runtime

check: test smoke runtime-test

selfhost:
	scripts/c1_smoke.sh

autopilot-help:
	@scripts/project_autopilot_supervisor.py --help
