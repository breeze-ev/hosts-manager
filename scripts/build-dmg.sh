#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$ROOT_DIR/hosts-manager.xcodeproj/project.pbxproj"

# Defaults are read from the Xcode project so a bare `./scripts/build-dmg.sh` works.
VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PBXPROJ" | head -1)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' "$PBXPROJ" | head -1)}"
TEAM_ID="${TEAM_ID:-$(sed -n 's/.*DEVELOPMENT_TEAM = \([^;]*\);.*/\1/p' "$PBXPROJ" | head -1)}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
ADHOC="${ADHOC:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --team-id)
      TEAM_ID="$2"
      shift 2
      ;;
    --signing-identity)
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    --adhoc)
      ADHOC=1
      SKIP_NOTARIZE=1
      SIGNING_IDENTITY="-"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TEAM_ID" ]]; then
  echo "Missing required --team-id" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/export-options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

mkdir -p "$ROOT_DIR/$OUTPUT_DIR"

DMG_PATHS=()

for ARCH in arm64 x86_64; do
  ARCHIVE_PATH="$WORK_DIR/HostsManager-${ARCH}.xcarchive"
  EXPORT_PATH="$WORK_DIR/export-${ARCH}"
  STAGING_PATH="$WORK_DIR/staging-${ARCH}"
  DMG_PATH="$ROOT_DIR/$OUTPUT_DIR/Hosts-Manager-${VERSION}-${BUILD_NUMBER}-${ARCH}.dmg"

  echo "Archiving Hosts Manager v${VERSION} (${BUILD_NUMBER}) [${ARCH}]..."
  if [[ "$ADHOC" == "1" ]]; then
    xcodebuild archive \
      -project "$ROOT_DIR/hosts-manager.xcodeproj" \
      -scheme hosts-manager \
      -configuration Release \
      -destination 'generic/platform=macOS' \
      -archivePath "$ARCHIVE_PATH" \
      -derivedDataPath "$WORK_DIR/DerivedData-${ARCH}" \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=YES \
      MARKETING_VERSION="$VERSION" \
      CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
      BUMP_BUILD_NUMBER=0 \
      ARCHS="$ARCH" \
      ONLY_ACTIVE_ARCH=NO
    APP_PATH="$ARCHIVE_PATH/Products/Applications/Hosts Manager.app"
  else
    xcodebuild archive \
      -project "$ROOT_DIR/hosts-manager.xcodeproj" \
      -scheme hosts-manager \
      -configuration Release \
      -destination 'generic/platform=macOS' \
      -archivePath "$ARCHIVE_PATH" \
      -derivedDataPath "$WORK_DIR/DerivedData-${ARCH}" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
      CODE_SIGN_STYLE=Manual \
      MARKETING_VERSION="$VERSION" \
      CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
      BUMP_BUILD_NUMBER=0 \
      ARCHS="$ARCH" \
      ONLY_ACTIVE_ARCH=NO

    echo "Exporting signed app [${ARCH}]..."
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$WORK_DIR/export-options.plist"
    APP_PATH="$EXPORT_PATH/Hosts Manager.app"
  fi

  HELPER_PATH="$APP_PATH/Contents/MacOS/HostsManagerHelper"

  echo "Verifying signatures and architecture [${ARCH}]..."
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  codesign --verify --strict --verbose=2 "$HELPER_PATH"

  for binary in "$APP_PATH/Contents/MacOS/Hosts Manager" "$HELPER_PATH"; do
    architectures="$(lipo -archs "$binary")"
    if [[ "$architectures" != "$ARCH" ]]; then
      echo "Expected single-arch ${ARCH}, got: ${architectures}" >&2
      exit 1
    fi
  done

  mkdir -p "$STAGING_PATH"
  ditto "$APP_PATH" "$STAGING_PATH/Hosts Manager.app"
  ln -s /Applications "$STAGING_PATH/Applications"

  echo "Creating DMG [${ARCH}]..."
  hdiutil create \
    -volname "Hosts Manager" \
    -srcfolder "$STAGING_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
  DMG_PATHS+=("$DMG_PATH")
done

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  echo "Skipping notarization."
  printf 'Built %s\n' "${DMG_PATHS[@]}"
  exit 0
fi

if [[ -z "${APPLE_API_KEY_ID:-}" || -z "${APPLE_API_ISSUER_ID:-}" || -z "${APPLE_API_KEY_PATH:-}" ]]; then
  echo "Notarization requested but APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, and APPLE_API_KEY_PATH are not set." >&2
  exit 1
fi

for DMG_PATH in "${DMG_PATHS[@]}"; do
  echo "Submitting for notarization: $DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" \
    --wait \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --key "$APPLE_API_KEY_PATH" \
    --team-id "$TEAM_ID"

  echo "Stapling and validating..."
  xcrun stapler staple "$DMG_PATH"
  spctl --assess --type execute --verbose=4 "$DMG_PATH" || true
done

printf 'Built %s\n' "${DMG_PATHS[@]}"
