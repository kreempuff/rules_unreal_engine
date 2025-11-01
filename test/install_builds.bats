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

@test "install_builds: Installs Core BUILD.bazel" {
    run "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    [ "$status" -eq 0 ]
    [ -f "$TEST_UE_DIR/Engine/Source/Runtime/Core/BUILD.bazel" ]

    # Verify content
    grep -q "ue_module" "$TEST_UE_DIR/Engine/Source/Runtime/Core/BUILD.bazel"
    grep -q "name = \"Core\"" "$TEST_UE_DIR/Engine/Source/Runtime/Core/BUILD.bazel"
}

@test "install_builds: Installs TraceLog BUILD.bazel" {
    "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    [ -f "$TEST_UE_DIR/Engine/Source/Runtime/TraceLog/BUILD.bazel" ]
    grep -q "TraceLog" "$TEST_UE_DIR/Engine/Source/Runtime/TraceLog/BUILD.bazel"
}

@test "install_builds: Installs BuildSettings BUILD.bazel" {
    "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    [ -f "$TEST_UE_DIR/Engine/Source/Runtime/BuildSettings/BUILD.bazel" ]
    grep -q "BuildSettings" "$TEST_UE_DIR/Engine/Source/Runtime/BuildSettings/BUILD.bazel"
}

@test "install_builds: Installs AtomicQueue BUILD.bazel" {
    "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    [ -f "$TEST_UE_DIR/Engine/Source/ThirdParty/AtomicQueue/BUILD.bazel" ]
    grep -q "AtomicQueue" "$TEST_UE_DIR/Engine/Source/ThirdParty/AtomicQueue/BUILD.bazel"
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

@test "install_builds: All BUILD files have correct ue_module load" {
    "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    # Check all installed BUILD files load ue_module
    for build in "$TEST_UE_DIR"/Engine/Source/*/*/BUILD.bazel; do
        if [ -f "$build" ]; then
            grep -q '@rules_unreal_engine//bzl:module.bzl' "$build" || {
                echo "Missing ue_module load in: $build"
                return 1
            }
        fi
    done
}

@test "install_builds: Installed BUILD files are valid Starlark" {
    "$INSTALL_SCRIPT" "$TEST_UE_DIR"

    # Add minimal MODULE.bazel for validation
    cd "$TEST_UE_DIR"
    cat > MODULE.bazel << EOF
module(name = "test", version = "1.0.0")
bazel_dep(name = "rules_unreal_engine")
local_path_override(
    module_name = "rules_unreal_engine",
    path = "$PROJECT_ROOT",
)
bazel_dep(name = "platforms", version = "1.0.0")
EOF

    # Query should not fail (validates Starlark syntax)
    run bazel query //Engine/Source/Runtime/Core:all

    echo "Output: $output"
    [ "$status" -eq 0 ]
}
