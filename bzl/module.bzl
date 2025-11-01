"""Bazel rules for building Unreal Engine modules.

This replaces UnrealBuildTool's .Build.cs files with native Bazel rules.
"""

load("@rules_cc//cc:defs.bzl", "cc_library")

def ue_module(
        name,
        module_type = "Runtime",
        srcs = None,
        hdrs = None,
        public_deps = [],
        private_deps = [],
        public_includes = [],
        private_includes = [],
        system_includes = [],
        defines = [],
        local_defines = [],
        linkopts = [],
        frameworks = [],
        visibility = None,
        **kwargs):
    """Defines an Unreal Engine module.

    This rule replaces .Build.cs files with Bazel-native configuration.
    Maps to UBT's ModuleRules class.

    Args:
        name: Module name (e.g., "Core", "CoreUObject")
        module_type: Module type - "Runtime", "Developer", "Editor", "Program"
        srcs: Source files (.cpp, .c, .mm). If None, uses glob(["Private/**/*.cpp"])
        hdrs: Header files (.h, .hpp). If None, uses glob(["Public/**/*.h"])
        public_deps: Public module dependencies (visible to dependents)
            Maps to: PublicDependencyModuleNames
        private_deps: Private module dependencies (internal only)
            Maps to: PrivateDependencyModuleNames
        public_includes: Public include directories (relative to module)
            Maps to: PublicIncludePaths
        private_includes: Private include directories
            Maps to: PrivateIncludePaths
        system_includes: System include paths (for third-party libs)
            Maps to: PublicSystemIncludePaths
        defines: Public preprocessor definitions
            Maps to: PublicDefinitions
        local_defines: Private preprocessor definitions
            Maps to: PrivateDefinitions
        linkopts: Linker options and system libraries
            Maps to: PublicSystemLibraries, PublicAdditionalLibraries
        frameworks: Apple frameworks (Mac/iOS/tvOS/visionOS)
            Maps to: PublicFrameworks
        visibility: Bazel visibility
        **kwargs: Additional cc_library arguments

    Example:
        ue_module(
            name = "Core",
            module_type = "Runtime",
            public_deps = [
                "//Engine/Source/Runtime/TraceLog",
            ],
            private_deps = [
                "//Engine/Source/Runtime/BuildSettings",
            ],
            frameworks = select({
                "@platforms//os:macos": ["Cocoa", "Carbon", "IOKit"],
                "//conditions:default": [],
            }),
            defines = ["UE_ENABLE_ICU=1"],
        )
    """

    # Default source/header discovery
    if srcs == None:
        srcs = native.glob([
            "Private/**/*.cpp",
            "Private/**/*.c",
            "Private/**/*.mm",  # Objective-C++
        ])

    if hdrs == None:
        hdrs = native.glob([
            "Public/**/*.h",
            "Public/**/*.hpp",
            "Public/**/*.inl",
        ])

    # Build include paths
    includes = []
    if public_includes:
        includes.extend(public_includes)
    else:
        # Default: Public directory
        includes.append("Public")

    # Collect all dependencies
    deps = []
    deps.extend(public_deps)
    deps.extend(private_deps)

    # Process frameworks and linkopts
    # Note: frameworks should be pre-formatted as "-framework Name" when using select()
    processed_linkopts = linkopts
    if frameworks:
        # If frameworks is a simple list, convert to linker flags
        if type(frameworks) == type([]) and len(frameworks) > 0:
            framework_opts = []
            for fw in frameworks:
                if not fw.startswith("-framework"):
                    framework_opts.extend(["-framework", fw])
                else:
                    framework_opts.append(fw)
            processed_linkopts = framework_opts + processed_linkopts
        else:
            # It's a select() - add it directly
            # Values in select() should already be formatted as ["-framework Foo"]
            if type(linkopts) == type([]):
                processed_linkopts = frameworks + linkopts
            else:
                # Both are selects - can't combine easily, just use frameworks
                processed_linkopts = frameworks

    # Create tags for module metadata
    tags = [
        "ue_module",
        "ue_module_type:" + module_type,
    ]

    # Create the underlying cc_library
    cc_library(
        name = name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        includes = includes,
        defines = defines,
        local_defines = local_defines,
        linkopts = processed_linkopts,
        visibility = visibility,
        tags = tags,
        **kwargs
    )

# Module type constants for documentation
MODULE_TYPE_RUNTIME = "Runtime"
MODULE_TYPE_DEVELOPER = "Developer"
MODULE_TYPE_EDITOR = "Editor"
MODULE_TYPE_PROGRAM = "Program"
MODULE_TYPE_THIRD_PARTY = "ThirdParty"
