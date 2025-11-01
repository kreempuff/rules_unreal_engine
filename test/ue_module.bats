#!/usr/bin/env bats
# Tests for ue_module Bazel rule
#
# Environment variables:
#   RUN_SLOW_TESTS=1  - Enable E2E tests (clones real UE, takes 5-10 min)
#   UE_GIT_URL        - UE git URL (default: https://github.com/EpicGames/UnrealEngine.git)
#   UE_BRANCH         - UE branch/tag (default: 5.5)
#
# Examples:
#   bats test/ue_module.bats                           # Fast tests only
#   RUN_SLOW_TESTS=1 bats test/ue_module.bats         # Include E2E tests
#   UE_BRANCH=5.4 RUN_SLOW_TESTS=1 bats test/ue_module.bats  # Test with UE 5.4

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
    run bazel build //test/module_rule_test:SimpleModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libSimpleModule.a" ]]
}

@test "ue_module: Module with dependencies builds" {
    run bazel build //test/module_rule_test:DependentModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libDependentModule.a" ]]
}

@test "ue_module: Platform conditionals work with select()" {
    run bazel build //test/module_rule_test:PlatformModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libPlatformModule.a" ]]
}

@test "ue_module: All test modules build together" {
    run bazel build //test/module_rule_test/...

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
}

@test "ue_module: Rule generates proper cc_library tags" {
    run bazel query 'attr(tags, "ue_module", //test/module_rule_test:SimpleModule)'

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SimpleModule" ]]
}

@test "ue_module: Module type tag is set correctly" {
    run bazel query 'attr(tags, "ue_module_type:Runtime", //test/module_rule_test:SimpleModule)'

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SimpleModule" ]]
}

@test "ue_module: Dependencies are resolved correctly" {
    run bazel query 'deps(//test/module_rule_test:DependentModule)'

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SimpleModule" ]]
    [[ "$output" =~ "DependentModule" ]]
}

@test "ue_module: Public includes are exported" {
    # Check that the rule sets up includes properly
    run bazel query --output=build //test/module_rule_test:SimpleModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    # Should have includes attribute
    [[ "$output" =~ "includes" ]]
}

@test "ue_module: UE compiler flags are applied (C++20, no exceptions, no RTTI)" {
    # This test validates that UE default flags are working
    # TestUEFlags.cpp has #error directives that fail if flags are wrong
    run bazel build //test/module_rule_test:UEFlagsTest

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libUEFlagsTest.a" ]]
}

@test "ue_module: Clean build from scratch" {
    # Clean first
    bazel clean

    run bazel build //test/module_rule_test:SimpleModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
}

@test "ue_module: Incremental rebuild is fast" {
    # First build
    bazel build //test/module_rule_test:SimpleModule > /dev/null 2>&1

    # Second build should be cached
    run bazel build //test/module_rule_test:SimpleModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    # Should use cache
    [[ "$output" =~ "0 processes" ]] || [[ "$output" =~ "up-to-date" ]]
}

@test "ue_module: Preprocessor defines are applied" {
    run bazel query --output=build //test/module_rule_test:DependentModule

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WITH_TEST=1" ]]
}

@test "ue_module: BUILD file loads without errors" {
    run bazel query //test/module_rule_test:all

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SimpleModule" ]]
    [[ "$output" =~ "DependentModule" ]]
    [[ "$output" =~ "PlatformModule" ]]
}

@test "ue_module: Real UE module structure builds (TraceLog-like mock)" {
    # Create a realistic UE module structure in temp dir
    TEST_MODULE_DIR="$PROJECT_ROOT/test/ue_real_module_test"
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
    run bazel build //test/ue_real_module_test:TraceLog

    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
    [[ "$output" =~ "libTraceLog.a" ]]

    # Cleanup
    rm -rf "$TEST_MODULE_DIR"
}

@test "ue_module: E2E - Build AtomicQueue from real UE (header-only)" {
    # Skip unless RUN_SLOW_TESTS=1
    if [ -z "$RUN_SLOW_TESTS" ]; then
        skip "Slow test - set RUN_SLOW_TESTS=1 to run (clones UE once)"
    fi

    # Skip if clone failed
    if [ -n "$UE_CLONE_FAILED" ]; then
        skip "UE clone failed (requires Epic GitHub access)"
    fi

    # Use shared UE clone (setup_file cloned it once)
    cd "$UE_CLONE_DIR"

    # Add rules_unreal_engine dependency
    cat > MODULE.bazel << EOF
module(name = "unreal_engine", version = "5.5.0")

bazel_dep(name = "rules_unreal_engine")
local_path_override(
    module_name = "rules_unreal_engine",
    path = "$PROJECT_ROOT",
)
EOF

    # Install BUILD files from ue_modules/
    cp "$PROJECT_ROOT/ue_modules/ThirdParty/AtomicQueue/BUILD.bazel" \
       Engine/Source/ThirdParty/AtomicQueue/BUILD.bazel

    # Build the module (header-only, should be fast)
    run bazel build //Engine/Source/ThirdParty/AtomicQueue:AtomicQueue

    echo "Output: $output"

    # Return to project root (teardown will clean UE_CLONE_DIR)
    cd "$PROJECT_ROOT"

    # Assert build succeeded
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
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
