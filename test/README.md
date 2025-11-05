# rules_unreal_engine Test Suite

This directory contains all tests for the rules_unreal_engine project, organized by test type.

## Test Categories

### verification/ - External Tool Behavior Tests
**Purpose:** Verify assumptions about external tools (UHT, UBT, dotnet, etc.)

**Examples:**
- `verification/uht/` - Verify UHT generates code correctly, no-ops gracefully, etc.

**When to add tests here:** Testing Epic's tools to validate our assumptions.

### unit/ - Our Tool Unit Tests
**Purpose:** Test our Go binaries, shell scripts, and utilities in isolation

**Examples:**
- `unit/gitdeps.bats` - Test gitDeps Go binary (printUrls, extract, etc.)
- `unit/install_builds.bats` - Test install_builds.sh script

**When to add tests here:** Testing rules_unreal_engine code without UE dependencies.

### module/ - ue_module Macro Tests
**Purpose:** Test ue_module BUILD files with shallow UE clone (like .test_ue)

**Examples:**
- `module/fixtures/` - Test module source files
- `module/ue_module.bats` - Test ue_module macro functionality
- `module/build_core.bats` - Test building Core module

**When to add tests here:** Testing BUILD file generation and compilation without full hermetic setup.

### integration/ - Full Build Integration Tests
**Purpose:** End-to-end tests using the hermetic repository rule

**Examples:**
- `integration/minimal/` - Minimal Bazel workspace using repo rule
- `integration/full_build/` - Full UE build from scratch

**When to add tests here:** Testing complete hermetic builds, game projects, etc.

## Running Tests

```bash
# Run all tests
./test/run_all.sh

# Run specific category
bats test/unit/*.bats
bats test/module/*.bats
bats test/verification/**/*.bats
bats test/integration/**/*.bats

# Run just fast tests (unit + verification)
just test-all

# Run all tests including slow integration tests
just test-all-slow
```

## Test Organization Principles

1. **Fast tests first** - unit and verification tests should be sub-second
2. **Isolated fixtures** - Each test category has its own test data
3. **Clear naming** - Test files and directories self-document their purpose
4. **Git history** - All files moved with `git mv` to preserve history
5. **Parallel safe** - Tests should not interfere with each other

## Adding New Tests

1. Choose the appropriate category (verification/unit/module/integration)
2. Create a descriptive subdirectory if needed
3. Write BATS tests following existing patterns
4. Update this README if adding a new test category
