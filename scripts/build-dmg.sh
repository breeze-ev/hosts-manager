#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
TEAM_ID="${TEAM_ID:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ARCHIVE_PATH="$WORK_DIR/HostsManager.xcarchive"
EXPORT_PATH="$WORK_DIR/export"
STAGING_PATH="$WORK_DIR/staging"
DMG_NAME="Hosts-Manager-${VERSION}-universal.dmg"
DMG_PATH="$ROOT_DIR/$OUTPUT_DIR/$DMG_NAME"

echo "Archiving Hosts Manager v${VERSION} (${BUILD_NUMBER})..."
xcodebuild archive \
  -project "$ROOT_DIR/hosts-manager.xcodeproj" \
  -scheme hosts-manager \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

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

echo "Exporting signed app..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$WORK_DIR/export-options.plist"

APP_PATH="$EXPORT_PATH/Hosts Manager.app"
HELPER_PATH="$APP_PATH/Contents/MacOS/HostsManagerHelper"

echo "Verifying signatures and architectures..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --verify --strict --verbose=2 "$HELPER_PATH"

for binary in "$APP_PATH/Contents/MacOS/Hosts Manager" "$HELPER_PATH"; do
  architectures="$(lipo -archs "$binary")"
  if ! [[ "$architectures" =~ arm64 && "$architectures" =~ x86_64 ]]; then
    echo "Expected universal arm64 + x86_64, got: $architectures" >&2
    exit 1
  fi
done

mkdir -p "$STAGING_PATH"
ditto "$APP_PATH" "$STAGING_PATH/Hosts Manager.app"
ln -s /Applications "$STAGING_PATH/Applications"

mkdir -p "$ROOT_DIR/$OUTPUT_DIR"
echo "Creating DMG..."
hdiutil create \
  -volname "Hosts Manager" \
  -srcfolder "$STAGING_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  echo "Skipping notarization."
  exit 0
fi

if [[ -z "${APPLE_API_KEY_ID:-}" || -z "${APPLE_API_ISSUER_ID:-}" || -z "${APPLE_API_KEY_PATH:-}" ]]; then
  echo "Notarization requested but APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, and APPLE_API_KEY_PATH are not set." >&2
  exit 1
fi

echo "Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --wait \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --key "$APPLE_API_KEY_PATH" \
  --team-id "$TEAM_ID"

echo "Stapling and validating..."
xcrun stapler staple "$DMG_PATH"
spctl --assess --type execute --verbose=4 "$DMG_PATH" || true

echo "Built $DMG_PATH"
