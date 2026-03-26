"""Test rules for verifying UeModuleInfo provider propagation."""

load("//bzl:providers.bzl", "UeModuleInfo", "UeUhtInfo")

def _verify_provider_impl(ctx):
    """Test rule that verifies UeModuleInfo is present and has expected values."""

    info = ctx.attr.target[UeModuleInfo]

    # Collect verification results
    results = []
    results.append("Module: {}".format(info.name))
    results.append("Type: {}".format(info.module_type))
    results.append("Source headers: {}".format(len(info.source_hdrs.to_list())))
    results.append("UHT headers: {}".format(len(info.uht_hdrs.to_list())))
    results.append("UHT include dir: {}".format(info.uht_include_dir))
    results.append("Includes: {}".format(info.includes.to_list()))
    results.append("Defines: {} items".format(len(info.defines.to_list())))
    results.append("Transitive source headers: {}".format(len(info.transitive_source_hdrs.to_list())))
    results.append("Transitive UHT headers: {}".format(len(info.transitive_uht_hdrs.to_list())))
    results.append("Transitive includes: {}".format(len(info.transitive_includes.to_list())))

    # Check expected values
    failures = []
    if ctx.attr.expected_name and info.name != ctx.attr.expected_name:
        failures.append("Expected name '{}', got '{}'".format(ctx.attr.expected_name, info.name))

    if ctx.attr.expected_module_type and info.module_type != ctx.attr.expected_module_type:
        failures.append("Expected type '{}', got '{}'".format(ctx.attr.expected_module_type, info.module_type))

    if ctx.attr.min_source_hdrs > 0 and len(info.source_hdrs.to_list()) < ctx.attr.min_source_hdrs:
        failures.append("Expected at least {} source headers, got {}".format(
            ctx.attr.min_source_hdrs, len(info.source_hdrs.to_list())))

    if ctx.attr.expect_uht_hdrs and len(info.uht_hdrs.to_list()) == 0:
        failures.append("Expected UHT headers but found none")

    if ctx.attr.min_transitive_hdrs > 0 and len(info.transitive_source_hdrs.to_list()) < ctx.attr.min_transitive_hdrs:
        failures.append("Expected at least {} transitive headers, got {}".format(
            ctx.attr.min_transitive_hdrs, len(info.transitive_source_hdrs.to_list())))

    # Write test output
    output = ctx.actions.declare_file(ctx.attr.name + ".test_output")
    content = "\n".join(results)
    if failures:
        content += "\n\nFAILURES:\n" + "\n".join(failures)
        content += "\nRESULT: FAIL\n"
    else:
        content += "\nRESULT: PASS\n"

    ctx.actions.write(output, content)

    # Write test runner script
    script = ctx.actions.declare_file(ctx.attr.name + ".sh")
    ctx.actions.write(
        script,
        "#!/bin/bash\ncat {}\ngrep -q 'RESULT: PASS' {} || exit 1\n".format(
            output.short_path, output.short_path),
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = script,
            runfiles = ctx.runfiles(files = [output]),
        ),
    ]

verify_ue_module_info_test = rule(
    implementation = _verify_provider_impl,
    test = True,
    attrs = {
        "target": attr.label(mandatory = True, providers = [UeModuleInfo]),
        "expected_name": attr.string(default = ""),
        "expected_module_type": attr.string(default = ""),
        "min_source_hdrs": attr.int(default = 0),
        "expect_uht_hdrs": attr.bool(default = False),
        "min_transitive_hdrs": attr.int(default = 0),
    },
)
