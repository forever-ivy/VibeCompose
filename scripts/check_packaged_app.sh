#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

PACKAGED_APP="$ROOT/dist/$VIBECOMPOSE_APP_NAME.app"
CHECK_WORK_DIR="$(/usr/bin/mktemp -d /tmp/vibecompose-package-check.XXXXXX)"
APP="$CHECK_WORK_DIR/$VIBECOMPOSE_APP_NAME.app"
cleanup_check_work_dir() {
  rm -rf "$CHECK_WORK_DIR"
}
trap cleanup_check_work_dir EXIT
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/$VIBECOMPOSE_APP_NAME"
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"

"$ROOT/scripts/package_app.sh" >/dev/null
# Desktop File Provider can attach FinderInfo to the published bundle after
# packaging completes. Validate a metadata-free byte-for-byte copy under /tmp
# so those host xattrs cannot turn an intact code signature into a false fail.
/usr/bin/ditto --norsrc --noextattr --noqtn "$PACKAGED_APP" "$APP"
swift "$ROOT/scripts/verify_dependency_licenses.swift" \
  --root "$ROOT" \
  --app-resources "$APP/Contents/Resources"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Packaged app is missing the embedded Sparkle framework." >&2
  exit 1
fi

SPARKLE_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$SPARKLE_FRAMEWORK/Resources/Info.plist")"
if [[ "$SPARKLE_VERSION" != "2.9.4" ]]; then
  echo "Unexpected embedded Sparkle version: $SPARKLE_VERSION" >&2
  exit 1
fi

if ! /usr/bin/otool -L "$EXECUTABLE" \
  | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle'; then
  echo "VibeCompose is not linked against the embedded Sparkle framework." >&2
  exit 1
fi

if ! /usr/bin/otool -l "$EXECUTABLE" \
  | awk '
      $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
      in_rpath && $1 == "path" {
        if ($2 == "@executable_path/../Frameworks") {
          found = 1
        }
        in_rpath = 0
      }
      END { exit(found ? 0 : 1) }
    '; then
  echo "VibeCompose is missing the app Frameworks runtime search path." >&2
  exit 1
fi

FEED_URL="$(/usr/bin/plutil -extract SUFeedURL raw -o - "$PLIST" 2>/dev/null || true)"
PUBLIC_KEY="$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$PLIST" 2>/dev/null || true)"
if [[ -n "$FEED_URL" || -n "$PUBLIC_KEY" ]]; then
  [[ "$FEED_URL" == https://* && "$FEED_URL" != *"@"* ]] || {
    echo "Packaged Sparkle feed must use credential-free HTTPS." >&2
    exit 1
  }
  [[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || {
    echo "Packaged Sparkle public key is not a 32-byte base64 Ed25519 key." >&2
    exit 1
  }
fi

CAPABILITY_POLICY_URL="$(/usr/bin/plutil -extract OWCapabilityPolicyURL raw -o - "$PLIST" 2>/dev/null || true)"
CAPABILITY_PUBLIC_KEY="$(/usr/bin/plutil -extract OWCapabilityPublicEDKey raw -o - "$PLIST" 2>/dev/null || true)"
if [[ -n "$CAPABILITY_POLICY_URL" || -n "$CAPABILITY_PUBLIC_KEY" ]]; then
  [[ "$CAPABILITY_POLICY_URL" == https://* \
    && "$CAPABILITY_POLICY_URL" != *"@"* \
    && "$CAPABILITY_POLICY_URL" != *"?"* \
    && "$CAPABILITY_POLICY_URL" != *"#"* ]] || {
    echo "Packaged provider capability policy must use credential-free HTTPS without query or fragment." >&2
    exit 1
  }
  [[ "$CAPABILITY_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || {
    echo "Packaged provider capability public key is not a 32-byte base64 Ed25519 key." >&2
    exit 1
  }
fi

if /usr/bin/plutil -extract LSUIElement raw -o - "$PLIST" >/dev/null 2>&1; then
  echo "Packaged app must not declare LSUIElement in Info.plist; runtime should switch to accessory mode explicitly." >&2
  exit 1
fi

ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if [[ "$ENTITLEMENTS" != *"com.apple.security.device.audio-input"* ]]; then
  echo "Packaged app is missing hardened runtime audio input entitlement." >&2
  exit 1
fi
SIGNATURE_DETAILS="$(/usr/bin/codesign -dvvv "$APP" 2>&1)"
if [[ "$SIGNATURE_DETAILS" == *"Signature=adhoc"* ]]; then
  if [[ "$ENTITLEMENTS" != *"com.apple.security.cs.disable-library-validation"* ]]; then
    echo "Ad-hoc Sparkle builds require a local-only library-validation exception." >&2
    exit 1
  fi
elif [[ "$SIGNATURE_DETAILS" == *"Authority=Developer ID Application:"* \
  && "$ENTITLEMENTS" == *"com.apple.security.cs.disable-library-validation"* ]]; then
  echo "Developer ID releases must not disable library validation." >&2
  exit 1
fi

for sound in recording-start.wav recording-stop.wav; do
  if [[ ! -f "$APP/Contents/Resources/Sounds/$sound" ]]; then
    echo "Packaged app is missing feedback sound resource: $sound" >&2
    exit 1
  fi
done

for brand_resource in AppIcon.icns StatusBarLogoTemplate.png; do
  if [[ ! -f "$APP/Contents/Resources/$brand_resource" ]]; then
    echo "Packaged app is missing brand resource: $brand_resource" >&2
    exit 1
  fi
done

STATUS_ICON_WIDTH="$(/usr/bin/sips -g pixelWidth "$APP/Contents/Resources/StatusBarLogoTemplate.png" | awk '/pixelWidth:/ { print $2 }')"
STATUS_ICON_HEIGHT="$(/usr/bin/sips -g pixelHeight "$APP/Contents/Resources/StatusBarLogoTemplate.png" | awk '/pixelHeight:/ { print $2 }')"
STATUS_ICON_ALPHA="$(/usr/bin/sips -g hasAlpha "$APP/Contents/Resources/StatusBarLogoTemplate.png" | awk '/hasAlpha:/ { print $2 }')"
if [[ "$STATUS_ICON_WIDTH" != "72" \
  || "$STATUS_ICON_HEIGHT" != "72" \
  || "$STATUS_ICON_ALPHA" != "yes" ]]; then
  echo "Packaged status bar template must be a 72x72 PNG with alpha." >&2
  exit 1
fi

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
if [[ "$BUNDLE_ID" != "$VIBECOMPOSE_BUNDLE_ID" ]]; then
  echo "Packaged app bundle identifier mismatch: expected $VIBECOMPOSE_BUNDLE_ID, got $BUNDLE_ID" >&2
  exit 1
fi

EXECUTABLE_NAME="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$PLIST")"
if [[ "$EXECUTABLE_NAME" != "$VIBECOMPOSE_APP_NAME" ]]; then
  echo "Packaged app executable mismatch: expected $VIBECOMPOSE_APP_NAME, got $EXECUTABLE_NAME" >&2
  exit 1
fi

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$PLIST")"
if [[ "$VERSION" != "$VIBECOMPOSE_VERSION" ]]; then
  echo "Packaged app version mismatch: expected $VIBECOMPOSE_VERSION, got $VERSION" >&2
  exit 1
fi

BUILD="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$PLIST")"
if [[ "$BUILD" != "$VIBECOMPOSE_BUILD" ]]; then
  echo "Packaged app build mismatch: expected $VIBECOMPOSE_BUILD, got $BUILD" >&2
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

[[ "$MANIFEST_VERSION" == "$VIBECOMPOSE_VERSION" ]] || {
  echo "Release manifest version mismatch." >&2
  exit 1
}
[[ "$MANIFEST_BUILD" == "$VIBECOMPOSE_BUILD" ]] || {
  echo "Release manifest build mismatch." >&2
  exit 1
}
[[ "$MANIFEST_BUNDLE_ID" == "$VIBECOMPOSE_BUNDLE_ID" ]] || {
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
