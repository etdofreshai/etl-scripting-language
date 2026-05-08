#!/usr/bin/env node
// calculator_runner.js — Node.js WebAssembly runner for ETL calculator.wasm.
//
// This serves as the "browser-equivalent JS runtime" harness for VAL-DIST-004.
// It loads calculator.wasm via the standard WebAssembly API (same API available
// in browsers), instantiates with WASI stubs, calls _start(), and asserts the
// value passed to proc_exit() equals 42 (6 * 7).
//
// ETL WASM ABI: _start calls main() then calls proc_exit(return_value).
// The exit code is the value passed to proc_exit, not the return of _start.
//
// Run: node calculator_runner.js <path/to/calculator.wasm>
// Exit: 0 on PASS, 1 on FAIL or error.

'use strict';

const fs = require('fs');
const path = require('path');

const wasmPath = process.argv[2] || path.join(__dirname, 'calculator.wasm');

if (!fs.existsSync(wasmPath)) {
  console.error(`calculator_runner: ERROR — WASM file not found: ${wasmPath}`);
  process.exit(1);
}

const bytes = fs.readFileSync(wasmPath);
const expected = 42;
let exitCode = null;

WebAssembly.instantiate(bytes, {
  wasi_snapshot_preview1: {
    // Capture the value passed to proc_exit (that is the ETL main() return value).
    proc_exit: (code) => { exitCode = code; },
    fd_write: (_fd, _iovs, _iovsLen, _nwritten) => 0,
  }
}).then(({ instance }) => {
  if (typeof instance.exports._start === 'function') {
    try { instance.exports._start(); } catch (_) { /* proc_exit throws in some runtimes */ }
  } else if (typeof instance.exports.main === 'function') {
    exitCode = instance.exports.main();
  } else {
    console.error('calculator_runner: ERROR — no _start or main export');
    process.exit(1);
  }

  if (exitCode === expected) {
    console.log(`calculator_runner: PASS — proc_exit received ${exitCode} (expected ${expected})`);
    process.exitCode = 0;
  } else {
    console.error(`calculator_runner: FAIL — proc_exit received ${exitCode} (expected ${expected})`);
    process.exitCode = 1;
  }
}).catch((err) => {
  console.error(`calculator_runner: ERROR — ${err.message}`);
  process.exit(1);
});
