"""Providers for Unreal Engine module information.

These providers separate compilation and linking concerns:
- UeModuleInfo: headers, includes, defines for compilation
- UeLinkInfo: .a files and link deps for linking (resolved at binary time)
- UeUhtInfo: UHT code generation outputs
"""

UeModuleInfo = provider(
    doc = "Compilation info for a UE module. Carries headers and includes for dependents.",
    fields = {
        "name": "Module name (e.g., 'Core', 'CoreUObject')",
        "module_type": "Module type: Runtime, Developer, Editor, Program, ThirdParty",
        "compilation_context": "CompilationContext from cc_common.compile()",
    },
)

UeLinkInfo = provider(
    doc = """Link-time dependency info for a UE module.

    Carries .o files and transitive link deps WITHOUT creating Bazel dep edges.
    This is how we break circular deps: compilation deps are real Bazel deps
    (to _headers targets), but link deps are just data flowing through providers.
    The ue_binary rule collects all transitive UeLinkInfo and links everything together.
    """,
    fields = {
        "object_files": "depset of .o files (or .a) produced by this module",
        "linker_inputs": "depset of LinkerInput objects for cc_common.link()",
        "transitive_linker_inputs": "depset of all transitive LinkerInput objects",
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
