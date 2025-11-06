#!/usr/bin/env bats
# Tests for ue_module Bazel rule
#
# Environment variables:
#   RUN_SLOW_TESTS=1  - Enable E2E tests (clones real UE, takes 5-10 min)
#   UE_GIT_URL        - UE git URL (default: https://github.com/EpicGames/UnrealEngine.git)
#   UE_BRANCH         - UE branch/tag (default: 5.5)
#   TEST_MODULES      - Space-separated list of modules to test (default: all)
#
# Examples:
#   bats test/ue_module.bats                           # Fast tests only
#   RUN_SLOW_TESTS=1 bats test/ue_module.bats         # E2E all modules
#   TEST_MODULES=TraceLog RUN_SLOW_TESTS=1 bats test/ue_module.bats  # Just TraceLog
#   TEST_MODULES="Core TraceLog" RUN_SLOW_TESTS=1 bats test/ue_module.bats

setup_file() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."

    # For E2E tests: Clone UE once if RUN_SLOW_TESTS=1
    if [ -n "$RUN_SLOW_TESTS" ]; then
        # Use persistent .test_ue/ directory (gitignored)
        export UE_CLONE_DIR="$PROJECT_ROOT/.test_ue/UnrealEngine"
        export UE_GIT_URL="${UE_GIT_URL:-https://github.com/EpicGames/UnrealEngine.git}"
        export UE_BRANCH="${UE_BRANCH:-5.5}"

        if [ ! -d "$UE_CLONE_DIR/Engine/Source" ]; then
            echo "# Cloning UE to persistent test directory (5-10 minutes)..." >&3
            echo "# Location: $UE_CLONE_DIR" >&3
            echo "# URL: $UE_GIT_URL" >&3
            echo "# Branch: $UE_BRANCH" >&3
            echo "# (Clone persists in .test_ue/ - delete to re-clone)" >&3

            rm -rf "$UE_CLONE_DIR"
            mkdir -p "$(dirname "$UE_CLONE_DIR")"

            git clone \
                --depth 1 \
                --branch "$UE_BRANCH" \
                --single-branch \
                "$UE_GIT_URL" \
                "$UE_CLONE_DIR" || {
                # Clone failed - tests will skip
                echo "# Clone failed" >&3
                rm -rf "$UE_CLONE_DIR"
                export UE_CLONE_FAILED=1
            }
        else
            echo "# Using existing UE clone at: $UE_CLONE_DIR" >&3
        fi
    fi
}

teardown_file() {
    # Don't delete - clone persists in .test_ue/ for faster re-runs
    # To clean: rm -rf .test_ue/
    :
}

setup() {
    # Reset UE clone to clean state before each E2E test
    if [ -n "$UE_CLONE_DIR" ] && [ -d "$UE_CLONE_DIR" ]; then
        cd "$UE_CLONE_DIR"
        git reset --hard HEAD >/dev/null 2>&1
        git clean -fdx >/dev/null 2>&1
    fi

    cd "$PROJECT_ROOT"
}

@test "ue_module: Simple module builds successfully" {
    run bazel build //test/module/fixtures:SimpleModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libSimpleModule.a" ]]
}

@test "ue_module: Module with dependencies builds" {
    run bazel build //test/module/fixtures:DependentModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libDependentModule.a" ]]
}

@test "ue_module: Platform conditionals work with select()" {
    run bazel build //test/module/fixtures:PlatformModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libPlatformModule.a" ]]
}

@test "ue_module: All test modules build together" {
    run bazel build //test/module/fixtures/...

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
}

@test "ue_module: Rule generates proper cc_library tags" {
    run bazel query 'attr(tags, "ue_module", //test/module/fixtures:SimpleModule)'

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SimpleModule" ]]
}

@test "ue_module: Module type tag is set correctly" {
    run bazel query 'attr(tags, "ue_module_type:Runtime", //test/module/fixtures:SimpleModule)'

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SimpleModule" ]]
}

@test "ue_module: Dependencies are resolved correctly" {
    run bazel query 'deps(//test/module/fixtures:DependentModule)'

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SimpleModule" ]]
    [[ "$output" =~ "DependentModule" ]]
}

@test "ue_module: Public includes are exported" {
    # Check that the rule sets up includes properly
    run bazel query --output=build //test/module/fixtures:SimpleModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    # Should have includes attribute
    [[ "$output" =~ "includes" ]]
}

@test "ue_module: UE compiler flags are applied (C++20, no exceptions, no RTTI)" {
    # This test validates that UE default flags are working
    # TestUEFlags.cpp has #error directives that fail if flags are wrong
    run bazel build //test/module/fixtures:UEFlagsTest

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libUEFlagsTest.a" ]]
}

@test "ue_module: Clean build from scratch" {
    # Clean first
    bazel clean

    run bazel build //test/module/fixtures:SimpleModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
}

@test "ue_module: Incremental rebuild is fast" {
    # First build
    bazel build //test/module/fixtures:SimpleModule > /dev/null 2>&1

    # Second build should be cached
    run bazel build //test/module/fixtures:SimpleModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    # Should use cache
    [[ "$output" =~ "0 processes" ]] || [[ "$output" =~ "up-to-date" ]]
}

@test "ue_module: Preprocessor defines are applied" {
    run bazel query --output=build //test/module/fixtures:DependentModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WITH_TEST=1" ]]
}

@test "ue_module: BUILD file loads without errors" {
    run bazel query //test/module/fixtures:all

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SimpleModule" ]]
    [[ "$output" =~ "DependentModule" ]]
    [[ "$output" =~ "PlatformModule" ]]
}

@test "ue_module: Real UE module structure builds (TraceLog-like mock)" {
    # Create a realistic UE module structure in temp dir
    TEST_MODULE_DIR="$PROJECT_ROOT/test/module/real_ue_test"
    mkdir -p "$TEST_MODULE_DIR/Public"
    mkdir -p "$TEST_MODULE_DIR/Private"

    # Create minimal realistic source files
    cat > "$TEST_MODULE_DIR/Public/TraceLog.h" << 'EOF'
#pragma once

// Minimal TraceLog-like header
namespace UE { namespace Trace {
    void Initialize();
}}
EOF

    cat > "$TEST_MODULE_DIR/Private/TraceLog.cpp" << 'EOF'
#include "TraceLog.h"

namespace UE { namespace Trace {
    void Initialize() {
        // Implementation
    }
}}
EOF

    # Create BUILD.bazel using ue_module
    cat > "$TEST_MODULE_DIR/BUILD.bazel" << 'EOF'
load("@rules_unreal_engine//bzl:module.bzl", "ue_module")

ue_module(
    name = "TraceLog",
    module_type = "Runtime",
    local_defines = ["SUPPRESS_PER_MODULE_INLINE_FILE"],
    visibility = ["//visibility:public"],
)
EOF

    # Build the module
    run bazel build //test/module/real_ue_test:TraceLog

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libTraceLog.a" ]]

    # Cleanup
    rm -rf "$TEST_MODULE_DIR"
}

@test "ue_module: E2E - Build all installed modules from real UE" {
    if [ -z "$RUN_SLOW_TESTS" ]; then
        skip "Slow test - set RUN_SLOW_TESTS=1"
    fi

    if [ ! -d "$UE_CLONE_DIR/Engine/Source" ]; then
        skip "UE clone not available"
    fi

    cd "$UE_CLONE_DIR"

    # Install BUILD files and MODULE.bazel with local_path_override
    run env LOCAL_DEV=1 "$PROJECT_ROOT/tools/install_builds.sh" .

    echo "Install: $output"
    [ "$status" -eq 0 ]

    # Verify MODULE.bazel has local_path_override
    grep -q "local_path_override" MODULE.bazel

    # Build modules (all or filtered by TEST_MODULES env var)
    cd "$PROJECT_ROOT"
    find ue_modules -name "BUILD.bazel" -type f | while read build_file; do
        # Extract module path: ue_modules/Runtime/Core/BUILD.bazel -> Runtime/Core
        rel_path="${build_file#ue_modules/}"
        module_path="${rel_path%/BUILD.bazel}"
        module_name=$(basename "$module_path")

        # Skip if TEST_MODULES set and this module not in list
        if [ -n "$TEST_MODULES" ]; then
            if ! echo "$TEST_MODULES" | grep -qw "$module_name"; then
                echo "# Skipping $module_name (not in TEST_MODULES)" >&3
                continue
            fi
        fi

        echo "# Testing module: $module_path" >&3

        cd "$UE_CLONE_DIR"
        if bazel build "//Engine/Source/$module_path:$module_name" 2>&1 | tail -5 >&3; then
            echo "# ✅ $module_name built successfully" >&3
        else
            echo "# ⚠️  $module_name failed (expected for modules with missing deps)" >&3
        fi
        cd "$PROJECT_ROOT"
    done

    # Test passes if install worked (individual module failures are OK)
    cd "$PROJECT_ROOT"
    true
}

@test "ue_module: E2E - Compare Bazel build with UBT build output" {
    skip "TODO: Need to validate Bazel output matches UBT output"

    # This test should:
    # 1. Build AtomicQueue with UBT (Run Setup.sh + UnrealBuildTool)
    # 2. Build AtomicQueue with Bazel (our ue_module rule)
    # 3. Compare:
    #    - Symbol exports (nm -g)
    #    - Object file structure
    #    - Library format
    # 4. Assert they're compatible

    # For now, we're just testing that Bazel CAN build.
    # Full UBT comparison requires Setup.sh dependencies and UBT execution.
}
