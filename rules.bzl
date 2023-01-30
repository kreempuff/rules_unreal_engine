"""

"""
UnrealModuleInfo = provider(
    doc = """Module""",
    fields = ["name"],
)

def _unreal_target_impl(ctx):
    target_file = ctx.actions.declare_file(
        ctx.label.name + ".Target.cs",
    )

    ctx.actions.write(
        target_file,
        content = """
// Hi
""",
    )

    return [DefaultInfo(files = depset([target_file]))]

unreal_target = rule(
    doc = """
Attributes for defining a target (application/executable)

https://github.com/EpicGames/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetRules.cs#L303
""",
    implementation = _unreal_target_impl,
    attrs = {
        "type": attr.string(
            doc = """
Types of target.

game: Cooked monolithic game executable (GameName.exe).  Also used for a game-agnostic engine executable (UnrealGame.exe or RocketGame.exe)

editor: Uncooked modular editor executable and DLLs (UnrealEditor.exe, UnrealEditor*.dll, GameName*.dll)

client: Cooked monolithic game client executable (GameNameClient.exe, but no server code)

server: Cooked monolithic game server executable (GameNameServer.exe, but no client code)

program: Program (standalone program, e.g. ShaderCompileWorker.exe, can be modular or monolithic depending on the program)

- https://github.com/EpicGames/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetRules.cs#L310
- https://github.com/EpicGames/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetRules.cs#L24
""",
            values = ["game", "editor", "client", "server", "program"],
            mandatory = True,
        ),
        "default_build_settings": attr.string(
            doc = """Specifies the engine version to maintain backwards-compatible default build settings with (eg. DefaultSettingsVersion.Release_4_23, DefaultSettingsVersion.Release_4_24). Specify DefaultSettingsVersion.Latest to always
use defaults for the current engine version, at the risk of introducing build errors while upgrading.

- https://github.com/EpicGames/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetRules.cs#L461
- https://github.com/EpicGames/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetRules.cs#L115
""",
            values = ["v1", "v2", "latest"],
            default = "v2",
        ),
        "build_environment": attr.string(
            doc = """
The build environment override
- https://github.com/EpicGames/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetRules.cs#L1942
- https://github.com/EpicGames/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetRules.cs#L76
            """,
            values = ["shared", "unique"],
        ),
        # TODO(add default module as an attribute)
        # Watching a YT video on how to create a Unreal project from scratch, I learned that an Unreal Target needs
        # one default module that invokes special functions that mark it as the primary module. I should expose this as a property. In the meantime, I'm going to expose
        # what TargetRules expose: a list of "extra modules" to include in this target
        # Ref: https://youtu.be/94FvzO1HVzY?t=824
        "extra_module_names": attr.label_list(
            doc = """
List of additional modules to be compiled into the target.

- https://github.com/EpicGames/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/TargetRules.cs#L1920
""",
            providers = [UnrealModuleInfo],

            #            cfg = "target", # The modules for a target should be always be built for the target
        ),
    },
)

def _unreal_module_impl(ctx):
    pass

unreal_module = rule(
    implementation = _unreal_module_impl,
    attrs = {
        "type": attr.string(
            default = "cpp",
            values = ["cpp", "external"],
            doc = """
Default value:
https://github.com/kreempuff/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/ModuleRules.cs#L596
Possible Values:
https://github.com/kreempuff/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/ModuleRules.cs#L70
""",
        ),
        "pch_usage": attr.string(
            values = ["default", "none", "noshared", "shared", "explicit_or_shared"],
            doc = """
Usage of Precompiled Headers

Possible Values:
https://github.com/kreempuff/UnrealEngine/blob/cdaec5b33ea5d332e51eee4e4866495c90442122/Engine/Source/Programs/UnrealBuildTool/Configuration/ModuleRules.cs#L155
""",
        ),
        #        TODO(add providers)
        "public_include_path_modules": attr.label_list(),
        "public_dependency_modules": attr.label_list(),
        "private_include_path_modules": attr.label_list(),
        "private_dependency_modules": attr.label_list(),
    },
)
