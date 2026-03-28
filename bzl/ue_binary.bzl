"""Custom Bazel rule for linking Unreal Engine executables.

Collects all transitive UeLinkInfo from module deps and links
everything together into one executable. This is where circular
module deps get resolved — the binary is a terminal node, so
there are no cycles.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//bzl:providers.bzl", "UeLinkInfo")

def _ue_binary_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    # Compile any direct sources (e.g., main.cpp)
    dep_compilation_contexts = []
    for dep in ctx.attr.deps:
        if CcInfo in dep:
            dep_compilation_contexts.append(dep[CcInfo].compilation_context)

    own_compilation_context = None
    own_compilation_outputs = None
    if ctx.files.srcs:
        own_compilation_context, own_compilation_outputs = cc_common.compile(
            actions = ctx.actions,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            srcs = ctx.files.srcs,
            compilation_contexts = dep_compilation_contexts,
            name = ctx.attr.name,
        )

    # Collect ALL transitive linker inputs from all module deps
    all_linker_inputs = []
    all_linking_contexts = []

    for dep in ctx.attr.deps:
        # Get UeLinkInfo for transitive module link deps
        if UeLinkInfo in dep:
            all_linker_inputs.append(dep[UeLinkInfo].transitive_linker_inputs)

        # Also get CcInfo linking context for non-UE deps (system libs, etc.)
        if CcInfo in dep:
            all_linking_contexts.append(dep[CcInfo].linking_context)

    # Merge all linker inputs into one linking context
    merged_linker_inputs = depset(transitive = all_linker_inputs)
    module_linking_context = cc_common.create_linking_context(
        linker_inputs = merged_linker_inputs,
    )
    all_linking_contexts.append(module_linking_context)

    # Link everything into an executable
    linking_outputs = cc_common.link(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = own_compilation_outputs,
        linking_contexts = all_linking_contexts,
        user_link_flags = ctx.attr.linkopts,
        name = ctx.attr.name,
        output_type = "executable",
    )

    executable = linking_outputs.executable

    return [
        DefaultInfo(
            files = depset([executable]),
            executable = executable,
        ),
    ]

ue_binary = rule(
    implementation = _ue_binary_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".cpp", ".c", ".mm"]),
        "deps": attr.label_list(),
        "linkopts": attr.string_list(),
    },
    executable = True,
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
)
