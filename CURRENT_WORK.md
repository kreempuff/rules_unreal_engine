# Current Work: UHT File Generation Issue

**Date:** 2025-11-07
**Branch:** feat/phase1.3-core-deps
**Status:** Debugging why UHT-generated files are empty

## Problem Statement

UHT (UnrealHeaderTool) reports success and claims to write files, but all generated .gen.cpp and .generated.h files are 0 bytes.

## What We've Built Today

### Completed ✅
1. **uhtscan tool** (cmd/uhtscan/main.go)
   - Scans C++ headers for UCLASS/USTRUCT/UENUM macros
   - Uses regex matching (no full C++ parser needed)
   - **Validated:** Selects exactly 24 CoreUObject headers (matches Epic's 23-24)
   - Works perfectly: filters Object.h, VVMValue.h (no macros)

2. **uhtscan integration** (bzl/uht.bzl)
   - Replaced path-based heuristics with actual macro scanning
   - Derives BaseDirectory from filtered headers
   - Integrated into manifest generation pipeline

3. **CoreUObject BUILD files**
   - ue_modules/Runtime/CorePreciseFP/BUILD.bazel
   - ue_modules/Runtime/CoreUObject/BUILD.bazel

### The Mystery 🔍

**UHT Output:**
```
INFO: From Running UHT for TestModule:
Total of 3 written
Result: Succeeded

INFO: From Running UHT for CoreUObject:
Total of 50 written
Result: Succeeded
```

**But Actual Files:**
```bash
$ ls -lh bazel-bin/*.gen.cpp
-r-xr-xr-x  0B  TestModule.init.gen.cpp
-r-xr-xr-x  0B  Public_TestEnum.gen.cpp
```

**All 0 bytes!**

**Yet Build Succeeds:**
```
Target //:TestModule up-to-date:
  bazel-bin/libTestModule.a (5.7KB)
```

## Investigation Notes

### Theory 1: File Location Mismatch
**Hypothesis:** UHT writes to different directory than our copy script expects

**Evidence:**
- Copy script checks: `{output_dir}/$OUTBASE`
- If not found: `touch "$out"` (creates 0-byte placeholder)
- All files are placeholders → copy never found real files

**Test Needed:**
- Add debug output to copy script
- Print what paths are being checked
- Search entire filesystem for UHT output

### Theory 2: UHT Write Failure
**Hypothesis:** UHT fails to write but doesn't report error

**Evidence:**
- UHT log only shows TestModule entries, not CoreUObject
- "50 written" may be cached stdout from earlier run
- WriteFileIfChanged() API may silently skip writes

**Test Needed:**
- Remove `|| true` from UHT command (DONE)
- Check full UHT log file for all modules
- Verify UHT actually runs for each module

### Theory 3: Manifest Path Issues
**Hypothesis:** OutputDirectory is correct but BaseDirectory confuses UHT

**Current Manifest (CoreUObject):**
```json
{
  "BaseDirectory": "/path/to/CoreUObject",
  "OutputDirectory": "/path/to/bazel-out/bin",
  "PublicHeaders": ["/path/to/CoreUObject/Public/MetaData.h", ...]
}
```

**Question:** Does UHT expect headers to be RELATIVE to BaseDirectory?

## Code Locations

**Copy Script:** bzl/uht.bzl:168-185
```bash
for out in {outputs}; do
    OUTBASE=$(basename "$out")
    if [ -f "{output_dir}/$OUTBASE" ]; then
        cp "{output_dir}/$OUTBASE" "$out"
    else
        touch "$out"  # ← ALL FILES HIT THIS
    fi
done
```

**UHT Invocation:** bzl/uht.bzl:163
```bash
"$DOTNET" "$UBT" -Mode=UnrealHeaderTool "$PROJECT" "$MANIFEST" -Verbose
```

**Manifest Generation:** bzl/uht.bzl:93-127
- Uses uhtscan to filter headers
- Derives BaseDirectory from first header
- Calls gitDeps to generate JSON

## TODO: Next Debugging Steps

### Immediate (Next Session)

1. **Add verbose logging to copy script:**
   ```bash
   echo "Looking for: {output_dir}/$OUTBASE" >&2
   ls -la "{output_dir}/" >&2
   ```

2. **Find where UHT actually writes:**
   ```bash
   find /entire/cache -name "*.gen.cpp" -size +0 -mmin -5
   ```

3. **Check if UHT even ran:**
   - Verify timestamp on UHT log file
   - Search for CoreUObject in log
   - Check if multiple modules share same log

4. **Validate manifest paths:**
   - Print manifest before UHT
   - Verify OutputDirectory is writable
   - Test with simpler absolute paths

### Completed So Far

- [x] Created uhtscan tool (cmd/uhtscan/main.go) - 90 lines
- [x] Validated uhtscan: 24/24 CoreUObject headers (perfect match with Epic)
- [x] Integrated uhtscan into bzl/uht.bzl manifest generation
- [x] Derived BaseDirectory from filtered headers
- [x] Removed || true to expose actual errors
- [x] Clean rebuild confirms UHT runs and reports success
- [ ] **DEBUG:** Files are 0 bytes despite "50 written" - root cause unknown
- [ ] Fix file generation/copying
- [ ] Verify CoreUObject .generated.h files have content
- [ ] Confirm TestModule uses CoreUObject reflection internals

## Success Criteria

When this is fixed, we should see:
```bash
$ ls -lh bazel-bin/Public_TestEnum.gen.cpp
-r-xr-xr-x  4.3K  Public_TestEnum.gen.cpp

$ head -5 bazel-bin/Public_TestEnum.gen.cpp
// Copyright Epic Games...
#include "TestEnum.h"
#include "UObject/GeneratedCppIncludes.h"
...
```

## Related Issues

- **Original blocker:** CoreUObject headers need CoreUObject's own .generated.h files
- **uhtscan solved:** Header selection (Object.h vs MetaData.h)
- **Current blocker:** File generation/copying

## Commit History on This Branch

1. `8a03190` - wip: add CorePreciseFP and CoreUObject BUILD files
2. `ec67000` - feat: add uhtscan header scanner for UHT
3. `ef726d5` - wip: uhtscan successfully filters CoreUObject headers
4. (uncommitted) - fix: derive BaseDirectory + remove || true

## Session Summary

**Merged Today:**
- PR #111: UHT Integration (10 commits)
- PR #112: Test Infrastructure (5 commits)

**In Progress:**
- uhtscan tool (complete and validated)
- CoreUObject BUILD files (created)
- File generation issue (debugging)
