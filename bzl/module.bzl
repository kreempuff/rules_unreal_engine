"""Bazel rules for building Unreal Engine modules.

This replaces UnrealBuildTool's .Build.cs files with native Bazel rules.
"""

load("@rules_cc//cc:defs.bzl", "cc_library")

def ue_module(
        name,
        module_type = "Runtime",
        srcs = None,
        hdrs = None,
        exclude_srcs = [],
        additional_hdrs = [],
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

    # Default source/header discovery with platform filtering
    if srcs == None:
        # Build exclude list: platform dirs (including subdirs) + user excludes
        base_excludes = [
            "Private/Android/**", "Private/Windows/**", "Private/Linux/**",
            "Private/Unix/**", "Private/IOS/**", "Private/Mac/**", "Private/Apple/**",
            # Also exclude platform subdirectories (e.g., Private/ProfilingDebugging/Unix/)
            "Private/**/Android/**", "Private/**/Windows/**", "Private/**/Linux/**",
            "Private/**/Unix/**", "Private/**/IOS/**", "Private/**/Mac/**", "Private/**/Apple/**",
            "Private/**/Microsoft/**",  # Windows-specific (e.g., Private/ProfilingDebugging/Microsoft/)
        ]
        all_excludes = base_excludes + exclude_srcs

        # Common sources (exclude platform-specific directories + user exclusions)
        common_cpp = native.glob(
            ["Private/**/*.cpp", "Private/**/*.mm"],
            exclude = all_excludes,
            allow_empty = True,
        )
        common_c = native.glob(
            ["Private/**/*.c"],
            exclude = all_excludes,
            allow_empty = True,
        )

        # Platform-specific C++ sources
        platform_cpp = select({
            "@platforms//os:macos": native.glob(
                ["Private/Mac/**/*.cpp", "Private/Mac/**/*.mm", "Private/Apple/**/*.cpp", "Private/Apple/**/*.mm"],
                allow_empty = True),
            "@platforms//os:ios": native.glob(
                ["Private/IOS/**/*.cpp", "Private/IOS/**/*.mm", "Private/Apple/**/*.cpp", "Private/Apple/**/*.mm"],
                allow_empty = True),
            "@platforms//os:linux": native.glob(
                ["Private/Linux/**/*.cpp", "Private/Unix/**/*.cpp"],
                allow_empty = True),
            "@platforms//os:windows": native.glob(
                ["Private/Windows/**/*.cpp"],
                allow_empty = True),
            "@platforms//os:android": native.glob(
                ["Private/Android/**/*.cpp", "Private/Linux/**/*.cpp", "Private/Unix/**/*.cpp"],
                allow_empty = True),
            "//conditions:default": [],
        })

        # Platform-specific C sources
        platform_c = select({
            "@platforms//os:macos": native.glob(
                ["Private/Mac/**/*.c", "Private/Apple/**/*.c"],
                allow_empty = True),
            "@platforms//os:ios": native.glob(
                ["Private/IOS/**/*.c", "Private/Apple/**/*.c"],
                allow_empty = True),
            "@platforms//os:linux": native.glob(
                ["Private/Linux/**/*.c", "Private/Unix/**/*.c"],
                allow_empty = True),
            "@platforms//os:windows": native.glob(
                ["Private/Windows/**/*.c"],
                allow_empty = True),
            "@platforms//os:android": native.glob(
                ["Private/Android/**/*.c", "Private/Linux/**/*.c", "Private/Unix/**/*.c"],
                allow_empty = True),
            "//conditions:default": [],
        })

        # Don't combine - we already have them separated
        # Set a flag so we skip the separation step later
        _auto_globbed_srcs = True
        _globbed_cpp = common_cpp + platform_cpp
        _globbed_c = common_c + platform_c
    else:
        _auto_globbed_srcs = False

    if hdrs == None:
        hdrs = native.glob(
            [
                "Public/**/*.h",
                "Public/**/*.hpp",
                "Public/**/*.inl",
                "Internal/**/*.h",      # Internal headers (visible to internal modules)
                "Internal/**/*.hpp",
                "Internal/**/*.inl",
                "Private/**/*.h",       # Private headers (needed for includes)
                "Private/**/*.hpp",
                "Private/**/*.inl",     # Private inline files (e.g., LZ4/lz4.c.inl)
            ],
            allow_empty = True,
        )

    # Add additional headers (e.g., unity build .cpp files that should be included)
    hdrs = hdrs + additional_hdrs

    # UE default compiler flags (from UBT ClangToolChain.cs and AppleToolChain.cs)
    # On Apple platforms, .cpp files are compiled as Objective-C++ to support Foundation headers
    ue_default_copts = select({
        "@platforms//os:macos": [
            "-x", "objective-c++",        # Compile as Objective-C++ (AppleToolChain.cs:455)
            "-std=c++20",                  # C++20 standard
            "-stdlib=libc++",              # Use libc++ (AppleToolChain.cs:457)
            "-fno-exceptions",             # C++ exceptions OFF
            "-fno-rtti",                   # RTTI OFF
            "-Wall",                       # Enable all warnings
            # Note: Objective-C exceptions NOT disabled - Mac code uses @try/@catch
        ],
        "@platforms//os:ios": [
            "-x", "objective-c++",        # Compile as Objective-C++ (iOS also uses AppleToolChain)
            "-std=c++20",
            "-stdlib=libc++",
            "-fno-exceptions",             # C++ exceptions OFF
            "-fno-rtti",
            "-Wall",
            # Note: Objective-C exceptions NOT disabled - iOS code may use @try/@catch
        ],
        "//conditions:default": [
            "-std=c++20",                  # Regular C++ for non-Apple platforms
            "-fno-exceptions",
            "-fno-rtti",
            "-Wall",
        ],
    })

    # UE build configuration defines (required by Core/Misc/Build.h)
    # TODO: Make these configurable via Bazel config_setting
    ue_build_defines = [
        "__UNREAL__=1",                   # Standard UE define (used by third-party code)
        "UE_BUILD_DEVELOPMENT=1",         # Development build (default)
        "UE_BUILD_DEBUG=0",
        "UE_BUILD_TEST=0",
        "UE_BUILD_SHIPPING=0",
        "WITH_EDITOR=0",                  # Game build, not editor
        "WITH_ENGINE=1",                  # Compiling with engine
        "WITH_UNREAL_DEVELOPER_TOOLS=0",
        "WITH_PLUGIN_SUPPORT=1",
        "WITH_SERVER_CODE=1",             # Include server code (for dedicated servers)
        "IS_MONOLITHIC=0",                # Modular build
        "IS_PROGRAM=0",                   # Not a standalone program
        "TBBMALLOC_ENABLED=0",            # Disable Intel TBB malloc (platform-specific)
        "USE_MALLOC_BINNED2=1",           # Use Binned2 allocator (UE default)
        "USE_MALLOC_BINNED3=0",           # Binned3 experimental allocator OFF
        "USE_STATS_WITHOUT_ENGINE=0",     # Stats system without full Engine (OFF for modular builds)
        "FORCE_USE_STATS=0",              # Don't force stats in non-stat builds
        'UBT_MODULE_MANIFEST=\\"Manifest.dat\\"',  # Module manifest filename
        'UBT_MODULE_MANIFEST_DEBUGGAME=\\"Manifest-DebugGame.dat\\"',  # DebugGame manifest
        'UE_APP_NAME=\\"UnrealGame\\"',   # Application name (default for games)
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
            "PLATFORM_COMPILER_OPTIMIZATION_PG=0",           # Profile-guided optimization disabled
            "PLATFORM_COMPILER_OPTIMIZATION_PG_PROFILING=0", # PG profiling disabled
            "PLATFORM_COMPILER_OPTIMIZATION_LTCG=0",         # Link-time code generation disabled
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

    # Add module-specific local defines (private to this module only)
    # UE_MODULE_NAME: Used by IMPLEMENT_MODULE macro
    module_local_defines = ['UE_MODULE_NAME=\\"' + name + '\\"']
    all_local_defines = module_local_defines + local_defines

    # Build include paths
    includes = []
    if public_includes:
        includes.extend(public_includes)
    else:
        # Default: Public, Internal, and Private directories
        # UE modules expect to include from these paths
        includes.extend(["Public", "Internal", "Private"])

    # Add any additional private includes
    if private_includes:
        includes.extend(private_includes)

    # Separate C and C++ source files
    if _auto_globbed_srcs:
        # Already separated during glob
        c_files = _globbed_c
        cpp_files = _globbed_cpp
    else:
        # User provided srcs - separate them
        c_files = [s for s in srcs if s.endswith(".c")]
        cpp_files = [s for s in srcs if not s.endswith(".c")]

    # Collect all dependencies
    deps = []
    deps.extend(public_deps)
    deps.extend(private_deps)

    # If we have C files, create a separate C library with C-specific flags
    if c_files:
        c_lib_name = name + "_c"
        cc_library(
            name = c_lib_name,
            srcs = c_files,
            hdrs = hdrs,
            includes = includes,
            defines = all_defines,
            local_defines = all_local_defines,
            copts = ["-std=c11", "-Wall"],  # C flags (not C++)
            tags = ["ue_module_c_part"],
            visibility = ["//visibility:private"],
        )
        # Add C library as dependency for main target
        deps.append(":" + c_lib_name)

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

    # Create the main cc_library (C++ files only, C files in separate library)
    cc_library(
        name = name,
        srcs = cpp_files,  # Only C++ files (C files in _c library)
        hdrs = hdrs,
        deps = deps,  # Includes _c library if C files exist
        includes = includes,
        defines = all_defines,
        local_defines = all_local_defines,
        copts = all_copts,  # C++ flags
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
