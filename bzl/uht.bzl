"""Bazel rules for UHT (UnrealHeaderTool) code generation.

This module provides a custom rule for running Epic's UnrealHeaderTool
to generate reflection code from UCLASS/USTRUCT/UENUM macros.
"""

load("//bzl:providers.bzl", "UeUhtInfo")


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

        # Skip Detail/ and Impl/ subdirectories (implementation details, never have macros)
        # Note: Private/ headers CAN have reflection macros (e.g., CoreUObject/Private/UObject/PropertyHelper.h)
        if "/Detail/" in path or "/Impl/" in path:
            continue

        # Skip NoExportTypes.h — its .gen.cpp references types from Slate/Engine
        # that aren't in CoreUObject's deps. The .generated.h is never included.
        if hdr.basename == "NoExportTypes.h":
            continue

        # Skip VerseVM internal headers (no reflection macros)
        # Epic's UBT scans headers and only includes ones with UCLASS/USTRUCT/UENUM
        # VVMValue.h, etc. don't have reflection macros, so Epic excludes them too
        # Only VVMVerse*.h headers (VVMVerseClass, VVMVerseStruct, etc.) have macros
        # TODO: Implement proper header scanning like UBT instead of path-based filtering
        if "/VerseVM/VVM" in path and not path.endswith("Verse.h") and "VVMVerse" not in path:
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

    # UHT output directory: per-module subdir so filenames don't collide
    # UHT writes files using header basenames (e.g., TestEnum.generated.h)
    # We declare Bazel outputs matching those exact names under a module-specific dir
    uht_output_dir = ctx.attr.module_name + "_uht_gen"

    # Declare output files using the names UHT actually writes
    outputs = []
    outputs.append(ctx.actions.declare_file(uht_output_dir + "/" + ctx.attr.module_name + ".init.gen.cpp"))

    for hdr in filtered_hdrs:
        basename_no_ext = hdr.basename.rsplit(".", 1)[0]
        outputs.append(ctx.actions.declare_file(uht_output_dir + "/" + basename_no_ext + ".generated.h"))
        outputs.append(ctx.actions.declare_file(uht_output_dir + "/" + basename_no_ext + ".gen.cpp"))

    # Generate manifest with uhtscan filtering
    manifest = ctx.actions.declare_file(ctx.attr.module_name + ".uhtmanifest")

    # The output directory for UHT is the declared output dir (absolute path resolved at action time)
    # We use the first output's dirname since all outputs share the same directory
    uht_output_path = outputs[0].dirname

    # Use run_shell to chain uhtscan → gitdeps manifest
    # uhtscan scans headers for UCLASS/USTRUCT/UENUM macros (matches Epic's UBT behavior)
    all_header_paths = " ".join([hdr.path for hdr in ctx.files.hdrs])

    ctx.actions.run_shell(
        command = """
            # Scan headers for reflection macros (like Epic's UBT does)
            UHTSCAN={uhtscan}
            FILTERED_HEADERS=$($UHTSCAN {headers})

            # Convert to comma-separated for gitdeps
            HEADERS_CSV=$(echo "$FILTERED_HEADERS" | tr '\\n' ',' | sed 's/,$//')

            # Derive BaseDirectory from first header (parent of Public/ or Private/)
            # E.g., external/.../CoreUObject/Public/Foo.h -> external/.../CoreUObject
            FIRST_HEADER=$(echo "$FILTERED_HEADERS" | head -1)
            if [ -n "$FIRST_HEADER" ]; then
                # Remove /Public/... or /Private/... to get module root
                BASE_DIR=$(echo "$FIRST_HEADER" | sed 's|/Public/.*||' | sed 's|/Private/.*||' | sed 's|/Internal/.*||')
            else
                # No headers with macros, use fallback
                BASE_DIR="{fallback_base_dir}"
            fi

            # Resolve output dir to absolute path
            EXECROOT=$(pwd)
            ABS_OUTPUT_DIR="$EXECROOT/{output_dir}"

            # Generate manifest with filtered headers
            GITDEPS={gitdeps}
            $GITDEPS uht manifest \\
                --module-name {module_name} \\
                --module-type {module_type} \\
                --game-target={game_target} \\
                --base-dir "$BASE_DIR" \\
                --output-dir "$ABS_OUTPUT_DIR" \\
                --headers "$HEADERS_CSV" \\
                --output {manifest}
        """.format(
            uhtscan = ctx.executable._uhtscan.path,
            gitdeps = ctx.executable._gitdeps.path,
            headers = all_header_paths,
            module_name = ctx.attr.module_name,
            module_type = ctx.attr.module_type,
            game_target = "true" if ctx.attr.game_target else "false",
            fallback_base_dir = ctx.bin_dir.path,
            output_dir = uht_output_path,
            manifest = manifest.path,
        ),
        inputs = ctx.files.hdrs,
        outputs = [manifest],
        tools = [ctx.executable._uhtscan, ctx.executable._gitdeps],
        mnemonic = "UHTManifest",
        progress_message = "Scanning and generating UHT manifest for %s" % ctx.attr.module_name,
        execution_requirements = {"no-sandbox": "1"},  # uhtscan and gitDeps need real execroot
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

    # Run UHT — outputs go directly to the declared output directory
    ctx.actions.run_shell(
        command = """
            EXECROOT=$(pwd)
            DOTNET="$EXECROOT/{dotnet}"
            UBT="$EXECROOT/{ubt}"
            PROJECT="$EXECROOT/{project}"
            MANIFEST="$EXECROOT/{manifest}"
            OUTPUT_DIR="$EXECROOT/{output_dir}"

            # Ensure output directory exists
            mkdir -p "$OUTPUT_DIR"

            # UHT requires running from UE root
            cd {ue_root}
            "$DOTNET" "$UBT" -Mode=UnrealHeaderTool "$PROJECT" "$MANIFEST" -NoGoWide
            UHT_EXIT=$?
            if [ $UHT_EXIT -ne 0 ]; then
                echo "ERROR: UHT failed with exit code $UHT_EXIT" >&2
                cat {ue_root}/Engine/Programs/UnrealHeaderTool/Saved/Logs/UnrealHeaderTool.log >&2
                exit $UHT_EXIT
            fi

            # Create empty stubs for any declared outputs UHT didn't generate
            # (modules without reflection macros legitimately produce 0 files)
            cd "$EXECROOT"
            for out in {outputs}; do
                if [ ! -f "$out" ]; then
                    touch "$out"
                fi
            done
        """.format(
            ue_root = ctx.file.ubt.dirname + "/../../..",
            dotnet = ctx.file.dotnet.path,
            ubt = ctx.file.ubt.path,
            project = uproject.path,
            manifest = manifest.path,
            output_dir = uht_output_path,
            outputs = " ".join([f.path for f in outputs]),
        ),
        inputs = [manifest, uproject, ctx.file.dotnet, ctx.file.ubt] + filtered_hdrs,
        outputs = outputs,
        mnemonic = "UHTCodegen",
        progress_message = "Running UHT for %s" % ctx.attr.module_name,
        execution_requirements = {"no-sandbox": "1"},  # UBT writes to Engine/Saved/
    )

    generated_hdrs = [f for f in outputs if f.path.endswith(".generated.h")]
    generated_srcs = [f for f in outputs if f.path.endswith(".cpp")]

    return [
        DefaultInfo(files = depset(outputs)),
        UeUhtInfo(
            generated_hdrs = depset(generated_hdrs),
            generated_srcs = depset(generated_srcs),
            include_dir = uht_output_path,
        ),
    ]

uht_codegen = rule(
    implementation = _uht_codegen_impl,
    attrs = {
        "module_name": attr.string(mandatory = True),
        "module_type": attr.string(default = "Runtime"),
        "game_target": attr.bool(default = True),
        "hdrs": attr.label_list(allow_files = [".h", ".hpp", ".inl", ".cpp"]),  # .cpp for unity builds
        "_gitdeps": attr.label(
            default = Label("//:rules_unreal_engine"),
            executable = True,
            cfg = "exec",
        ),
        "_uhtscan": attr.label(
            default = Label("//cmd/uhtscan"),
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
