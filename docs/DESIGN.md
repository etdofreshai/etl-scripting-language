# ETL Feature and Design Summary

This document captures the broader design philosophy and open questions
for ETL beyond the immediate phased roadmap in `docs/ROADMAP.md`. It is
the long-term identity statement; the roadmap is the short-term
sequencing.

## 1. Project Vision

ETL is intended to become a minimal, readable, self-hosting scripting
language for building applications, games, tools, and platform-compatible
runtimes.

The core idea is to make a language that is:

- Small enough to bootstrap and understand completely.
- Readable enough for humans and LLMs to write, debug, and repair.
- Portable enough to target desktop, web, mobile, and eventually consoles.
- Powerful enough to build real applications and arcade-style games.
- Self-hosting, meaning the long-term ETL compiler is written in ETL
  itself.

The language should start with a tiny compiler-0 bootstrap implementation,
then grow only as needed until ETL can compile its own compiler. After
that, language improvements happen by modifying the ETL-authored compiler.

## 2. Development Workflow

The project is being developed with an overseer/subagent model.

The coordinator/supervisor role is responsible for:

- Maintaining the roadmap.
- Deciding the next small task.
- Delegating implementation work to AI subagents.
- Reviewing results.
- Ensuring tests pass.
- Ensuring each successful step is committed and pushed.
- Keeping scope under control.

Implementation work should generally be delegated rather than done
directly by the coordinator.

Preferred provider cadence:

```
codex → codex → glm → codex → codex → glm → codex → codex → claude
```

The goal is not speed. Sequential work is acceptable. The priority is
steady progress, clean commits, and strong verification.

## 3. Bootstrap Strategy

ETL starts with compiler-0, currently written in Python.

Compiler-0 is the bootstrap compiler. Its purpose is to compile the
minimal ETL subset needed to write compiler-1.

The long-term goal is:

- compiler-0 builds compiler-1
- compiler-1 builds compiler-2
- compiler-2 matches compiler-1 behavior
- compiler-0 freezes as historical bootstrap/reference

Once the self-hosted compiler reaches fixed point, future language
development should happen in ETL itself.

## 4. Backend Strategy

The original plan used C as the first backend because C offers broad
portability and lets ETL avoid writing architecture-specific assembly
immediately.

However, the newer architectural direction is to treat WASM or a
WASM-like intermediate representation as the central low-level target,
because it provides a compact, portable, stack-based instruction model.

A practical backend ladder:

```
ETL source
  → tokens / AST
  → ETL IR
  → compact bytecode / WASM-like representation
  → C backend for portability/bootstrap
  → WASM backend for web/runtime portability
  → native ASM backend later
```

The important design goal is not necessarily "C first forever," but to
define a minimal IR that can map cleanly to C, WASM, and assembly.

## 5. Why C Was Considered

C is useful because:

- C compilers exist almost everywhere.
- C can target many CPU architectures and operating systems.
- It avoids writing register allocators and platform-specific calling
  conventions at the start.
- It lets the project validate language semantics before building direct
  native backends.
- It can act as a portable backend while ETL matures.

C should be treated as a practical bridge, not the final identity of the
language.

## 6. Why WASM Is Attractive

WASM feels like a strong target because:

- It is compact.
- It is portable.
- It has a relatively small instruction set.
- It uses a stack-machine model.
- Each instruction can be encoded compactly, often as a byte opcode plus
  operands.
- WASM runtimes can compile to native machine code.
- It can run in browsers and non-browser runtimes.
- It provides a useful model for a compact ETL bytecode format.

The project may eventually use a WASM-like intermediate bytecode as a
common language between ETL source and final targets.

## 7. Assembly Concepts ETL Should Respect

Even if ETL does not emit assembly immediately, it should be designed
with assembly concepts in mind.

Core concepts across assembly targets:

- Registers: small, fast storage locations inside the CPU.
- Memory: general RAM used for program data, globals, heap data, and
  code.
- Stack: a structured region of memory used for function calls, return
  addresses, local temporary values, and saved registers.
- Load/store: moving values between memory and registers.
- Arithmetic and logic: add, subtract, compare, bit operations, etc.
- Branching: conditional and unconditional jumps.
- Function calls: calling conventions, arguments, return values, and
  return addresses.
- Pointers/addresses: references to memory locations.

ETL should expose high-level readability while compiling down to these
simple concepts.

## 8. Stack vs Memory

The stack is not a different kind of hardware memory. It is a disciplined
region of RAM.

The stack is best for:

- Function call bookkeeping.
- Return addresses.
- Small local variables.
- Temporary values.
- Data that naturally disappears when a function returns.

General memory / heap / static memory is better for:

- Large data structures.
- Objects that outlive a single function call.
- Shared resources.
- Dynamic allocations.
- Long-lived application state.

ETL should keep the stack reasonably light and use explicit allocation or
runtime-managed storage for larger or longer-lived data.

## 9. Language Style

ETL should be English-driven and word-oriented.

The language should avoid excessive symbols where possible and prefer
readable words.

Possible direction:

- Prefer `function` over `fn`, if readability wins.
- Prefer `integer` over `int`, if verbosity is acceptable.
- Prefer end-terminated blocks.
- Prefer explicit types.
- Prefer readable control flow.
- Avoid dense symbolic syntax when word-based syntax is clear.

The current bootstrap syntax may stay shorter for practicality, but the
long-term language identity can be more natural-language-like.

## 10. Character Set and Source Compression

One idea is to constrain the source language to a small character set,
such as:

```
26 letters + 10 digits + space + underscore + dash + newline ≈ 40 chars
```

A normal UTF-8 text file using plain ASCII characters costs about 1 byte
per character.

A custom 40-character encoding can represent each character in 6 bits,
because 6 bits can encode 64 possible values.

Example:

- 100 ASCII/UTF-8 characters ≈ 100 bytes
- 100 custom 40-symbol characters = 600 bits = 75 bytes

This saves about 25% at the character encoding level.

However, the bigger compression win comes after parsing/tokenization.
Once source is tokenized, keywords, identifiers, scopes, and instructions
can be encoded as compact symbols or bytecode rather than spelled-out
words.

Pipeline idea:

```
Readable ETL source
  → token stream
  → compact token format
  → IR / bytecode
  → interpreter or compiled backend
```

## 11. Minimal IR / Bytecode Direction

The most important internal representation should be a small, stable IR.

This IR should represent:

- Constants.
- Arithmetic.
- Comparisons.
- Memory load/store.
- Function calls.
- Branches.
- Loops.
- Stack/value operations.
- Imports/extern calls.
- Return values.

The IR should be small enough to map to:

- C.
- WASM.
- Native assembly.
- A custom ETL bytecode interpreter.

The IR is the true "common language" of ETL.

## 12. Tokenized / Binary Format

ETL can have both:

- Human-readable source.
- Compact tokenized or bytecode form.

The tokenized form could be used for:

- Faster loading.
- Smaller distribution files.
- Script execution by an interpreter.
- Intermediate compiler artifacts.
- Cross-platform portable modules.

The bytecode could be stack-based, inspired by WASM, because stack-based
bytecode is easy to encode and maps cleanly to many targets.

## 13. Platform Compatibility Goal

ETL should aim for maximum platform compatibility.

Target categories:

- Desktop: Windows, macOS, Linux.
- Web: WASM/browser.
- Mobile: iOS and Android.
- Consoles: PlayStation, Xbox, Switch, or future console-like devices.
- Headless CI/testing environments.

The key strategy is to keep ETL platform-agnostic and push platform
differences behind runtime libraries and bindings.

## 14. SDL3 Runtime Strategy

SDL3 was chosen as the main platform/runtime abstraction for graphics,
audio, input, and gamepad support.

ETL should not expose all of SDL3 directly.

Instead, it should expose a clean ETL runtime API that maps onto SDL3
where available.

SDL3-backed capabilities may include:

- Window creation.
- Renderer creation.
- Frame lifecycle.
- Keyboard input.
- Mouse input.
- Touch input.
- Gamepad input.
- Audio streams.
- Simple drawing.
- Texture upload.
- Framebuffer readback for screenshots.

The ETL-facing API should remain stable even if the backend
implementation changes.

## 15. FFI and Platform Bindings

ETL needs a foreign function interface (FFI) or import system.

The FFI allows ETL to call functions implemented outside ETL.

Examples:

- SDL3 functions on desktop.
- JavaScript host functions in WASM/browser.
- iOS native APIs.
- Android native APIs.
- Console-specific APIs.
- Custom C runtime functions.

The ideal pattern:

```
ETL app code
  calls ETL standard library
    calls ETL platform abstraction
      calls FFI/import binding
        calls SDL3 / platform API / host runtime
```

ETL code should prefer the standard library and platform abstraction
rather than direct low-level API calls.

## 16. Platform Capability Model

Some features may not exist on every platform.

Examples: GPS, haptics, gyroscope, touch, gamepad rumble, microphone,
camera, filesystem, network.

ETL should support a capability model. A capability can be:

- Supported.
- Unsupported.
- Mocked.
- Partially supported.
- Permission denied.
- Runtime unavailable.

Instead of crashing, unsupported features should fail gracefully.

Example behavior:

```
get gps location
```

If GPS is unavailable:

- Return mock/default coordinates if configured.
- Emit a warning that the result is mocked.
- Allow the application to query whether GPS is real or simulated.

This keeps ETL apps portable while still making platform differences
visible.

## 17. ETL Libraries

The goal is to write as much as possible in ETL itself.

Low-level host bindings may be implemented in C, WASM imports,
JavaScript, Objective-C/Swift, Java/Kotlin, or console-native APIs. But
the higher-level library logic should be ETL.

Example layering:

```
low-level platform binding
  → ETL platform module
  → ETL graphics module
  → ETL UI/game/app libraries
  → user application
```

This keeps ETL as the primary development language.

## 18. Modularity

ETL should support modules so code can be organized and reused.

A module should be able to define: functions, types, constants, imports,
exports, platform-specific bindings, tests.

Possible concepts:

```
module graphics
module input
module audio
module platform
module application
module game
```

The module system should be simple at first and avoid package-management
complexity until the language is self-hosted.

## 19. Types and Static Checking

Types are important because they allow compile-time checking.

Static checks can catch errors before runtime, such as:

- Passing the wrong type to a function.
- Returning the wrong type.
- Calling missing functions.
- Accessing missing fields.
- Using unsupported platform features incorrectly.
- Mixing incompatible modules.

Release builds do not need runtime type-check metadata if all type
checking is done at compile time.

## 20. Data Types

Early primitive types:

- Boolean.
- Integer types.
- Byte / character.
- Pointer or handle types for FFI.
- Void / no return.

Later or optional primitive types:

- Floating point.
- Larger integer widths.
- Platform-sized integer.

Compound types:

- Structs.
- Fixed-size arrays.
- Dynamic arrays or buffers.
- Strings.
- Optional/result types.
- Handles/resources.

Structs should arrive before the self-hosted compiler becomes large,
because writing a compiler with parallel arrays would be painful and
hard to maintain.

## 21. Object-Oriented-Like Design Without Heavy OOP

ETL does not need full C#-style object orientation at the beginning.

Instead, ETL can use:

- Structs for data.
- Functions for behavior.
- Modules for organization.
- Naming conventions for grouping.
- Interfaces/contracts later if needed.
- Composition over inheritance.

Example conceptual style:

```
module sprite
  type sprite
  function create sprite
  function update sprite
  function draw sprite
end
```

This gives "Lego blocks" without requiring classes, inheritance, virtual
dispatch, or complex object lifetimes in v0.

## 22. Extensibility Model

ETL should be extensible through libraries and modules. The core
language should stay small.

Library areas: graphics, audio, input, UI, physics, file, network,
testing, async.

The language should only add new syntax when a library solution is too
awkward or impossible.

## 23. Function Calls, Inlining, and Code Size

Trade-off:

- Inlining can improve speed but increases code size.
- Function calls keep code smaller but add call overhead.

The compiler can choose based on function size, call frequency, build
mode, optimization settings, and backend target.

Release builds may inline more aggressively. Debug builds should
preserve function boundaries.

## 24. Async Model

ETL should eventually support asynchronous code.

The preferred model is one consistent async/await-style system. Avoid
having multiple competing async patterns (callbacks, coroutines,
promises, futures, event handlers, threads all at once).

Choose one primary concept: `future` / `task` + `await`.

Useful helpers: `await all`, `await any`, `sleep`, wait for file/network/
input/animation.

The goal is readable code that looks mostly sequential while still
allowing asynchronous behavior.

## 25. Async Without Heavy Garbage Collection

ETL should avoid making async garbage-collection-heavy.

Possible strategies:

- Explicit task objects.
- Fixed-size task pools.
- Manual allocation for tasks.
- Reference-counted task/state objects.
- Stackless coroutine state machines generated by the compiler.
- Debug-mode leak checks.
- Release-mode stripped metadata.

ETL should prefer predictable allocation over hidden allocation.

## 26. Memory Management

Potential memory models: manual, reference counting, region/arena, GC,
hybrid.

The current direction leans toward reference counting or explicit
ownership rather than a full garbage collector.

Reference counting provides:

- More safety than raw manual memory.
- More predictability than full GC.
- Immediate cleanup when count reaches zero.
- Easier integration with resources like textures, audio, files, and
  platform handles.

## 27. Destroy / Release Semantics

Possible design:

- `release` decrements the reference count.
- Object is destroyed when count reaches zero.
- `destroy` may only work on uniquely owned resources.
- Forced destroy should be rare and possibly debug-checked.
- Debug builds can detect use-after-release or double-release.

Resource handles should be designed to fail safely when invalid or
unavailable.

## 28. Error Handling and Exceptions

A minimal, predictable approach is to start with result-style errors:

```
result value error
```

This keeps failures explicit and avoids hidden control flow. Later, ETL
could add exception-like syntax if needed, but simple error values may
fit better with the minimal language goal.

The language should distinguish: recoverable errors, warnings, panics,
platform-capability-unavailable, permission-denied, resource-not-found.

## 29. Debug and Release Builds

ETL should support at least two build modes: `debug` and `release`.

Debug builds include type/debug metadata, source maps, breakpoint hooks,
logging, profiling counters, runtime checks, use-after-release checks,
bounds checks if available, better diagnostics.

Release builds strip or reduce debug metadata, breakpoint hooks, verbose
logging, runtime type metadata, expensive checks. Release builds
optimize for speed, smaller output, less memory overhead.

## 30. Debugging Features

ETL should eventually support: breakpoints, inspecting locals, stack
frames, module state, pausing, stepping, viewing async task state,
viewing memory/resource handles, logs tied to source locations.

Initial implementation can be lightweight: insert debug hooks during
debug builds, emit source line mappings, provide a runtime debug
callback, allow tools to pause at tagged locations.

## 31. Profiling Features

Useful profiling data: function call counts, time per function, frame
time, allocation counts, peak memory, task counts, resource usage, draw
call counts, audio buffer underruns, input latency.

Release builds should remove or minimize profiling instrumentation
unless explicitly requested.

## 32. Testing

Categories: unit tests, compiler golden tests, runtime tests, visual
screenshot tests, log assertion tests, platform capability tests,
example application tests.

The project's validation loop:

```
make check
make selfhost
make visual
make examples
```

## 33. Headless Graphical Testing

The runtime should support: software rendering mode, deterministic frame
count, fake clock, scripted input, seeded random numbers, screenshot
capture, PNG output, visual comparison, log capture.

Recommended path:

```
SDL3 software renderer
  → SDL_RenderReadPixels
  → PNG output
  → golden image comparison
```

## 34. Example Application Ladder

Suggested order: calculator → Conway's Life → breakout → snake →
asteroids → pong → simple CLI apps → file tools → text/markdown viewer
→ more advanced games/apps later.

Each example should include source code, build command, headless run
command, scripted inputs, screenshot goldens, log assertions.

## 35. Standard Library Areas

Potential modules: core types, math, strings, buffers, arrays, files,
logging, errors/results, time, random numbers, async/tasks, platform
capabilities, graphics, audio, input, testing.

The standard library should be written in ETL where possible, with thin
platform bindings underneath.

## 36. Source, Token, and Runtime Layers

```
Readable ETL source
  ↓
Lexer / tokenizer
  ↓
Parser / AST
  ↓
Static checks / type checks
  ↓
Minimal IR
  ↓
Compact bytecode or WASM-like form
  ↓
Backend target:
    - C
    - WASM
    - native assembly
    - interpreter
  ↓
Runtime / platform bindings
```

Each layer should remain understandable and testable.

## 37. Minimalism Rules

The language should avoid adding features just because they are familiar
from C#, TypeScript, Unity, or modern languages.

Features should be added when they directly support: self-hosting,
runtime/platform compatibility, clear application/game examples,
debugging/profiling, LLM readability and repair.

Deferred until later: full OOP inheritance, generics, traits/interfaces,
pattern matching, exceptions (if results suffice), closures, GC,
complex package management, hot reload, native ASM backend,
mobile-specific APIs beyond capability wrappers.

## 38. Key Open Design Questions

- Should long-form keywords replace short bootstrap keywords?
- Should WASM become the primary backend before C is fully mature?
- What exact IR format should ETL use?
- Should the compact binary format be custom or WASM-compatible?
- How should modules/imports look syntactically?
- What is the minimal ownership/reference-counting model?
- Should ETL have exceptions, result values, or both?
- How much async should be compiler-supported vs library-supported?
- What debug metadata format should be emitted?
- What is the smallest SDL/platform abstraction that still maps well to
  consoles, mobile, desktop, and web?

## 39. Current Best Direction

1. Finish the bootstrap syntax cleanup.
2. Complete the minimal compiler-0 feature set.
3. Define a tiny, stable IR.
4. Keep the C backend as a practical bridge.
5. Treat WASM / WASM-like bytecode as the long-term portable instruction
   model.
6. Build self-hosting as the main milestone.
7. Add platform/runtime libraries through FFI/imports.
8. Wrap SDL3 behind a clean ETL standard library.
9. Add debug/release build modes.
10. Add headless visual testing.
11. Build real example apps and games.

## 40. One-Sentence Summary

ETL is a minimal, English-readable, self-hosting scripting language that
compiles through a small portable IR toward C, WASM, and eventually
assembly, while using ETL-written libraries and platform bindings to
build cross-platform apps and games with strong debug, profiling, async,
and visual-test support.
