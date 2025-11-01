def _parse_pack_urls(repo_ctx, manifest_path):
    """Parse .gitdeps XML and return list of pack URLs using gitDeps tool"""
    gitdeps_binary = repo_ctx.path(repo_ctx.attr._gitdeps_tool)

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
        pack_urls = _parse_pack_urls(repo_ctx, manifest_path)
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

        # Extract all packs using gitDeps
        gitdeps_binary = repo_ctx.path(repo_ctx.attr._gitdeps_tool)
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
        gitdeps_binary = repo_ctx.path(repo_ctx.attr._gitdeps_tool)

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
        "_gitdeps_tool": attr.label(
            default = "@//:rules_unreal_engine",
            executable = True,
            cfg = "exec",
            doc = "The gitDeps tool for downloading/extracting dependencies",
        ),
    },
)
