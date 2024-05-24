def _unreal_engine_impl(repo_ctx):
    repo_ctx.file("WORKSPACE", "")
    repo_ctx.file("BUILD", """""")

    exec_result = repo_ctx.execute(["git", "clone", repo_ctx.attr.git_repository, "--depth", "1", "--branch", repo_ctx.attr.commit, "UnrealEngine"], quiet = False)
    if exec_result.return_code != 0:
        fail("Failed to clone Unreal Engine: " + exec_result.stdout + exec_result.stderr)

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
    repo_ctx.execute(["tools/deno/deno", "run", "--allow-read", "--allow-write", repo_ctx.path(repo_ctx.attr._parse_xml_script), "UnrealEngine/Engine/Build/Commit.gitdeps.xml", "Commit.gitdeps.json"])

    # Create build file
    repo_ctx.file("UnrealEngine/BUILD", """exports_files(["Setup.sh"])""")

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
            default = "@//:parse-xml-cli.ts",
            allow_single_file = True,
        ),
    },
)
