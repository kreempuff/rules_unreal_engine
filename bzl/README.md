# Bazel Rules for Unreal Engine

This directory contains Bazel rules for building Unreal Engine modules and projects.

## Rules

### `ue_module`

Replaces UBT's `.Build.cs` files with native Bazel configuration.

**Location:** `bzl/module.bzl`

**Usage:**
```starlark
load("@rules_unreal_engine//bzl:module.bzl", "ue_module")

ue_module(
    name = "MyModule",
    module_type = "Runtime",
    public_deps = ["//Engine/Source/Runtime/Core"],
    private_deps = ["//Engine/Source/Runtime/Json"],
    defines = ["WITH_MYFEATURE=1"],
)
```

**Parameters:**

| Parameter | Type | Description | Maps to ModuleRules |
|-----------|------|-------------|---------------------|
| `name` | string | Module name | Class name |
| `module_type` | string | "Runtime", "Developer", "Editor", "Program" | Inferred from path |
| `srcs` | list | Source files (auto-discovered if omitted) | - |
| `hdrs` | list | Header files (auto-discovered if omitted) | - |
| `public_deps` | list | Public module dependencies | `PublicDependencyModuleNames` |
| `private_deps` | list | Private module dependencies | `PrivateDependencyModuleNames` |
| `public_includes` | list | Public include directories | `PublicIncludePaths` |
| `private_includes` | list | Private include directories | `PrivateIncludePaths` |
| `system_includes` | list | System include paths | `PublicSystemIncludePaths` |
| `defines` | list | Public preprocessor definitions | `PublicDefinitions` |
| `local_defines` | list | Private preprocessor definitions | `PrivateDefinitions` |
| `linkopts` | list | Linker options and system libraries | `PublicSystemLibraries` |
| `frameworks` | list | Apple frameworks (Mac/iOS) | `PublicFrameworks` |

**Platform Conditionals:**

Use Bazel's `select()` for platform/configuration-specific settings:

```starlark
ue_module(
    name = "Core",
    private_deps = select({
        "@platforms//os:macos": ["//ThirdParty:mimalloc"],
        "@platforms//os:windows": ["//ThirdParty:libpas"],
        "//conditions:default": [],
    }),

    frameworks = select({
        "@platforms//os:macos": ["-framework Cocoa", "-framework Carbon"],
        "//conditions:default": [],
    }),
)
```

**Configuration Conditionals:**

```starlark
ue_module(
    name = "MyModule",
    defines = select({
        "//build:editor": ["WITH_EDITOR=1"],
        "//build:shipping": ["UE_BUILD_SHIPPING=1"],
        "//conditions:default": [],
    }),
)
```

## Examples

See `examples/Core_BUILD.bazel` for a complete real-world example of converting `Core.Build.cs` to Bazel.

## Architecture

```
.Build.cs (C#)              ue_module (Bazel)
├─ ModuleRules class    →   ue_module() macro
├─ Target conditionals  →   select() statements
├─ Dependencies         →   deps, public_deps, private_deps
├─ Includes             →   includes, system_includes
├─ Definitions          →   defines, local_defines
└─ Frameworks/Libs      →   linkopts, frameworks
```

The `ue_module` rule wraps Bazel's native `cc_library` rule with UE-specific conventions:
- Auto-discovery of source/header files
- Proper mapping of public/private dependencies
- Platform-specific framework handling
- Module type metadata via tags

## Migration Guide

### From Core.Build.cs to BUILD.bazel

**Before (C#):**
```csharp
public class Core : ModuleRules
{
    public Core(ReadOnlyTargetRules Target) : base(Target)
    {
        PrivateDependencyModuleNames.Add("BuildSettings");
        PublicDependencyModuleNames.Add("TraceLog");

        if (Target.Platform == UnrealTargetPlatform.Mac)
        {
            PublicFrameworks.AddRange(new string[] { "Cocoa" });
        }
    }
}
```

**After (Starlark):**
```starlark
load("@rules_unreal_engine//bzl:module.bzl", "ue_module")

ue_module(
    name = "Core",
    public_deps = ["//Engine/Source/Runtime/TraceLog"],
    private_deps = ["//Engine/Source/Runtime/BuildSettings"],
    frameworks = select({
        "@platforms//os:macos": ["-framework Cocoa"],
        "//conditions:default": [],
    }),
)
```

## Limitations (Phase 1.2)

Current implementation supports:
- ✅ Basic dependencies (public/private)
- ✅ Include paths
- ✅ Preprocessor definitions
- ✅ Platform conditionals (`select()`)
- ✅ Frameworks (Apple platforms)
- ✅ System libraries

Not yet implemented:
- ❌ PCH (Precompiled Headers) configuration
- ❌ Unity build settings
- ❌ Runtime dependencies
- ❌ Type libraries (Windows)
- ❌ Bundle resources
- ❌ Custom optimization overrides

These will be added in future phases as needed.

## Testing

To test the rule with a real module:

```bash
# Create BUILD.bazel in Core module directory
cp examples/Core_BUILD.bazel Engine/Source/Runtime/Core/BUILD.bazel

# Try building (will fail until dependencies are defined)
bazel build //Engine/Source/Runtime/Core
```

## Future Work

- `ue_program` rule for standalone programs (UnrealHeaderTool, ShaderCompileWorker)
- `ue_plugin` rule for plugin modules
- `ue_project` rule for game projects (Phase 2)
- `ue_test` rule for unit tests

## References

- UBT Source: `Engine/Source/Programs/UnrealBuildTool/Configuration/ModuleRules.cs`
- Bazel cc_library: https://bazel.build/reference/be/c-cpp#cc_library
- Bazel select(): https://bazel.build/docs/configurable-attributes
