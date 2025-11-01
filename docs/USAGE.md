# Usage Guide: rules_unreal_engine

This guide explains how to use `rules_unreal_engine` in two different scenarios:

1. **Scenario 1:** Building a game project that depends on Unreal Engine (UE as external dependency)
2. **Scenario 2:** Building Unreal Engine itself from source (in-place UE development)

---

## Prerequisites

- **Bazel 8.0+** installed ([installation guide](https://bazel.build/install))
- **Git** for cloning repositories
- **Platform-specific tools:**
  - **Mac:** Xcode Command Line Tools
  - **Windows:** MSVC 2022
  - **Linux:** Clang/GCC

---

## Scenario 1: Game Project (UE as External Dependency)

Use this approach when you're building a game or plugin that depends on Unreal Engine.

### Overview

```
MyGameProject/
├── MODULE.bazel           # References rules_unreal_engine
├── BUILD.bazel           # Build rules for your game
├── Source/               # Your C++ source code
│   └── MyGame/
└── Content/              # Your assets
```

**What happens:**
1. Bazel downloads `rules_unreal_engine`
2. `rules_unreal_engine` clones Unreal Engine as an external repository
3. Dependencies are downloaded and extracted automatically
4. Your game builds against the downloaded UE

### Step 1: Create MODULE.bazel

```starlark
# MyGameProject/MODULE.bazel

module(
    name = "my_game",
    version = "1.0.0",
)

# Add rules_unreal_engine dependency
bazel_dep(name = "rules_unreal_engine", version = "0.1.0")

# Configure Unreal Engine as external dependency
unreal_engine = use_repo_rule("@rules_unreal_engine//internal/repo:rule.bzl", "unreal_engine")

unreal_engine(
    name = "ue",
    commit = "5.5",                                          # UE version/branch
    git_repository = "https://github.com/EpicGames/UnrealEngine.git",
    use_bazel_downloader = True,                            # Use Bazel HTTP cache
)
```

**Available options:**
- `commit`: Git branch, tag, or commit hash (e.g., `"5.5"`, `"5.4.4-release"`, `"main"`)
- `git_repository`: Git URL to UE repository (requires Epic Games GitHub access)
- `use_bazel_downloader`:
  - `True` (default): Uses Bazel's HTTP cache for pack downloads (faster on rebuilds)
  - `False`: Uses gitDeps binary directly (simpler, no caching)

### Step 2: Reference UE in BUILD Files

```starlark
# MyGameProject/BUILD.bazel

load("@rules_cc//cc:defs.bzl", "cc_binary")

cc_binary(
    name = "MyGame",
    srcs = ["Source/MyGame/MyGame.cpp"],
    deps = [
        "@ue//Engine/Source/Runtime/Core",
        "@ue//Engine/Source/Runtime/CoreUObject",
        "@ue//Engine/Source/Runtime/Engine",
    ],
)
```

### Step 3: Build Your Game

```bash
cd MyGameProject

# Sync external dependencies (clones UE, downloads packs)
bazel sync

# Build your game
bazel build //:MyGame

# Run your game
bazel run //:MyGame
```

### First-Time Setup

**Expected behavior on first run:**
```bash
$ bazel sync
Cloning Unreal Engine from: https://github.com/EpicGames/UnrealEngine.git
Downloading dependencies using Bazel HTTP cache...
Found 9758 packs to download
Downloading pack 1/9758
Downloading pack 100/9758
...
All packs downloaded, extracting...
Unreal Engine dependencies ready
```

**Time estimate:**
- Clone UE: 10-20 minutes (depending on network)
- Download packs: 1-2 hours (9,758 files, ~20GB compressed)
- Extract packs: 10-15 minutes

**Subsequent runs (with Bazel cache):**
- Bazel reuses HTTP cached packs
- Only extraction needed (~10 minutes)

---

## Scenario 2: In-Place UE Development

Use this approach when you're working directly in the Unreal Engine source tree.

### Overview

```
UnrealEngine/
├── MODULE.bazel           # Add this file
├── BUILD.bazel           # Add this file
├── Engine/
│   ├── Build/
│   │   └── Commit.gitdeps.xml
│   └── Source/
└── ...
```

**What happens:**
1. You manually clone Unreal Engine
2. Add `MODULE.bazel` to the UE root
3. Run `bazel run` command to download dependencies **into your workspace**
4. Build UE modules with Bazel

### Step 1: Clone Unreal Engine

```bash
# Clone UE (requires Epic Games GitHub access)
git clone https://github.com/EpicGames/UnrealEngine.git
cd UnrealEngine
git checkout 5.5
```

### Step 2: Create MODULE.bazel

```starlark
# UnrealEngine/MODULE.bazel

module(
    name = "unreal_engine",
    version = "5.5.0",
)

# Add rules_unreal_engine as dependency
bazel_dep(name = "rules_unreal_engine", version = "0.1.0")

# For local development, you might use a local_path_override:
# local_path_override(
#     module_name = "rules_unreal_engine",
#     path = "../rules_unreal_engine",
# )
```

### Step 3: Download Dependencies

```bash
# Option A: Download + extract in one step
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps \
  --input Engine/Build/Commit.gitdeps.xml \
  --output-dir .

# Option B: Two-step process (useful for debugging)
# Step 1: Get pack URLs
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps printUrls \
  --input Engine/Build/Commit.gitdeps.xml \
  --output json > pack_urls.json

# Step 2: Download manually with curl/wget, then extract
mkdir -p packs
# ... download packs ...

bazel run @rules_unreal_engine//:rules_unreal_engine -- extract \
  --packs-dir packs \
  --manifest Engine/Build/Commit.gitdeps.xml \
  --output-dir .
```

**Expected output:**
```bash
$ bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps --input Engine/Build/Commit.gitdeps.xml --output-dir .

INFO: Parsed manifest with 23916 files, 9758 packs
INFO: Downloading pack 1/9758: https://cdn.unrealengine.com/dependencies/...
INFO: Downloading pack 100/9758...
...
INFO: All packs downloaded
INFO: Extracting files...
INFO: Extracted Engine/Binaries/ThirdParty/Steamworks/...
INFO: Complete! Extracted 23916 files
```

### Step 4: Create BUILD.bazel (Optional)

If you want to build UE modules with Bazel:

```starlark
# UnrealEngine/BUILD.bazel

load("@rules_cc//cc:defs.bzl", "cc_library")

cc_library(
    name = "Core",
    srcs = glob(["Engine/Source/Runtime/Core/Private/**/*.cpp"]),
    hdrs = glob(["Engine/Source/Runtime/Core/Public/**/*.h"]),
    visibility = ["//visibility:public"],
)

# More modules...
```

---

## Command Reference

### gitDeps Command

Downloads and extracts all dependencies from a `.gitdeps.xml` manifest.

```bash
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps [flags]
```

**Flags:**
- `--input <path>` - Path to `.gitdeps.xml` manifest (required)
- `--output-dir <path>` - Where to extract files (default: current directory)
- `--verify` - Verify SHA1 checksums after extraction (default: true)

**Examples:**
```bash
# Download dependencies for current UE directory
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps \
  --input Engine/Build/Commit.gitdeps.xml \
  --output-dir .

# Skip checksum verification (faster)
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps \
  --input Engine/Build/Commit.gitdeps.xml \
  --output-dir . \
  --verify=false
```

### printUrls Command

Extracts pack URLs from a manifest (useful for custom download pipelines).

```bash
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps printUrls [flags]
```

**Flags:**
- `--input <path>` - Path to `.gitdeps.xml` manifest (required)
- `--output <format>` - Output format: `json` or `bazel` (default: `json`)

**Examples:**
```bash
# Get URLs as JSON array
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps printUrls \
  --input Engine/Build/Commit.gitdeps.xml \
  --output json

# Output: ["https://cdn.unrealengine.com/dependencies/...", ...]

# Get URLs in Bazel-friendly format
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps printUrls \
  --input Engine/Build/Commit.gitdeps.xml \
  --output bazel
```

### extract Command

Extracts pre-downloaded pack files (useful with Bazel HTTP cache).

```bash
bazel run @rules_unreal_engine//:rules_unreal_engine -- extract [flags]
```

**Flags:**
- `--packs-dir <path>` - Directory containing downloaded `.pack.gz` files (required)
- `--manifest <path>` - Path to `.gitdeps.xml` manifest (required)
- `--output-dir <path>` - Where to extract files (required)

**Example:**
```bash
# Extract packs that were downloaded via Bazel
bazel run @rules_unreal_engine//:rules_unreal_engine -- extract \
  --packs-dir ~/.cache/bazel/packs \
  --manifest Engine/Build/Commit.gitdeps.xml \
  --output-dir .
```

---

## Troubleshooting

### Error: "Failed to clone Unreal Engine"

**Cause:** You don't have access to Epic's GitHub repository.

**Solution:**
1. Sign up at [unrealengine.com](https://www.unrealengine.com/)
2. Link your Epic account to GitHub
3. Accept Epic's GitHub invitation
4. Try cloning again

### Error: "Failed to download pack: 404 Not Found"

**Cause:** Epic's CDN URL changed or pack was removed.

**Solution:**
1. Update to latest UE version/branch
2. Check if your `.gitdeps.xml` is from an old/unsupported UE version
3. Report issue at [github.com/kreempuff/rules_unreal_engine/issues](https://github.com/kreempuff/rules_unreal_engine/issues)

### Error: "SHA1 checksum mismatch"

**Cause:** Downloaded pack is corrupted or CDN served wrong file.

**Solution:**
```bash
# Retry download with verification disabled
bazel run @rules_unreal_engine//:rules_unreal_engine -- gitDeps \
  --input Engine/Build/Commit.gitdeps.xml \
  --output-dir . \
  --verify=false
```

### Error: "No such file or directory: rules_unreal_engine"

**Cause:** Binary not built yet.

**Solution:**
```bash
# Build the binary first
cd /path/to/rules_unreal_engine
bazel build //:rules_unreal_engine
```

### Performance: Downloads are slow

**Scenario 1 (external repo):**
- Use `use_bazel_downloader = True` to enable HTTP caching
- Set up Bazel remote cache for your team

**Scenario 2 (in-place):**
- Download packs once, keep them in a shared location
- Use `extract` command to reuse downloaded packs

---

## Comparison: Setup.sh vs rules_unreal_engine

| Feature | Setup.sh (Original) | rules_unreal_engine |
|---------|---------------------|---------------------|
| **Language** | .NET/C# | Go |
| **Dependencies** | Mono/.NET Runtime | None (static binary) |
| **Caching** | None | Bazel HTTP cache |
| **Parallelism** | Limited | Full (Bazel) |
| **Error messages** | Cryptic | Clear |
| **Platform support** | Mac, Windows, Linux | Mac, Windows, Linux |
| **Hermetic** | No | Yes |
| **Reproducible** | No | Yes |

**Time comparison (first run, 9,758 packs):**
- Setup.sh: ~2 hours
- rules_unreal_engine: ~1.5 hours (with `use_bazel_downloader = True`)

**Time comparison (subsequent runs):**
- Setup.sh: ~2 hours (re-downloads everything)
- rules_unreal_engine: ~10 minutes (Bazel cache)

---

## Advanced Usage

### Using a Local UE Clone

If you already have UE cloned locally:

```starlark
# MODULE.bazel
unreal_engine(
    name = "ue",
    commit = "main",
    git_repository = "file:///Users/you/UnrealEngine",  # Local path
    use_bazel_downloader = True,
)
```

### Custom CDN Base URL

If you're mirroring Epic's CDN:

```go
// Modify pkg/gitDeps/gitDeps.go
// Change BaseUrl in WorkingManifest struct
```

(Feature not yet exposed via CLI - coming soon)

### Integrating with CI/CD

```yaml
# .github/workflows/build.yml
name: Build Game

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Bazel
        uses: bazel-contrib/setup-bazel@0.8.1
        with:
          bazelisk-cache: true
          disk-cache: ${{ github.workflow }}
          repository-cache: true

      - name: Build game
        run: bazel build //...

      - name: Run tests
        run: bazel test //...
```

**Benefits:**
- Bazel's remote cache speeds up CI builds by 10-50x
- Hermetic builds ensure reproducibility across machines
- Automatic dependency caching

---

## FAQ

### Q: Do I need Epic's Setup.sh anymore?

**A:** No! `rules_unreal_engine` completely replaces `Setup.sh`.

### Q: Can I use this with Epic's UBT/UAT?

**A:** Yes! The gitDeps binary downloads dependencies to the same locations Epic's Setup.sh does. You can use UBT/UAT after running gitDeps.

### Q: What about plugins and marketplace content?

**A:** Phase 1 (current) only handles engine dependencies. Plugin support is planned for Phase 2.

### Q: Does this work with UE 4.x?

**A:** Yes! Any UE version that uses `.gitdeps.xml` manifests (UE 4.20+).

### Q: Can I contribute?

**A:** Absolutely! See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

---

## Next Steps

- **For Game Developers:** See [Scenario 1](#scenario-1-game-project-ue-as-external-dependency)
- **For Engine Developers:** See [Scenario 2](#scenario-2-in-place-ue-development)
- **For Contributors:** See [CONTRIBUTING.md](../CONTRIBUTING.md)
- **For Roadmap:** See [README.md](../README.md#roadmap-to-10)

---

**Last Updated:** 2025-11-01
**Project Status:** Phase 1.1 Complete (Setup.sh replacement)
**Repository:** [github.com/kreempuff/rules_unreal_engine](https://github.com/kreempuff/rules_unreal_engine)
