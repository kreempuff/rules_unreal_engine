def _unreal_engine_impl(repo_ctx):
    repo_ctx.file("WORKSPACE", "")
    repo_ctx.file("BUILD", """""")
    exec_result = repo_ctx.execute(["git", "clone", repo_ctx.attr.git_repository, "--depth", "1", "--branch", repo_ctx.attr.commit, "UnrealEngine"], quiet = False)
    if exec_result.return_code != 0:
        fail("Failed to clone Unreal Engine")
    repo_ctx.file("UnrealEngine/BUILD", """exports_files(["Setup.sh"])""")

    version = "v1.30.1"
    arch = ""
    os = ""

    if repo_ctx.os.name == "mac os x" and repo_ctx.os.arch == "aarch64":
        os = "apple-darwin"
        arch = "aarch64"
    elif repo_ctx.os.name == "mac os x" and repo_ctx.os.arch == "x86_64":
        os = "apple-darwin"
        arch = "x86_64"
    elif repo_ctx.os.name == "linux" and repo_ctx.os.arch == "x86_64":
        os = "linux"
        arch = "x86_64"
    else:
        fail("Unsupported operating system and architecture: (" + repo_ctx.os.name + ", " + repo_ctx.os.arch + ")")

    repo_ctx.download_and_extract(
        url = "https://github.com/denoland/deno/releases/download/{version}/deno-{arch}-{os}.zip".format(version = version, arch = arch, os = os),
        output = "tools/deno",
    )
    repo_ctx.execute(["chmod", "+x", "tools/deno/deno"])

    # Result is a json file with this structure:
    # {
    #   "<PACK_HASH>": {
    #     "url": "<URL>",
    #     "sha256": "<SHA256>",
    #   },
    #   ...
    # }
    deps_json_filename = "Commit.gitdeps.json"
    result = repo_ctx.execute(["tools/deno/deno", "run", "--allow-env", "--allow-read", "--allow-write", repo_ctx.path(repo_ctx.attr._parse_xml_script), "UnrealEngine/Engine/Build/Commit.gitdeps.xml", deps_json_filename, repo_ctx.path(repo_ctx.attr._sqlitedb)])
    if result.return_code != 0:
        fail("Failed to parse gitdeps file" + "\n" + result.stderr)
    deps_str = repo_ctx.read(deps_json_filename)
    deps = json.decode(deps_str)
    for hash, pack in deps.items():
        repo_ctx.download(
            url = pack.get("url"),
            sha256 = pack.get("sha256"),
            output = "gitdeps/" + hash,
        )

unreal_engine = repository_rule(
    implementation = _unreal_engine_impl,
    doc = """Downloads and configures an instance of Unreal Engine. Expects `git` to be installed on the system and
configured to clone Unreal Engine from the given repository""",
    attrs = {
        "commit": attr.string(
            doc = """The version of Unreal Engine to download""",
            mandatory = True,
        ),
        "git_repository": attr.string(
            doc = """The repository to download Unreal Engine from""",
            mandatory = True,
        ),
        "_parse_xml_script": attr.label(
            default = "@//parse-xml:index.ts",
            allow_single_file = True,
        ),
        "_sqlitedb": attr.label(
            default = "@//:shas.db",
            allow_single_file = True,
        ),
    },
)
