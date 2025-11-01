# UE Module BUILD Files

This directory contains BUILD.bazel files for Unreal Engine modules, maintained in version control.

## Structure

```
ue_modules/
├── Runtime/           # Runtime modules (always loaded)
│   ├── Core/
│   ├── CoreUObject/
│   ├── Engine/
│   └── TraceLog/
├── Developer/         # Editor-only development modules
├── Editor/            # Editor modules
├── ThirdParty/        # Third-party libraries
│   └── AtomicQueue/
└── Programs/          # Standalone programs
    └── UnrealHeaderTool/
```

## Usage

### Option 1: Copy to Your UE Checkout

```bash
# Copy all BUILD files to your UE installation
cp -r ue_modules/Runtime/Core/BUILD.bazel \
      /path/to/UnrealEngine/Engine/Source/Runtime/Core/

cp -r ue_modules/Runtime/TraceLog/BUILD.bazel \
      /path/to/UnrealEngine/Engine/Source/Runtime/TraceLog/
```

### Option 2: Use Install Script

```bash
# TODO: Create install script
bazel run //tools:install_ue_builds -- /path/to/UnrealEngine
```

### Option 3: Symlink (Development)

```bash
# For active development, symlink instead of copy
cd /path/to/UnrealEngine/Engine/Source/Runtime/Core
ln -sf /path/to/rules_unreal_engine/ue_modules/Runtime/Core/BUILD.bazel .
```

## Module Status

| Module | Status | Dependencies | Notes |
|--------|--------|--------------|-------|
| **Runtime** |  |  |  |
| Core | 🟡 Partial | TraceLog | Missing ThirdParty deps, needs UHT |
| TraceLog | ✅ Complete | Core (headers only) | Circular with Core |
| BuildSettings | 🟡 Partial | Core (headers only) | Needs version defines |
| AtomicQueue | ✅ Complete | None | Header-only |
| CoreUObject | ❌ Not started | Core | Needs UHT |
| Engine | ❌ Not started | Core, CoreUObject | Needs UHT |

**Legend:**
- ✅ Complete - Fully implemented and tested
- 🟡 Partial - Compiles but missing dependencies
- ❌ Not started - Not yet implemented

## Adding a New Module

1. **Create directory:**
   ```bash
   mkdir -p ue_modules/Runtime/MyModule
   ```

2. **Create BUILD.bazel:**
   ```starlark
   load("@rules_unreal_engine//bzl:module.bzl", "ue_module")

   ue_module(
       name = "MyModule",
       module_type = "Runtime",
       public_deps = ["//Engine/Source/Runtime/Core"],
       visibility = ["//visibility:public"],
   )
   ```

3. **Reference the .Build.cs:**
   - Add comment with original file path
   - Document dependencies
   - Note any special build settings

4. **Test:**
   ```bash
   # Copy to UE
   cp ue_modules/Runtime/MyModule/BUILD.bazel \
      /path/to/UE/Engine/Source/Runtime/MyModule/

   # Build
   cd /path/to/UE
   bazel build //Engine/Source/Runtime/MyModule
   ```

## Known Issues

### Circular Dependencies

Core and TraceLog have a circular dependency:
- Core depends on TraceLog (public dependency)
- TraceLog depends on Core (headers only, for HAL/Platform.h)

**Current solution:** Both reference each other. Bazel handles header-only circular deps.

**Future:** May need to split Core into Core-Headers and Core-Implementation.

### UHT-Generated Code

Modules with UCLASS/UPROPERTY (CoreUObject, Engine) need UnrealHeaderTool:
- Generate `*.generated.h` and `*.generated.cpp` files
- Must run BEFORE compilation

**Status:** Not yet implemented (Phase 1.3, weeks 5-8)

### Platform-Specific Code

Some modules have platform-specific source files that should only compile on certain platforms.

**Current solution:** All sources compile on all platforms (may fail on wrong platform)

**Future:** Use `select()` to filter sources per-platform

## References

- Parent: `../../bzl/module.bzl` - ue_module rule implementation
- Examples: `../../examples/Core_BUILD.bazel` - Full Core example with all deps
- Tests: `../../test/ue_module.bats` - E2E tests
