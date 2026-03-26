"""Rule that wraps a cc_library and provides UeModuleInfo.

This rule collects UeModuleInfo from deps and merges them with
the current module's info, propagating transitive headers,
includes, and defines through the dependency graph.
"""

load("//bzl:providers.bzl", "UeModuleInfo", "UeUhtInfo")

def _ue_module_info_impl(ctx):
    """Collect module info from deps and provide merged UeModuleInfo."""

    # Collect own headers
    source_hdrs = depset(ctx.files.source_hdrs)

    # Collect UHT info if available
    uht_hdrs = depset()
    uht_include_dir = ""
    if ctx.attr.uht_target and UeUhtInfo in ctx.attr.uht_target:
        uht_info = ctx.attr.uht_target[UeUhtInfo]
        uht_hdrs = uht_info.generated_hdrs
        uht_include_dir = uht_info.include_dir

    includes = depset(ctx.attr.includes)
    defines = depset(ctx.attr.defines)

    # Collect transitive info from deps
    transitive_source_hdrs = []
    transitive_uht_hdrs = []
    transitive_includes = []
    transitive_defines = []

    for dep in ctx.attr.public_deps:
        if UeModuleInfo in dep:
            info = dep[UeModuleInfo]
            transitive_source_hdrs.append(info.transitive_source_hdrs)
            transitive_uht_hdrs.append(info.transitive_uht_hdrs)
            transitive_includes.append(info.transitive_includes)
            transitive_defines.append(info.transitive_defines)

    # Include public_header_deps in transitive sets too
    for dep in ctx.attr.public_header_deps:
        if UeModuleInfo in dep:
            info = dep[UeModuleInfo]
            transitive_source_hdrs.append(info.transitive_source_hdrs)
            transitive_includes.append(info.transitive_includes)
            transitive_defines.append(info.transitive_defines)

    return [
        UeModuleInfo(
            name = ctx.attr.module_name,
            module_type = ctx.attr.module_type,
            source_hdrs = source_hdrs,
            uht_hdrs = uht_hdrs,
            uht_include_dir = uht_include_dir,
            includes = includes,
            defines = defines,
            transitive_source_hdrs = depset(
                transitive = [source_hdrs] + transitive_source_hdrs,
            ),
            transitive_uht_hdrs = depset(
                transitive = [uht_hdrs] + transitive_uht_hdrs,
            ),
            transitive_includes = depset(
                transitive = [includes] + transitive_includes,
                direct = [uht_include_dir] if uht_include_dir else [],
            ),
            transitive_defines = depset(
                transitive = [defines] + transitive_defines,
            ),
        ),
    ]

ue_module_info = rule(
    implementation = _ue_module_info_impl,
    attrs = {
        "module_name": attr.string(mandatory = True),
        "module_type": attr.string(default = "Runtime"),
        "source_hdrs": attr.label_list(allow_files = True),
        "uht_target": attr.label(providers = [UeUhtInfo]),
        "includes": attr.string_list(),
        "defines": attr.string_list(),
        "public_deps": attr.label_list(),
        "public_header_deps": attr.label_list(),
    },
)
