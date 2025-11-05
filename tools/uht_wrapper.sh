#!/bin/bash
# TEMPORARY UHT Wrapper - Uses Epic's .NET UHT
# TODO: Replace with cmd/uht Go implementation (Phase 2)
#
# Usage:
#   ./tools/uht_wrapper.sh <dotnet-binary> <ubt-dll> <project-file.uproject> <manifest-file.uhtmanifest>
#
# Arguments:
#   dotnet-binary: Path to bundled dotnet executable
#   ubt-dll: Path to UnrealBuildTool.dll
#   project-file: Path to .uproject file
#   manifest-file: Path to .uhtmanifest JSON
#
# This script invokes Epic's UnrealHeaderTool via bundled dotnet runtime.
# It's marked as TEMPORARY TECHNICAL DEBT and will be replaced with a pure Go implementation.

set -euo pipefail

DOTNET="$1"
UBT_DLL="$2"
PROJECT_FILE="$3"
MANIFEST_FILE="$4"

# Convert to absolute paths if needed (UBT requires absolute paths)
if [[ "$PROJECT_FILE" != /* ]]; then
    PROJECT_FILE="$(pwd)/$PROJECT_FILE"
fi
if [[ "$MANIFEST_FILE" != /* ]]; then
    MANIFEST_FILE="$(pwd)/$MANIFEST_FILE"
fi

# Validate inputs
if [ ! -f "$DOTNET" ]; then
    echo "Error: dotnet binary not found at $DOTNET"
    exit 1
fi

if [ ! -f "$UBT_DLL" ]; then
    echo "Error: UnrealBuildTool.dll not found at $UBT_DLL"
    exit 1
fi

# Get UE root from UBT.dll location
# Path: Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll
# UE_ROOT is 4 levels up
UE_ROOT="$(cd "$(dirname "$UBT_DLL")/../../../.." && pwd)"

# Invoke UHT via UBT
# Must run from UE root for relative paths to work correctly
cd "$UE_ROOT"

"$DOTNET" "$UBT_DLL" \
    -Mode=UnrealHeaderTool \
    "$PROJECT_FILE" \
    "$MANIFEST_FILE" \
    -Verbose
