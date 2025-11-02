# Phase 1.3 Remaining Work Plan

**Status:** In Progress
**Last Updated:** 2025-11-02

**See also:** [MODULE_ROADMAP.md](MODULE_ROADMAP.md) for long-term module priorities and strategic planning

## Scope

**Total UE Modules:** 835 (across Engine/Source)
**Modules Converted:** 5 (AtomicQueue, GuidelinesSupportLibrary, TraceLog, BuildSettings, Core)
**Progress:** 0.6%

**For Core Module to Build on Mac:**
- Need: ~8 modules (core dependencies on Mac platform)
- Have: 4/8 (50%!)
- Remaining: AutoRTFM, BLAKE3, OodleDataCompression, xxhash

**Realistic Scope:**
- Don't need all 835 modules
- For working Editor build: ~50-100 key modules
- Strategy: Build incrementally (Core → CoreUObject → Engine → Editor)

## Completed ✅

**Compiler Flags:**
- ✅ Extract flags from ClangToolChain.cs
- ✅ Document in `docs/UE_COMPILER_FLAGS.md`
- ✅ Add UE default compiler flags (-std=c++20, -fno-exceptions, -fno-rtti, -Wall)
- ✅ Add UE build configuration defines (UE_BUILD_*, WITH_*, IS_*)
- ✅ Add platform defines (UBT_COMPILED_PLATFORM, PLATFORM_MAC, etc.)
- ✅ Add module API macros (CORE_API, ENGINE_API, auto-generated)
- ✅ Test flags with compile-time validation (TestUEFlags.cpp)
- ✅ **C/C++ file separation** - Detects .c vs .cpp, applies appropriate flags

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
- ✅ Write BUILD.bazel for BuildSettings (uses Core_headers correctly)
- ✅ Write BUILD.bazel for BLAKE3 (C source files compile with C flags!)
- 🔲 Write BUILD.bazel for AutoRTFM
- 🔲 Write BUILD.bazel for OodleDataCompression
- 🔲 Write BUILD.bazel for xxhash
- 🔲 Platform-specific: mimalloc, IntelTBB, jemalloc, PLCrashReporter

**Progress:** 5/8 Core dependencies completed (62.5% on Mac platform)

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

**IMPORTANT:** Successful compilation ≠ working code. Multiple failure modes exist even after clean builds.

#### Known Risks

| Risk | Severity | Detection Method | Mitigation |
|------|----------|------------------|------------|
| **Missing/wrong defines** | HIGH | Symbol comparison, runtime testing | Extract from UE headers/Build.cs dynamically |
| **Linking failures** | HIGH | Link minimal executable | Resolve missing symbols, add platform libs |
| **UHT missing** | CRITICAL | CoreUObject compilation | Implement UHT integration (Phase 1.3 weeks 5-8) |
| **Precompiled ABI mismatch** | MEDIUM | Runtime crashes, weird bugs | Build from source, match Xcode versions |
| **Module init order** | MEDIUM | Startup crashes | Match UBT link order exactly |
| **Platform services** | MEDIUM | Missing functionality | Add frameworks, test on target platforms |

#### Validation Steps

**Phase 1.3 (Current):**
- 🔲 Symbol comparison with UBT build
  - Build Core with UBT: `UnrealBuildTool Core Mac Development`
  - Build Core with Bazel: `bazel build //Engine/Source/Runtime/Core`
  - Compare symbols: `nm -g bazel-bin/.../libCore.a > bazel-symbols.txt`
  - Verify compatibility: `diff bazel-symbols.txt ubt-symbols.txt`
  - **Expected:** Identical or very similar symbol sets

**Phase 1.4 (Link Testing):**
- 🔲 Link a minimal program
  - Create minimal `main.cpp` using Core APIs
  - Link with Bazel: `bazel build //test:minimal_program`
  - Run: `./bazel-bin/test/minimal_program`
  - **Expected:** No crashes, basic APIs work (FString, TArray, etc.)

**Phase 2 (Integration Testing):**
- 🔲 Build UnrealEditor
  - All modules compile
  - Link into UnrealEditor executable
  - Launch and test basic functionality
  - **Expected:** Editor launches, can open projects

**Phase 3 (End-to-End):**
- 🔲 Cook and run a game
  - Full BuildCookRun workflow
  - Test on Mac client + Linux server (multiplayer use case)
  - **Expected:** Game runs, networking works, identical behavior to UBT builds

#### Specific Concerns for Multiplayer (Mac Dev + Linux Server)

1. **Cross-platform determinism**
   - Physics simulation must be identical Mac ↔ Linux
   - RNG seeding must match
   - Floating-point behavior must match
   - **Test:** Record replay on Mac, play on Linux (should be identical)

2. **Networking modules untested**
   - Sockets, Networking, OnlineSubsystem not built yet
   - Server-specific modules unknown
   - **Test:** Build dedicated server, connect Mac client

3. **Linux server build untested**
   - Only building on Mac so far
   - Linux-specific code paths unverified
   - **Test:** Cross-compile or build on Linux CI

## Precompiled Dependencies (Future Work)

**Goal:** Convert all precompiled binary dependencies to Bazel-native source builds for full hermetic builds.

**Why:**
- Hermetic builds (no dependency on vendor-provided binaries)
- Cross-platform consistency
- Better caching and incremental builds
- Ability to customize and debug library code
- Eliminate binary blob security concerns

### Known Precompiled Modules

| Module | Type | Current Status | Priority | Notes |
|--------|------|----------------|----------|-------|
| **OodleDataCompression** | Compression | Precompiled .a/.lib | High | RAD Game Tools library, version 2.9.13. Essential for Core. |
| **BLAKE3** | Hashing | Partial (SIMD issues) | Medium | C implementation compiles, SIMD intrinsics blocked on Mac ARM |
| **mimalloc** | Allocator | Unknown | Low | Platform-specific, may be precompiled |
| **IntelTBB** | Threading | Unknown | Low | Platform-specific, likely precompiled |
| **jemalloc** | Allocator | Unknown | Low | Platform-specific, may be precompiled |
| **PLCrashReporter** | Crash Reporting | Unknown | Low | Mac-specific, likely precompiled |

**Action Items:**
- 🔲 Survey all Core dependencies to identify precompiled modules
- 🔲 Research source availability for each module
- 🔲 Create Bazel build rules for open-source libraries (BLAKE3, TBB, jemalloc)
- 🔲 Evaluate licensing for proprietary libraries (Oodle)
- 🔲 Phase 2+: Systematically replace precompiled deps with source builds

### Build-from-Source Modules (Reference)

These modules successfully build from source with Bazel:
- ✅ AtomicQueue (header-only)
- ✅ GuidelinesSupportLibrary (header-only)
- ✅ xxhash (header-only in UE)
- ✅ BuildSettings (UE source)
- ✅ AutoRTFM (UE source)
- ✅ TraceLog (UE source, partial - Objective-C++ blocker)
- 🟡 Core (UE source, in progress)

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
