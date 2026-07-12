#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

APP="$ROOT/dist/$OPENWHISPER_APP_NAME.app"
PLIST="$APP/Contents/Info.plist"

"$ROOT/scripts/package_app.sh" >/dev/null
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

if /usr/bin/plutil -extract LSUIElement raw -o - "$PLIST" >/dev/null 2>&1; then
  echo "Packaged app must not declare LSUIElement in Info.plist; runtime should switch to accessory mode explicitly." >&2
  exit 1
fi

ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if [[ "$ENTITLEMENTS" != *"com.apple.security.device.audio-input"* ]]; then
  echo "Packaged app is missing hardened runtime audio input entitlement." >&2
  exit 1
fi

for sound in recording-start.wav recording-stop.wav; do
  if [[ ! -f "$APP/Contents/Resources/Sounds/$sound" ]]; then
    echo "Packaged app is missing feedback sound resource: $sound" >&2
    exit 1
  fi
done

for localized_resource in \
  "zh-Hans.lproj/Localizable.strings" \
  "zh-Hans.lproj/InfoPlist.strings"; do
  if [[ ! -f "$APP/Contents/Resources/$localized_resource" ]]; then
    echo "Packaged app is missing Simplified Chinese resource: $localized_resource" >&2
    exit 1
  fi
done

LOCALIZATIONS="$(/usr/bin/plutil -extract CFBundleLocalizations json -o - "$PLIST")"
if [[ "$LOCALIZATIONS" != *'"zh-Hans"'* ]]; then
  echo "Packaged app does not declare the zh-Hans localization." >&2
  exit 1
fi

BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$PLIST")"
if [[ "$BUNDLE_ID" != "$OPENWHISPER_BUNDLE_ID" ]]; then
  echo "Packaged app bundle identifier mismatch: expected $OPENWHISPER_BUNDLE_ID, got $BUNDLE_ID" >&2
  exit 1
fi

EXECUTABLE_NAME="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$PLIST")"
if [[ "$EXECUTABLE_NAME" != "$OPENWHISPER_APP_NAME" ]]; then
  echo "Packaged app executable mismatch: expected $OPENWHISPER_APP_NAME, got $EXECUTABLE_NAME" >&2
  exit 1
fi

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$PLIST")"
if [[ "$VERSION" != "$OPENWHISPER_VERSION" ]]; then
  echo "Packaged app version mismatch: expected $OPENWHISPER_VERSION, got $VERSION" >&2
  exit 1
fi

BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$PLIST")"
if [[ "$BUILD" != "$OPENWHISPER_BUILD" ]]; then
  echo "Packaged app build mismatch: expected $OPENWHISPER_BUILD, got $BUILD" >&2
  exit 1
fi

SHA256_FILE="$ROOT/dist/SHA256SUMS"
if [[ ! -f "$SHA256_FILE" ]]; then
  echo "Missing SHA-256 manifest: $SHA256_FILE" >&2
  exit 1
fi
(
  cd "$ROOT/dist"
  /usr/bin/shasum -a 256 -c "$(basename "$SHA256_FILE")"
)

RELEASE_MANIFEST="$ROOT/dist/release-manifest.json"
if [[ ! -f "$RELEASE_MANIFEST" ]]; then
  echo "Missing release metadata manifest: $RELEASE_MANIFEST" >&2
  exit 1
fi

MANIFEST_VERSION="$(/usr/bin/plutil -extract release.version raw -o - "$RELEASE_MANIFEST")"
MANIFEST_BUILD="$(/usr/bin/plutil -extract release.build raw -o - "$RELEASE_MANIFEST")"
MANIFEST_BUNDLE_ID="$(/usr/bin/plutil -extract product.bundleIdentifier raw -o - "$RELEASE_MANIFEST")"
MANIFEST_ZIP_NAME="$(/usr/bin/plutil -extract artifacts.0.fileName raw -o - "$RELEASE_MANIFEST")"
MANIFEST_ZIP_SHA256="$(/usr/bin/plutil -extract artifacts.0.sha256 raw -o - "$RELEASE_MANIFEST")"
MANIFEST_DMG_NAME="$(/usr/bin/plutil -extract artifacts.1.fileName raw -o - "$RELEASE_MANIFEST")"
MANIFEST_DMG_SHA256="$(/usr/bin/plutil -extract artifacts.1.sha256 raw -o - "$RELEASE_MANIFEST")"

[[ "$MANIFEST_VERSION" == "$OPENWHISPER_VERSION" ]] || {
  echo "Release manifest version mismatch." >&2
  exit 1
}
[[ "$MANIFEST_BUILD" == "$OPENWHISPER_BUILD" ]] || {
  echo "Release manifest build mismatch." >&2
  exit 1
}
[[ "$MANIFEST_BUNDLE_ID" == "$OPENWHISPER_BUNDLE_ID" ]] || {
  echo "Release manifest bundle identifier mismatch." >&2
  exit 1
}

EXPECTED_ZIP_SHA256="$(/usr/bin/shasum -a 256 "$ROOT/dist/$MANIFEST_ZIP_NAME" | awk '{print $1}')"
EXPECTED_DMG_SHA256="$(/usr/bin/shasum -a 256 "$ROOT/dist/$MANIFEST_DMG_NAME" | awk '{print $1}')"
[[ "$MANIFEST_ZIP_SHA256" == "$EXPECTED_ZIP_SHA256" ]] || {
  echo "Release manifest ZIP checksum mismatch." >&2
  exit 1
}
[[ "$MANIFEST_DMG_SHA256" == "$EXPECTED_DMG_SHA256" ]] || {
  echo "Release manifest DMG checksum mismatch." >&2
  exit 1
}

echo "Packaged app metadata looks correct."
