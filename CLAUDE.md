# rules_unreal_engine - Project Context

## Why This Project Exists

This project was created to replace Unreal Engine's .NET-based build system (UnrealBuildTool and UnrealAutomationTool) with a Bazel + Go implementation.

### The Problem: Current UAT/UBT Experience

**Date:** 2025-10-30
**Context:** Attempting to cook a game project using UnrealAutomationTool

#### What Should Be Simple

```bash
just ue-cook  # Cook the game for Mac platform
```

#### What Actually Happens

1. **NullReferenceException in Program.cs**
   - AutomationUtils.Automation module not discovered by module system
   - Only 3 of ~30 automation modules returned by InitializeScriptModules()
   - Root cause: AutomationUtils lacks `.Automation.cs` marker file

2. **NuGet Package Vulnerability Errors**
   - Can't rebuild AutomationTool to fix the bug
   - `Magick.NET-Q16-HDRI-AnyCPU` has 8 known vulnerabilities
   - `Microsoft.Build` has 1 high severity vulnerability
   - Errors block compilation even though vulnerabilities are irrelevant to local dev

3. **Fix Attempt #1: Disable NuGet Audit**
   ```bash
   export DOTNET_CLI_ENABLE_AUDIT=false
   ```
   - Result: Didn't work, environment variable ignored

4. **Fix Attempt #2: Suppress Warnings in .csproj**
   - Modified `Gauntlet.Automation.csproj` line 14
   - Modified `AutomationUtils.Automation.csproj` line 14
   - Added: `<WarningsNotAsErrors>NU1901,NU1902,NU1903</WarningsNotAsErrors>`
   - Result: Build succeeded, still crashed with NullReferenceException

5. **Fix Attempt #3: Add Fallback Logic in Program.cs**
   - Lines 515-525: Manual path construction when module not discovered
   - Result: **Still failing** - now crashes on line 514 with NullReferenceException
   - Suspected issue: `ScriptModuleAssemblyPaths` contains null entries

6. **Time Spent Debugging:** ~3 hours and counting
7. **Time to Fix with Working Build System:** ~0 seconds

#### What Happens Next: The ShaderCompileWorker Saga

**Date:** 2025-10-30 (continued)
**Context:** After fixing the NullReferenceException with `-nocompile` flag

1. **Cook Finally Starts**
   - UAT cook command runs successfully
   - Starts loading assets and compiling shaders
   - Progress looks good...

2. **ShaderCompileWorker Crashes**
   ```
   dyld[97617]: Symbol not found: __ZNSt12length_errorD1Ev
     Referenced from: <112CFFC8-73BD-3194-B4A2-CEB698790C9F> ShaderCompileWorker-Core.dylib
     Expected in:     <7D70205D-2B4C-36B0-BE24-6BD483FD4DB8> libtbb.dylib

   LogShaderCompilers: Error: ShaderCompileWorker terminated unexpectedly!
   LogShaderCompilers: Error: Falling back to directly compiling which will be very slow.
   ```

3. **Root Cause: C++ ABI Compatibility**
   - ShaderCompileWorker-Core.dylib compiled with older Xcode version
   - libtbb.dylib has different C++ standard library ABI
   - Symbol `std::length_error` destructor missing
   - Xcode version changes (26.0.1 → 15.4 → 16.1) caused mismatch

4. **The "Solution": Rebuild the Entire Engine**
   ```bash
   cd /Users/kareemmarch/projects/UnrealEngine
   ./Engine/Build/BatchFiles/Mac/Build.sh UnrealEditor Mac Development
   ```
   - **Total Actions:** 4,958
   - **Estimated Time:** 60-90 minutes
   - **Why:** Need to rebuild 2 dylib files (ShaderCompileWorker-Core.dylib, libtbb.dylib)
   - **Result:** Waiting 1+ hour to get 2 files recompiled

5. **What We Want to Do**
   ```bash
   # Just rebuild the affected libraries
   bazel build //Engine/Binaries/Mac:ShaderCompileWorker-Core
   bazel build //Engine/Binaries/Mac:libtbb
   ```
   - **Estimated Time:** 30 seconds
   - **Actions:** 2 targets, not 4,958
   - **Why It Would Work:** Fine-grained build graph, explicit dependencies

6. **Total Time Wasted on This Issue**
   - 30 minutes discovering the dyld error
   - 30 minutes diagnosing C++ ABI mismatch
   - 60-90 minutes waiting for Engine rebuild
   - **Total: 2-2.5 hours** to fix 2 dylib files

7. **Why This Happened**
   - No hermetic builds (ABI mismatch across Xcode versions)
   - No fine-grained targets (can't rebuild individual dylibs)
   - Build system doesn't track dylib dependencies properly
   - "Target is up to date" lied because it didn't detect ABI change

### The Core Issues with UAT/UBT

1. **Fragile Module Discovery**
   - Uses magic marker files (`.Automation.cs`)
   - No explicit dependency declarations
   - Fails silently when modules not found
   - Returns null entries in collections

2. **Build-Time Code Compilation**
   - UAT compiles itself every time it runs
   - NuGet audit runs on every build
   - Slow startup (4-5 seconds just to compile UAT)
   - Failure modes are cryptic

3. **Poor Error Messages**
   ```
   Unhandled exception: System.NullReferenceException: Object reference not set to an instance of an object.
      at AutomationToolDriver.Program.MainProc() in Program.cs:line 514
   ```
   - No indication which variable is null
   - No explanation of what failed
   - Stack trace doesn't show the lambda call

4. **Dependency Hell**
   - 46 NuGet warning messages on every build
   - Security vulnerabilities in transitive dependencies
   - Can't upgrade packages without Epic's approval
   - Breaking changes in .NET SDK affect builds

5. **Platform-Specific Weirdness**
   - Different behavior on Windows vs Mac vs Linux
   - Xcode version compatibility issues
   - SDK path detection failures
   - Hard-coded paths in C# code

### What We Want Instead

**Bazel + Go Implementation:**

```bash
# Build the engine
bazel build //engine:editor

# Cook a game project
bazel run //tools:cook -- --project=/path/to/game.uproject --platform=Mac

# Package for distribution
bazel build //game:package_mac
```

**Benefits:**

1. **Hermetic Builds**
   - All dependencies explicitly declared
   - No surprise compilation steps
   - Reproducible across machines

2. **Fast Incremental Builds**
   - Bazel caching (local + remote)
   - Only rebuild what changed
   - No "rebuild UAT every time"

3. **Clear Error Messages**
   ```
   ERROR: //engine:core failed to build
   Missing dependency: //engine:reflection_system
   ```

4. **No Runtime Compilation**
   - Pre-compiled binaries
   - No NuGet on every build
   - No .NET SDK version issues

5. **Cross-Platform Consistency**
   - Same build commands everywhere
   - Same toolchain everywhere
   - Same caching everywhere

### Current Status (2025-10-30)

- **rules_unreal_engine:** ~5-10% complete
- **Estimated Effort:** 12-18 months, 2-3 engineers
- **See:** `docs/effort-estimate.md` for full breakdown

### Immediate Goal

**Short-term:** Fix the NullReferenceException and get cooking working with existing UAT

**Long-term:** Replace UAT/UBT entirely with this project

### Lessons Learned

1. **Magic Discovery Systems Are Evil**
   - Explicit dependency declarations > file naming conventions
   - Fail-fast with clear errors > silent failures

2. **Build Systems Should Not Compile Themselves**
   - UAT compiling itself on every invocation is a terrible design
   - Pre-compiled tools are faster and more reliable

3. **Security Warnings Should Not Block Local Development**
   - NuGet audit is useful for CI/CD
   - Blocking local builds helps no one

4. **Null Safety Matters**
   - C#'s nullable reference types would have caught this
   - Go's explicit nil checks are better
   - Epic's codebase predates C# 8.0 nullable features

### References

**Current Debugging Session:**
- Branch: `ops/build-cook-package` (Kra project)
- Files Modified:
  - `/Users/kareemmarch/projects/UnrealEngine/Engine/Source/Programs/AutomationTool/Program.cs` (lines 515-525)
  - `/Users/kareemmarch/projects/UnrealEngine/Engine/Source/Programs/AutomationTool/Gauntlet/Gauntlet.Automation.csproj` (line 14)
  - `/Users/kareemmarch/projects/UnrealEngine/Engine/Source/Programs/AutomationTool/AutomationUtils/AutomationUtils.Automation.csproj` (line 14)

**Related Documentation:**
- `docs/effort-estimate.md` - Full effort estimate for 1.0 release
- `docs/decisions/` - ADRs for architectural decisions

---

## Project Architecture

### Replacement Strategy

#### Phase 1: UnrealBuildTool (UBT) Replacement
- Parse `.Build.cs` files to extract module dependencies
- Generate Bazel `cc_library` and `cc_binary` rules
- Integrate UnrealHeaderTool (reflection code generation)
- Build all engine C++ modules

#### Phase 2: UnrealAutomationTool (UAT) Replacement
- Port AutomationUtils.Automation to Go
- Implement BuildCookRun command
- Platform-specific automation (Mac, Windows, Linux, iOS, Android)
- Code signing and packaging

#### Phase 3: Testing & Validation
- Unit tests for all modules
- Integration tests for full pipeline
- Performance optimization (remote caching)
- Documentation and migration guides

### Technology Stack

- **Build System:** Bazel
- **Tooling:** Go (for automation commands)
- **Module Discovery:** Static analysis of `.Build.cs` files
- **Dependency Management:** Bazel's WORKSPACE and MODULE.bazel

### Success Criteria

1. Build UE Editor in <1 hour (vs 2-3 hours with UBT)
2. 90%+ cache hit rate on incremental builds
3. Bit-identical output to Epic's official builds
4. Support all major platforms (Mac, Windows, Linux, iOS, Android)

---

## Contributing

This project is in early development. Contributions welcome once core architecture is established.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/kreempuff/rules_unreal_engine
cd rules_unreal_engine

# Build tooling
bazel build //cmd/...

# Run tests
bazel test //...

# Run BATS integration tests
bats test/gitdeps.bats
bats test/ue_module.bats
```

### Testing Guidelines

**IMPORTANT: Always use BATS tests for real repository structures**

When testing features that interact with Unreal Engine source code:

✅ **DO:**
- Create mock UE directory structures in BATS tests using temp directories
- Copy minimal source files into test/ue_*_test/ directories
- Test with representative examples (e.g., TraceLog-like module)
- Clean up test directories in teardown

❌ **DO NOT:**
- Modify files in actual UnrealEngine repository during tests
- Write BUILD files directly to /Users/kareemmarch/Projects/UnrealEngine
- Depend on specific UE checkout states in tests

**Example:**
```bash
@test "Build real UE module structure" {
    mkdir -p test/my_module_test/Public
    mkdir -p test/my_module_test/Private
    # Create minimal source files...
    # Create BUILD.bazel...
    bazel build //test/my_module_test:MyModule
    # Cleanup
    rm -rf test/my_module_test
}
```

### Current Priorities

1. ✅ ~~Complete Phase 1.1: Setup.sh replacement (gitDeps.go)~~ **DONE**
2. **Active:** Phase 1.2: `ue_module` Bazel rule (replaces .Build.cs)
3. Test building Core and CoreUObject modules with Bazel
4. Document architecture decisions in `docs/decisions/`

---

## Why Go + Bazel?

**Go:**
- Fast compilation
- Great CLI tooling (Cobra, Viper)
- Cross-platform binaries
- No runtime dependencies
- Strong standard library

**Bazel:**
- Industry-proven (Google, Uber, Dropbox)
- Hermetic builds
- Remote caching
- Multi-language support
- Active community

**Alternatives Considered:**
- CMake: Too imperative, poor caching
- Meson: Limited platform support
- Buck2: Facebook-specific, less mature
- Native UE Build System: This document explains why not

---

## Timeline

**Current:** Proof-of-concept stage
**Q1 2026:** Phase 1.1-1.2 complete (Setup + Module parsing)
**Q2-Q3 2026:** Phase 1.3-1.4 (Compiler integration + Engine build)
**Q4 2026 - Q2 2027:** Phase 2 (UAT replacement)
**Q3 2027:** Phase 3 (Testing + 1.0 release)

**Realistic Estimate:** 18-24 months with 2-3 dedicated engineers

---

## Appendix: This Exact Moment

**What I'm doing right now:** Waiting 60-90 minutes for the entire Unreal Engine to rebuild (4,958 actions) just to recompile 2 dylib files with the correct C++ ABI.

**What I'd rather be doing:** Running `bazel build //Engine/Binaries/Mac:ShaderCompileWorker-Core` and waiting 30 seconds.

**Time wasted on today's bugs:**
- NullReferenceException debugging: 3 hours
- ShaderCompileWorker dyld error: 2-2.5 hours
- **Total: 5-5.5 hours**

**Time wasted on similar UAT/UBT bugs this year:** 45-50+ hours

**Why this project matters:** Those 50 hours could have built 10-15% of rules_unreal_engine.

**Concrete example of what Bazel gives us:**
- **UBT:** Rebuild 4,958 actions to fix 2 dylib files = 60-90 minutes
- **Bazel:** Rebuild 2 targets = 30 seconds
- **Time saved:** 98% faster

---

**Last Updated:** 2025-10-30
**Status:** Pre-alpha, actively motivated by production pain
