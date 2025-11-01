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

# Function to install BUILD file
install_build() {
    local src="$1"
    local dst="$2"

    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "[DRY RUN] Would copy: $src -> $dst"
    else
        echo "Installing: $dst"
        cp "$src" "$dst"
    fi
}

# Install Runtime modules
if [ -f "$UE_MODULES_DIR/Runtime/Core/BUILD.bazel" ]; then
    install_build "$UE_MODULES_DIR/Runtime/Core/BUILD.bazel" \
                  "$UE_PATH/Engine/Source/Runtime/Core/BUILD.bazel"
fi

if [ -f "$UE_MODULES_DIR/Runtime/TraceLog/BUILD.bazel" ]; then
    install_build "$UE_MODULES_DIR/Runtime/TraceLog/BUILD.bazel" \
                  "$UE_PATH/Engine/Source/Runtime/TraceLog/BUILD.bazel"
fi

if [ -f "$UE_MODULES_DIR/Runtime/BuildSettings/BUILD.bazel" ]; then
    install_build "$UE_MODULES_DIR/Runtime/BuildSettings/BUILD.bazel" \
                  "$UE_PATH/Engine/Source/Runtime/BuildSettings/BUILD.bazel"
fi

# Install ThirdParty modules
if [ -f "$UE_MODULES_DIR/ThirdParty/AtomicQueue/BUILD.bazel" ]; then
    install_build "$UE_MODULES_DIR/ThirdParty/AtomicQueue/BUILD.bazel" \
                  "$UE_PATH/Engine/Source/ThirdParty/AtomicQueue/BUILD.bazel"
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
