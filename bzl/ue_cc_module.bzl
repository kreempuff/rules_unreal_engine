"""Custom Bazel rule for Unreal Engine C++ modules.

Separates compilation (needs headers) from linking (needs .a files)
to eliminate circular dependency cycles that exist in UE's module graph.

Compilation deps point to _headers targets (no cycles possible).
Link deps flow through UeLinkInfo provider (just data, no dep edges).
The ue_binary rule collects all transitive UeLinkInfo and links at the end.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//bzl:providers.bzl", "UeLinkInfo", "UeModuleInfo")

def _ue_cc_module_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    # Collect compilation contexts from deps (these are _headers targets providing CcInfo)
    dep_compilation_contexts = []
    for dep in ctx.attr.deps:
        if CcInfo in dep:
            dep_compilation_contexts.append(dep[CcInfo].compilation_context)

    # Separate source files from headers (UHT genrule produces both in one output group)
    src_extensions = [".cpp", ".c", ".mm", ".cc"]
    hdr_extensions = [".h", ".hpp", ".inl"]
    actual_srcs = [f for f in ctx.files.srcs if any([f.path.endswith(ext) for ext in src_extensions])]
    extra_hdrs = [f for f in ctx.files.srcs if any([f.path.endswith(ext) for ext in hdr_extensions])]

    all_public_hdrs = ctx.files.public_hdrs + extra_hdrs

    # Resolve include paths relative to the package directory
    package_path = ctx.label.package
    resolved_includes = [package_path + "/" + inc if not inc.startswith("/") else inc for inc in ctx.attr.includes]

    # Add UHT output directories to include paths (for .generated.h files)
    uht_dirs = {}
    for f in extra_hdrs:
        if f.path.endswith(".generated.h"):
            uht_dirs[f.dirname] = True
    resolved_includes = resolved_includes + uht_dirs.keys()

    # Compile sources
    compilation_context, compilation_outputs = cc_common.compile(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = actual_srcs,
        public_hdrs = all_public_hdrs,
        private_hdrs = ctx.files.private_hdrs,
        includes = resolved_includes,
        defines = ctx.attr.defines,
        local_defines = ctx.attr.local_defines,
        user_compile_flags = ctx.attr.copts,
        compilation_contexts = dep_compilation_contexts,
        name = ctx.attr.name,
    )

    # Create linking context from compilation outputs
    linking_context, linking_outputs = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        name = ctx.attr.name,
    )

    # Get linker inputs from the linking context
    linker_inputs = linking_context.linker_inputs

    # CcInfo for consumers: compilation_context propagates headers/includes
    # linking_context carries THIS module's .a only
    cc_info = CcInfo(
        compilation_context = compilation_context,
        linking_context = linking_context,
    )

    return [
        DefaultInfo(
            files = depset(compilation_outputs.objects),
        ),
        cc_info,
        UeModuleInfo(
            name = ctx.attr.module_name or ctx.attr.name,
            module_type = ctx.attr.module_type,
            compilation_context = compilation_context,
        ),
        UeLinkInfo(
            object_files = depset(compilation_outputs.objects),
            linker_inputs = linker_inputs,
            transitive_linker_inputs = linker_inputs,
        ),
    ]

ue_cc_module = rule(
    implementation = _ue_cc_module_impl,
    attrs = {
        # Sources
        "srcs": attr.label_list(allow_files = [".cpp", ".c", ".mm", ".cc"]),
        "public_hdrs": attr.label_list(allow_files = [".h", ".hpp", ".inl"]),
        "private_hdrs": attr.label_list(allow_files = [".h", ".hpp", ".inl"]),

        # Compilation deps — these are real Bazel deps, must be acyclic
        # Point to _headers targets or other header-only targets
        "deps": attr.label_list(),

        # Compilation settings
        "includes": attr.string_list(),
        "defines": attr.string_list(),
        "local_defines": attr.string_list(),
        "copts": attr.string_list(),

        # Module metadata
        "module_name": attr.string(),
        "module_type": attr.string(default = "Runtime"),
    },
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
)
