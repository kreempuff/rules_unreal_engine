"""Providers for Unreal Engine module information.

These providers carry module metadata between ue_module rules,
replacing the three-tier _headers/_uht_headers/full target pattern
with native Bazel provider propagation.
"""

UeModuleInfo = provider(
    doc = "Information about an Unreal Engine module for dependency resolution.",
    fields = {
        "name": "Module name (e.g., 'Core', 'CoreUObject')",
        "module_type": "Module type: Runtime, Developer, Editor, Program, ThirdParty",
        "source_hdrs": "depset of source header files (no UHT outputs)",
        "uht_hdrs": "depset of UHT-generated .generated.h files",
        "uht_include_dir": "String path to UHT output directory (for -I flag)",
        "includes": "depset of include path strings (Public, Internal, Private dirs)",
        "defines": "depset of public preprocessor defines",
        "transitive_source_hdrs": "depset of all transitive source headers",
        "transitive_uht_hdrs": "depset of all transitive UHT-generated headers",
        "transitive_includes": "depset of all transitive include paths",
        "transitive_defines": "depset of all transitive public defines",
    },
)

UeUhtInfo = provider(
    doc = "UHT code generation outputs for a module.",
    fields = {
        "generated_hdrs": "depset of .generated.h files",
        "generated_srcs": "depset of .gen.cpp and .init.gen.cpp files",
        "include_dir": "String path to the UHT output directory",
    },
)
