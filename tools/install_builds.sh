#!/bin/bash
# Install UE module BUILD files into an Unreal Engine checkout
#
# Usage:
#   ./tools/install_builds.sh /path/to/UnrealEngine
#   ./tools/install_builds.sh /path/to/UnrealEngine --dry-run

set -e

UE_PATH="$1"
DRY_RUN="$2"

if [ -z "$UE_PATH" ]; then
    echo "Usage: $0 <path-to-unreal-engine> [--dry-run]"
    echo ""
    echo "Example:"
    echo "  $0 /Users/you/UnrealEngine"
    echo "  $0 /Users/you/UnrealEngine --dry-run"
    exit 1
fi

if [ ! -d "$UE_PATH/Engine/Source" ]; then
    echo "Error: $UE_PATH doesn't look like an Unreal Engine directory"
    echo "Expected to find: $UE_PATH/Engine/Source"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UE_MODULES_DIR="$SCRIPT_DIR/ue_modules"

echo "Installing UE module BUILD files..."
echo "From: $UE_MODULES_DIR"
echo "To:   $UE_PATH/Engine/Source"
echo ""

# Discover and install all BUILD files from ue_modules/
install_count=0
find "$UE_MODULES_DIR" -name "BUILD.bazel" -type f | while read build_file; do
    # Extract relative path from ue_modules/
    # e.g., /path/to/ue_modules/Runtime/Core/BUILD.bazel -> Runtime/Core
    rel_path="${build_file#$UE_MODULES_DIR/}"
    module_path="${rel_path%/BUILD.bazel}"

    # Destination in UE
    dest="$UE_PATH/Engine/Source/$module_path/BUILD.bazel"

    # Check if destination directory exists
    if [ -d "$(dirname "$dest")" ]; then
        if [ "$DRY_RUN" = "--dry-run" ]; then
            echo "[DRY RUN] Would copy: $module_path/BUILD.bazel"
        else
            echo "Installing: Engine/Source/$module_path/BUILD.bazel"
            cp "$build_file" "$dest"
        fi
        install_count=$((install_count + 1))
    else
        echo "Warning: Skipping $module_path (directory not found in UE)"
    fi
done

if [ "$install_count" -eq 0 ]; then
    echo "Warning: No BUILD files found to install"
fi

# Create MODULE.bazel if it doesn't exist
MODULE_BAZEL="$UE_PATH/MODULE.bazel"
if [ ! -f "$MODULE_BAZEL" ]; then
    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "[DRY RUN] Would create: $MODULE_BAZEL"
    else
        echo "Creating: $MODULE_BAZEL"
        cat > "$MODULE_BAZEL" << 'EOF'
module(name = "unreal_engine", version = "5.5.0")

bazel_dep(name = "platforms", version = "1.0.0")
bazel_dep(name = "rules_cc", version = "0.2.13")
bazel_dep(name = "rules_unreal_engine", version = "0.1.0")

# For local development, uncomment and adjust path:
# local_path_override(
#     module_name = "rules_unreal_engine",
#     path = "../rules_unreal_engine",
# )
EOF
    fi
else
    echo "Skipping MODULE.bazel (already exists)"
fi

echo ""
if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "Dry run complete. Run without --dry-run to actually install files."
else
    echo "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  cd $UE_PATH"
    echo "  bazel build //Engine/Source/Runtime/Core"
fi
