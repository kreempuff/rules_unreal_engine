#!/usr/bin/env bats
# Tests for ue_module Bazel rule

setup_file() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
}

setup() {
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

@test "ue_module: E2E - Clone real UE and build AtomicQueue (header-only)" {
    # Skip unless RUN_SLOW_TESTS=1
    if [ -z "$RUN_SLOW_TESTS" ]; then
        skip "Slow test - set RUN_SLOW_TESTS=1 to run (takes 5-10 minutes)"
    fi

    # Create temp directory for UE clone
    UE_CLONE_DIR="$(mktemp -d)"
    echo "Cloning UE to: $UE_CLONE_DIR"

    # Clone minimal UE
    # Using depth 1 for speed
    git clone \
        --depth 1 \
        --branch 5.5 \
        --single-branch \
        https://github.com/EpicGames/UnrealEngine.git \
        "$UE_CLONE_DIR" || {
        # If clone fails (requires auth), skip test
        rm -rf "$UE_CLONE_DIR"
        skip "Cannot clone UE (requires Epic GitHub access)"
    }

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

    # Create BUILD.bazel for AtomicQueue (header-only, no dependencies!)
    cat > Engine/Source/ThirdParty/AtomicQueue/BUILD.bazel << 'EOF'
load("@rules_unreal_engine//bzl:module.bzl", "ue_module")

ue_module(
    name = "AtomicQueue",
    module_type = "ThirdParty",
    # Header-only module
    srcs = [],
    hdrs = ["AtomicQueue.h"],
    visibility = ["//visibility:public"],
)
EOF

    # Build the module (header-only, should be fast)
    run bazel build //Engine/Source/ThirdParty/AtomicQueue:AtomicQueue

    echo "Output: $output"

    # Cleanup
    cd /
    rm -rf "$UE_CLONE_DIR"

    # Assert build succeeded
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Build completed successfully" ]]
}
