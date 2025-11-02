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

# Setup test UE repository from local UE clone
setup-test-ue ue_path=("file://" + justfile_directory() / "../UnrealEngine") branch="kreempuff-release" depth="1":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d .test_ue/UnrealEngine ]; then
        echo "Test UE already exists at .test_ue/UnrealEngine"
        echo "Run 'just clean-test-ue' first if you want to reclone"
        exit 1
    fi
    echo "Cloning UE from {{ue_path}} (branch: {{branch}}, depth: {{depth}})..."
    mkdir -p .test_ue
    git clone --branch "{{branch}}" --depth "{{depth}}" "{{ue_path}}" .test_ue/UnrealEngine
    echo "Test UE setup complete!"

# Reset test UE repository to clean state (git clean + hard reset)
reset-test-ue:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d .test_ue/UnrealEngine/.git ]; then
        echo "Resetting test UE repository..."
        cd .test_ue/UnrealEngine
        git clean -fdx
        git reset --hard
        echo "Test UE reset complete!"
    else
        echo "No test UE repository found. Run 'just setup-test-ue' first."
        exit 1
    fi

# Clean .test_ue/ persistent clone
clean-test-ue:
    rm -rf .test_ue/UnrealEngine

# Clean Bazel cache
clean-bazel:
    bazel clean

# Clean everything
clean-all: clean-test-ue clean-bazel
    rm -rf bazel-*
