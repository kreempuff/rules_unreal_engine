#!/usr/bin/env bash
# Test runner for rules_unreal_engine
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo "❌ BATS is not installed"
    echo ""
    echo "Install with:"
    echo "  brew install bats-core  # macOS"
    echo "  apt-get install bats    # Debian/Ubuntu"
    echo ""
    exit 1
fi

echo "🧪 Running rules_unreal_engine tests..."
echo ""

# Build the binary first
echo "📦 Building binary..."
cd "$PROJECT_ROOT"
bazel build //:rules_unreal_engine
echo ""

# Run BATS tests
echo "🏃 Running BATS tests..."
bats "$SCRIPT_DIR/gitdeps.bats"
