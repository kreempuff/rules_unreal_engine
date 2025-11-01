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
        copts = [],
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
        copts: Compiler options. UE defaults are added automatically.
            Override with additional flags as needed.
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
        srcs = native.glob(
            [
                "Private/**/*.cpp",
                "Private/**/*.c",
                "Private/**/*.mm",  # Objective-C++
            ],
            allow_empty = True,
        )

    if hdrs == None:
        hdrs = native.glob(
            [
                "Public/**/*.h",
                "Public/**/*.hpp",
                "Public/**/*.inl",
                "Internal/**/*.h",      # Internal headers (visible to internal modules)
                "Internal/**/*.hpp",
                "Private/**/*.h",       # Private headers (needed for includes)
                "Private/**/*.hpp",
            ],
            allow_empty = True,
        )

    # UE default compiler flags (from UBT ClangToolChain.cs)
    ue_default_copts = [
        "-std=c++20",                      # C++20 standard (UE default)
        "-fno-exceptions",                 # Exceptions OFF (UE default)
        "-fno-rtti",                       # RTTI OFF (UE default)
        "-Wall",                           # Enable all warnings
        # Note: -fdiagnostics-absolute-paths is Clang-only, not supported by GCC
        # TODO: Add conditionally for Clang toolchain
    ]

    # UE build configuration defines (required by Core/Misc/Build.h)
    # TODO: Make these configurable via Bazel config_setting
    ue_build_defines = [
        "UE_BUILD_DEVELOPMENT=1",         # Development build (default)
        "UE_BUILD_DEBUG=0",
        "UE_BUILD_TEST=0",
        "UE_BUILD_SHIPPING=0",
        "WITH_EDITOR=0",                  # Game build, not editor
        "WITH_ENGINE=1",                  # Compiling with engine
        "WITH_UNREAL_DEVELOPER_TOOLS=0",
        "WITH_PLUGIN_SUPPORT=1",
        "IS_MONOLITHIC=0",                # Modular build
        "IS_PROGRAM=0",                   # Not a standalone program
    ]

    # Module API export macros (e.g., CORE_API, ENGINE_API)
    # For static library builds, these are empty
    # TODO: For DLL builds, use __declspec(dllexport/dllimport) on Windows
    module_api_define = name.upper() + "_API="
    ue_build_defines.append(module_api_define)

    # UE platform-specific defines (required by Core/HAL/Platform.h)
    ue_platform_defines = select({
        "@platforms//os:macos": [
            "UBT_COMPILED_PLATFORM=Mac",
            "PLATFORM_MAC=1",
            "PLATFORM_APPLE=1",
        ],
        "@platforms//os:linux": [
            "UBT_COMPILED_PLATFORM=Linux",
            "PLATFORM_LINUX=1",
            "PLATFORM_UNIX=1",
        ],
        "@platforms//os:windows": [
            "UBT_COMPILED_PLATFORM=Windows",
            "PLATFORM_WINDOWS=1",
            "PLATFORM_MICROSOFT=1",
        ],
        "//conditions:default": [],
    })

    # Combine user copts with UE defaults (user copts can override)
    all_copts = ue_default_copts + copts

    # Combine UE defines with user defines
    # Order: UE build config → UE platform → user defines
    all_defines = ue_build_defines + ue_platform_defines + defines

    # Build include paths
    includes = []
    if public_includes:
        includes.extend(public_includes)
    else:
        # Default: Public, Internal, and Private directories
        # UE modules expect to include from these paths
        includes.extend(["Public", "Internal", "Private"])

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
        defines = all_defines,
        local_defines = local_defines,
        copts = all_copts,
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
