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
        # Use persistent .test_ue/ directory for faster iteration
        export UE_CLONE_DIR="$PROJECT_ROOT/.test_ue/UnrealEngine"
        export UE_GIT_URL="${UE_GIT_URL:-https://github.com/EpicGames/UnrealEngine.git}"
        export UE_BRANCH="${UE_BRANCH:-5.5}"

        if [ ! -d "$UE_CLONE_DIR/Engine/Source" ]; then
            echo "# Cloning UE to persistent test directory (5-10 minutes)..." >&3
            echo "# Location: $UE_CLONE_DIR" >&3
            echo "# URL: $UE_GIT_URL" >&3
            echo "# Branch: $UE_BRANCH" >&3
            echo "# (This clone persists in .test_ue/ for faster re-runs)" >&3

            rm -rf "$UE_CLONE_DIR"
            mkdir -p "$(dirname "$UE_CLONE_DIR")"

            git clone \
                --depth 1 \
                --branch "$UE_BRANCH" \
                --single-branch \
                "$UE_GIT_URL" \
                "$UE_CLONE_DIR" || {
                echo "# Clone failed with exit code: $?" >&3
                rm -rf "$UE_CLONE_DIR"
                export UE_CLONE_FAILED=1
            }
        else
            echo "# Using existing UE clone at: $UE_CLONE_DIR" >&3
        fi
    fi
}

teardown_file() {
    # Don't delete UE clone - it persists in .test_ue/ for reuse
    # To clean: rm -rf .test_ue/
    :
}

setup() {
    # Reset UE clone to clean state before each test
    if [ -n "$UE_CLONE_DIR" ] && [ -d "$UE_CLONE_DIR" ]; then
        cd "$UE_CLONE_DIR"
        git reset --hard HEAD >/dev/null 2>&1
        git clean -fdx >/dev/null 2>&1
    fi

    cd "$PROJECT_ROOT"
}

@test "Core: Create minimal BUILD.bazel for Core module" {
    if [ -z "$RUN_SLOW_TESTS" ]; then
        skip "Slow test - set RUN_SLOW_TESTS=1"
    fi

    echo "# Debug: UE_CLONE_DIR=$UE_CLONE_DIR" >&3
    echo "# Debug: BATS_TEST_TMPDIR=$BATS_TEST_TMPDIR" >&3

    # Check if UE clone actually exists and has Engine directory
    if [ ! -d "$UE_CLONE_DIR/Engine/Source" ]; then
        echo "# Debug: Directory check failed" >&3
        echo "# Debug: Listing $UE_CLONE_DIR:" >&3
        ls -la "$UE_CLONE_DIR" 2>&1 >&3 || echo "# Directory doesn't exist" >&3
        skip "UE clone not available (Engine/Source not found at $UE_CLONE_DIR)"
    fi

    cd "$UE_CLONE_DIR"

    # Install BUILD files and MODULE.bazel with local_path_override
    run env LOCAL_DEV=1 "$PROJECT_ROOT/tools/install_builds.sh" .

    echo "Install: $output"
    [ "$status" -eq 0 ]

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
