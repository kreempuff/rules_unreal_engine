# Test UE Clone Directory

This directory contains a persistent Unreal Engine clone used for E2E testing.

## Purpose

E2E tests need a real UE checkout to validate BUILD files work correctly.
Cloning UE every test run takes 5-10 minutes. This directory persists the
clone for faster iteration.

## Usage

**First run (clones UE):**
```bash
RUN_SLOW_TESTS=1 bats test/ue_module.bats  # Takes 5-10 min
```

**Subsequent runs (reuses clone):**
```bash
RUN_SLOW_TESTS=1 bats test/ue_module.bats  # Takes < 30 seconds
```

## Contents

```
.test_ue/
└── UnrealEngine/          # Cloned from UE_GIT_URL at UE_BRANCH
    ├── Engine/
    │   └── Source/
    │       └── Runtime/
    └── MODULE.bazel       # Created by tests
```

## Configuration

Set environment variables to customize:

```bash
# Clone from local UE checkout (fast!)
UE_GIT_URL=file:///Users/you/UnrealEngine \
UE_BRANCH=your-branch \
RUN_SLOW_TESTS=1 \
bats test/build_core.bats

# Clone from Epic's GitHub (requires auth)
UE_BRANCH=5.4 RUN_SLOW_TESTS=1 bats test/ue_module.bats
```

## Cleaning

To force a fresh clone:

```bash
rm -rf .test_ue/
RUN_SLOW_TESTS=1 bats test/ue_module.bats  # Will clone again
```

## .gitignore

This directory is gitignored - it won't be committed to the repository.

## Test Workflow

1. **setup_file()** - Clone UE if `.test_ue/UnrealEngine` doesn't exist
2. **setup()** - Reset clone with `git reset --hard && git clean -fdx`
3. **test** - Install BUILD files, run bazel build
4. **teardown_file()** - Do nothing (keep clone for next run)

## Benefits

- ✅ **Fast iteration** - Clone once, reuse forever
- ✅ **Debuggable** - Can inspect `.test_ue/UnrealEngine` manually
- ✅ **Flexible** - Point to local UE or remote
- ✅ **Clean** - Gitignored, easy to delete and reclone
