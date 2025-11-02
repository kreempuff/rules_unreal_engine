# Phase 1.3 Remaining Work Plan

**Status:** In Progress
**Last Updated:** 2025-11-01

## Completed ✅

**Compiler Flags:**
- ✅ Extract flags from ClangToolChain.cs
- ✅ Document in `docs/UE_COMPILER_FLAGS.md`
- ✅ Add UE default compiler flags (-std=c++20, -fno-exceptions, -fno-rtti, -Wall)
- ✅ Add UE build configuration defines (UE_BUILD_*, WITH_*, IS_*)
- ✅ Add platform defines (UBT_COMPILED_PLATFORM, PLATFORM_MAC, etc.)
- ✅ Add module API macros (CORE_API, ENGINE_API, auto-generated)
- ✅ Test flags with compile-time validation (TestUEFlags.cpp)

**Build Core Module:**
- ✅ Create BUILD.bazel for Core module
- ✅ Fix include path issues (added Private/ and Internal/ to includes)
- ✅ Fix missing preprocessor defines (all UE_BUILD_*, WITH_*, platform defines)
- ✅ Try building Core module (compiles, but needs dependencies)
- ✅ **Resolve Core/TraceLog circular dependency** (split Core into Core_headers + Core)
- ✅ **TraceLog compiles successfully!**

## To Do 🔲

### Build Core Module (Continued)

**Immediate:**
- ✅ Add LZ4 third-party dependency to TraceLog
  - LZ4 is vendored in TraceLog/Private/Trace/LZ4/ (not external)
  - Fixed: Added Private/**/*.inl to hdrs glob
  - Fixed: Implemented private_includes parameter
  - Result: TraceLog compiles 9/21 files (blocked on Objective-C++ for Mac)

**Core Dependencies:**
- ✅ Write BUILD.bazel for GuidelinesSupportLibrary (header-only, builds successfully!)
- ✅ Write BUILD.bazel for BuildSettings (builds, but needs version defines)
- 🔲 Write BUILD.bazel for AutoRTFM
- 🔲 Write BUILD.bazel for BLAKE3
- 🔲 Write BUILD.bazel for OodleDataCompression
- 🔲 Write BUILD.bazel for xxhash
- 🔲 Platform-specific: mimalloc, IntelTBB, jemalloc, PLCrashReporter

**Core Compilation:**
- 🔲 Add all Core dependencies to Core BUILD.bazel
- 🔲 Try building Core with all dependencies
- 🔲 Fix any remaining compilation errors
- 🔲 Expected blocker: UHT-generated code (*.generated.h)

### UnrealHeaderTool (UHT) Integration

- 🔲 Build UHT as Bazel target
  - UHT is in Engine/Source/Programs/UnrealHeaderTool
  - Has its own dependencies
  - Needs Core, CoreUObject to be built first (chicken-egg!)

- 🔲 Study UHT command-line API
  - How to invoke UHT
  - What files it needs (manifests, headers)
  - What it generates (.generated.h, .generated.cpp)

- 🔲 Create genrule for code generation
  - Run UHT before C++ compilation
  - Generate reflection code
  - Make generated files available to module compilation

- 🔲 Integrate UHT into `ue_module` build flow
  - Detect modules with UCLASS/UPROPERTY
  - Auto-run UHT genrule
  - Include generated code in srcs

- 🔲 Build CoreUObject (heavily uses UHT reflection)
  - First module to fully test UHT integration
  - Has many UCLASS/UPROPERTY macros

### Validation

- 🔲 Compare Bazel vs UBT output (symbols, binary format)
  - Build Core with UBT
  - Build Core with Bazel
  - Compare with nm -g (symbol exports)
  - Verify compatibility

## Current Branch

Working on main - all Phase 1.3 work merged!

Next work will likely be:
- Branch: `feat/phase1.3-lz4-and-core-deps`
- Focus: Build all Core dependencies
- Goal: Core module fully compiles

## References

- Phase 1.3 Compiler Flags: `docs/UE_COMPILER_FLAGS.md`
- UE Modules: `ue_modules/Runtime/Core/BUILD.bazel`
- Test Infrastructure: `.test_ue/README.md`
- Quick Commands: `justfile`

---

**Progress:** Phase 1.3 is ~60% complete (compiler integration done, Core dependencies in progress)
