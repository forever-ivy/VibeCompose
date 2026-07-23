#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

APP="${VIBEWHISPER_RELEASE_APP_PATH:-$ROOT/dist/$VIBEWHISPER_APP_NAME.app}"
MANIFEST="${VIBEWHISPER_RELEASE_MANIFEST_PATH:-$ROOT/dist/release-manifest.json}"
LOCAL_ZIP="$ROOT/dist/${VIBEWHISPER_APP_NAME}-${VIBEWHISPER_VERSION}-macos-$(uname -m).zip"
LOCAL_APPCAST="${VIBEWHISPER_SPARKLE_APPCAST_PATH:-$ROOT/dist/appcast.xml}"
LOCAL_POLICY="${VIBEWHISPER_CAPABILITY_POLICY_PATH:-$ROOT/dist/provider-capabilities.json}"

[[ -d "$APP" \
  && -f "$MANIFEST" \
  && -f "$LOCAL_ZIP" \
  && -f "$LOCAL_APPCAST" \
  && ! -L "$LOCAL_APPCAST" \
  && -f "$LOCAL_POLICY" \
  && ! -L "$LOCAL_POLICY" ]] || {
  echo "Missing packaged app, release manifest, local ZIP, appcast, or capability policy." >&2
  exit 1
}

PLIST="$APP/Contents/Info.plist"
FEED_URL="$(/usr/bin/plutil -extract SUFeedURL raw -o - "$PLIST")"
SPARKLE_PUBLIC_KEY="$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$PLIST")"
CAPABILITY_POLICY_URL="$(/usr/bin/plutil -extract OWCapabilityPolicyURL raw -o - "$PLIST")"
CAPABILITY_PUBLIC_KEY="$(/usr/bin/plutil -extract OWCapabilityPublicEDKey raw -o - "$PLIST")"
ZIP_URL="$(/usr/bin/plutil -extract artifacts.0.downloadURL raw -o - "$MANIFEST")"
ZIP_SHA256="$(/usr/bin/plutil -extract artifacts.0.sha256 raw -o - "$MANIFEST")"
DMG_URL="$(/usr/bin/plutil -extract artifacts.1.downloadURL raw -o - "$MANIFEST")"
DMG_SHA256="$(/usr/bin/plutil -extract artifacts.1.sha256 raw -o - "$MANIFEST")"

for url in "$FEED_URL" "$CAPABILITY_POLICY_URL" "$ZIP_URL" "$DMG_URL"; do
  [[ "$url" == https://* \
    && "$url" != *"@"* \
    && "$url" != *"?"* \
    && "$url" != *"#"* ]] || {
    echo "Remote release URLs must be credential-free canonical HTTPS URLs: $url" >&2
    exit 1
  }
done

TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/vibewhisper-remote-release.XXXXXX")"
chmod 0700 "$TEMPORARY_DIRECTORY"
trap 'rm -rf "$TEMPORARY_DIRECTORY"' EXIT

download() {
  local url="$1"
  local output="$2"
  local maximum_bytes="$3"
  /usr/bin/curl \
    --fail \
    --silent \
    --show-error \
    --proto '=https' \
    --tlsv1.2 \
    --max-redirs 0 \
    --max-filesize "$maximum_bytes" \
    --output "$output" \
    "$url"
  [[ -s "$output" && ! -L "$output" ]] || {
    echo "Remote release download is empty or unsafe: $url" >&2
    exit 1
  }
}

REMOTE_ZIP="$TEMPORARY_DIRECTORY/release.zip"
REMOTE_DMG="$TEMPORARY_DIRECTORY/release.dmg"
REMOTE_APPCAST="$TEMPORARY_DIRECTORY/appcast.xml"
REMOTE_POLICY="$TEMPORARY_DIRECTORY/provider-capabilities.json"

download "$ZIP_URL" "$REMOTE_ZIP" $((1024 * 1024 * 1024))
download "$DMG_URL" "$REMOTE_DMG" $((1024 * 1024 * 1024))
download "$FEED_URL" "$REMOTE_APPCAST" $((2 * 1024 * 1024))
download "$CAPABILITY_POLICY_URL" "$REMOTE_POLICY" $((64 * 1024))

actual_zip_sha256="$(/usr/bin/shasum -a 256 "$REMOTE_ZIP" | awk '{print $1}')"
actual_dmg_sha256="$(/usr/bin/shasum -a 256 "$REMOTE_DMG" | awk '{print $1}')"
[[ "$actual_zip_sha256" == "$ZIP_SHA256" ]] || {
  echo "Remote ZIP SHA-256 does not match the release manifest." >&2
  exit 1
}
[[ "$actual_dmg_sha256" == "$DMG_SHA256" ]] || {
  echo "Remote DMG SHA-256 does not match the release manifest." >&2
  exit 1
}
/usr/bin/cmp -s "$REMOTE_APPCAST" "$LOCAL_APPCAST" || {
  echo "Published appcast does not exactly match the gated local appcast." >&2
  exit 1
}
/usr/bin/cmp -s "$REMOTE_POLICY" "$LOCAL_POLICY" || {
  echo "Published provider capability policy does not exactly match the gated local policy." >&2
  exit 1
}

/usr/bin/xmllint --noout "$REMOTE_APPCAST"
"$ROOT/scripts/verify_sparkle_appcast.swift" \
  --appcast "$REMOTE_APPCAST" \
  --archive "$LOCAL_ZIP" \
  --manifest "$MANIFEST" \
  --public-key "$SPARKLE_PUBLIC_KEY"
"$ROOT/scripts/verify_provider_capability_policy.swift" \
  --policy "$REMOTE_POLICY" \
  --public-key "$CAPABILITY_PUBLIC_KEY" \
  --build "$VIBEWHISPER_BUILD"

echo "Remote VibeWhisper release assets, appcast, and provider policy verified."
