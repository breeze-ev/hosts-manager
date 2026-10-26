#!/bin/bash
# Increment the local build number (CURRENT_PROJECT_VERSION) by 1.
# The number lives in Config/BuildNumber.xcconfig, which is git-ignored.
set -euo pipefail

# Only bump on Release builds (archives); Debug builds leave the file untouched.
if [ "${CONFIGURATION:-Release}" != "Release" ]; then
    echo "Skipping build number bump (configuration: ${CONFIGURATION})"
    exit 0
fi

# Packaging scripts pin the build number explicitly; don't auto-bump there.
if [ "${BUMP_BUILD_NUMBER:-1}" = "0" ]; then
    echo "Skipping build number bump (BUMP_BUILD_NUMBER=0)"
    exit 0
fi

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIG="$ROOT/Config/BuildNumber.xcconfig"

if [ ! -f "$CONFIG" ]; then
    cp "$ROOT/Config/BuildNumber.xcconfig.example" "$CONFIG"
fi

current=$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9]*\).*/\1/p' "$CONFIG")
next=$((current + 1))
sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $next/" "$CONFIG"
echo "Bumped build number: $current -> $next (applies to the next build)"
