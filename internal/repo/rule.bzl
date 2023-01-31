def _unreal_engine_impl(repo_ctx):
    repo_ctx.file("WORKSPACE", "")
    repo_ctx.file("BUILD", """""")
    exec_result = repo_ctx.execute(["git", "clone", repo_ctx.attr.git_repository, "--depth", "1", "--branch", repo_ctx.attr.commit, "UnrealEngine"], quiet = False)
    if exec_result.return_code != 0:
        fail("Failed to clone Unreal Engine")
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
    },
)
