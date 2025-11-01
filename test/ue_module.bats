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
