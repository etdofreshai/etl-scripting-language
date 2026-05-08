ETL_RUNTIME = runtime/etl_runtime.c runtime/etl_string.c runtime/etl_dynarr.c runtime/etl_etlval.c

ETL_VM_ETL_RUNTIME = runtime/etl_runtime.c runtime/etl_string.c runtime/etl_dynarr.c runtime/etl_etlval.c runtime/vm_bridge.c

# Build the ETL-implemented VM binary from compiler1/vm.etl via compiler0.
# This is the parallel ETL implementation of the bytecode interpreter.
bin/etl-vm-etl: compiler1/vm.etl $(ETL_VM_ETL_RUNTIME)
	python3 -m compiler0 compile compiler1/vm.etl -o build/vm_etl.c
	cc -std=c11 -Wall -Wextra -Werror build/vm_etl.c $(ETL_VM_ETL_RUNTIME) -I runtime -o bin/etl-vm-etl

etl-vm-etl: bin/etl-vm-etl

.PHONY: test smoke runtime-test check c1-pipeline selfhost-equiv selfhost selfhost-selfcompile selfhost-bootstrap equiv backend-plan backend-plan-smoke backend-subset backend-asm backend-wasm backend-vm selfhost-asm headless-selfeval selfeval-trace graphics-software graphics-headless sdl3-visual selfeval-all headless-ready autopilot-help examples-cli visual examples release-check release-check-x86_64 release-tarball-x86_64 release-check-aarch64 release-tarball-aarch64 release-tarball-macos release-check-macos release-check-wasm etl-vm-etl vm-equivalence triple-equivalence backend-vm-triple

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
	scripts/c1_source_to_c_bool_param_smoke.sh
	scripts/c1_source_to_c_byte_string_smoke.sh
	scripts/c1_source_to_c_byte_string_multi_buffer_smoke.sh
	scripts/c1_source_to_c_byte_string_var_index_smoke.sh
	scripts/c1_source_to_c_byte_string_extern_smoke.sh
	scripts/c1_source_to_c_struct_field_smoke.sh
	scripts/c1_source_to_c_struct_array_smoke.sh
	scripts/c1_source_to_c_struct_param_smoke.sh
	scripts/c1_source_to_c_scalar_param_smoke.sh
	scripts/c1_extern_call_smoke.sh
	scripts/c1_extern_scalar_param_smoke.sh
	scripts/c1_emit_bytecode_smoke.sh

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

# c1 self-compile probe. Allowed to fail loudly today: not wired into
# `make check` or `make selfhost`. Records the next blocker into
# build/fixedpoint/selfcompile-status.md when it fails.
selfhost-selfcompile:
	scripts/c1_selfcompile_smoke.sh

# c1 bootstrap chain probe (c0 -> c1 -> c2 -> c3 -> c4). Verifies that
# three consecutive self-compilations emit byte-identical C, which is
# the fixed-point criterion. Depends on selfhost-selfcompile being
# green; otherwise records BLOCKED-AT-SELFCOMPILE in
# build/fixedpoint/bootstrap-status.md and fails loudly. Not wired into
# `make check` or `make selfhost`.
selfhost-bootstrap:
	scripts/c1_bootstrap_smoke.sh

backend-plan-smoke:
	scripts/backend_plan_smoke.sh

backend-asm:
	scripts/c1_emit_asm_smoke.sh
	scripts/c1_asm_function_call_smoke.sh
	scripts/c1_asm_extern_call_smoke.sh
	scripts/c1_asm_extern_scalar_param_smoke.sh
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
	scripts/c1_wat_extern_import_smoke.sh
	scripts/c1_wat_extern_call_smoke.sh
	scripts/c1_wat_array_smoke.sh
	scripts/c1_wat_struct_field_smoke.sh
	scripts/c1_wat_struct_array_smoke.sh

backend-vm:
	scripts/c1_emit_bytecode_smoke.sh
	scripts/c1_vm_return_smoke.sh
	scripts/c1_vm_expr_smoke.sh
	scripts/c1_vm_control_flow_smoke.sh
	scripts/c1_vm_function_smoke.sh
	scripts/c1_vm_heap_alloc_smoke.sh
	scripts/c1_vm_string_smoke.sh
	scripts/c1_runtime_compile_smoke.sh
	scripts/c1_dynarr_equiv_smoke.sh
	scripts/c1_tagged_union_equiv_smoke.sh
	scripts/c1_etl_vm_smoke.sh

backend-vm-triple: backend-vm
	make triple-equivalence backend-vm-triple


vm-equivalence: bin/etl-vm-etl
	scripts/vm_equivalence_smoke.sh

triple-equivalence: bin/etl-vm-etl
	scripts/triple_equiv_smoke.sh

headless-selfeval:
	scripts/selfeval_smoke.sh

selfeval-trace:
	scripts/selfeval_trace_smoke.sh

graphics-software:
	scripts/software_graphics_smoke.sh

graphics-headless:
	scripts/sdl3_headless_smoke.sh


sdl3-visual:
	scripts/sdl3_visual_smoke.sh

selfeval-all:
	scripts/selfeval_all.sh

headless-ready: check selfhost backend-plan backend-subset backend-wasm selfeval-all

autopilot-help:
	@scripts/project_autopilot_supervisor.py --help

examples-cli:
	scripts/examples_cli_smoke.sh
	scripts/cli_calculator_smoke.sh
	scripts/cli_file_transform_smoke.sh
	scripts/cli_config_rules_smoke.sh

# Aggregate examples gate. Runs CLI examples, visual examples, and the
# runtime-compile (VM) example end-to-end. Visual gracefully skips the
# SDL3 branch when SDL3 is not installed.
examples: examples-cli visual
	scripts/c1_runtime_compile_smoke.sh

# Build the Linux x86_64 release tarball.
# Stages into build/release/etl-linux-x86_64/ and tarballs to
# build/release/etl-linux-x86_64.tar.gz.
# Reproducible: --sort=name --owner=0 --group=0 --mtime.
release-tarball-x86_64: bin/etl-vm-etl
	scripts/build_release_tarball_x86_64.sh

# Smoke-test the release tarball: untar to temp dir, compile+run a
# hello-world ETL program, verify exit 42.
release-check-x86_64: release-tarball-x86_64
	scripts/release_smoke_x86_64.sh


# WASI + browser-equivalent WASM smoke (VAL-DIST-004).
# ETL→WAT→WASM via wasmtime (WASI) and via Node.js WebAssembly API (browser-equiv).
release-check-wasm:
	scripts/release_smoke_wasi.sh
	scripts/release_smoke_wasm_browser.sh
# Release-readiness gate. Aggregates check + selfhost + every backend
# gate + examples + visual + x86_64 release tarball smoke. Fails if any
# non-optional gate fails. The selfhost-selfcompile and selfhost-bootstrap
# probes are NOT included here because they are designed to fail loudly
# until the c1 emit_c expansion long-tail closes; their status lives in
# build/fixedpoint/{selfcompile,bootstrap}-status.md.
release-check: check selfhost backend-vm backend-subset backend-asm backend-wasm examples release-check-x86_64

# Build the Linux aarch64 release tarball via zig cc cross-compile.
release-tarball-aarch64:
	scripts/build_release_tarball_aarch64.sh

# Smoke-test the aarch64 release: cross-compile c1 corpus subset and run
# each fixture under .deps/qemu-aarch64-static, verify exit codes match.
release-check-aarch64:
	scripts/release_smoke_aarch64.sh

# Build macOS release tarballs for x86_64 and arm64 via zig cc cross-compile.
# Build-validated only: Mach-O binaries produced and confirmed via `file`.
# No execution on the Linux host; no Apple SDK required (zig bundled libc).
release-tarball-macos:
	scripts/build_release_tarball_macos.sh

# Validate macOS release tarballs: untar each, run `file` on bin/etl-vm-etl,
# assert "Mach-O" present. Does NOT execute the binary (Linux host).
release-check-macos: release-tarball-macos
	scripts/release_validate_macos.sh

visual:
	scripts/visual_smoke.sh
