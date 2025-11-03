def _build_gitdeps(repo_ctx):
    """Build gitDeps tool using downloaded Go SDK (hermetic, during loading phase).

    Repository rules cannot use Bazel-built binaries (they run during loading phase).
    Solution: Download Go SDK and compile gitDeps directly, same pattern as rules_go/Gazelle.
    """
    # Detect platform
    os_name = repo_ctx.os.name.lower()
    os_arch = repo_ctx.os.arch.lower()

    # Map to Go SDK platform names
    if "mac" in os_name or "darwin" in os_name:
        if "aarch64" in os_arch or "arm64" in os_arch:
            go_platform = "darwin-arm64"
        else:
            go_platform = "darwin-amd64"
    elif "linux" in os_name:
        if "aarch64" in os_arch or "arm64" in os_arch:
            go_platform = "linux-arm64"
        else:
            go_platform = "linux-amd64"
    else:
        # TODO: Add Windows support (windows-amd64, windows-arm64)
        fail("Unsupported platform: {} {}. Windows support coming soon.".format(os_name, os_arch))

    # Download Go SDK (version 1.24.3 - matches rules_go version, hermetic)
    # SHA256s verified from https://go.dev/dl/ (2025-11-03)
    go_version = "1.24.3"
    go_sdk_url = "https://go.dev/dl/go{}.{}.tar.gz".format(go_version, go_platform)

    # SHA256 checksums for Go 1.24.3 (from https://go.dev/dl/)
    go_sha256 = {
        "darwin-arm64": "64a3fa22142f627e78fac3018ce3d4aeace68b743eff0afda8aae0411df5e4fb",
        "darwin-amd64": "13e6fe3fcf65689d77d40e633de1e31c6febbdbcb846eb05fc2434ed2213e92b",
        "linux-arm64": "a463cb59382bd7ae7d8f4c68846e73c4d589f223c589ac76871b66811ded7836",
        "linux-amd64": "3333f6ea53afa971e9078895eaa4ac7204a8c6b5c68c10e6bc9a33e8e391bdd8",
        # TODO: Add Windows support
        # "windows-amd64": "...",
        # "windows-arm64": "...",
    }

    print("Downloading Go SDK {} for {}...".format(go_version, go_platform))
    repo_ctx.download_and_extract(
        url = go_sdk_url,
        sha256 = go_sha256[go_platform],
        stripPrefix = "go",
        output = "_go_sdk",
    )

    go_binary = repo_ctx.path("_go_sdk/bin/go")

    # Build gitDeps using downloaded Go SDK
    print("Building gitDeps tool...")
    gitdeps_src_dir = repo_ctx.path(Label("//:go.mod")).dirname
    gitdeps_binary = repo_ctx.path("_gitdeps")

    # Run 'go build' from the gitDeps source directory (where go.mod lives)
    # Set fresh cache directories to avoid Go version mismatch issues
    go_cache = repo_ctx.path("_go_cache")
    go_mod_cache = repo_ctx.path("_go_mod_cache")

    result = repo_ctx.execute(
        [go_binary, "build", "-o", str(gitdeps_binary), "."],
        working_directory = str(gitdeps_src_dir),
        environment = {
            "GOCACHE": str(go_cache),
            "GOMODCACHE": str(go_mod_cache),
        },
    )
    if result.return_code != 0:
        fail("Failed to build gitDeps:\nstdout: {}\nstderr: {}".format(result.stdout, result.stderr))

    print("gitDeps built successfully")
    return gitdeps_binary

def _parse_pack_urls(repo_ctx, gitdeps_binary, manifest_path):
    """Parse .gitdeps XML and return list of pack URLs using gitDeps tool"""
    result = repo_ctx.execute([
        gitdeps_binary,
        "gitDeps",
        "printUrls",
        "--input", manifest_path,
        "--output", "json",
    ])

    if result.return_code != 0:
        fail("Failed to parse manifest: " + result.stderr)

    # Parse JSON output: ["url1", "url2", ...]
    urls = json.decode(result.stdout)
    return urls

def _unreal_engine_impl(repo_ctx):
    repo_ctx.file("WORKSPACE", "")
    repo_ctx.file("BUILD", """""")

    # Build gitDeps tool (downloads Go SDK, compiles gitDeps during loading phase)
    gitdeps_binary = _build_gitdeps(repo_ctx)

    # Clone Unreal Engine repository
    print("Cloning Unreal Engine from: " + repo_ctx.attr.git_repository)
    exec_result = repo_ctx.execute(
        ["git", "clone", repo_ctx.attr.git_repository, "--depth", "1", "--branch", repo_ctx.attr.commit, "UnrealEngine"],
        quiet = False,
    )
    if exec_result.return_code != 0:
        fail("Failed to clone Unreal Engine: " + exec_result.stdout + exec_result.stderr)

    manifest_path = "UnrealEngine/Engine/Build/Commit.gitdeps.xml"

    if repo_ctx.attr.use_bazel_downloader:
        # Bazel-native approach: Use repo_ctx.download() for HTTP caching
        print("Downloading dependencies using Bazel HTTP cache...")

        # Parse manifest to get pack URLs
        pack_urls = _parse_pack_urls(repo_ctx, gitdeps_binary, manifest_path)
        pack_count = len(pack_urls)
        print("Found {} packs to download".format(pack_count))

        # Download each pack using Bazel's downloader (gets cached!)
        repo_ctx.file("packs/.gitkeep", "")
        for i, url in enumerate(pack_urls):
            # Extract hash from URL (last component)
            hash = url.split("/")[-1]

            if i % 100 == 0:
                print("Downloading pack {}/{}".format(i + 1, pack_count))

            # Download pack (Bazel caches this!)
            repo_ctx.download(
                url = url,
                output = "packs/{}.pack.gz".format(hash),
                # Note: Pack.Hash is not the file's SHA256, it's a URL identifier
                # So we can't use sha256 verification here
            )

        print("All packs downloaded, extracting...")

        # Extract all packs using gitDeps (already built above)
        exec_result = repo_ctx.execute(
            [
                gitdeps_binary,
                "extract",
                "--packs-dir", "packs",
                "--manifest", manifest_path,
                "--output-dir", "UnrealEngine",
            ],
            quiet = False,
            timeout = 1800,  # 30 min for extraction
        )

        if exec_result.return_code != 0:
            fail("Failed to extract packs: " + exec_result.stdout + exec_result.stderr)
    else:
        # Fallback: Use gitDeps directly (downloads + extracts in one go)
        print("Downloading dependencies using gitDeps (no Bazel cache)...")

        # gitDeps already built above
        exec_result = repo_ctx.execute(
            [
                gitdeps_binary,
                "gitDeps",
                "--input", manifest_path,
                "--output-dir", "UnrealEngine",
                "--verify=false",
            ],
            quiet = False,
            timeout = 3600,  # 1 hour timeout
        )

        if exec_result.return_code != 0:
            fail("Failed to download dependencies: " + exec_result.stdout + exec_result.stderr)

    print("Unreal Engine dependencies ready")

    # Create build file
    repo_ctx.file("UnrealEngine/BUILD", """exports_files(["Setup.sh"])""")

unreal_engine = repository_rule(
    implementation = _unreal_engine_impl,
    doc = """Downloads and configures an instance of Unreal Engine.

This rule:
1. Clones the Unreal Engine repository (requires git)
2. Downloads and extracts all dependencies from .ue4dependencies
3. Sets up the engine workspace ready for building

Replaces Epic's Setup.sh with a hermetic Bazel implementation.

When use_bazel_downloader=True, leverages Bazel's HTTP cache for faster rebuilds.""",
    attrs = {
        "commit": attr.string(
            doc = """The version/branch of Unreal Engine to download""",
            mandatory = True,
        ),
        "git_repository": attr.string(
            doc = """The git repository URL to clone Unreal Engine from""",
            mandatory = True,
        ),
        "use_bazel_downloader": attr.bool(
            default = True,
            doc = """Use Bazel's native downloader (repo_ctx.download) for HTTP caching.
            When True, packs are downloaded using Bazel's HTTP cache and reused across builds.
            When False, uses gitDeps directly (no caching, but simpler).""",
        ),
        # Note: No _gitdeps_tool needed - we build it during loading phase using downloaded Go SDK
    },
)
