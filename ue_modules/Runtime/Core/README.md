# Core Module - Build Notes

**Location:** `Engine/Source/Runtime/Core`
**Type:** Runtime (foundation module)
**Status:** 🔨 In Progress - Compiles ~72/540 files

## Module Overview

Core is the foundation module for all of Unreal Engine, providing:
- Platform abstraction (HAL)
- Container types (TArray, TMap, TSet, etc.)
- Math types (FVector, FMatrix, FQuat, etc.)
- Memory management and allocators
- Threading primitives
- File I/O and serialization
- String handling (FString, FName, FText)

## Build Quirks

### 1. Unity Build Pattern (lz4.cpp)

**Issue:** `Private/Compression/lz4hc.cpp:66` includes `lz4.cpp` as source:
```cpp
#include "lz4.cpp"   /* LZ4_count, constants, mem */
```

**Solution:**
- Exclude `lz4.cpp` from `srcs` (prevent double compilation)
- Add `lz4.cpp` to `hdrs` (allow lz4hc.cpp to include it)

**Why:** Unity build optimization - combines files to reduce compilation overhead.

**BUILD.bazel:**
```python
srcs = glob(
    ["Private/**/*.cpp"],
    exclude = ["Private/Compression/lz4.cpp"],  # Included by lz4hc.cpp
),
hdrs = glob([
    "Private/**/*.h",
    "Private/Compression/lz4.cpp",  # Unity build: included by lz4hc.cpp
]),
```

### 2. Objective-C++ Compilation on Mac

**Issue:** Apple platform files include Foundation headers with Objective-C syntax:
- `ApplePlatformMemory.h:11` → `<Foundation/NSObject.h>`
- Contains `@class NSString` (Objective-C keyword)
- Regular C++ compiler fails on `@` syntax

**Solution:** Compile ALL .cpp files as Objective-C++ on Mac/iOS:
```python
copts = select({
    "@platforms//os:macos": [
        "-x", "objective-c++",  # Enable Objective-C++ mode
        "-std=c++20",
        "-stdlib=libc++",
    ],
    "//conditions:default": ["-std=c++20"],
})
```

**Why:** UE's `AppleToolChain.cs:455` does this - all .cpp files are Objective-C++ on Apple platforms.

### 3. Circular Dependency with TraceLog

**Issue:**
- Core depends on TraceLog (public dependency)
- TraceLog depends on Core (for HAL/Platform.h)

**Solution:** Split Core into two targets:
- `Core_headers`: Headers-only library (no sources)
- `Core`: Full implementation (depends on TraceLog, which depends on Core_headers)

**Dependency graph:**
```
TraceLog → Core_headers (headers only, no cycle)
Core → TraceLog (implementation)
```

### 4. Platform-Specific Source Files

**Pattern:** Core has platform-specific subdirectories:
- `Private/Mac/` - macOS-specific code
- `Private/Apple/` - Shared iOS/macOS code
- `Private/Android/` - Android-specific code
- `Private/Windows/` - Windows-specific code
- `Private/Linux/` - Linux-specific code
- `Private/Unix/` - Shared Linux/Unix code

**Handled automatically** by `ue_module` macro with `select()`.

### 5. MiMalloc Subdirectory Includes

**Issue:** `Private/Thirdparty/MiMalloc.c` includes `"IncludeMiMalloc.h"` from same directory.

**Solution:** Add subdirectory to includes:
```python
private_includes = ["Private/Thirdparty"],
```

## Dependencies

### Public Dependencies
- **TraceLog**: Tracing and profiling infrastructure
- **GuidelinesSupportLibrary**: C++ Core Guidelines (GSL) - header-only
- **AtomicQueue**: Lock-free queue - header-only

### Private Dependencies
- **BuildSettings**: Build metadata (version, changelist, etc.)
- **AutoRTFM**: Transactional memory system
- **BLAKE3**: Fast cryptographic hashing
- **OodleDataCompression**: RAD compression (precompiled)
- **xxhash**: Fast hashing - header-only
- **PLCrashReporter**: Crash reporting (Mac/iOS, precompiled)

### Platform-Specific Dependencies (TODO)
- **mimalloc**: Memory allocator (Windows/Linux)
- **IntelTBB**: Threading Building Blocks (Windows/Linux)
- **jemalloc**: Alternative allocator (Linux)

## Known Issues

### Objective-C++ Compilation
- Status: ✅ Fixed (added `-x objective-c++` for Mac)
- All Mac .cpp files compile as Objective-C++ to support Foundation headers

### UHT-Generated Code (Future)
- Core doesn't heavily use UHT reflection (minimal UCLASS/UPROPERTY)
- CoreUObject will be the main UHT testing ground
- Will need `*.generated.h` files before full build works

### Precompiled Dependencies
- **OodleDataCompression**: Uses vendor `.a` file (lib/Mac/liboo2coremac64.a)
- **PLCrashReporter**: Uses vendor `.a` file (lib/lib-Xcode-15.4/Mac/Release/libCrashReporter.a)
- Future: Build from source for hermetic builds

## Build Status

**Last tested:** 2025-11-02
**Compiled:** ~72/540 files (13%)
**Current blocker:** lz4.cpp unity build handling

**Progress history:**
- 2025-11-01: All 8 Core dependencies building ✅
- 2025-11-02: Platform filtering working ✅
- 2025-11-02: Objective-C++ compilation fixed ✅
- 2025-11-02: BuildSettings defines added ✅
- 2025-11-02: PLCrashReporter added ✅

## References

- **Original:** `Engine/Source/Runtime/Core/Core.Build.cs`
- **Platform handling:** `bzl/module.bzl` (lines 93-137)
- **Compiler flags:** `docs/UE_COMPILER_FLAGS.md`
- **Dependencies:** `docs/PLAN.md` (Precompiled Dependencies section)
