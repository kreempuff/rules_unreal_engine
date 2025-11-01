#!/usr/bin/env bats
# Tests for building Core module from real UE
#
# Environment variables:
#   RUN_SLOW_TESTS=1  - Enable these tests (requires UE clone)
#   UE_GIT_URL        - UE git URL (default: https://github.com/EpicGames/UnrealEngine.git)
#   UE_BRANCH         - UE branch/tag (default: 5.5)

setup_file() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."

    # Clone UE once if RUN_SLOW_TESTS=1
    if [ -n "$RUN_SLOW_TESTS" ]; then
        export UE_CLONE_DIR="$BATS_TEST_TMPDIR/UnrealEngine"
        export UE_GIT_URL="${UE_GIT_URL:-https://github.com/EpicGames/UnrealEngine.git}"
        export UE_BRANCH="${UE_BRANCH:-5.5}"

        if [ ! -d "$UE_CLONE_DIR" ]; then
            echo "# Cloning UE once for Core build tests (5-10 minutes)..." >&3
            echo "# URL: $UE_GIT_URL" >&3
            echo "# Branch: $UE_BRANCH" >&3

            git clone \
                --depth 1 \
                --branch "$UE_BRANCH" \
                --single-branch \
                "$UE_GIT_URL" \
                "$UE_CLONE_DIR" || {
                rm -rf "$UE_CLONE_DIR"
                export UE_CLONE_FAILED=1
            }
        fi
    fi
}

teardown_file() {
    if [ -n "$UE_CLONE_DIR" ] && [ -d "$UE_CLONE_DIR" ]; then
        rm -rf "$UE_CLONE_DIR"
    fi
}

setup() {
    cd "$PROJECT_ROOT"

    # Reset UE clone before each test
    if [ -n "$UE_CLONE_DIR" ] && [ -d "$UE_CLONE_DIR" ]; then
        cd "$UE_CLONE_DIR"
        git reset --hard HEAD >/dev/null 2>&1
        git clean -fdx >/dev/null 2>&1
        cd "$PROJECT_ROOT"
    fi
}

@test "Core: Create minimal BUILD.bazel for Core module" {
    if [ -z "$RUN_SLOW_TESTS" ]; then
        skip "Slow test - set RUN_SLOW_TESTS=1"
    fi

    if [ -n "$UE_CLONE_FAILED" ]; then
        skip "UE clone failed"
    fi

    cd "$UE_CLONE_DIR"

    # Add MODULE.bazel
    cat > MODULE.bazel << EOF
module(name = "unreal_engine", version = "5.5.0")

bazel_dep(name = "rules_unreal_engine")
local_path_override(
    module_name = "rules_unreal_engine",
    path = "$PROJECT_ROOT",
)
EOF

    # Create minimal BUILD.bazel for Core (no dependencies yet)
    cat > Engine/Source/Runtime/Core/BUILD.bazel << 'EOF'
load("@rules_unreal_engine//bzl:module.bzl", "ue_module")

ue_module(
    name = "Core",
    module_type = "Runtime",
    # Sources auto-discovered from Private/**/*.cpp
    # Headers auto-discovered from Public/**/*.h
    visibility = ["//visibility:public"],
)
EOF

    # Try to build Core
    run bazel build //Engine/Source/Runtime/Core:Core

    echo "Output: $output"
    echo "Status: $status"

    # We expect this to fail with missing dependencies
    # Just capture the errors to understand what's needed
    cd "$PROJECT_ROOT"

    # Don't assert success - we expect failures
    # This test is for discovery, not validation
    true
}

@test "Core: Identify missing dependencies from build errors" {
    skip "TODO: Parse errors from previous test to create dependency BUILD files"

    # This test should:
    # 1. Parse compile errors from Core build
    # 2. Identify missing headers (HAL/Platform.h, etc.)
    # 3. Map headers to modules (Core/Public/HAL → Core)
    # 4. Generate BUILD files for dependencies
}
