# Current Context: UHT Code Generation Debugging

**Date:** 2025-11-07 → 2026-03-14 (resumed)
**Branch:** feat/phase1.3-core-deps
**Bazel Version:** 9.0.0 (upgraded this session from unset)

## The Problem

UHT (UnrealHeaderTool) runs, parses headers successfully, but generates **0 output files**. All `.gen.cpp` and `.generated.h` files are 0-byte placeholders.

## Root Cause (Narrowed Down This Session)

The UHT log at:
```
/private/var/tmp/_bazel_kareemmarch/07d50ad05f2fa2e49021d83bce5b5524/external/+_repo_rules+unreal_engine_source/UnrealEngine/Engine/Programs/UnrealHeaderTool/Saved/Logs/UnrealHeaderTool.log
```

Shows:
```
Step - Starting exporters.
Step - Exports
       Exporter Stats skipped
       Exporter Json skipped
       Running exporter CodeGen
Total of 0 written
WriteFileIfChanged() wrote 0 changed files of 0 requested writes.
```

**Key insight:** UHT didn't even *attempt* to write files. `0 requested writes` means the CodeGen exporter decided there was nothing to generate. This is NOT a file-location mismatch — UHT genuinely produced nothing.

## The Manifest Being Generated

```json
{
  "IsGameTarget": true,
  "RootLocalPath": "/private/var/tmp/.../execroot/_main/test/verification/uht/simple_enum",
  "TargetName": "BazelTarget",
  "Modules": [{
    "Name": "TestModule",
    "ModuleType": "EngineRuntime",
    "BaseDirectory": "/private/var/tmp/.../execroot/_main/test/verification/uht/simple_enum",
    "IncludePaths": [".../simple_enum/Public", ".../simple_enum/Private"],
    "OutputDirectory": "/private/var/tmp/.../bazel-out/darwin_arm64-fastbuild/bin",
    "PublicHeaders": [".../simple_enum/Public/TestEnum.h"],
    "GeneratedCPPFilenameBase": ".../bazel-out/darwin_arm64-fastbuild/bin/TestModule.gen",
    "SaveExportedHeaders": true,
    "UHTGeneratedCodeVersion": "None"
  }]
}
```

## Suspects

1. **`"UHTGeneratedCodeVersion": "None"`** — Could this be telling UHT "don't generate code"? Need to check what values UHT expects (e.g., "V2", "VLatest").

2. **`"ModuleType": "EngineRuntime"`** — The test module is marked as a game target (`IsGameTarget: true`) but uses `EngineRuntime` module type. Possible mismatch.

3. **Manifest format** — The manifest might be missing fields that UHT needs, or field values might not match what UHT's CodeGen exporter checks before generating.

## What Was Done This Session

### Completed
- [x] Set up `.test_ue/` test repo (cloned from sibling UE)
- [x] Installed BUILD files via `just install .test_ue/UnrealEngine`
- [x] Added debug logging to copy script in `bzl/uht.bzl` (lines 168-180)
- [x] Ran build, confirmed UHT produces 0 files (not a copy issue)
- [x] Read UHT log — confirmed `0 requested writes`
- [x] Upgraded to Bazel 9.0.0 (`.bazelversion`)
- [x] Removed broken `sh_binary` from root `BUILD.bazel` (Bazel 9 compat)
- [x] Installed bazelisk via Homebrew, added to laptop-setup playbook

### Completed (2026-03-14 session)
- [x] Investigated `UHTGeneratedCodeVersion` — "None" is the normal default (falls back to V1), NOT a skip signal. Even Epic's CoreUObject manifest uses "None".
- [x] Compared manifest against real Epic manifest (found at `Engine/Intermediate/Build/Mac/ShaderCompileWorker/Development/ShaderCompileWorker.uhtmanifest`)
- [x] Checked UHT source — `EGeneratedCodeVersion` enum: None, V1, V2, VLatest(=V2). Default config is V1.
- [x] **Found root cause: `ModuleType` was `"EngineRuntime"` but should be `"GameRuntime"` for game targets.** The old code hardcoded `"Engine" + opts.ModuleType` regardless of target type.
- [x] Fixed `pkg/uht/manifest.go`: added `IsGameTarget` option, uses "Game" or "Engine" prefix accordingly
- [x] Fixed `pkg/uht/manifest.go`: added all missing manifest fields to match Epic schema (`OverrideModuleType`, `ClassesHeaders`, `InternalHeaders`, `PrivateHeaders`, `PublicDefines`, `VersePath`, `VerseScope`, `HasVerse`, `VerseMountPoint`, `AlwaysExportStructs`, `AlwaysExportEnums`, `ExternalDependenciesFile`)
- [x] Fixed `cmd/uht.go`: added `--game-target` CLI flag (defaults to true)
- [x] Fixed `bzl/uht.bzl`: added `game_target` rule attribute, passes through to CLI
- [x] Verified Go code compiles cleanly

### Not Yet Done
- [ ] Verify Bazel 9 build works — run `bazel build //test/verification/uht/simple_enum:TestModule` with fixed manifest
- [ ] Confirm UHT now generates actual output files (not 0-byte placeholders)
- [ ] Remove debug logging from `bzl/uht.bzl` once codegen is confirmed working

## Key Files

| File | Purpose |
|------|---------|
| `bzl/uht.bzl` | UHT Bazel rule — manifest gen + UHT invocation + output copy |
| `pkg/uht/manifest.go` | Go code that generates UHT manifest JSON (fixed: GameRuntime + full schema) |
| `cmd/uht.go` | CLI command for manifest generation (fixed: --game-target flag) |
| `cmd/uhtscan/main.go` | Header scanner for UCLASS/USTRUCT/UENUM macros |
| `test/verification/uht/simple_enum/` | Minimal test module with UENUM |
| `test/verification/uht/simple_enum/Public/TestEnum.h` | Test header with valid UENUM macro |
| `.bazelversion` | Pinned to 9.0.0 |
| `BUILD.bazel` | Root BUILD — `sh_binary` removed for Bazel 9 compat |

## UHT Invocation Flow

```
bzl/uht.bzl
  ├── Action 1: UHTManifest
  │   ├── uhtscan scans headers for reflection macros
  │   ├── Derives BaseDirectory from first header path
  │   └── gitdeps generates .uhtmanifest JSON
  │
  └── Action 2: UHTCodegen
      ├── cd to UE root
      ├── dotnet run UBT -Mode=UnrealHeaderTool with manifest
      ├── Debug logging (find/ls for generated files)
      └── Copy loop: try output_dir/basename → unsanitized → touch placeholder
```

### Completed (2026-03-14 session, part 2)
- [x] Upgraded rules_go from 0.58.3 to 0.60.0 for Bazel 9 compatibility (cc_common.configure_features removed in Bazel 9)
- [x] Ran Bazel build — build succeeded but UHT still produced 0 files
- [x] Discovered UHT throws `System.ArgumentException: The path is empty. (Parameter 'relativeTo')` during CodeGen (exit code 6, silently swallowed by Bazel rule)
- [x] Verified manifest is correct — running with REAL compiled UBT produces `Total of 3 written`
- [x] **Found REAL root cause:** The Bazel cache UE has a **pre-compiled UBT.dll** (2.7MB, sha `64e426df`) that differs from the locally-compiled UBT.dll (2.9MB, sha `e339484e`). The pre-compiled version has the `relativeTo` bug; the compiled-from-source version works.
- [x] The repo rule runs gitdeps (downloads dependencies) but does NOT compile UBT from source like `Setup.sh` does

## Key Discovery

**The UBT.dll shipped in the git repo is a pre-compiled stub/bootstrap version.** After cloning UE and running gitdeps, you must also compile UBT from source (this is what `Setup.sh` / `Build.sh` does). The compiled UBT.dll is different (larger, different hash) and contains the working CodeGen exporter.

Evidence:
- Cache UBT: 2,713,088 bytes, sha1 `64e426df` (pre-compiled, breaks with `relativeTo` error)
- Real UBT: 2,926,592 bytes, sha1 `e339484e` (compiled from source, works)
- Same manifest + same UE root + real UBT → `Total of 3 written`
- Same manifest + same UE root + cache UBT → `ArgumentException: The path is empty`

### Completed (2026-03-14 session, part 3)
- [x] Pushed updated `kreempuff-release` branch with UE 5.6.1 (includes working UHT/UBT source)
- [x] Upgraded rules_go to 0.60.0 in MODULE.bazel for Bazel 9 compatibility
- [x] Confirmed UHT codegen works end-to-end: `Total of 3 written` for TestModule
- [x] Fixed UHT exit code handling — now fails on non-zero exit
- [x] Fixed output file mapping — extracts UHT basename from sanitized Bazel paths using `${STEM##*_}` pattern
- [x] Changed `{output_dir}` to `$OUTPUT_DIR` (absolute path) in copy loop — relative paths broke after `cd` to UE root
- [x] Removed debug logging from `bzl/uht.bzl`
- [x] Added `-NoGoWide` to UHT invocation for deterministic single-threaded runs

### Current State
UHT codegen is proven working. TestModule generates 3 files correctly. The build fails at C++ compilation because **engine module UHT outputs** (CoreUObject's MetaData.generated.h etc.) are empty stubs — they need real UHT runs too, not just the test module.

### Completed (2026-03-18 session)
- [x] Eliminated copy loop — UHT now writes directly to Bazel's declared output directory
- [x] Per-module output directory (`{name}_uht_gen/`) prevents filename collisions
- [x] Outputs declared with UHT's actual basenames (e.g., `TestEnum.generated.h`)
- [x] Added UHT output dir to `includes` in `module.bzl` so `#include "Foo.generated.h"` resolves
- [x] Confirmed CoreUObject UHT generates real output (e.g., `MetaData.generated.h` = 3978 bytes)
- [x] Build now gets past UHT-generated header resolution — fails on missing engine module deps (ImageCore)

### Current State
UHT pipeline is fully working end-to-end. The build progresses through UHT codegen and header resolution. Current failure is `ImageCore.h` not found — a normal missing engine module dependency, not a UHT issue. This means the UHT integration work is complete and the next work is expanding the engine module dependency graph.

## Next Steps

1. **Add missing engine module BUILD files** — ImageCore and other modules that CoreUObject transitively depends on need BUILD files in `ue_modules/`
2. **Build.cs → BUILD.bazel codegen tool** — C# CLI using Roslyn to parse `.Build.cs` files and emit `ue_module()` Bazel rules. Maps PublicDependencyModuleNames → public_deps, PublicIncludePathModuleNames → headers-only deps, platform conditionals → select(), etc. Runs via UE's bundled dotnet at repo rule time. Replaces manual BUILD file authoring.
3. **Replace UBT with minimal UHT shim** — long-term, write a tiny C# program or Go wrapper that invokes `EpicGames.UHT.dll` directly, bypassing UBT entirely
