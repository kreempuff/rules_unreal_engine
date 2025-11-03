# UHT Integration Status

**Branch:** `feat/phase1.3-uht-bootstrap`
**Last Updated:** 2025-11-03

---

## ✅ COMPLETED

### 1. UHT Wrapper Script (TEMPORARY)
**File:** `tools/uht_wrapper.sh`

- Takes UE_ROOT, .uproject, .uhtmanifest as parameters
- Invokes Epic's bundled dotnet + UnrealBuildTool.dll
- Converts relative paths to absolute (UBT requirement)
- **Tested:** ✅ Generates 3 files from simple UENUM in 0.42s
- **Marked:** TEMPORARY - will be replaced with Go UHT

### 2. UHT Test Cases
**Directory:** `test/uht_test/`

**Test 1: UENUM with macros**
- Input: TestEnum.h (UENUM with 3 values, UMETA tags)
- Output: 154 lines across 3 files
  - TestEnum.generated.h (34 lines)
  - TestEnum.gen.cpp (91 lines)
  - TestModule.init.gen.cpp (29 lines)
- Result: ✅ Working

**Test 2: Plain class without macros**
- Input: PlainClass.h (no UCLASS/USTRUCT/UENUM)
- Output: 0 files ("Total of 0 written")
- Result: ✅ UHT no-ops gracefully

**Key Finding:** UHT can run on every module with zero penalty!

### 3. Hermetic Repository Rule
**File:** `internal/repo/rule.bzl`

**Features:**
- Downloads Go SDK 1.24.3 during loading phase (hermetic)
- Compiles gitDeps from source using downloaded Go SDK
- Clones UnrealEngine repository
- Runs gitDeps to fetch dependencies
- **Two modes:**
  - Bazel HTTP cache: `gitDeps printUrls` → `repo_ctx.download()` → `extract`
  - Simple mode: `gitDeps` (download + extract in one go)

**Platform Support:**
- ✅ Mac ARM64 (darwin-arm64) - verified SHA256
- ✅ Mac x64 (darwin-amd64) - verified SHA256
- ✅ Linux ARM64 (linux-arm64) - verified SHA256
- ✅ Linux x64 (linux-amd64) - verified SHA256
- ❌ Windows - TODO (need SHA256 checksums)

**Tested:**
- ✅ Go SDK download (cached by Bazel)
- ✅ gitDeps compilation (fresh GOCACHE/GOMODCACHE)
- ✅ UE clone (196k files)
- ✅ gitDeps printUrls (9758 packs)
- ⏳ Bazel HTTP cache downloading (in progress: ~6600/9758)

### 4. Documentation
- **UHT_INTEGRATION_PLAN.md** - Two-phase bootstrap + Go replacement strategy
- **GO_UHT_NOTES.md** - Tracking learnings for Go UHT implementation
- Manifest JSON schema documented
- Generated code patterns captured
- Command-line invocations recorded

---

## 🚧 IN PROGRESS

### Bazel HTTP Cache Download
**Status:** Running in background (pack ~6600/9758, ~68% complete)

Verifying `use_bazel_downloader=True` mode works end-to-end:
- gitDeps printUrls extracts URLs ✅
- repo_ctx.download() caches each pack ⏳
- gitDeps extract unpacks them (pending)

---

## ❌ TODO - Next Steps

### 1. Integrate UHT into ue_module() Macro
**File:** `bzl/module.bzl`

**Approach:**
- Always run UHT on every module (no-ops if no macros)
- Generate empty placeholder files for all headers:
  ```
  ModuleName.init.gen.cpp (always)
  HeaderName.generated.h (per header)
  HeaderName.gen.cpp (per header)
  ```
- Run UHT to overwrite placeholders (or leave empty)
- Add generated files to srcs/hdrs in cc_library

**Genrule structure:**
```python
native.genrule(
    name = name + "_uht",
    srcs = hdrs,
    outs = [
        name + ".init.gen.cpp",
        # + .generated.h/.gen.cpp for each header
    ],
    tools = ["//tools:uht_wrapper.sh"],
    cmd = '''
        # Create empty placeholders
        touch $(OUTS)

        # Generate manifest JSON
        cat > manifest.json <<EOF
        {...}
        EOF

        # Run UHT (overwrites placeholders if macros exist)
        $(location //tools:uht_wrapper.sh) $$UE_ROOT ...

        # Copy generated files to Bazel output
        cp generated/* $$(@D)/
    ''',
)
```

**Challenges:**
- **UE_ROOT parameter:** How to pass UnrealEngine path to wrapper?
  - Option A: Environment variable
  - Option B: ue_module parameter
  - Option C: Reference from repo rule (needs research)
- **Manifest paths:** Need absolute paths in JSON
- **Bazel sandboxing:** UHT writes to fixed OutputDirectory
- **Empty file handling:** Verified working ✅

### 2. Test UHT Integration End-to-End

**Test module:** Use TestModule from test/uht_test/

```python
ue_module(
    name = "TestModule",
    # UHT runs automatically, generates code for TestEnum.h
)
```

**Verify:**
- Placeholder files created
- UHT runs successfully
- Generated code included in build
- Module compiles with generated files

### 3. Build Real Module with UHT

**Target:** CoreUObject (first real UHT user)

- Ensure all CoreUObject dependencies built
- Create ue_modules/Runtime/CoreUObject/BUILD.bazel
- Run `bazel build //Engine/Source/Runtime/CoreUObject`
- Verify UHT generates all ~57 files correctly

---

## Key Insights

1. **UHT no-ops gracefully** - Can run on all modules without penalty
2. **Empty .generated.h compiles** - Placeholder strategy works
3. **Hermetic Go SDK** - Repo rule compiles gitDeps during loading phase
4. **Bazel HTTP cache** - Dependency packs cached and reusable

---

## Commits on Branch (5 total)

```
939af4b test: verify UHT no-ops on modules without macros
829112a chore: ignore UHT test artifacts
a1a9d95 feat: hermetic repository rule with Go SDK download
5bf5872 feat: working UHT wrapper and test case (TEMPORARY)
0bff651 docs: create GO_UHT_NOTES.md for tracking UHT learnings
```

---

---

## ❌ NOT TESTED YET - CRITICAL

### UBT Building in Repository Rule

**What was added:** Code to build UnrealBuildTool.dll from source (internal/repo/rule.bzl:176-212)
**Status:** Written and committed, **NOT tested**
**Blocker:** This is the critical path - everything depends on this working

**Why it matters:**
- UBT.dll is a build artifact (compiled from .NET source)
- NOT in git repository (only .cs source files)
- NOT in gitdeps (only runtime binaries like dotnet)
- We MUST build it to run UHT

---

## 🔬 NEXT STEPS - Critical Test

### Test Command (Run Tomorrow)

```bash
cd /Users/kareemmarch/projects/rules_unreal_engine/test/uht_test
bazel clean --expunge
bazel build //:TestModule
```

### Expected Timeline (~5-7 minutes)

1. Download Go SDK 1.24.3 (~5 sec, cached)
2. Compile gitDeps (~10 sec)
3. Clone UE (~2 min, 196k files)
4. printUrls --prefix "Engine/Binaries/ThirdParty/DotNet" (~1 sec)
   - Returns 825 packs instead of 9758 (91% reduction!)
5. Download 825 packs (~2-3 min, Bazel HTTP cache)
6. Extract DotNet files (~30 sec)
   - Includes dotnet binary with execute permissions
7. **Build UnrealBuildTool.dll (~30-60 sec)** ← CRITICAL TEST
8. Run UHT genrule (creates empty files)
9. Build TestModule (~5 sec)

### Expected Outcomes

**✅ SUCCESS:**
```
DEBUG: UnrealBuildTool built successfully
INFO: Build completed successfully
Target //:TestModule up-to-date
```

**Next:** Fix UHT genrule cmd to actually run UHT and copy files

**❌ FAIL: Missing Dependencies**
```
ERROR: Metadata file 'EpicGames.Core.dll' could not be found
```

**Fix:** UBT needs Epic's libraries. Options:
- Extract Engine/Binaries/DotNET too (widen prefix)
- Build those from source (add to repo rule)

**❌ FAIL: Missing Source**
```
ERROR: UnrealBuildTool.csproj not found
```

**Fix:** UBT source should be in git. Verify clone worked.

**❌ FAIL: NuGet/Network Issues**
```
ERROR: Unable to load service index for NuGet
```

**Fix:** Sandbox blocks network. Try `--spawn_strategy=local` or `--no-restore`

### After UBT Works

1. **Fix UHT genrule cmd** - Currently just touches empty files, need to:
   - Run UHT wrapper with real paths
   - Copy generated files from UHT output dir to Bazel output dir
   - Handle manifest path resolution

2. **Test end-to-end** - Verify:
   - UHT generates real code (not empty files)
   - Generated code compiles
   - Module links successfully

3. **Remove DotNet prefix** - Need full UE for real builds:
   ```python
   prefix = ""  # Full extraction
   ```

4. **Create PR** - Merge 13 commits to main

### Debugging Commands

**Check if dotnet is executable:**
```bash
find ~/.config/cache/bazel/_bazel_*/*/external/+_repo_rules+unreal_engine_source -name "dotnet" -exec file {} \;
```

**Check if UBT.dll was built:**
```bash
find ~/.config/cache/bazel/_bazel_*/*/external/+_repo_rules+unreal_engine_source -name "UnrealBuildTool.dll"
```

**Check what was extracted:**
```bash
ls ~/.config/cache/bazel/_bazel_*/*/external/+_repo_rules+unreal_engine_source/UnrealEngine/Engine/Binaries/
```

---

## Long-Term Remaining Work

### After UHT Integration Complete

- [ ] Build CoreUObject with UHT (~27 headers with UCLASS/USTRUCT)
- [ ] Unlock 90% of modules (JsonUtilities, Serialization, PakFile, Messaging, etc.)
- [ ] Complete Core 100% (7 remaining files need ImageCore, TargetPlatform, etc.)
- [ ] Build InputDevice → unlock ApplicationCore

### Phase 2: Go UHT Replacement

- [ ] Implement cmd/uht/ package (C++ parser + code generator)
- [ ] Test on simple modules (TraceLog, BuildSettings)
- [ ] Replace Epic's .NET UHT completely
- [ ] Remove all TEMPORARY markers

### Platform Support

- [ ] Add Linux testing
- [ ] Add Windows support (SHA256s, paths)
- [ ] Cross-platform validation

---

**Last Updated:** 2025-11-03
**Branch:** `feat/phase1.3-uht-bootstrap` (13 commits)
**Next:** Test UBT building with `cd test/uht_test && bazel build //:TestModule`
