#!/usr/bin/env bats
# Tests for tools/install_builds.sh

setup_file() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
    export INSTALL_SCRIPT="$PROJECT_ROOT/tools/install_builds.sh"
}

setup() {
    # Create temp UE-like directory for each test
    export TEST_UE_DIR="$(mktemp -d)"
    mkdir -p "$TEST_UE_DIR/Engine/Source/Runtime/Core"
    mkdir -p "$TEST_UE_DIR/Engine/Source/Runtime/TraceLog"
    mkdir -p "$TEST_UE_DIR/Engine/Source/Runtime/BuildSettings"
    mkdir -p "$TEST_UE_DIR/Engine/Source/ThirdParty/AtomicQueue"
}

teardown() {
    rm -rf "$TEST_UE_DIR"
}

@test "install_builds: Script exists and is executable" {
    [ -f "$INSTALL_SCRIPT" ]
    [ -x "$INSTALL_SCRIPT" ]
}

@test "install_builds: Shows usage when no arguments" {
    run "$INSTALL_SCRIPT"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "install_builds: Fails with invalid UE path" {
    run "$INSTALL_SCRIPT" /nonexistent/path

    [ "$status" -eq 1 ]
    [[ "$output" =~ "doesn't look like an Unreal Engine directory" ]]
}

@test "install_builds: Dry run shows what would be copied" {
    run "$INSTALL_SCRIPT" "$TEST_UE_DIR" --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" =~ "[DRY RUN]" ]]
    [[ "$output" =~ "Core/BUILD.bazel" ]]
    [[ "$output" =~ "TraceLog/BUILD.bazel" ]]
    [[ "$output" =~ "Dry run complete" ]]
}

@test "install_builds: Dry run does not create files" {
    "$INSTALL_SCRIPT" "$TEST_UE_DIR" --dry-run

    # BUILD files should NOT exist after dry run
    [ ! -f "$TEST_UE_DIR/Engine/Source/Runtime/Core/BUILD.bazel" ]
    [ ! -f "$TEST_UE_DIR/Engine/Source/Runtime/TraceLog/BUILD.bazel" ]
}

@test "install_builds: Installs all discovered BUILD files" {
    run "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    [ "$status" -eq 0 ]

    # Dynamically check all BUILD files from ue_modules/ were installed
    cd "$PROJECT_ROOT"

    # Count expected modules
    expected_count=$(find ue_modules -name "BUILD.bazel" -type f | wc -l | tr -d ' ')
    installed_count=0

    find ue_modules -name "BUILD.bazel" -type f | while read build_file; do
        # Extract module path
        rel_path="${build_file#ue_modules/}"
        module_path="${rel_path%/BUILD.bazel}"

        dest="$TEST_UE_DIR/Engine/Source/$module_path/BUILD.bazel"

        # Verify it was installed
        if [ ! -f "$dest" ]; then
            echo "Missing: Engine/Source/$module_path/BUILD.bazel"
            exit 1
        fi

        # Verify it has ue_module
        if ! grep -q "ue_module" "$dest"; then
            echo "Invalid BUILD file (missing ue_module): $dest"
            exit 1
        fi

        installed_count=$((installed_count + 1))
    done

    # Currently we have 4 modules
    [ "$expected_count" -ge 4 ]
}

@test "install_builds: All installed BUILD files have valid syntax" {
    "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    # Check each installed BUILD file
    cd "$PROJECT_ROOT"
    find ue_modules -name "BUILD.bazel" -type f | while read build_file; do
        rel_path="${build_file#ue_modules/}"
        module_path="${rel_path%/BUILD.bazel}"
        dest="$TEST_UE_DIR/Engine/Source/$module_path/BUILD.bazel"

        # Verify ue_module load statement
        grep -q '@rules_unreal_engine//bzl:module.bzl' "$dest" || {
            echo "Missing ue_module load in: $dest"
            return 1
        }
    done
}

@test "install_builds: Creates MODULE.bazel if missing" {
    "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    [ -f "$TEST_UE_DIR/MODULE.bazel" ]
    grep -q "module(name = \"unreal_engine\"" "$TEST_UE_DIR/MODULE.bazel"
    grep -q "bazel_dep(name = \"rules_unreal_engine\"" "$TEST_UE_DIR/MODULE.bazel"
}

@test "install_builds: Skips MODULE.bazel if exists" {
    # Create existing MODULE.bazel
    echo "# Custom MODULE.bazel" > "$TEST_UE_DIR/MODULE.bazel"

    run "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Skipping MODULE.bazel (already exists)" ]]

    # Should not overwrite
    grep -q "# Custom MODULE.bazel" "$TEST_UE_DIR/MODULE.bazel"
}

@test "install_builds: Counts correct number of modules installed" {
    run "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    [ "$status" -eq 0 ]

    # Count expected vs installed
    expected=$(find "$PROJECT_ROOT/ue_modules" -name "BUILD.bazel" -type f | wc -l | tr -d ' ')
    installed=$(find "$TEST_UE_DIR/Engine/Source" -name "BUILD.bazel" -type f | wc -l | tr -d ' ')

    echo "Expected: $expected, Installed: $installed"
    [ "$installed" -eq "$expected" ]
}
