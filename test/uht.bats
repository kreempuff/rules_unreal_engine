#!/usr/bin/env bats
# Tests for UnrealHeaderTool (UHT) wrapper script

setup() {
    # Run slow tests only if RUN_SLOW_TESTS=1
    if [ -z "$RUN_SLOW_TESTS" ]; then
        skip "Slow test - set RUN_SLOW_TESTS=1 to run"
    fi

    # Require UE_ROOT to be set (no defaults)
    if [ -z "$UE_ROOT" ]; then
        skip "UE_ROOT not set - export UE_ROOT=/path/to/UnrealEngine"
    fi

    # Verify UE installation exists
    if [ ! -d "$UE_ROOT" ]; then
        skip "UnrealEngine not found at $UE_ROOT"
    fi

    # Clean generated files before each test
    rm -rf test/uht_test/generated test/uht_test/generated_plain
}

teardown() {
    # Clean up after tests
    rm -rf test/uht_test/generated test/uht_test/generated_plain
    rm -rf test/uht_test/Intermediate test/uht_test/Saved
    rm -f test/uht_test/*.deps
}

@test "UHT wrapper generates code for UENUM" {
    # Run UHT on TestEnum (has UENUM macro)
    run ./tools/uht_wrapper.sh \
        "$UE_ROOT" \
        test/uht_test/TestProject.uproject \
        test/uht_test/TestModule.uhtmanifest

    [ "$status" -eq 0 ]
    [[ "$output" == *"Succeeded"* ]]

    # Verify 3 files generated
    [ -f test/uht_test/generated/TestEnum.generated.h ]
    [ -f test/uht_test/generated/TestEnum.gen.cpp ]
    [ -f test/uht_test/generated/TestModule.init.gen.cpp ]

    # Verify files are not empty
    [ -s test/uht_test/generated/TestEnum.generated.h ]
    [ -s test/uht_test/generated/TestEnum.gen.cpp ]
    [ -s test/uht_test/generated/TestModule.init.gen.cpp ]

    # Verify content contains expected UHT patterns
    grep -q "FOREACH_ENUM_ETESTENUM" test/uht_test/generated/TestEnum.generated.h
    grep -q "StaticEnum<ETestEnum>" test/uht_test/generated/TestEnum.generated.h
}

@test "UHT wrapper no-ops on plain class without macros" {
    # Run UHT on PlainClass (no UCLASS/USTRUCT/UENUM)
    run ./tools/uht_wrapper.sh \
        "$UE_ROOT" \
        test/uht_test/TestProject.uproject \
        test/uht_test/TestPlain.uhtmanifest

    [ "$status" -eq 0 ]
    [[ "$output" == *"Succeeded"* ]]
    [[ "$output" == *"Total of 0 written"* ]]

    # Verify output directory is empty
    if [ -d test/uht_test/generated_plain ]; then
        file_count=$(find test/uht_test/generated_plain -type f 2>/dev/null | wc -l)
        [ "$file_count" -eq 0 ]
    fi
}

@test "Empty .generated.h files compile successfully" {
    # Create empty placeholder files
    mkdir -p test/uht_test/generated_empty
    touch test/uht_test/generated_empty/Empty.generated.h

    # Create test file that includes empty header
    cat > test/uht_test/test_empty.cpp <<'EOF'
#include "test/uht_test/generated_empty/Empty.generated.h"
int main() { return 0; }
EOF

    # Compile should succeed with empty file
    run clang++ -c test/uht_test/test_empty.cpp -I. -o /tmp/test_empty.o

    [ "$status" -eq 0 ]

    # Cleanup
    rm -f test/uht_test/test_empty.cpp /tmp/test_empty.o
    rm -rf test/uht_test/generated_empty
}
