#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$ROOT_DIR/hosts-manager.xcodeproj/project.pbxproj"
BUILD_NUMBER_CONFIG="$ROOT_DIR/Config/BuildNumber.xcconfig"

VERSION=""
BUILD_NUMBER=""
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-personal.hosts-manager}"
SKIP_UPLOAD=0
SKIP_PUSH=0

usage() {
  cat <<'USAGE'
Usage: release-local.sh --version VERSION [options]

Builds and signs both architectures with the local free Apple Development
certificate, generates signed Sparkle appcasts, creates a GitHub Release, and
commits the updated appcasts.

Requirements:
  - Xcode and a valid "Apple Development" signing identity in the Keychain
  - Sparkle private key in the Keychain
  - GitHub CLI authenticated with permission to publish releases
  - pandoc

Options:
  --version VERSION          Marketing version, for example 1.0.1
  --build-number N           Defaults to Config/BuildNumber.xcconfig
  --sparkle-account NAME     Sparkle Keychain account
  --skip-upload              Build locally without creating a GitHub Release
  --skip-push                Do not commit or push the generated appcasts
  --help, -h                 Show this help
USAGE
}

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
    --sparkle-account)
      SPARKLE_ACCOUNT="$2"
      shift 2
      ;;
    --skip-upload)
      SKIP_UPLOAD=1
      shift
      ;;
    --skip-push)
      SKIP_PUSH=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Missing required --version" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Version may only contain letters, digits, dots, underscores, and hyphens." >&2
  exit 1
fi
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9]*\).*/\1/p' "$BUILD_NUMBER_CONFIG" 2>/dev/null || true)"
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Missing build number. Pass --build-number or create Config/BuildNumber.xcconfig." >&2
  exit 1
fi

TEAM_ID="$(sed -n 's/.*DEVELOPMENT_TEAM = \([^;]*\);.*/\1/p' "$PBXPROJ" | head -1)"
if [[ -z "$TEAM_ID" ]]; then
  echo "Unable to read DEVELOPMENT_TEAM from hosts-manager.xcodeproj." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -q '"Apple Development:'; then
  echo "No Apple Development signing identity found. Sign in with a free Apple ID in Xcode first." >&2
  exit 1
fi
if ! command -v pandoc >/dev/null 2>&1; then
  echo "pandoc is required to render Sparkle release notes. Install it with: brew install pandoc" >&2
  exit 1
fi
if [[ "$SKIP_UPLOAD" != "1" ]] && ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required to publish a release. Install it with: brew install gh" >&2
  exit 1
fi
if [[ "$SKIP_UPLOAD" != "1" ]] && ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

NOTES_MARKDOWN="$WORK_DIR/release-notes.md"
NOTES_HTML="$WORK_DIR/release-notes.html"

awk -v version="$VERSION" '
  $0 ~ "^## " version "([[:space:]]|$)" { found=1; next }
  found && /^## / { exit }
  found { print }
' "$ROOT_DIR/CHANGELOG.md" > "$NOTES_MARKDOWN"

if [[ ! -s "$NOTES_MARKDOWN" ]]; then
  awk '
    /^## Unreleased$/ { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$ROOT_DIR/CHANGELOG.md" > "$NOTES_MARKDOWN"
fi
if [[ ! -s "$NOTES_MARKDOWN" ]]; then
  echo "No release notes found in CHANGELOG.md for ${VERSION}." >&2
  exit 1
fi

{
  printf '<style>body{background:#fff;color:#1d1d1f;font:14px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;line-height:1.55;padding:8px 4px}h2{font-size:20px;margin:0 0 12px}h3{font-size:15px;margin:18px 0 8px}code{background:#f2f2f7;border-radius:4px;padding:1px 4px}li{margin:4px 0}</style>\n'
  printf '<h2>Hosts Manager %s</h2>\n' "$VERSION"
  pandoc -f gfm -t html5 "$NOTES_MARKDOWN"
} > "$NOTES_HTML"

echo "Building Hosts Manager ${VERSION} (${BUILD_NUMBER}) with Apple Development signing..."
(
  cd "$ROOT_DIR"
  # Sparkle's generator can merge an appcast already present at the output path.
  # Remove only generated local feeds so a smoke-test build cannot leak into a release.
  rm -f "$ROOT_DIR/dist/appcast-arm64.xml" "$ROOT_DIR/dist/appcast-x86_64.xml"
  GENERATE_APPCAST=1 \
  RELEASE_NOTES_HTML="$NOTES_HTML" \
  RELEASE_TAG="$VERSION" \
  SPARKLE_ACCOUNT="$SPARKLE_ACCOUNT" \
    ./scripts/build-dmg.sh \
      --dev \
      --team-id "$TEAM_ID" \
      --version "$VERSION" \
      --build-number "$BUILD_NUMBER"
)

for arch in arm64 x86_64; do
  DMG_PATH="$ROOT_DIR/dist/Hosts-Manager-${VERSION}-${BUILD_NUMBER}-${arch}.dmg"
  APPCAST_PATH="$ROOT_DIR/dist/appcast-${arch}.xml"
  if [[ ! -f "$DMG_PATH" || ! -f "$DMG_PATH.sha256" || ! -f "$APPCAST_PATH" ]]; then
    echo "Release artifact is missing for ${arch}." >&2
    exit 1
  fi
  if ! grep -q 'sparkle-signatures:' "$APPCAST_PATH"; then
    echo "Generated appcast is not signed for ${arch}." >&2
    exit 1
  fi
  if ! grep -Fq "<sparkle:version>${BUILD_NUMBER}</sparkle:version>" "$APPCAST_PATH"; then
    echo "Generated appcast does not contain build ${BUILD_NUMBER} for ${arch}." >&2
    exit 1
  fi
done

if [[ "$SKIP_UPLOAD" == "1" ]]; then
  echo "Build-only mode complete; the GitHub Release and appcast were not published."
  echo "DMGs: $ROOT_DIR/dist"
  exit 0
fi

echo "Creating GitHub Release ${VERSION}..."
gh release create "$VERSION" \
  "$ROOT_DIR"/dist/Hosts-Manager-"${VERSION}"-"${BUILD_NUMBER}"-*.dmg \
  "$ROOT_DIR"/dist/Hosts-Manager-"${VERSION}"-"${BUILD_NUMBER}"-*.dmg.sha256 \
  "$ROOT_DIR"/dist/appcast-*.xml \
  --repo breeze-ev/hosts-manager \
  --title "Hosts Manager ${VERSION}" \
  --notes-file "$NOTES_MARKDOWN" \
  --latest

cp "$ROOT_DIR"/dist/appcast-arm64.xml "$ROOT_DIR/Sparkle/appcast-arm64.xml"
cp "$ROOT_DIR"/dist/appcast-x86_64.xml "$ROOT_DIR/Sparkle/appcast-x86_64.xml"

if [[ "$SKIP_PUSH" != "1" ]]; then
  git -C "$ROOT_DIR" add Sparkle/appcast-arm64.xml Sparkle/appcast-x86_64.xml
  if ! git -C "$ROOT_DIR" diff --cached --quiet; then
    git -C "$ROOT_DIR" commit -m "Update Sparkle appcast for ${VERSION}"
    git -C "$ROOT_DIR" push origin "HEAD:$(git -C "$ROOT_DIR" branch --show-current)"
  fi
fi

echo "Release workflow complete."
echo "DMGs: $ROOT_DIR/dist"
echo "Appcasts: $ROOT_DIR/Sparkle"
