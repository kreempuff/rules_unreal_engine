# Unreal Engine Compiler Flags Reference

**Source:** Extracted from UnrealBuildTool Clang/MSVC toolchain files
**Date:** 2025-11-01
**Purpose:** Phase 1.3 - Replicate UBT compiler settings in Bazel

---

## C++ Standard

**Default:** C++20

```cpp
// From ClangToolChain.cs:390-403
switch (CompileEnvironment.CppStandard)
{
    case CppStandardVersion.Cpp17:
        Arguments.Add("-std=c++17");
    case CppStandardVersion.Cpp20:
        Arguments.Add("-std=c++20");  // ← DEFAULT
    case CppStandardVersion.Latest:
        Arguments.Add("-std=c++2b");  // C++23 draft
}
```

**Bazel mapping:**
```starlark
ue_module(
    name = "MyModule",
    copts = ["-std=c++20"],  # UE default
)
```

---

## Core Compiler Flags

### Exception Handling

```cpp
// ClangToolChain.cs:818-824
if (CompileEnvironment.bEnableExceptions)
    Arguments.Add("-fexceptions");
else
    Arguments.Add("-fno-exceptions");  // ← UE DEFAULT (exceptions OFF)
```

### RTTI (Run-Time Type Information)

```cpp
// Typically disabled in UE for performance
// Found in: ClangWarnings.cs and platform-specific code
-fno-rtti  // ← UE DEFAULT
```

### Diagnostics

```cpp
// ClangToolChain.cs:656-667
Arguments.Add("-fdiagnostics-absolute-paths");  // Full paths in errors

if (CompileEnvironment.bPrintTimingInfo)
    Arguments.Add("-ftime-trace");

if (bUseAnsiColors)
    Arguments.Add("-fdiagnostics-color");
```

---

## Optimization Flags

### Fast Math

```cpp
// ClangToolChain.cs:696-702
if (CompileEnvironment.bUsesFastMath)
    Arguments.Add("-ffast-math");
else
    Arguments.Add("-ffp-contract=off");  // Precise floating point
```

### Profile-Guided Optimization (PGO)

```cpp
// ClangToolChain.cs:724-732
if (Target.bPGOProfile)
{
    Arguments.Add("-fprofile-generate");
    Arguments.Add("-fno-inline-functions");
}

if (Target.bPGOOptimize)
{
    Arguments.Add($"-fprofile-use={ProfilePath}");
}
```

---

## Sanitizers (Debug/Testing)

```cpp
// ClangToolChain.cs:840-869
// Address Sanitizer (ASan)
if (CompileEnvironment.bEnableAddressSanitizer)
{
    Arguments.Add("-fsanitize=address");
    Arguments.Add("-fsanitize-recover=address");
}

// Thread Sanitizer (TSan)
if (CompileEnvironment.bEnableThreadSanitizer)
    Arguments.Add("-fsanitize=thread");

// Undefined Behavior Sanitizer (UBSan)
if (CompileEnvironment.bEnableUndefinedBehaviorSanitizer)
    Arguments.Add("-fsanitize=undefined");

// Memory Sanitizer (MSan)
if (CompileEnvironment.bEnableMemorySanitizer)
    Arguments.Add("-fsanitize=memory");

// Fuzzer instrumentation
if (CompileEnvironment.bEnableFuzzer)
    Arguments.Add("-fsanitize=fuzzer");
```

---

## PCH (Precompiled Headers)

```cpp
// ClangToolChain.cs:418-423
if (PrecompiledHeaderAction != PrecompiledHeaderAction.None)
{
    Arguments.Add("-Xclang -fno-pch-timestamp");
    Arguments.Add("-fpch-validate-input-files-content");
    Arguments.Add("-fpch-instantiate-templates");
}
```

---

## AutoRTFM (Automatic Reversible Time Flow)

UE's experimental feature for atomic transactions:

```cpp
// ClangToolChain.cs:425-443
if (CompileEnvironment.bEnableAutoRTFMInstrumentation)
{
    Arguments.Add("-fautortfm");

    if (CompileEnvironment.bEnableAutoRTFMVerification)
        Arguments.Add("-fautortfm-verify");
}

if (CompileEnvironment.bAutoRTFMVerify)
    Arguments.Add("-Xclang -mllvm -Xclang -autortfm-verify");
```

---

## Warnings

**From:** `ClangWarnings.cs`

### Common Warnings

```cpp
// Base warning flags (enabled for all modules)
-Wall
-Wextra
-Werror                    // Treat warnings as errors
-Wno-unused-variable       // Too noisy
-Wno-unused-parameter
-Wno-sign-compare
-Wno-missing-field-initializers
-Wno-implicit-fallthrough
```

### UE-Specific Warnings

```cpp
// Shadow variable warnings
-Wshadow
-Wshadow-field

// Unsafe type casts (configurable per module)
-Wcast-align               // Can be Error/Warning/Off
-Wcast-qual

// Thread safety analysis
-Wthread-safety
-Wthread-safety-negative
```

---

## Preprocessor Defines

### Platform Defines

```cpp
// Mac
-DPLATFORM_MAC=1
-DPLATFORM_APPLE=1
-DPLATFORM_UNIX=1

// Windows
-DPLATFORM_WINDOWS=1
-DPLATFORM_MICROSOFT=1

// Linux
-DPLATFORM_LINUX=1
-DPLATFORM_UNIX=1
```

### Build Configuration Defines

```cpp
// Development build (default)
-DUE_BUILD_DEVELOPMENT=1
-DWITH_EDITOR=0           // Or =1 for Editor builds
-DWITH_ENGINE=1

// Shipping build
-DUE_BUILD_SHIPPING=1
-DUE_BUILD_MINIMAL=1
-DWITH_EDITOR=0

// Debug build
-DUE_BUILD_DEBUG=1
-DDEBUG=1
```

### Module-Specific Defines

```cpp
// From BuildSettings.Build.cs
-DENGINE_VERSION_MAJOR=5
-DENGINE_VERSION_MINOR=5
-DENGINE_VERSION_HOTFIX=0
-DBRANCH_NAME="5.5"
-DCURRENT_CHANGELIST=12345

// From Core.Build.cs
-DUE_ENABLE_ICU=1
-DPLATFORM_BUILDS_MIMALLOC=1
-DYIELD_BETWEEN_TASKS=1
```

---

## Include Paths

### Standard UE Include Structure

```cpp
// Core module includes
-IEngine/Source/Runtime/Core/Public
-IEngine/Source/Runtime/Core/Internal
-IEngine/Source/Runtime/Core/Private

// Engine-wide includes
-IEngine/Source
-IEngine/Intermediate/Build/Mac/x86_64/UnrealEditor/Inc/Core
```

---

## Linker Flags

### Mac-Specific

```cpp
// From AppleToolChain.cs
-framework CoreFoundation
-framework Cocoa
-framework Carbon
-framework IOKit

-stdlib=libc++
-dead_strip               // Remove unused code
-ObjC                     // Link Objective-C
```

### Linux-Specific

```cpp
-lpthread
-ldl
-lrt
-Wl,--as-needed
```

---

## Bazel Toolchain Mapping

### Approach 1: Global Toolchain (Recommended)

Create a custom `cc_toolchain` that encodes UE defaults:

```starlark
# toolchains/ue_clang.bzl
cc_toolchain(
    name = "ue_clang_mac",
    all_files = ":all_files",
    compiler_files = ":compiler_files",
    ar_files = ":ar_files",
    linker_files = ":linker_files",
    dwp_files = ":empty",
    objcopy_files = ":empty",
    strip_files = ":empty",
    supports_param_files = 1,
    toolchain_identifier = "ue-clang-mac",
    toolchain_config = ":ue_clang_mac_config",
)

cc_toolchain_config(
    name = "ue_clang_mac_config",
    cpu = "darwin_arm64",
    compiler = "clang",
    cxx_builtin_include_directories = [
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/16.0.0/include",
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include",
    ],
    tool_paths = {
        "gcc": "/usr/bin/clang",
        "ar": "/usr/bin/libtool",
        "cpp": "/usr/bin/clang++",
        # ...
    },
    compile_flags = [
        "-std=c++20",
        "-fno-exceptions",
        "-fno-rtti",
        "-fdiagnostics-absolute-paths",
        "-Wall",
        "-Werror",
    ],
)
```

### Approach 2: Per-Module Flags

Add flags directly to `ue_module`:

```starlark
ue_module(
    name = "Core",
    copts = [
        "-std=c++20",
        "-fno-exceptions",
        "-fno-rtti",
    ],
    defines = [
        "PLATFORM_MAC=1",
        "UE_BUILD_DEVELOPMENT=1",
    ],
)
```

---

## Summary for Phase 1.3

### Must-Have Flags (Tier 1)

```bash
# C++ Standard
-std=c++20

# Exception/RTTI (UE defaults)
-fno-exceptions
-fno-rtti

# Warnings
-Wall
-Werror

# Platform defines
-DPLATFORM_MAC=1 (or WINDOWS/LINUX)
-DUE_BUILD_DEVELOPMENT=1
-DWITH_EDITOR=0/1
```

### Nice-to-Have (Tier 2)

```bash
# Diagnostics
-fdiagnostics-absolute-paths
-fdiagnostics-color

# PCH support
-fpch-validate-input-files-content

# Optimization
-ffast-math (or -ffp-contract=off)
```

### Advanced (Tier 3)

```bash
# AutoRTFM
-fautortfm

# Sanitizers
-fsanitize=address

# PGO
-fprofile-generate
```

---

## Next Steps

1. ✅ Document compiler flags (this file)
2. Create Bazel toolchain with UE defaults
3. Update `ue_module` rule to use UE toolchain
4. Test building Core module
5. Compare output with UBT build (symbols, binary format)

---

**References:**
- ClangToolChain.cs:380-1472
- ClangWarnings.cs
- AppleToolChain.cs
- VCToolChain.cs (Windows)
