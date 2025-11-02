# Justfile for rules_unreal_engine

# Run gitdeps BATS tests
test-gitdeps filter="":
    bats test/gitdeps.bats {{if filter != "" { "--filter '" + filter + "'" } else { "" } }}

# Run ue_module BATS tests (supports module filter for E2E tests)
test-ue-module filter="" modules="":
    {{if modules != "" { "TEST_MODULES='" + modules + "'" } else { "" } }} bats test/ue_module.bats {{if filter != "" { "--filter '" + filter + "'" } else { "" } }}

# Run install_builds BATS tests
test-install filter="":
    bats test/install_builds.bats {{if filter != "" { "--filter '" + filter + "'" } else { "" } }}

# Run build_core BATS tests (requires RUN_SLOW_TESTS=1)
test-core filter="":
    RUN_SLOW_TESTS=1 bats test/build_core.bats {{if filter != "" { "--filter '" + filter + "'" } else { "" } }}

# Run all BATS tests (fast tests only)
test-all:
    bats test/gitdeps.bats
    bats test/ue_module.bats
    bats test/install_builds.bats

# Run all BATS tests including slow E2E tests
test-all-slow:
    bats test/gitdeps.bats
    RUN_SLOW_TESTS=1 bats test/ue_module.bats
    bats test/install_builds.bats
    RUN_SLOW_TESTS=1 bats test/build_core.bats

# Run Bazel tests
test-bazel:
    bazel test //...

# Build the rules_unreal_engine binary
build:
    bazel build //:rules_unreal_engine

# Install BUILD files to UE (requires path argument)
install path:
    LOCAL_DEV=1 ./tools/install_builds.sh {{path}}

# Clean .test_ue/ persistent clone
clean-test-ue:
    rm -rf .test_ue/UnrealEngine

# Clean Bazel cache
clean-bazel:
    bazel clean

# Clean everything
clean-all: clean-test-ue clean-bazel
    rm -rf bazel-*
