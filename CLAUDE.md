# rules_unreal_engine - Project Context

## Development Session Tracking

**IMPORTANT: Use CURRENT_WORK.md for Active Debugging**

When working on complex debugging sessions that span multiple conversations:
1. Create/update `CURRENT_WORK.md` with:
   - Problem statement
   - What we've tried
   - Current theories
   - Next debugging steps
   - Relevant code locations
2. Commit to branch (not to main - it's work-in-progress notes)
3. Next session: Read CURRENT_WORK.md first to resume context

**Why:** Complex issues (like UHT file generation) need persistent state across sessions. Don't rely on conversation history alone.

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

**Note:** Development happens in sibling directories:
```
workspace/
├── rules_unreal_engine/  # This project
└── UnrealEngine/         # Your UE clone
```

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
     Referenced from: <...> ShaderCompileWorker-Core.dylib
     Expected in:     <...> libtbb.dylib

   LogShaderCompilers: Error: ShaderCompileWorker terminated unexpectedly!
   LogShaderCompilers: Error: Falling back to directly compiling which will be very slow.
   ```

3. **Root Cause: C++ ABI Compatibility**
   - ShaderCompileWorker-Core.dylib compiled with older Xcode version
   - libtbb.dylib has different C++ standard library ABI
   - Symbol `std::length_error` destructor missing
   - Xcode version changes caused mismatch

4. **The "Solution": Rebuild the Entire Engine**
   ```bash
   cd ../UnrealEngine
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

**Note on File Paths:**
- When examples show file paths, assume UnrealEngine/ is a sibling of rules_unreal_engine/
- Example structure: `workspace/rules_unreal_engine/` and `workspace/UnrealEngine/`

**Example Debugging Session (Historical):**
- Branch: `ops/build-cook-package` (game project)
- Files Modified in UnrealEngine clone:
  - `Engine/Source/Programs/AutomationTool/Program.cs` (lines 515-525)
  - `Engine/Source/Programs/AutomationTool/Gauntlet/Gauntlet.Automation.csproj` (line 14)
  - `Engine/Source/Programs/AutomationTool/AutomationUtils/AutomationUtils.Automation.csproj` (line 14)

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

### Development Workflow

**IMPORTANT: Follow the iterative development workflow for adding new UE modules**

See **[docs/DEVELOPMENT_WORKFLOW.md](docs/DEVELOPMENT_WORKFLOW.md)** for the complete workflow:
1. Create BUILD files in `ue_modules/` directory (project root)
2. Install to test repo with `just install .test_ue/UnrealEngine`
3. Test build in test repo
4. Commit when successful
5. Repeat for next module

**Key points:**
- Always create BUILD files in the project's `ue_modules/` directory
- Test repo (`.test_ue/UnrealEngine`) is for validation only
- Install script copies files (not symlinks), fast iteration
- Only commit BUILD files that successfully build

### Tracking Blockers

**IMPORTANT: Update docs/BLOCKERS.md whenever you skip files or modules**

When you exclude files from a BUILD.bazel (using `exclude_srcs`) or skip a module entirely:
1. **Document it immediately** in `docs/BLOCKERS.md`
2. **Explain the blocker** (missing module, missing header, etc.)
3. **Note the priority** (High/Medium/Low)
4. **Suggest resolution** (what module/fix is needed)

**Examples of when to update BLOCKERS.md:**
- Adding `exclude_srcs = ["Private/Foo.cpp"]` to a BUILD file
- Discovering a module needs another module you haven't built yet
- Finding a file needs a third-party library that doesn't exist
- Encountering platform-specific issues

**Why this matters:**
- Prevents forgetting about skipped work
- Helps prioritize what to build next
- Provides clear path forward when revisiting blockers
- Documents technical debt for the project

See **[docs/BLOCKERS.md](docs/BLOCKERS.md)** for current list of all blockers.

### Module Documentation

**IMPORTANT: Document BUILD file quirks in per-module READMEs**

When creating BUILD.bazel files for UE modules, create a README.md in the same directory documenting:
- Build quirks (unity builds, special includes, platform-specific issues)
- Dependencies and why they're needed
- Complexity notes and current status
- Known issues and blockers

**Example:** `ue_modules/Runtime/Core/README.md` documents:
- Unity build pattern (lz4.cpp)
- Objective-C++ requirement on Mac
- Circular dependency with TraceLog
- Platform-specific source files
- All discovered build issues

**Why:** Future contributors need context for non-obvious BUILD patterns without digging through commit history.

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
- Write BUILD files directly to ../UnrealEngine/ (sibling directory)
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

1. ✅ ~~Phase 1.1: Setup.sh replacement (gitDeps.go)~~ **DONE** (2025-10-30)
2. ✅ ~~Phase 1.2: `ue_module` Bazel rule (replaces .Build.cs)~~ **DONE** (2025-11-01)
   - ✅ Successfully built real UE module (AtomicQueue) with Bazel!
   - ✅ 13 BATS tests passing (12 fast + 1 E2E)
3. **Active:** Phase 1.3: Compiler Toolchain Integration
   - Week 1-2: Extract and implement UE compiler flags
   - Week 3-4: Build Core module incrementally
   - Week 5-8: UnrealHeaderTool (UHT) integration
4. Document architecture decisions in `docs/decisions/`

---

## Phase 1.3: Compiler Toolchain Integration (MOSTLY COMPLETE)

**Started:** 2025-11-01
**Status:** ~60% complete - Compiler integration done, Core dependencies in progress

### Major Achievements ✅

- ✅ Full UE compiler integration (C++20, all defines, platform-specific)
- ✅ **C/C++ file separation** (detects .c vs .cpp, applies correct flags)
- ✅ ue_modules/ repository architecture (6 modules converted)
- ✅ **Circular dependency SOLVED** (Core_headers splitting)
- ✅ **Module dependency builds working** (Core → TraceLog → Core_headers)
- ✅ TraceLog compiles (9/21 files, blocked on Objective-C++)
- ✅ Persistent .test_ue/ test infrastructure
- ✅ LOCAL_DEV flag for easy testing
- ✅ Justfile + TEST_MODULES filter for convenient testing

### Remaining Work

See **[docs/PLAN.md](docs/PLAN.md)** for detailed Phase 1.3 task list.

**Next priorities:**
- Add LZ4 third-party dependency to TraceLog
- Build remaining Core dependencies
- Get Core to fully compile
- UHT integration (code generation)

### Note on Precompiled Dependencies

Some UE modules (e.g., OodleDataCompression) currently link against precompiled libraries (`.a`, `.lib` files) provided by Epic or third-party vendors. While these work for now, the long-term goal is to compile them from source with Bazel for:
- Full hermetic builds
- Cross-platform consistency
- Better caching and incremental builds
- Elimination of binary blob dependencies

**Action item:** Track precompiled modules as we encounter them for future conversion to source builds.

### Quick Start

**IMPORTANT: Always use the `.test_ue/` test repository for development work. Never modify the main UE installation directly.**

```bash
# Setup test UE repository (first time only)
just setup-test-ue         # Clones from ../UnrealEngine (sibling directory)

# Install BUILD files to test repo
just install .test_ue/UnrealEngine

# Build UE modules in test repo
cd .test_ue/UnrealEngine
bazel build //Engine/Source/ThirdParty/AtomicQueue  # ✅ Works!
bazel build //Engine/Source/Runtime/TraceLog        # ✅ Compiles (needs LZ4)
bazel build //Engine/Source/Runtime/Core            # 🔨 In progress

# Clean test repo and start fresh
just clean-test-ue
just setup-test-ue

# Run tests
just test-all              # Fast tests
just test-all-slow         # Including E2E
```

### Development Workflow

**When starting new work, always follow this process:**

```bash
# 1. Hard reset test UE directory to clean state
just reset-test-ue         # Removes all uncommitted changes and BUILD files

# 2. Create new feature branch
git checkout main
git pull
git checkout -b feat/phase1.3-descriptive-name

# 3. Install BUILD files and start work
just install .test_ue/UnrealEngine
cd .test_ue/UnrealEngine
bazel build //Engine/Source/Runtime/Core
```

**Why this workflow?**
- **Clean state**: Prevents cross-contamination between work sessions
- **Isolated changes**: Each feature gets its own branch for clean git history
- **Easy rollback**: Failed experiments can be discarded without affecting other work
- **Consistent testing**: Always start from a known-good baseline

**Commands:**
- `just reset-test-ue` - Git clean + hard reset (keeps the clone)
- `just clean-test-ue` - Deletes entire test repo (for full reset)
- `just setup-test-ue` - Initial clone from main UE installation

### Pull Request Workflow

**When merging PRs:**

```bash
# Check PR status
gh pr list --head <branch-name>

# Merge with regular merge (preserves commit history)
gh pr merge <pr-number> --merge

# Verify merge
gh pr view <pr-number> --json state,mergedAt,title

# Switch back to main and pull
git checkout main && git pull
```

**Merge Strategy:**
- **Use `--merge`** for feature branches (preserves full commit history)
- **Avoid `--squash`** unless explicitly needed (loses commit granularity)
- **Never use `--auto`** for automatic merging (requires explicit action)

**After merging:**
- Always switch back to main and pull latest changes
- Delete the feature branch locally: `git branch -d <branch-name>`
- Continue work from updated main branch

**Commit Message Requirements:**
- **DO NOT** add Claude Code attributions (e.g., "🤖 Generated with Claude Code")
- **DO NOT** add Co-Authored-By: Claude lines
- Keep commit messages clean and focused on the actual changes
- Follow conventional commit format: `type: description`

### References

- **Task List:** `docs/PLAN.md`
- **Compiler Flags:** `docs/UE_COMPILER_FLAGS.md`
- **Module Status:** `ue_modules/README.md`
- **Test Infrastructure:** `.test_ue/README.md`
- **Quick Commands:** `justfile`

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