ETL_RUNTIME = runtime/etl_runtime.c

.PHONY: test smoke runtime-test check c1-pipeline selfhost-equiv selfhost equiv backend-plan backend-plan-smoke backend-subset backend-asm backend-wasm selfhost-asm headless-selfeval selfeval-trace graphics-software graphics-headless selfeval-all headless-ready autopilot-help

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
	scripts/full_word_alias_smoke.sh
	scripts/c1_lex_smoke.sh
	scripts/c1_parse_smoke.sh
	scripts/c1_sema_smoke.sh
	scripts/c1_emit_c_smoke.sh
	scripts/c1_emit_control_flow_smoke.sh
	scripts/c1_source_to_c_smoke.sh
	scripts/c1_source_to_c_array_smoke.sh
	scripts/c1_source_to_c_array_var_index_smoke.sh
	scripts/c1_source_to_c_byte_array_assign_smoke.sh
	scripts/c1_source_to_c_byte_array_param_smoke.sh
	scripts/c1_source_to_c_byte_string_smoke.sh
	scripts/c1_source_to_c_byte_string_var_index_smoke.sh
	scripts/c1_source_to_c_byte_string_extern_smoke.sh
	scripts/c1_source_to_c_struct_field_smoke.sh
	scripts/c1_source_to_c_struct_array_smoke.sh
	scripts/c1_extern_call_smoke.sh

runtime-test:
	$(CC) -std=c11 -Wall -Wextra -Werror -o runtime/test_runtime runtime/test_runtime.c $(ETL_RUNTIME)
	./runtime/test_runtime

check: test smoke runtime-test

c1-pipeline:
	scripts/c1_pipeline_smoke.sh

selfhost-equiv:
	scripts/c1_equiv_smoke.sh

equiv: selfhost-equiv

selfhost: c1-pipeline selfhost-equiv
	scripts/c1_smoke.sh

backend-plan-smoke:
	scripts/backend_plan_smoke.sh

backend-asm:
	scripts/c1_emit_asm_smoke.sh
	scripts/c1_asm_function_call_smoke.sh
	scripts/c1_asm_array_smoke.sh
	scripts/c1_asm_struct_field_smoke.sh
	scripts/c1_asm_struct_array_smoke.sh

selfhost-asm: backend-asm

backend-plan: backend-plan-smoke backend-asm

backend-subset:
	scripts/backend_subset_smoke.sh

backend-wasm:
	scripts/c1_wat_return_smoke.sh
	scripts/c1_wat_function_call_smoke.sh
	scripts/c1_wat_array_smoke.sh
	scripts/c1_wat_struct_field_smoke.sh
	scripts/c1_wat_struct_array_smoke.sh

headless-selfeval:
	scripts/selfeval_smoke.sh

selfeval-trace:
	scripts/selfeval_trace_smoke.sh

graphics-software:
	scripts/software_graphics_smoke.sh

graphics-headless:
	scripts/sdl3_headless_smoke.sh

selfeval-all:
	scripts/selfeval_all.sh

headless-ready: check selfhost backend-plan backend-subset backend-wasm selfeval-all

autopilot-help:
	@scripts/project_autopilot_supervisor.py --help
