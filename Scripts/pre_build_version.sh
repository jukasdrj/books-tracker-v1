#!/bin/bash
# pre_build_version.sh - Auto-update build number before Xcode builds
# Add this as a "Run Script" build phase in Xcode

set -e

# Only run in CI or when FORCE_VERSION_UPDATE is set
if [[ "$CI" != "true" && "$FORCE_VERSION_UPDATE" != "true" ]]; then
    echo "Skipping version update (not in CI). Set FORCE_VERSION_UPDATE=true to force."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔄 Auto-updating build number..."
"$SCRIPT_DIR/update_version.sh" build

echo "✅ Build number updated successfully"