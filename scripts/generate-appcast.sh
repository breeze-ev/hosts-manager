#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH=""
DMG_PATH=""
OUTPUT_PATH=""
TOOL_PATH=""
RELEASE_NOTES_HTML=""
RELEASE_TAG=""
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-personal.hosts-manager}"

usage() {
  cat <<'USAGE'
Usage: generate-appcast.sh --arch ARCH --dmg FILE --output FILE --tool FILE [options]

Options:
  --release-tag TAG       GitHub release tag used for download URLs
  --release-notes FILE    HTML release notes copied beside the DMG
  --sparkle-account NAME  Keychain account for local signing

Set SPARKLE_PRIVATE_KEY to pass a CI private key through stdin. Otherwise the
Sparkle private key is read from the macOS Keychain.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) ARCH="$2"; shift 2 ;;
    --dmg) DMG_PATH="$2"; shift 2 ;;
    --output) OUTPUT_PATH="$2"; shift 2 ;;
    --tool) TOOL_PATH="$2"; shift 2 ;;
    --release-tag) RELEASE_TAG="$2"; shift 2 ;;
    --release-notes) RELEASE_NOTES_HTML="$2"; shift 2 ;;
    --sparkle-account) SPARKLE_ACCOUNT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ARCH" || -z "$DMG_PATH" || -z "$OUTPUT_PATH" || -z "$TOOL_PATH" ]]; then
  usage >&2
  exit 1
fi
if [[ ! -x "$TOOL_PATH" ]]; then
  echo "Sparkle generate_appcast tool not found: $TOOL_PATH" >&2
  exit 1
fi
SIGN_TOOL_PATH="$(dirname "$TOOL_PATH")/sign_update"
if [[ ! -x "$SIGN_TOOL_PATH" ]]; then
  echo "Sparkle sign_update tool not found: $SIGN_TOOL_PATH" >&2
  exit 1
fi
if [[ ! -f "$DMG_PATH" ]]; then
  echo "Update DMG not found: $DMG_PATH" >&2
  exit 1
fi
if [[ -z "$RELEASE_TAG" ]]; then
  echo "Missing --release-tag" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp "$DMG_PATH" "$STAGE_DIR/"
DMG_NAME="$(basename "$DMG_PATH")"

if [[ -n "$RELEASE_NOTES_HTML" && -f "$RELEASE_NOTES_HTML" ]]; then
  cp "$RELEASE_NOTES_HTML" "$STAGE_DIR/${DMG_NAME%.dmg}.html"
fi

EXISTING_APPCAST="$ROOT_DIR/Sparkle/appcast-${ARCH}.xml"
if [[ -f "$EXISTING_APPCAST" ]]; then
  cp "$EXISTING_APPCAST" "$STAGE_DIR/appcast.xml"
fi

DOWNLOAD_PREFIX="https://github.com/breeze-ev/hosts-manager/releases/download/${RELEASE_TAG}/"
mkdir -p "$(dirname "$OUTPUT_PATH")"

COMMON_ARGS=(
  --account "$SPARKLE_ACCOUNT"
  --download-url-prefix "$DOWNLOAD_PREFIX"
  --link "https://breeze-ev.github.io/hosts-manager/"
  --embed-release-notes
  --maximum-versions 3
  -o "$OUTPUT_PATH"
  "$STAGE_DIR"
)

sign_file() {
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" |
      "$SIGN_TOOL_PATH" --ed-key-file - "$@"
  else
    "$SIGN_TOOL_PATH" --account "$SPARKLE_ACCOUNT" "$@"
  fi
}

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" |
    "$TOOL_PATH" --ed-key-file - "${COMMON_ARGS[@]}"
else
  "$TOOL_PATH" "${COMMON_ARGS[@]}"
fi

# Existing apps that predate Sparkle have no SUPublicEDKey in their bundle, so
# generate_appcast cannot infer that the new enclosure should be signed.
if ! rg -q "<enclosure[^>]*${DMG_NAME}[^>]*sparkle:edSignature[^>]*>" "$OUTPUT_PATH"; then
  SIGNATURE_OUTPUT="$(sign_file "$DMG_PATH")"
  DMG_SIGNATURE="$(printf '%s\n' "$SIGNATURE_OUTPUT" |
    sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')"
  if [[ -z "$DMG_SIGNATURE" || "$DMG_SIGNATURE" == "$SIGNATURE_OUTPUT" ]]; then
    echo "Unable to parse the Sparkle DMG signature" >&2
    exit 1
  fi

  python3 - "$OUTPUT_PATH" "$DMG_NAME" "$DMG_SIGNATURE" <<'PY'
import re
import sys
from pathlib import Path

appcast_path, dmg_name, signature = sys.argv[1:]
path = Path(appcast_path)
text = path.read_text()
marker = re.escape(dmg_name)
pattern = re.compile(
    rf"<enclosure\b(?=[^>]*{marker})(?![^>]*sparkle:edSignature)[^>]*>",
    re.IGNORECASE,
)

def add_signature(match: re.Match[str]) -> str:
    tag = re.sub(r"\s*/?>$", "", match.group(0))
    return f'{tag} sparkle:edSignature="{signature}"/>'

text, count = pattern.subn(add_signature, text, count=1)
if count != 1:
    raise SystemExit(f"Expected one unsigned enclosure for {dmg_name}, patched {count}")
path.write_text(text)
PY
fi

sign_file "$OUTPUT_PATH" >/dev/null

if ! rg -q 'sparkle-signatures:' "$OUTPUT_PATH"; then
  echo "Generated appcast feed is not signed: $OUTPUT_PATH" >&2
  exit 1
fi

echo "Generated signed appcast: $OUTPUT_PATH"
