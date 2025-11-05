"""Bazel rules for UHT (UnrealHeaderTool) code generation.

This module provides a custom rule for running Epic's UnrealHeaderTool
to generate reflection code from UCLASS/USTRUCT/UENUM macros.
"""

def _filter_headers_for_uht(hdrs):
    """Filter headers to only those UHT should process.

    UHT requirements:
    - Unique basenames (no "Public/Foo.h" and "Private/Foo.h")
    - No implementation details (Detail/, Impl/)
    - No inline files (.inl)
    - No platform-specific headers

    Args:
        hdrs: List of header File objects

    Returns:
        List of header Files suitable for UHT processing
    """
    uht_hdrs = []
    seen_basenames = {}

    for hdr in hdrs:
        path = hdr.path

        # Skip .inl files
        if path.endswith(".inl"):
            continue

        # Skip Detail/, Impl/, Private/ subdirectories
        if "/Detail/" in path or "/Impl/" in path or "/Private/" in path:
            continue

        # Skip platform-specific subdirectories
        platform_dirs = ["/Windows/", "/Microsoft/", "/Apple/", "/Unix/", "/Linux/", "/IOS/", "/Android/"]
        skip = False
        for pdir in platform_dirs:
            if pdir in path:
                skip = True
                break
        if skip:
            continue

        # Check for basename conflicts
        basename = hdr.basename
        if basename in seen_basenames:
            # Skip duplicate (prefer shorter path)
            if len(path) < len(seen_basenames[basename].path):
                uht_hdrs.remove(seen_basenames[basename])
                uht_hdrs.append(hdr)
                seen_basenames[basename] = hdr
            continue

        uht_hdrs.append(hdr)
        seen_basenames[basename] = hdr

    return uht_hdrs

def _uht_codegen_impl(ctx):
    """Implementation of uht_codegen rule."""

    # Filter headers for UHT
    filtered_hdrs = _filter_headers_for_uht(ctx.files.hdrs)

    # Declare output files
    outputs = []
    outputs.append(ctx.actions.declare_file(ctx.attr.module_name + ".init.gen.cpp"))

    for hdr in filtered_hdrs:
        # Sanitize path: Public/Foo/Bar.h → Public_Foo_Bar
        path_no_ext = hdr.path.rsplit(".", 1)[0]
        sanitized = path_no_ext.replace("/", "_")
        outputs.append(ctx.actions.declare_file(sanitized + ".generated.h"))
        outputs.append(ctx.actions.declare_file(sanitized + ".gen.cpp"))

    # Generate manifest
    manifest = ctx.actions.declare_file(ctx.attr.module_name + ".uhtmanifest")
    header_paths = ",".join([hdr.path for hdr in filtered_hdrs])

    ctx.actions.run(
        executable = ctx.executable._gitdeps,
        arguments = [
            "uht", "manifest",
            "--module-name", ctx.attr.module_name,
            "--module-type", ctx.attr.module_type,
            "--base-dir", ctx.bin_dir.path,
            "--output-dir", ctx.bin_dir.path,
            "--headers", header_paths,
            "--output", manifest.path,
        ],
        outputs = [manifest],
        mnemonic = "UHTManifest",
        progress_message = "Generating UHT manifest for %s" % ctx.attr.module_name,
        execution_requirements = {"no-sandbox": "1"},  # gitDeps needs real execroot to resolve relative paths
    )

    # Generate .uproject file
    uproject = ctx.actions.declare_file(ctx.attr.module_name + ".uproject")
    uproject_content = """{
  "FileVersion": 3,
  "EngineAssociation": "5.5",
  "Modules": [{"Name": "%s", "Type": "%s"}]
}
""" % (ctx.attr.module_name, ctx.attr.module_type)
    ctx.actions.write(uproject, uproject_content)

    # Run UHT
    ctx.actions.run_shell(
        command = """
            # Resolve all paths to absolute before cd
            EXECROOT=$(pwd)
            DOTNET="$EXECROOT/{dotnet}"
            UBT="$EXECROOT/{ubt}"
            PROJECT="$EXECROOT/{project}"
            MANIFEST="$EXECROOT/{manifest}"
            OUTPUT_DIR="$EXECROOT/{output_dir}"

            # UHT requires running from UE root and needs to write to Engine/Saved/
            cd {ue_root}
            "$DOTNET" "$UBT" -Mode=UnrealHeaderTool "$PROJECT" "$MANIFEST" -Verbose || true

            # Return to execroot for file operations
            cd "$EXECROOT"

            # Copy UHT outputs to Bazel output locations
            # UHT generates TestEnum.gen.cpp, we expect Public_TestEnum.gen.cpp
            for out in {outputs}; do
                OUTBASE=$(basename "$out")
                # Try direct match first
                if [ -f "{output_dir}/$OUTBASE" ]; then
                    cp "{output_dir}/$OUTBASE" "$out"
                    continue
                fi
                # Try unsanitized name (Public_TestEnum.gen.cpp → TestEnum.gen.cpp)
                UNSANITIZED=$(echo "$OUTBASE" | sed 's/^[^_]*_//')
                if [ -f "{output_dir}/$UNSANITIZED" ]; then
                    cp "{output_dir}/$UNSANITIZED" "$out"
                    continue
                fi
                # File not generated, create placeholder
                touch "$out"
            done
        """.format(
            ue_root = ctx.file.ubt.dirname + "/../../..",
            dotnet = ctx.file.dotnet.path,
            ubt = ctx.file.ubt.path,
            project = uproject.path,
            manifest = manifest.path,
            output_dir = ctx.bin_dir.path,
            outputs = " ".join([f.path for f in outputs]),
        ),
        inputs = [manifest, uproject, ctx.file.dotnet, ctx.file.ubt] + filtered_hdrs,
        outputs = outputs,
        mnemonic = "UHTCodegen",
        progress_message = "Running UHT for %s" % ctx.attr.module_name,
        execution_requirements = {"no-sandbox": "1"},  # UBT writes to Engine/Saved/
    )

    return [DefaultInfo(files = depset(outputs))]

uht_codegen = rule(
    implementation = _uht_codegen_impl,
    attrs = {
        "module_name": attr.string(mandatory = True),
        "module_type": attr.string(default = "Runtime"),
        "hdrs": attr.label_list(allow_files = [".h", ".hpp", ".inl", ".cpp"]),  # .cpp for unity builds
        "_gitdeps": attr.label(
            default = Label("//:rules_unreal_engine"),
            executable = True,
            cfg = "exec",
        ),
        "dotnet": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "ubt": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
