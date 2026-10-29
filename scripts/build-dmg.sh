#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$ROOT_DIR/hosts-manager.xcodeproj/project.pbxproj"
BUILD_NUMBER_CONFIG="$ROOT_DIR/Config/BuildNumber.xcconfig"

# Defaults are read from the Xcode project so a bare `./scripts/build-dmg.sh` works.
VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PBXPROJ" | head -1)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9]*\).*/\1/p' "$BUILD_NUMBER_CONFIG" 2>/dev/null || echo 1)}"
TEAM_ID="${TEAM_ID:-$(sed -n 's/.*DEVELOPMENT_TEAM = \([^;]*\);.*/\1/p' "$PBXPROJ" | head -1)}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
ADHOC="${ADHOC:-0}"
DEV="${DEV:-0}"
GENERATE_APPCAST="${GENERATE_APPCAST:-0}"
RELEASE_NOTES_HTML="${RELEASE_NOTES_HTML:-}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-personal.hosts-manager}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<'USAGE'
Usage: build-dmg.sh [options]

Signing modes (pick one):
  (default)            Developer ID signing + notarization (paid certificate; for release)
  --dev                Apple Development signing, skips notarization; stable identity so the
                       SMAppService background helper works. Recommended without a paid account.
  --adhoc              Ad-hoc signing, no certificate needed. WARNING: Login Items approval
                       never sticks for ad-hoc builds, so the background helper stays
                       unavailable. Only useful for UI testing.

Other options:
  --version V          Marketing version (default: read from the Xcode project)
  --build-number N     Build number (default: read from the Xcode project)
  --team-id ID         Development team ID (default: read from the Xcode project)
  --signing-identity S Override the code signing identity
  --output-dir DIR     Output directory (default: dist)
  --skip-notarize      Build signed DMGs without notarizing

For a complete development-signed release and Sparkle appcast, use:
  ./scripts/release-local.sh --version VERSION --build-number N
USAGE
      exit 0
      ;;
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
    --dev)
      # Sign with an Apple Development certificate. Unlike adhoc builds this
      # gives the app a stable code-signing identity, so SMAppService login
      # item approval sticks across launches.
      DEV=1
      SKIP_NOTARIZE=1
      SIGNING_IDENTITY="Apple Development"
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

RELEASE_TAG="${RELEASE_TAG:-$VERSION}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/export-options-dev.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

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
DMG_ARCHES=()

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
  elif [[ "$DEV" == "1" ]]; then
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

    echo "Exporting development-signed app [${ARCH}]..."
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$WORK_DIR/export-options-dev.plist"
    APP_PATH="$EXPORT_PATH/Hosts Manager.app"
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

  DMG_PATHS+=("$DMG_PATH")
  DMG_ARCHES+=("$ARCH")
done

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  echo "Skipping notarization."
else
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
fi

for DMG_PATH in "${DMG_PATHS[@]}"; do
  shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
done

if [[ "$GENERATE_APPCAST" == "1" ]]; then
  for index in "${!DMG_PATHS[@]}"; do
    ARCH="${DMG_ARCHES[$index]}"
    DERIVED_DATA="$WORK_DIR/DerivedData-${ARCH}"
    SPARKLE_TOOL="$(find "$DERIVED_DATA" -type f \
      -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' \
      -print -quit)"
    if [[ -z "$SPARKLE_TOOL" ]]; then
      echo "Sparkle generate_appcast was not found in ${DERIVED_DATA}" >&2
      exit 1
    fi

    APPCAST_PATH="$ROOT_DIR/$OUTPUT_DIR/appcast-${ARCH}.xml"
    if [[ -n "$RELEASE_NOTES_HTML" ]]; then
      "$ROOT_DIR/scripts/generate-appcast.sh" \
        --arch "$ARCH" \
        --dmg "${DMG_PATHS[$index]}" \
        --output "$APPCAST_PATH" \
        --tool "$SPARKLE_TOOL" \
        --release-tag "$RELEASE_TAG" \
        --sparkle-account "$SPARKLE_ACCOUNT" \
        --release-notes "$RELEASE_NOTES_HTML"
    else
      "$ROOT_DIR/scripts/generate-appcast.sh" \
        --arch "$ARCH" \
        --dmg "${DMG_PATHS[$index]}" \
        --output "$APPCAST_PATH" \
        --tool "$SPARKLE_TOOL" \
        --release-tag "$RELEASE_TAG" \
        --sparkle-account "$SPARKLE_ACCOUNT"
    fi
  done
fi

printf 'Built %s\n' "${DMG_PATHS[@]}"
