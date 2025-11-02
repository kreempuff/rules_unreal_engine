# UnrealHeaderTool (UHT) Integration Plan

**Status:** Planning phase
**Priority:** Critical path blocker
**Blocks:** CoreUObject and 90% of remaining modules

---

## ⚠️ TWO-PHASE APPROACH

**This project's mission is to replace ALL .NET tools with Go + Bazel.**

### Phase 1: Bootstrap (TEMPORARY - Unblock Development)
- Use Epic's precompiled UHT (.NET) temporarily via wrapper script
- Uses UE's bundled dotnet runtime (Engine/Binaries/ThirdParty/DotNet/)
- Unblocks CoreUObject and dependent modules quickly
- **MARKED AS TECHNICAL DEBT** - will be replaced

### Phase 2: Go UHT (LONG-TERM - Project Mission)
- Rewrite UHT in Go (C++ parser + code generator)
- Replace Epic's .NET UHT completely
- Full alignment with project goals
- Built incrementally while Phase 1 enables progress

**Everything we learn from Epic's UHT in Phase 1 will be documented for the Go implementation in Phase 2.**

---

## The Problem

**CoreUObject requires UHT-generated code:**
- Every file with `UCLASS`, `USTRUCT`, `UENUM`, `UPROPERTY`, `UFUNCTION` needs UHT
- UHT parses C++ headers and generates `.generated.h` and `.gen.cpp` files
- These generated files contain reflection metadata (class info, property descriptors, serialization)
- Without UHT: Modules with reflection macros won't compile

**The Chicken-Egg Problem:**
- UHT is a C++ program that depends on Core, CoreUObject, Projects, Json, and many others
- CoreUObject needs UHT to generate its own reflection code
- Can't build UHT without CoreUObject, can't build CoreUObject without UHT

---

## UHT Architecture Overview

### What UHT Does

1. **Parse C++ headers** for reflection macros:
   - `UCLASS()` - Marks classes for reflection
   - `USTRUCT()` - Marks structs for reflection
   - `UENUM()` - Marks enums for reflection
   - `UPROPERTY()` - Marks properties for serialization/replication
   - `UFUNCTION()` - Marks functions for Blueprint/RPC

2. **Generate code** for each module:
   - `ModuleName.init.gen.cpp` - Module initialization (IMPLEMENT_MODULE)
   - `ClassName.generated.h` - Inline generated code for each class
   - `ClassName.gen.cpp` - Out-of-line generated implementations

3. **Create metadata:**
   - Class descriptors (UClass objects)
   - Property descriptors (UProperty objects)
   - Function descriptors (UFunction objects)
   - Serialization code
   - Replication code (for networking)

### UHT's Dependencies

**From UnrealHeaderTool.Build.cs:**
```csharp
PublicDependencyModuleNames:
  - Core
  - CoreUObject
  - Projects
  - Json

PrivateDependencyModuleNames:
  - DesktopPlatform (editor only)
  - ApplicationCore
  - Json
```

**The core dependencies:**
- Core ✅ (98.6% built)
- Projects ✅ (100% built)
- Json ✅ (100% built)
- CoreUObject ❌ (blocked by UHT - chicken-egg)

---

## Solution Strategies

### PHASE 1: Bootstrap with Epic's UHT (TEMPORARY)

**Approach:**
1. Use Epic's UHT (.NET library) via bundled dotnet runtime
2. Create wrapper script that invokes: `dotnet UnrealBuildTool.dll -Mode=UnrealHeaderTool`
3. Run UHT on CoreUObject sources to generate `.generated.h/.gen.cpp` files
4. Build CoreUObject with generated files
5. Unblock all modules depending on CoreUObject

**Important:**
- Uses **UE's bundled dotnet**: `Engine/Binaries/ThirdParty/DotNet/8.*/Mac/dotnet`
- NOT system dotnet (hermetic build requirement)
- Wrapper script marked as **TEMPORARY TECHNICAL DEBT**

**Pros:**
- Fastest path forward (no need to bootstrap minimal Core)
- Proven approach (similar to how Epic builds)
- Can immediately generate correct code

**Cons:**
- Dependency on Epic's binary (until we rebuild our own)
- Need to ensure our CoreUObject matches Epic's binary expectations

**Implementation:**
```python
# In CoreUObject BUILD.bazel

genrule(
    name = "generate_uht_code",
    srcs = glob(["Public/**/*.h", "Classes/**/*.h"]),
    outs = [
        # List all expected .generated.h and .gen.cpp files
        "Classes/Object.generated.h",
        "Classes/Object.gen.cpp",
        # ... hundreds more
    ],
    tools = ["@unreal_engine//Engine/Binaries/Mac:UnrealHeaderTool"],
    cmd = "$(location @unreal_engine//Engine/Binaries/Mac:UnrealHeaderTool) " +
          "-Mode=Parse -Project=... -Module=CoreUObject ...",
)

ue_module(
    name = "CoreUObject",
    srcs = glob(["Private/**/*.cpp"]) + [":generate_uht_code"],
    hdrs = glob(["Public/**/*.h", "Classes/**/*.h"]) + [":generate_uht_code"],
    # ...
)
```

### Option 2: Build Minimal CoreUObject Without Reflection

**Approach:**
1. Temporarily disable/stub out all UCLASS/UPROPERTY macros
2. Build a minimal CoreUObject that compiles without reflection
3. Build UHT with minimal CoreUObject
4. Run UHT on real CoreUObject sources
5. Rebuild CoreUObject with full reflection

**Pros:**
- No dependency on Epic's binaries
- Fully hermetic build from source

**Cons:**
- Very complex (need to stub hundreds of macros)
- Fragile (any UObject usage in UHT will break)
- Takes longer to implement

**Not recommended:** Too much engineering effort for marginal benefit.

### Option 3: Manual Code Generation (NOT RECOMMENDED)

**Approach:**
- Manually write all `.generated.h` and `.gen.cpp` files
- Skip UHT entirely for CoreUObject

**Why this won't work:**
- CoreUObject has 500+ classes with reflection
- Each class needs 100+ lines of generated code
- Manual maintenance is impossible
- Won't match Epic's format

---

## Recommended Approach: Bootstrap with Precompiled UHT

### Phase 1: Extract UHT Binary

**Steps:**
1. Copy Epic's UHT binary from UnrealEngine installation:
   - Mac: `Engine/Binaries/Mac/UnrealHeaderTool`
   - Windows: `Engine/Binaries/Win64/UnrealHeaderTool.exe`
   - Linux: `Engine/Binaries/Linux/UnrealHeaderTool`

2. Create Bazel external repository for precompiled UHT:
```python
# In MODULE.bazel or WORKSPACE
http_archive(
    name = "unreal_header_tool_prebuilt",
    urls = ["file:///path/to/UnrealEngine/Engine/Binaries/Mac/UnrealHeaderTool"],
    # Or: Check into repo temporarily
)
```

### Phase 2: Integrate UHT into Build

**Create `bzl/uht.bzl` rule:**
```python
def ue_module_with_uht(name, **kwargs):
    """UE module that runs UHT code generation."""

    # Step 1: Run UHT to generate code
    native.genrule(
        name = name + "_uht_codegen",
        srcs = kwargs.get("hdrs", []),
        outs = [
            # Auto-discover or explicitly list .generated.h files
            name + ".init.gen.cpp",
            # + per-class generated files
        ],
        tools = ["@unreal_header_tool_prebuilt//:UnrealHeaderTool"],
        cmd = "$(location @unreal_header_tool_prebuilt//:UnrealHeaderTool) ...",
    )

    # Step 2: Build module with generated files
    ue_module(
        name = name,
        srcs = kwargs.get("srcs", []) + [":" + name + "_uht_codegen"],
        hdrs = kwargs.get("hdrs", []) + [":" + name + "_uht_codegen"],
        **kwargs
    )
```

### Phase 3: Build CoreUObject

**Steps:**
1. Create `ue_modules/Runtime/CoreUObject/BUILD.bazel` using `ue_module_with_uht()`
2. List all expected generated files (or auto-discover from source headers)
3. Build CoreUObject: `bazel build //Engine/Source/Runtime/CoreUObject`
4. Verify generated code matches Epic's format

**Challenges:**
- UHT needs a .uproject file and module manifest
- UHT expects specific directory structure
- May need to create stub files to satisfy UHT's expectations

### Phase 4: Build Our Own UHT

**Once CoreUObject builds:**
1. Create `ue_modules/Programs/UnrealHeaderTool/BUILD.bazel`
2. Build UHT from source: `bazel build //Engine/Source/Programs/UnrealHeaderTool`
3. Replace precompiled UHT with Bazel-built version in `bzl/uht.bzl`
4. Rebuild CoreUObject with new UHT to verify correctness

### Phase 5: Extend to All Modules

**Once UHT works for CoreUObject:**
1. Replace `ue_module()` macro with `ue_module_with_uht()` for modules needing reflection
2. Auto-detect which modules need UHT (scan for UCLASS/USTRUCT/etc.)
3. Build remaining modules: JsonUtilities, PakFile, Messaging, etc.

---

## UHT Command Line Interface

**Typical UHT invocation:**
```bash
UnrealHeaderTool \
  -Mode=Parse \
  -Project=/path/to/Game.uproject \
  -Module=CoreUObject \
  -ModuleInfoFile=/path/to/CoreUObject.uhtmanifest \
  -OutputDir=/path/to/generated/code
```

**Required inputs:**
- `.uproject` file (project descriptor)
- `.uhtmanifest` file (module metadata - what headers to parse)
- Module name
- Output directory for generated code

**Outputs:**
- `ModuleName.init.gen.cpp` - Module registration
- `ClassName.generated.h` - Per-class inline code
- `ClassName.gen.cpp` - Per-class implementations

---

## Minimal UHT Example

**For a simple module with one class:**

Input: `Public/MyClass.h`
```cpp
#pragma once
#include "CoreMinimal.h"
#include "MyClass.generated.h"

UCLASS()
class MYMODULE_API UMyClass : public UObject
{
    GENERATED_BODY()

    UPROPERTY()
    int32 MyProperty;
};
```

UHT generates: `Public/MyClass.generated.h`
```cpp
// Auto-generated by UHT
#define MYMODULE_MyClass_generated_h
#define MYMODULE_MyClass_INCLASS \
    // ... reflection metadata macros
#define MYMODULE_MyClass_GENERATED_BODY \
    MYMODULE_MyClass_INCLASS \
    // ... more metadata
```

UHT generates: `Private/MyClass.gen.cpp`
```cpp
// Auto-generated by UHT
#include "MyClass.h"
#include "UObject/GeneratedCppIncludes.h"

// Class descriptor registration
IMPLEMENT_CLASS(UMyClass, 12345678);
// Property descriptors
// Serialization code
```

---

## Action Items

### Week 1-2: UHT Research & Setup

- [ ] Extract precompiled UHT from Epic's installation
- [ ] Study UHT command-line interface and inputs
- [ ] Create minimal .uproject stub for testing
- [ ] Create Bazel external for precompiled UHT
- [ ] Test running UHT manually on a simple module

### Week 3-4: UHT Bazel Integration

- [ ] Create `bzl/uht.bzl` with UHT genrule wrapper
- [ ] Implement .uhtmanifest generation
- [ ] Auto-detect which headers need UHT processing
- [ ] Create `ue_module_with_uht()` macro
- [ ] Test on a minimal module (not CoreUObject yet)

### Week 5-6: CoreUObject Build

- [ ] List all CoreUObject classes needing UHT
- [ ] Create CoreUObject BUILD.bazel with UHT integration
- [ ] Build CoreUObject: `bazel build //Engine/Source/Runtime/CoreUObject`
- [ ] Verify generated code correctness
- [ ] Run CoreUObject tests (if any)

### Week 7-8: Native UHT Build

- [ ] Create UnrealHeaderTool BUILD.bazel
- [ ] Build UHT from source: `bazel build //Engine/Source/Programs/UnrealHeaderTool`
- [ ] Replace precompiled UHT with Bazel-built version
- [ ] Rebuild CoreUObject with native UHT
- [ ] Verify bit-identical output

---

## Success Criteria

1. **CoreUObject builds successfully** with UHT-generated code
2. **Generated code matches Epic's format** (can compare with UBT build)
3. **UHT built from source** with Bazel (no dependency on Epic's binary)
4. **Other modules can use UHT** (JsonUtilities, PakFile, etc. all build)
5. **Clean integration** with `ue_module` macro (transparent to users)

---

## Risks & Unknowns

### High Risk
- **UHT compatibility:** Precompiled UHT may not work with our build structure
- **Generated file discovery:** Need to know all output files beforehand for Bazel genrule
- **Module manifest format:** .uhtmanifest format may be complex or undocumented

### Medium Risk
- **Build environment differences:** UHT may expect specific environment variables
- **Platform-specific issues:** Mac/Windows/Linux UHT binaries may behave differently
- **Version mismatches:** Our modules may not match Epic's UHT expectations

### Low Risk
- **Performance:** UHT is fast (< 1 second for most modules)
- **Caching:** Bazel will cache generated code properly

---

## Alternatives Considered

### Alternative 1: Pregenerate All Code

- Run UHT once outside Bazel, check in generated code
- **Rejected:** Defeats purpose of hermetic builds, hard to maintain

### Alternative 2: Build Our Own Reflection System

- Replace UHT/CoreUObject entirely with custom reflection
- **Rejected:** Massive scope, incompatible with UE ecosystem

### Alternative 3: Wait for Epic's Bazel Support

- Epic might add official Bazel support someday
- **Rejected:** Could be years, we need this now

---

---

## PHASE 2: Go UHT Implementation (Future Work)

**This is the long-term goal - replace Epic's .NET UHT entirely with Go.**

### Go UHT Architecture

**Package structure** (`cmd/uht/`):
```
cmd/uht/
├── main.go              # CLI entry point
├── parser/              # C++ header parser
│   ├── lexer.go        # Tokenize C++ source
│   ├── tokenizer.go    # Token stream processing
│   └── ast.go          # Abstract syntax tree
├── analyzer/            # Semantic analysis
│   ├── types.go        # Type resolution
│   ├── macros.go       # UCLASS/USTRUCT detection
│   └── metadata.go     # Extract metadata from specifiers
├── codegen/             # Code generation
│   ├── generated_h.go  # .generated.h files
│   ├── gen_cpp.go      # .gen.cpp files
│   └── init_gen.go     # .init.gen.cpp files
└── manifest/            # Manifest JSON handling
    ├── reader.go       # Parse .uhtmanifest
    └── writer.go       # Generate manifests
```

### Key Implementation Notes

**From Epic's UHT research:**
- UHT is ~34K lines of C# (130 files)
- Core components: Parser (13 files), Tokenizer (14 files), Code Gen (12 files)
- Generated code format is well-defined and stable
- Manifest JSON schema documented in agent research

**Go libraries to use:**
- `github.com/alecthomas/participle` - Parser combinators for C++ grammar
- `text/template` - Code generation templates
- `encoding/json` - Manifest JSON
- Standard library for file I/O

**Complexity estimate:**
- Lexer/Tokenizer
- C++ Parser (UCLASS/USTRUCT only, not full C++)
- Code generators
- Testing + iteration

### What to Document During Phase 1

**As we use Epic's UHT, document:**
1. **Exact command-line invocations** and arguments
2. **Manifest JSON schema** (all required fields)
3. **Generated code patterns** (.generated.h/.gen.cpp templates)
4. **Edge cases** (nested UPROPERTY, Blueprint specifics, etc.)
5. **Error messages** that Epic's UHT produces
6. **Performance characteristics** (parse time per module)

**Where to document:** Add notes to `docs/GO_UHT_NOTES.md` (create when starting Phase 1)

### Replacement Strategy

**Once Go UHT is ready:**
1. Test on simple module (TraceLog, BuildSettings)
2. Compare output with Epic's UHT (must be bit-identical)
3. Gradually replace wrapper script invocations
4. Remove Epic's UHT dependency entirely
5. **Celebrate:** Pure Go + Bazel build system!

---

## Next Steps (Phase 1 Bootstrap)

1. **Create new branch:** `feat/phase1.3-uht-bootstrap`
2. **Locate bundled dotnet:** `Engine/Binaries/ThirdParty/DotNet/8.*/Mac/dotnet`
3. **Test Epic's UHT manually** to understand invocation
4. **Create wrapper script:** `tools/uht_wrapper.sh` (marked TEMPORARY)
5. **Create GO_UHT_NOTES.md** to track learnings for Go impl
6. **Implement UHT genrule** wrapper in Bazel
7. **Build CoreUObject** with generated code

**Phases:**
- Phase 1 (Bootstrap): Unblock CoreUObject with Epic's UHT
- Phase 2 (Go UHT): Replace with pure Go implementation (parallel work)

**See also:**
- [PLAN.md](PLAN.md) - Overall Phase 1.3 plan
- [BLOCKERS.md](BLOCKERS.md) - CoreUObject wall documentation
- [MODULE_ROADMAP.md](MODULE_ROADMAP.md) - Module priorities

---

**Last updated:** 2025-11-02
**Status:** Ready to begin
