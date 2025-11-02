# Development Workflow

This document describes the iterative development workflow for adding new UE modules.

## Overview

We use a test UE repository (`.test_ue/UnrealEngine`) to quickly iterate on BUILD files without modifying the main UE installation. The workflow ensures that BUILD files are validated before committing them to the project.

## The Workflow

### 1. Create BUILD Files in Project

Create BUILD.bazel files in the `ue_modules/` directory of the project:

```bash
# Example: Adding Json module
mkdir -p ue_modules/Runtime/Json
mkdir -p ue_modules/ThirdParty/RapidJSON

# Create BUILD.bazel files using your editor or Write tool
# - ue_modules/Runtime/Json/BUILD.bazel
# - ue_modules/ThirdParty/RapidJSON/BUILD.bazel
```

### 2. Install BUILD Files to Test Repo

Use the `just install` command to copy BUILD files to the test repository:

```bash
just install .test_ue/UnrealEngine
```

This command:
- Finds all BUILD.bazel files in `ue_modules/`
- Copies them to the corresponding locations in `.test_ue/UnrealEngine/Engine/Source/`
- Creates or updates MODULE.bazel with local_path_override (when LOCAL_DEV=1)

### 3. Build and Test

Test the build in the test repository:

```bash
cd .test_ue/UnrealEngine
bazel build //Engine/Source/Runtime/Json
bazel build //Engine/Source/ThirdParty/RapidJSON
```

If the build fails:
- Fix the BUILD.bazel file in `ue_modules/` (not in the test repo!)
- Re-run `just install .test_ue/UnrealEngine`
- Re-test the build

### 4. Commit When Successful

Once the build succeeds, commit the BUILD files:

```bash
git add ue_modules/Runtime/Json/ ue_modules/ThirdParty/RapidJSON/
git commit -m "feat: add Json and RapidJSON modules"
```

### 5. Repeat for Next Module

Continue this process for the next module on your list.

## Key Benefits

1. **Fast Iteration**: Copy files (sub-second) vs reinstalling symlinks
2. **Clean Separation**: Test repo changes don't affect project files
3. **Easy Reset**: `just reset-test-ue` or `just clean-test-ue` for fresh start
4. **Validated Changes**: Only commit BUILD files that successfully build

## Important Notes

### Install Script Behavior

The `tools/install_builds.sh` script **always copies files** (using `cp`), not symlinks. The `LOCAL_DEV=1` environment variable only affects the MODULE.bazel `local_path_override` setting, not the BUILD file installation method.

### Test Repo Management

The test repo (`.test_ue/UnrealEngine`) is:
- A separate git repository cloned from your main UE installation
- **Not tracked** in the rules_unreal_engine git repo (.gitignore)
- Safe to modify, reset, or delete at any time

Useful commands:
```bash
just setup-test-ue          # Initial clone
just reset-test-ue          # Git clean + hard reset
just clean-test-ue          # Delete entire test repo
```

### Working Directory

**Always create BUILD files in the project's `ue_modules/` directory**, not in the test repo. The test repo is only for validation, not for authoring changes.

## Example Session

```bash
# 1. Create BUILD files
mkdir -p ue_modules/Runtime/Json
# ... create ue_modules/Runtime/Json/BUILD.bazel

# 2. Install to test repo
just install .test_ue/UnrealEngine

# 3. Test build
cd .test_ue/UnrealEngine
bazel build //Engine/Source/Runtime/Json

# 4. If successful, commit
cd /Users/kareemmarch/projects/rules_unreal_engine
git add ue_modules/Runtime/Json/
git commit -m "feat: add Json module"

# 5. Move on to next module
# ... repeat process for next module
```

## Troubleshooting

### "BUILD file not found"

Make sure you ran `just install` after creating/modifying BUILD files in `ue_modules/`.

### "Wrong working directory"

The Write tool uses your current working directory. Make sure you're in the project root (`/Users/kareemmarch/projects/rules_unreal_engine`) when creating BUILD files, not in the test repo.

### "Symlinks instead of copies"

This shouldn't happen - the install script always uses `cp`. If you see symlinks, check that you're using the correct version of `tools/install_builds.sh`.

## See Also

- [PLAN.md](PLAN.md) - Overall project plan and phase breakdown
- [MODULE_ROADMAP.md](MODULE_ROADMAP.md) - Module conversion priorities
- [.test_ue/README.md](../.test_ue/README.md) - Test repository documentation
