#!/bin/bash
# TEMPORARY UHT Wrapper - Uses Epic's .NET UHT
# TODO: Replace with cmd/uht Go implementation (Phase 2)
#
# Usage:
#   ./tools/uht_wrapper.sh <ue-root> <project-file.uproject> <manifest-file.uhtmanifest>
#
# Arguments:
#   ue-root: Path to UnrealEngine installation (for bundled dotnet/UBT)
#   project-file: Path to .uproject file
#   manifest-file: Path to .uhtmanifest JSON
#
# This script invokes Epic's UnrealHeaderTool via bundled dotnet runtime.
# It's marked as TEMPORARY TECHNICAL DEBT and will be replaced with a pure Go implementation.

set -euo pipefail

UE_ROOT="$1"
PROJECT_FILE="$2"
MANIFEST_FILE="$3"

# Convert to absolute paths if needed (UBT requires absolute paths)
if [[ "$PROJECT_FILE" != /* ]]; then
    PROJECT_FILE="$(pwd)/$PROJECT_FILE"
fi
if [[ "$MANIFEST_FILE" != /* ]]; then
    MANIFEST_FILE="$(pwd)/$MANIFEST_FILE"
fi

if [ ! -d "$UE_ROOT" ]; then
    echo "Error: UnrealEngine installation not found at $UE_ROOT"
    exit 1
fi

# Bundled dotnet runtime (Mac ARM64)
DOTNET="$UE_ROOT/Engine/Binaries/ThirdParty/DotNet/8.0.300/mac-arm64/dotnet"

# UnrealBuildTool.dll with UHT mode
UBT_DLL="$UE_ROOT/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"

if [ ! -f "$DOTNET" ]; then
    echo "Error: Bundled dotnet not found at $DOTNET"
    exit 1
fi

if [ ! -f "$UBT_DLL" ]; then
    echo "Error: UnrealBuildTool.dll not found at $UBT_DLL"
    exit 1
fi

# Invoke UHT via UBT
# Must run from UE root for relative paths to work correctly
cd "$UE_ROOT"

"$DOTNET" "$UBT_DLL" \
    -Mode=UnrealHeaderTool \
    "$PROJECT_FILE" \
    "$MANIFEST_FILE" \
    -Verbose
