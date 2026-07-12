#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

APP="$ROOT/dist/$OPENWHISPER_APP_NAME.app"
DMG="$ROOT/dist/${OPENWHISPER_APP_NAME}-${OPENWHISPER_VERSION}-macos-$(uname -m).dmg"
MANIFEST="${OPENWHISPER_RELEASE_MANIFEST_PATH:-$ROOT/dist/release-manifest.json}"
CASK="$ROOT/packaging/homebrew/Casks/openwhisper.rb"
EXPECTED_TEAM_ID="${OPENWHISPER_TEAM_ID:-}"

[[ -n "$EXPECTED_TEAM_ID" ]] || {
  echo "OPENWHISPER_TEAM_ID is required for the commercial release gate." >&2
  exit 1
}
[[ -d "$APP" && -f "$DMG" && -f "$MANIFEST" ]] || {
  echo "Missing signed release artifacts or release manifest." >&2
  exit 1
}

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE_DETAILS="$(/usr/bin/codesign -dvvv "$APP" 2>&1)"
[[ "$SIGNATURE_DETAILS" == *"Authority=Developer ID Application:"* ]] || {
  echo "Commercial release requires Developer ID Application signing." >&2
  exit 1
}
[[ "$SIGNATURE_DETAILS" == *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]] || {
  echo "Commercial release Team ID mismatch." >&2
  exit 1
}

/usr/bin/xcrun stapler validate "$APP"
/usr/bin/xcrun stapler validate "$DMG"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP"
/usr/sbin/spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "$DMG"

MANIFEST_VERSION="$(/usr/bin/plutil -extract release.version raw -o - "$MANIFEST")"
MANIFEST_BUILD="$(/usr/bin/plutil -extract release.build raw -o - "$MANIFEST")"
ZIP_SHA256="$(/usr/bin/plutil -extract artifacts.0.sha256 raw -o - "$MANIFEST")"
[[ "$MANIFEST_VERSION" == "$OPENWHISPER_VERSION" ]] || {
  echo "Release manifest version mismatch." >&2
  exit 1
}
[[ "$MANIFEST_BUILD" == "$OPENWHISPER_BUILD" ]] || {
  echo "Release manifest build mismatch." >&2
  exit 1
}
grep -q "version \"$OPENWHISPER_VERSION\"" "$CASK"
grep -q "sha256 \"$ZIP_SHA256\"" "$CASK"
if grep -q "sha256 :no_check" "$CASK"; then
  echo "Homebrew Cask checksum verification is disabled." >&2
  exit 1
fi

PLIST="$APP/Contents/Info.plist"
if ! /usr/bin/plutil -extract SUFeedURL raw -o - "$PLIST" >/dev/null 2>&1; then
  echo "Signed updater feed is not configured (missing SUFeedURL)." >&2
  exit 1
fi
if ! /usr/bin/plutil -extract SUPublicEDKey raw -o - "$PLIST" >/dev/null 2>&1; then
  echo "Signed updater verification key is not configured (missing SUPublicEDKey)." >&2
  exit 1
fi

echo "OpenWhisper commercial release gate passed."
