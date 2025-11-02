# Go UHT Implementation Notes

**Purpose:** Track learnings from Epic's .NET UHT for eventual Go replacement

**Status:** Phase 1 (Bootstrap) in progress - documenting as we go

---

## Epic's UHT Invocation

### Bundled Dotnet Runtime
```bash
# Location (Mac ARM64)
/Users/kareemmarch/Projects/UnrealEngine/Engine/Binaries/ThirdParty/DotNet/8.0.300/mac-arm64/dotnet

# Version
8.0.300

# Other platforms
- mac-x64 (Intel Mac)
- linux-arm64 (Linux ARM)
```

### UBT Command-Line
```bash
dotnet UnrealBuildTool.dll -Mode=UnrealHeaderTool <manifest-file>

# UBT location
Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll

# UHT DLL
Engine/Binaries/DotNET/UnrealBuildTool/EpicGames.UHT.dll (697 KB)
```

### Manifest JSON Schema

**File:** `UnrealEditor.uhtmanifest`

**Top-level fields:**
```json
{
  "IsGameTarget": true,
  "RootLocalPath": "/path/to/UnrealEngine",
  "TargetName": "UnrealEditor",
  "ExternalDependenciesFile": "/path/to/UnrealEditor.deps",
  "Modules": [ ... ]
}
```

**Per-module fields:**
```json
{
  "Name": "ModuleName",
  "ModuleType": "EngineRuntime",
  "OverrideModuleType": "None",
  "BaseDirectory": "/path/to/module",
  "IncludePaths": [
    "/path/to/module/Public",
    "/path/to/module/Private"
  ],
  "OutputDirectory": "/path/to/Intermediate/Inc/ModuleName/UHT",
  "ClassesHeaders": [],
  "PublicHeaders": ["/path/to/Header.h"],
  "InternalHeaders": [],
  "PrivateHeaders": [],
  "PublicDefines": [],
  "GeneratedCPPFilenameBase": "/path/to/ModuleName.gen",
  "SaveExportedHeaders": true,
  "UHTGeneratedCodeVersion": "None",
  "VersePath": "",
  "VerseScope": "PublicUser",
  "HasVerse": false,
  "VerseMountPoint": "",
  "AlwaysExportStructs": true,
  "AlwaysExportEnums": true
}
```

---

## Generated Code Format

### Output Files Per Module

For a module with N headers containing UCLASS/USTRUCT:

```
OutputDirectory/
├── ModuleName.init.gen.cpp       # Module initialization
├── Header1.generated.h            # Per-header inline code
├── Header1.gen.cpp                # Per-header implementations
├── Header2.generated.h
├── Header2.gen.cpp
└── ...
```

### .generated.h Pattern

**Purpose:** Inline macro expansions for UCLASS/USTRUCT

**Example:** (from CoreNetTypes.generated.h)
```cpp
// Copyright notice
// IWYU pragma: private, include "UObject/CoreNetTypes.h"

#ifdef COREUOBJECT_CoreNetTypes_generated_h
#error "CoreNetTypes.generated.h already included"
#endif
#define COREUOBJECT_CoreNetTypes_generated_h

#include "Templates/IsUEnumClass.h"
#include "UObject/ObjectMacros.h"
#include "UObject/ReflectedTypeAccessors.h"

// Enum expansion macros
#define FOREACH_ENUM_ELIFETIMECONDITION(op) \
    op(COND_None) op(COND_InitialOnly) ...

// Static enum template
template<> COREUOBJECT_API UEnum* StaticEnum<ELifetimeCondition>();
```

### .gen.cpp Pattern

**Purpose:** Out-of-line registration and metadata

**Example structure:**
```cpp
#include "UObject/GeneratedCppIncludes.h"
#include "ModuleName/ClassName.h"

// Empty link function
void EmptyLinkFunctionForGeneratedCodeClassName() {}

// Registration statics
static FEnumRegistrationInfo Z_Registration_Info_UEnum_EnumName;
static UEnum* EnumName_StaticEnum() { ... }

// Metadata tables
static constexpr UECodeGen_Private::FMetaDataPairParam Enum_MetaDataParams[] = {
    { "ModuleRelativePath", "Public/Path/Header.h" },
    ...
};

// Constructor functions
UEnum* Z_Construct_UEnum_ModuleName_EnumName() { ... }
```

### .init.gen.cpp Pattern

**Purpose:** Module-wide initialization

**Example:**
```cpp
// Copyright notice
#include "UObject/GeneratedCppIncludes.h"

// Per-package init function
void EmptyLinkFunctionForGeneratedCodeModuleName_init() {}

// Package registration
static FPackageRegistrationInfo Z_Registration_Info_UPackage_ModuleName;
FORCENOINLINE UPackage* Z_Construct_UPackage__Script_ModuleName() { ... }
```

---

## Go UHT Design Notes

### Parser Requirements

**What to parse (not full C++ - just UE macros):**
- `UCLASS(specifiers)` - Class reflection
- `USTRUCT(specifiers)` - Struct reflection
- `UENUM(specifiers)` - Enum reflection
- `UINTERFACE(specifiers)` - Interface reflection
- `UPROPERTY(specifiers)` - Property metadata
- `UFUNCTION(specifiers)` - Function metadata
- `UMETA(specifiers)` - Metadata tags on enum values

**Specifiers to support:**
- BlueprintType, Blueprintable
- Category="Name"
- DisplayName="Name"
- Meta tags
- Replication flags (Replicated, ReplicatedUsing)
- Many more...

### Code Generator Requirements

**Templates needed:**
1. `.generated.h` template - Inline macros per header
2. `.gen.cpp` template - Registration code per header
3. `.init.gen.cpp` template - Module initialization

**Data for templates:**
- List of all UClasses/UStructs/UEnums in module
- Property/function metadata per class
- Include paths and module names
- Specifier values (BlueprintType, etc.)

### Minimal Go UHT MVP

**Phase 1 Goal:**
- Parse simple UENUM (easiest - no properties/functions)
- Generate .generated.h with enum template
- Generate .gen.cpp with enum registration
- Generate .init.gen.cpp stub
- Test on TraceLog or BuildSettings (minimal UHT usage)

**Phase 2 Goal:**
- Add USTRUCT parsing
- Property parsing (UPROPERTY)
- Function parsing (UFUNCTION)

**Phase 3 Goal:**
- Add UCLASS parsing
- Full CoreUObject support
- Replace Epic's UHT entirely

---

## Discoveries & Gotchas

### Discovery 1: Manifest Complexity
- Each module entry has 20+ fields
- Must track all public/private/internal headers separately
- Output directory must be specified precisely
- IncludePaths affect how UHT resolves types

### Discovery 2: Generated File Naming
- Pattern: `ClassName.generated.h` (not Class.gen.h)
- Module init: `ModuleName.init.gen.cpp`
- Generated CPP: `ClassName.gen.cpp`
- Must be precise - #include paths depend on this

### Discovery 3: IWYU Pragmas
- Generated headers use `// IWYU pragma: private, include "Public/Header.h"`
- Helps include-what-you-use tool
- Not critical for functionality but good practice

---

## Test Plan for Go UHT

### Test Case 1: Simple Enum
```cpp
// Input: TestEnum.h
UENUM(BlueprintType)
enum class ETestEnum : uint8 {
    Value1 UMETA(DisplayName="First Value"),
    Value2 UMETA(DisplayName="Second Value"),
};
```

**Expected output:**
- `TestEnum.generated.h` with FOREACH_ENUM macro
- `TestEnum.gen.cpp` with registration code
- Must match Epic's UHT output exactly

### Test Case 2: Simple Struct
```cpp
// Input: TestStruct.h
USTRUCT(BlueprintType)
struct FTestStruct {
    GENERATED_BODY()

    UPROPERTY(BlueprintReadWrite)
    int32 Value;
};
```

**Expected output:**
- Struct reflection metadata
- Property descriptors
- Serialization helpers

### Test Case 3: CoreUObject Compatibility
- Run on real CoreUObject headers
- Compare output with Epic's UHT
- Ensure bit-identical (or functionally equivalent)

---

## TODO: Document During Phase 1 Bootstrap

As we test Epic's UHT, add notes here for:
- [ ] Exact command-line syntax for UHT mode
- [ ] How UBT finds the manifest file
- [ ] What happens if manifest is malformed
- [ ] Performance: how long does UHT take per module?
- [ ] Error messages and how to debug UHT failures
- [ ] Any undocumented manifest fields we discover
- [ ] Platform differences (Mac vs Windows vs Linux)

---

**Last updated:** 2025-11-02
**Phase:** 1 (Bootstrap - documenting Epic's UHT)
**Next:** Test UHT invocation manually, create wrapper script
