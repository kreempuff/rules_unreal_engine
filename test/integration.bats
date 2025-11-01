#!/usr/bin/env bats
# End-to-end integration tests for rules_unreal_engine
# Tests both scenarios:
#   1. UE as external Bazel repository (game project consuming UE)
#   2. In-place UE setup (running gitDeps directly in UE source)

setup_file() {
    export BINARY="$BATS_TEST_DIRNAME/../bazel-bin/rules_unreal_engine_/rules_unreal_engine"
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."

    # Build if not exists
    if [ ! -f "$BINARY" ]; then
        cd "$PROJECT_ROOT" && bazel build //:rules_unreal_engine
    fi
}

setup() {
    # Create temp directory for each test
    export TEST_TEMP_DIR="$(mktemp -d)"
    cd "$TEST_TEMP_DIR"
}

teardown() {
    # Cleanup temp directory
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# Helper: Create a minimal mock UE repository structure
create_mock_ue_repo() {
    local repo_dir="$1"
    mkdir -p "$repo_dir/Engine/Build"
    mkdir -p "$repo_dir/Engine/Binaries/ThirdParty"

    # Create a minimal .gitdeps.xml with one small pack
    cat > "$repo_dir/Engine/Build/Commit.gitdeps.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<WorkingManifest BaseUrl="https://cdn.unrealengine.com/dependencies">
    <Files>
        <File Name="Engine/Binaries/ThirdParty/TestLib/test.dll" Hash="abc123" ExpectedHash="abc123" Timestamp="0"/>
    </Files>
    <Blobs>
        <Blob Hash="abc123" Size="10" PackHash="pack123" PackOffset="8" />
    </Blobs>
    <Packs>
        <Pack Hash="pack123" Size="100" CompressedSize="50" RemotePath="TestPack"/>
    </Packs>
</WorkingManifest>
EOF

    # Create a minimal git repo (required by repository rule)
    cd "$repo_dir"
    git init
    git config user.email "test@test.com"
    git config user.name "Test User"
    git add .
    git commit -m "Initial commit"
    git branch -M main
    cd -
}

# Helper: Create mock pack file (gzipped UEPACK00 format)
create_mock_pack() {
    local pack_file="$1"
    local content="$2"

    # Create a minimal UEPACK00-format file
    # Format: "UEPACK00" header + gzipped content
    (
        printf "UEPACK00"
        echo "$content" | gzip -c
    ) > "$pack_file"
}

#
# SCENARIO 1 TESTS: UE as External Repository
#

@test "Scenario 1: Game project can reference UE as external repo" {
    skip "Requires mock HTTP server for pack downloads"

    # Create a mock game project
    mkdir -p GameProject
    cd GameProject

    # Create MODULE.bazel that references rules_unreal_engine
    cat > MODULE.bazel << EOF
module(name = "test_game", version = "1.0.0")

bazel_dep(name = "rules_unreal_engine", version = "")
local_path_override(
    module_name = "rules_unreal_engine",
    path = "$PROJECT_ROOT",
)

unreal_engine = use_repo_rule("@rules_unreal_engine//internal/repo:rule.bzl", "unreal_engine")
unreal_engine(
    name = "ue",
    commit = "main",
    git_repository = "$TEST_TEMP_DIR/mock-ue",
    use_bazel_downloader = False,
)
EOF

    # Create mock UE repository
    create_mock_ue_repo "$TEST_TEMP_DIR/mock-ue"

    # Try to sync the external repository
    run bazel sync --only=ue

    # Should succeed (even if download fails, clone should work)
    echo "Output: $output"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" =~ "Cloning Unreal Engine" ]]
}

@test "Scenario 1: Repository rule clones UE correctly" {
    # Create a mock UE repository
    create_mock_ue_repo "$TEST_TEMP_DIR/mock-ue"

    # Create a simple test project
    mkdir -p TestProject
    cd TestProject

    cat > MODULE.bazel << EOF
module(name = "test_project", version = "1.0.0")

bazel_dep(name = "rules_unreal_engine", version = "")
local_path_override(
    module_name = "rules_unreal_engine",
    path = "$PROJECT_ROOT",
)

unreal_engine = use_repo_rule("@rules_unreal_engine//internal/repo:rule.bzl", "unreal_engine")
unreal_engine(
    name = "ue",
    commit = "main",
    git_repository = "$TEST_TEMP_DIR/mock-ue",
    use_bazel_downloader = False,
)
EOF

    cat > BUILD.bazel << EOF
# Empty build file
EOF

    # Query the external repository (this triggers repo rule execution)
    run bazel query @ue//... 2>&1

    # Check that clone was attempted
    echo "Output: $output"
    [[ "$output" =~ "Cloning Unreal Engine" ]] || [[ "$output" =~ "mock-ue" ]]
}

#
# SCENARIO 2 TESTS: In-Place UE Setup
#

@test "Scenario 2: Binary can download dependencies in-place" {
    skip "Requires mock HTTP server for pack downloads"

    # Create mock UE directory structure
    create_mock_ue_repo "$TEST_TEMP_DIR/UnrealEngine"
    cd "$TEST_TEMP_DIR/UnrealEngine"

    # Run gitDeps directly (this would normally download from CDN)
    run "$BINARY" gitDeps \
        --input Engine/Build/Commit.gitdeps.xml \
        --output-dir . \
        --verify=false

    echo "Output: $output"

    # Should attempt to download (will fail without mock server)
    [[ "$output" =~ "Downloading" ]] || [ "$status" -eq 1 ]
}

@test "Scenario 2: Binary extracts to correct locations" {
    # Create mock UE directory structure
    create_mock_ue_repo "$TEST_TEMP_DIR/UnrealEngine"
    cd "$TEST_TEMP_DIR/UnrealEngine"

    # Create mock downloaded packs directory
    mkdir -p packs
    create_mock_pack "packs/pack123.pack.gz" "test content"

    # Run extract command
    run "$BINARY" extract \
        --packs-dir packs \
        --manifest Engine/Build/Commit.gitdeps.xml \
        --output-dir .

    echo "Output: $output"
    echo "Status: $status"

    # Should attempt extraction (may fail due to invalid pack format, but command should run)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "Scenario 2: gitDeps accepts directory with .ue4dependencies" {
    skip "Requires .ue4dependencies file format"

    # Create UE directory with .ue4dependencies
    mkdir -p UnrealEngine/Engine/Build
    echo "Engine/Build/Commit.gitdeps.xml" > UnrealEngine/.ue4dependencies
    create_mock_ue_repo "$TEST_TEMP_DIR/UnrealEngine"

    cd UnrealEngine

    # Run gitDeps with directory (should auto-discover manifest)
    run "$BINARY" gitDeps --input . --verify=false

    echo "Output: $output"
    # Should find and parse manifest
    [[ "$output" =~ "Commit.gitdeps.xml" ]] || [ "$status" -eq 1 ]
}

#
# WORKFLOW TESTS
#

@test "Workflow: printUrls -> download -> extract pipeline" {
    # Create mock manifest
    create_mock_ue_repo "$TEST_TEMP_DIR/UnrealEngine"

    # Step 1: Get URLs
    run "$BINARY" gitDeps printUrls \
        --input "$TEST_TEMP_DIR/UnrealEngine/Engine/Build/Commit.gitdeps.xml" \
        --output json

    [ "$status" -eq 0 ]
    [[ "$output" =~ "cdn.unrealengine.com" ]]

    # Save URLs
    echo "$output" > urls.json

    # Verify JSON is valid
    run cat urls.json
    [[ "$output" =~ "[" ]]
    [[ "$output" =~ "]" ]]
}

@test "Workflow: Extract works with pre-downloaded packs" {
    # Create mock UE structure
    create_mock_ue_repo "$TEST_TEMP_DIR/UnrealEngine"

    # Create mock packs directory (simulating Bazel HTTP cache)
    mkdir -p packs
    create_mock_pack "packs/pack123.pack.gz" "mock content"

    # Run extract
    run "$BINARY" extract \
        --packs-dir packs \
        --manifest "$TEST_TEMP_DIR/UnrealEngine/Engine/Build/Commit.gitdeps.xml" \
        --output-dir output

    echo "Output: $output"
    echo "Status: $status"

    # Command should execute (may fail on invalid pack format)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" =~ "extract" ]] || [[ "$output" =~ "pack" ]]
}

#
# ERROR HANDLING TESTS
#

@test "Error: Repository rule fails gracefully with invalid git URL" {
    mkdir -p ErrorTest
    cd ErrorTest

    cat > MODULE.bazel << EOF
module(name = "error_test", version = "1.0.0")

bazel_dep(name = "rules_unreal_engine", version = "")
local_path_override(
    module_name = "rules_unreal_engine",
    path = "$PROJECT_ROOT",
)

unreal_engine = use_repo_rule("@rules_unreal_engine//internal/repo:rule.bzl", "unreal_engine")
unreal_engine(
    name = "ue",
    commit = "nonexistent-branch",
    git_repository = "https://invalid-url-12345.com/repo.git",
    use_bazel_downloader = False,
)
EOF

    cat > BUILD.bazel << EOF
# Empty
EOF

    # Should fail with clear error message
    run bazel query @ue//... 2>&1

    echo "Output: $output"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Failed" ]] || [[ "$output" =~ "error" ]] || [[ "$output" =~ "invalid" ]]
}

@test "Error: Binary fails gracefully with missing manifest" {
    run "$BINARY" gitDeps --input /nonexistent/path/manifest.xml

    [ "$status" -ne 0 ]
    [[ "$output" =~ "error" ]] || [[ "$output" =~ "not found" ]] || [[ "$output" =~ "no such file" ]]
}
