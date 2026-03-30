# Current Context: Bazel Build System for Unreal Engine

## Ultimate Goal

1. **`bazel build //:UnrealEditor`** — build and run the Unreal Editor
2. **`bazel build //:KraGame`** — build and run a game client target
3. **`bazel build //:KraServer --platforms=@platforms//os:linux`** — build a dedicated server for Linux

Everything else is in service of these targets.

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
- [x] Build gets past UHT-generated header resolution — initially failed on missing ImageCore dep

### Completed (2026-03-19 session)
- [x] Added ImageCore BUILD file (lightweight image types — FImage, FImageView, ERawImageFormat)
- [x] Fixed all ue_modules dep paths: `//Engine/Source/` → `//UnrealEngine/Engine/Source/` (34 refs across all BUILD files)
- [x] Discovered `_headers` targets had no `deps`, so transitive include paths didn't propagate
- [x] Added `public_header_deps` param to `ue_module()` — maps to UBT's `PublicIncludePathModuleNames` (include-path only, no link)
- [x] Used `source_hdrs` (pre-UHT) for `_headers` target to avoid triggering UHT and creating circular deps
- [x] Broke Core ↔ ImageCore cycle: Core uses `public_header_deps` for ImageCore_headers
- [x] Confirmed no more dependency cycles via `bazel query`

### Completed (2026-03-24 session)
- [x] **Resolved _headers vs UHT tension** — added `{name}_uht_headers` target tier
- [x] TestModule builds successfully end-to-end (UHT codegen → C++ compilation → library output)

### Completed (2026-03-25 session)
- [x] **Built Build.cs → BUILD.bazel parser** using Roslyn (`tools/buildcs-to-bazel/`)
- [x] AST-based static analysis — no UBT type dependencies
- [x] Scanned 870 modules: 447 simple (51%), 253 conditional (29%), 170 complex (19%)
- [x] Generated 700 BUILD files (81%) — verified against hand-written Json, ImageCore, Projects, Networking
- [x] Three commands: `scan` (complexity report), `generate` (emit BUILD files), `resolve` (module name→label map)

### Completed (2026-03-26 sessions)
- [x] Integrated parser into repo rule — 835 BUILD files auto-generated
- [x] Phase 2: platform conditionals — 82% coverage
- [x] Custom Bazel providers: UeModuleInfo + UeUhtInfo (test passing)
- [x] Configurable build defines: `--//bzl:target_type=game|editor|server`, `--//bzl:build_config=development|shipping`
- [x] Emitter fixes: select() compat, dep dedup (within/across/conditional), case-insensitive resolution, multi-Build.cs-per-directory, cycle-free _headers
- [x] **Json builds** (`libJson.a`), **Projects builds** (`libProjects.a`)
- [x] **Engine _headers resolves** (88 packages, 2272 targets)

### Completed (2026-03-27 sessions)
- [x] **ue_cc_module custom rule** — separates compilation (header-only deps) from linking (ue_binary)
- [x] **ue_binary custom rule** — collects UeLinkInfo providers, links all .a files at the end
- [x] **Circular deps test passes** — two modules with mutual deps compile and link correctly
- [x] Removed hand-written BUILD overrides — auto-generated BUILD files are source of truth

### Completed (2026-03-28/29 sessions)
- [x] **Single-invocation UHT** — replaces broken per-module approach
  - 693 modules, 9,356 generated files, 11 seconds
  - Topological sort with cycle-breaking for foundational modules (Core → CoreUObject → Engine)
  - uhtscan filtering with delegate macro support
  - Global basename dedup, stub module exclusion, Classes/ support
- [x] **uht_codegen_all rule** — single Bazel action for all UHT
- [x] **uht_module_extract rule** — copies per-module subdirectory for compilation
- [x] **UHT dep module include paths** — each module gets its deps' .generated.h include paths
  - Per-module extracted tree (own .generated.h) + full uht_gen_all (deps' .generated.h)
  - uht_dep_modules string_list carries dep module names for include path construction
- [x] **Module registry with deps** — buildcs-to-bazel `registry` command for topological sorting
- [x] **Classes/ support** — legacy UE header location added to hdrs glob and includes
- [x] All .generated.h headers resolve across module boundaries (UObject, delegates, etc.)

### Completed (2026-03-29 session, continued)
- [x] UHT dep module include paths via `uht_all_tree` attribute + `uht_dep_modules` string list
- [x] Dep module name extraction: use target name (after `:`) not directory name
- [x] Shaders pseudo-module for `Engine/Shaders/Shared` includes
- [x] `Engine/Source` as include root for absolute-style UE includes (`Runtime/Engine/Internal/...`)
- [x] `Classes/` in default hdrs glob and includes (legacy UE header location)
- [x] Relaxed `allow_files` on `ue_cc_module` for tree artifacts
- [x] Tree artifact handling from both `srcs` and `public_hdrs`
- [x] Off-by-one fix in Engine/Source include root path computation
- [x] `--keep_going` build: 96+ Engine compilations succeed

### Current State
**Engine module: 96+ compilations succeed. All UHT and .generated.h headers resolve.**

With `--keep_going`, 19 unique fatal errors remain — all are regular C++ include path issues:
- **5 `Runtime/...` absolute includes** — may be fixed by the off-by-one fix (needs verification)
- **6 `Iris/` includes** — Iris networking module include path not available
- **3 `DistributedBuildControllerInterface.h`** — unresolved DistributedBuildInterface module
- **1 `ISlateReflectorModule.h`** — SlateReflector module header
- **1 `KismetMathLibrary.inl`** — .inl file include
- **3 other** — Version.h, MaterialIR, CoreRedirects

These are Build.cs → Bazel mapping refinements, not architectural issues. Each is fixable by
adding the right module include path or excluding the file.

## Architecture Summary

```
Build.cs parser → Module registry (693 modules with deps, topologically sortable)
                → BUILD.bazel files (835, auto-generated)

UHT (single invocation, 11s) → uht_gen_all/ tree artifact (9,356 files, 693 modules)
                              → per-module extraction (uht_module_extract)
                              → dep module include paths (uht_all_tree + uht_dep_modules)

ue_module macro → ue_cc_module (compilation, header-only deps, no cycles)
               → _headers / _uht_headers (cc_library, for dep resolution)
               → ue_binary (linking, collects UeLinkInfo)

Config flags → --//bzl:target_type=game|editor|server
             → --//bzl:build_config=development|shipping
```

## Next Steps

1. **Fix remaining 19 Engine include paths** — Iris module, DistributedBuild, SlateReflector, absolute path includes
2. **Replace UBT with minimal UHT shim** — invoke EpicGames.UHT.dll directly (faster, no UBT overhead)
3. **Platform toolchains** — cross-compilation to Linux for dedicated server
4. **Executable targets** — ue_binary for editor, game client, server
