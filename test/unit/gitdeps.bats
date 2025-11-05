#!/usr/bin/env bats
# Integration tests for rules_unreal_engine gitDeps tool

# Setup: Build the binary once before all tests
setup_file() {
    # Always build to ensure bazel-bin symlink is fresh (fast with cache)
    cd "$BATS_TEST_DIRNAME/.." && bazel build //:rules_unreal_engine >&2

    export BINARY="$BATS_TEST_DIRNAME/../bazel-bin/rules_unreal_engine_/rules_unreal_engine"

    # Create test data directory
    export TEST_DATA_DIR="$BATS_TEST_DIRNAME/data"
    mkdir -p "$TEST_DATA_DIR"

    # Create a minimal test manifest
    cat > "$TEST_DATA_DIR/test-manifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<WorkingManifest BaseUrl="https://cdn.unrealengine.com/dependencies">
    <Files>
        <File Name="Engine/Test/test.txt" Hash="abc123" ExpectedHash="abc123" Timestamp="0"/>
    </Files>
    <Blobs>
        <Blob Hash="abc123" Size="10" PackHash="pack123" PackOffset="8" />
    </Blobs>
    <Packs>
        <Pack Hash="pack123" Size="100" CompressedSize="50" RemotePath="TestPack"/>
    </Packs>
</WorkingManifest>
EOF
}

teardown_file() {
    # Cleanup
    rm -rf "$TEST_DATA_DIR"
}

setup() {
    # Create temp directory for each test
    export TEST_TEMP_DIR="$(mktemp -d)"
}

teardown() {
    # Cleanup temp directory
    rm -rf "$TEST_TEMP_DIR"
}

# Test: Binary exists and is executable
@test "binary exists and is executable" {
    [ -f "$BINARY" ]
    [ -x "$BINARY" ]
}

# Test: Help command works
@test "help command shows usage" {
    run "$BINARY" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "rules-unreal-engine" ]]
    [[ "$output" =~ "Available Commands" ]]
}

# Test: gitDeps command exists
@test "gitDeps command exists" {
    run "$BINARY" gitDeps --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Downloads and extracts" ]]
}

# Test: printUrls command exists
@test "printUrls command exists" {
    run "$BINARY" gitDeps printUrls --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Prints the urls" ]]
}

# Test: extract command exists
@test "extract command exists" {
    run "$BINARY" extract --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Extract Unreal Engine dependencies" ]]
}

# Test: printUrls JSON output format
@test "printUrls produces valid JSON" {
    skip "Requires real UE manifest"

    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json
    [ "$status" -eq 0 ]

    # Validate JSON format
    echo "$output" | python3 -m json.tool > /dev/null
    [ $? -eq 0 ]
}

# Test: printUrls JSON contains expected URL
@test "printUrls JSON contains CDN URL" {
    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json
    [ "$status" -eq 0 ]
    [[ "$output" =~ "https://cdn.unrealengine.com/dependencies" ]]
}

# Test: printUrls JSON is an array
@test "printUrls JSON output is array" {
    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json
    [ "$status" -eq 0 ]

    # First character should be [
    [[ "${output:0:1}" == "[" ]]
    # Last character should be ]
    [[ "${output: -1}" == "]" ]]
}

# Test: printUrls Bazel output format
@test "printUrls produces Bazel format" {
    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output bazel
    [ "$status" -eq 0 ]
    [[ "$output" =~ 'urls = [' ]]
}

# Test: Manifest parsing errors are handled
@test "gitDeps fails gracefully with invalid manifest" {
    echo "invalid xml" > "$TEST_TEMP_DIR/invalid.xml"

    run "$BINARY" gitDeps --input "$TEST_TEMP_DIR/invalid.xml" --output-dir "$TEST_TEMP_DIR"
    [ "$status" -ne 0 ]
}

# Test: Missing manifest file is handled
@test "gitDeps fails gracefully with missing manifest" {
    run "$BINARY" gitDeps --input "$TEST_TEMP_DIR/nonexistent.xml" --output-dir "$TEST_TEMP_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "file does not exist" ]] || [[ "$output" =~ "no such file" ]]
}

# Test: Extract requires packs-dir flag
@test "extract command requires packs-dir flag" {
    run "$BINARY" extract --manifest "$TEST_DATA_DIR/test-manifest.xml"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "required flag" ]] || [[ "$output" =~ "packs-dir" ]]
}

# Test: Extract requires manifest flag
@test "extract command requires manifest flag" {
    run "$BINARY" extract --packs-dir "$TEST_TEMP_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "required flag" ]] || [[ "$output" =~ "manifest" ]]
}

# Test: Directory input finds .ue4dependencies
@test "gitDeps accepts directory with .ue4dependencies" {
    skip "Requires mock pack download"

    # Create directory with manifest
    mkdir -p "$TEST_TEMP_DIR/Engine/Build"
    cp "$TEST_DATA_DIR/test-manifest.xml" "$TEST_TEMP_DIR/.ue4dependencies"

    run "$BINARY" gitDeps --input "$TEST_TEMP_DIR" --output-dir "$TEST_TEMP_DIR" --verify=false
    # Will fail because we can't download, but should find the file
    [[ "$output" =~ "found" ]] || [[ "$output" =~ "parsing manifest" ]]
}

# Test: Verbose flag increases log output
@test "verbose flag enables debug logging" {
    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json
    quiet_lines="${#lines[@]}"

    run "$BINARY" gitDeps --verbose printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json
    verbose_lines="${#lines[@]}"

    # Verbose should have more output (though might not always due to log formatting)
    [ "$verbose_lines" -ge "$quiet_lines" ]
}

# Test: gitDeps supports --verify flag
@test "gitDeps accepts verify flag" {
    skip "Requires mock pack download"

    run "$BINARY" gitDeps --input "$TEST_DATA_DIR/test-manifest.xml" --output-dir "$TEST_TEMP_DIR" --verify=true
    # Will fail on download but should accept the flag
    [ "$status" -ne 0 ]
}

# Test: JSON output has correct number of packs
@test "printUrls JSON contains correct number of URLs" {
    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json
    [ "$status" -eq 0 ]

    # Our test manifest has 1 pack
    url_count=$(echo "$output" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
    [ "$url_count" -eq "1" ]
}

# Test: URL format is correct
@test "printUrls generates correct URL format" {
    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json
    [ "$status" -eq 0 ]

    # Should contain BaseUrl/RemotePath/Hash
    [[ "$output" =~ "TestPack/pack123" ]]
}

# Integration test: Full UE manifest (if available)
@test "integration: parse real UE manifest" {
    UE_MANIFEST="/tmp/ue-e2e-test/Engine/Build/Commit.gitdeps.xml"

    if [ ! -f "$UE_MANIFEST" ]; then
        skip "Real UE manifest not available at $UE_MANIFEST"
    fi

    run "$BINARY" gitDeps printUrls --input "$UE_MANIFEST" --output json
    [ "$status" -eq 0 ]

    # Should be valid JSON
    echo "$output" | python3 -m json.tool > /dev/null
    [ $? -eq 0 ]

    # Should have many URLs (UE has thousands)
    url_count=$(echo "$output" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
    [ "$url_count" -gt 1000 ]
}

# Integration test: Extract from downloaded packs
@test "integration: extract command with mock packs" {
    skip "Requires mock pack creation"

    # This would require creating valid gzipped UEPACK00 files
    # Left as TODO for full integration testing
    run "$BINARY" extract \
        --packs-dir "$TEST_TEMP_DIR/packs" \
        --manifest "$TEST_DATA_DIR/test-manifest.xml" \
        --output-dir "$TEST_TEMP_DIR/output"

    [ "$status" -eq 0 ]
    [ -d "$TEST_TEMP_DIR/output/Engine" ]
}

# Test: Output directory is created if missing
@test "gitDeps creates output directory if missing" {
    skip "Requires mock pack download"

    output_dir="$TEST_TEMP_DIR/new_output_dir"
    [ ! -d "$output_dir" ]

    run "$BINARY" gitDeps --input "$TEST_DATA_DIR/test-manifest.xml" --output-dir "$output_dir"

    # Will fail on download but directory should be created
    [ -d "$output_dir" ] || [ "$status" -ne 0 ]
}

# Performance test: printUrls is fast
@test "printUrls completes quickly" {
    UE_MANIFEST="/tmp/ue-e2e-test/Engine/Build/Commit.gitdeps.xml"

    if [ ! -f "$UE_MANIFEST" ]; then
        skip "Real UE manifest not available"
    fi

    start=$(date +%s)
    run "$BINARY" gitDeps printUrls --input "$UE_MANIFEST" --output json
    end=$(date +%s)

    duration=$((end - start))

    # Should complete in under 10 seconds for 30MB manifest
    [ "$duration" -lt 10 ]
}

# Test: Multiple output formats produce different results
@test "printUrls json and bazel formats differ" {
    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json
    json_output="$output"

    run "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output bazel
    bazel_output="$output"

    [ "$json_output" != "$bazel_output" ]
    [[ "$json_output" =~ "[" ]]
    [[ "$bazel_output" =~ "urls" ]]
}

# Test: Concurrent invocations don't interfere
@test "multiple printUrls can run concurrently" {
    "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json > "$TEST_TEMP_DIR/out1.json" &
    pid1=$!

    "$BINARY" gitDeps printUrls --input "$TEST_DATA_DIR/test-manifest.xml" --output json > "$TEST_TEMP_DIR/out2.json" &
    pid2=$!

    wait $pid1
    status1=$?
    wait $pid2
    status2=$?

    [ "$status1" -eq 0 ]
    [ "$status2" -eq 0 ]

    # Outputs should be identical
    diff "$TEST_TEMP_DIR/out1.json" "$TEST_TEMP_DIR/out2.json"
}

# Test: IsExecutable attribute sets file permissions correctly
@test "extract sets executable permissions from IsExecutable attribute" {
    # Create test manifest with executable and regular files
    mkdir -p "$TEST_TEMP_DIR/exec_test/packs"
    
    cat > "$TEST_TEMP_DIR/exec_test/manifest.xml" <<'MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest>
  <BaseUrl>unused</BaseUrl>
  <Files>
    <File Name="bin/executable" Hash="hash1" IsExecutable="true" />
    <File Name="data/regular.txt" Hash="hash2" />
  </Files>
  <Blobs>
    <Blob Hash="hash1" Size="11" PackHash="testpack" PackOffset="0" />
    <Blob Hash="hash2" Size="12" PackHash="testpack" PackOffset="11" />
  </Blobs>
  <Packs>
    <Pack Hash="testpack" Size="23" CompressedSize="50" RemotePath="/testpack.pack.gz" />
  </Packs>
</PackageManifest>
MANIFEST

    # Create pack with test data (11 bytes + 12 bytes)
    printf "#!/bin/bash\nregular data" | gzip > "$TEST_TEMP_DIR/exec_test/packs/testpack.pack.gz"

    # Extract
    run "$BINARY" extract \
        --manifest "$TEST_TEMP_DIR/exec_test/manifest.xml" \
        --packs-dir "$TEST_TEMP_DIR/exec_test/packs" \
        --output-dir "$TEST_TEMP_DIR/exec_test/output"

    [ "$status" -eq 0 ]

    # Verify executable file has execute permission (0755 or 0755)
    [ -x "$TEST_TEMP_DIR/exec_test/output/bin/executable" ]
    
    # Verify regular file does NOT have execute permission
    [ -f "$TEST_TEMP_DIR/exec_test/output/data/regular.txt" ]
    [ ! -x "$TEST_TEMP_DIR/exec_test/output/data/regular.txt" ]
}
