#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_ENV="$ROOT/product.env"
VERSION_ENV="$ROOT/version.env"
ENV_LOADER="$ROOT/scripts/lib/load_env.sh"

# shellcheck disable=SC1090
source "$ENV_LOADER"
load_product_env "$PRODUCT_ENV"
load_version_env "$VERSION_ENV"

: "${OPENWHISPER_APP_NAME:?OPENWHISPER_APP_NAME is required}"
: "${OPENWHISPER_BUNDLE_ID:?OPENWHISPER_BUNDLE_ID is required}"
: "${OPENWHISPER_MIN_MACOS:?OPENWHISPER_MIN_MACOS is required}"
: "${OPENWHISPER_VERSION:?OPENWHISPER_VERSION is required}"
: "${OPENWHISPER_BUILD:?OPENWHISPER_BUILD is required}"

APP_NAME="$OPENWHISPER_APP_NAME"
BUILD_DIR="$ROOT/.build/debug"
APP_DIR="$ROOT/dist/$APP_NAME.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_NAME"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
PLIST="$APP_DIR/Contents/Info.plist"
ICONSET_DIR="$ROOT/dist/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
ENTITLEMENTS_FILE="$ROOT/dist/OpenWhisper.entitlements"
SIGNING_IDENTITY="${OPENWHISPER_CODESIGN_IDENTITY:-}"
ALLOW_ADHOC_SIGNING="${OPENWHISPER_ALLOW_ADHOC_SIGNING:-0}"
REQUIRE_DEVELOPER_ID="${OPENWHISPER_REQUIRE_DEVELOPER_ID:-0}"
EXPECTED_TEAM_ID="${OPENWHISPER_TEAM_ID:-}"
NOTARIZE="${OPENWHISPER_NOTARIZE:-0}"
NOTARY_PROFILE="${OPENWHISPER_NOTARY_PROFILE:-}"
ADHOC_DESIGNATED_REQUIREMENT="=designated => identifier \"$OPENWHISPER_BUNDLE_ID\""

resolve_signing_identity() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    printf '%s\n' "$SIGNING_IDENTITY"
    return
  fi

  local resolved
  # Use the fingerprint so duplicate certificate names cannot select a revoked cert.
  resolved="$(security find-identity -v -p codesigning 2>/dev/null | awk '$0 !~ /CSSMERR_/ && ($0 ~ /Developer ID Application:/ || $0 ~ /Apple Development:/) { print $2; exit }')"
  if [[ -n "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return
  fi

  resolved="$(security find-identity -v -p codesigning 2>/dev/null | awk '$0 !~ /CSSMERR_/ && /Apple Development:/ { print $2; exit }')"
  printf '%s\n' "$resolved"
}

ARCH="$(uname -m)"
ZIP_PATH="$ROOT/dist/${APP_NAME}-${OPENWHISPER_VERSION}-macos-${ARCH}.zip"
DMG_PATH="$ROOT/dist/${APP_NAME}-${OPENWHISPER_VERSION}-macos-${ARCH}.dmg"
SHA256_PATH="$ROOT/dist/SHA256SUMS"
DMG_STAGING_DIR="$ROOT/dist/.dmg-staging"
DMG_RAW_PATH="$ROOT/dist/.${APP_NAME}-${OPENWHISPER_VERSION}-macos-${ARCH}.raw.dmg"
NOTARY_ZIP_PATH="$ROOT/dist/.${APP_NAME}-${OPENWHISPER_VERSION}-notary.zip"

mkdir -p "$ROOT/dist"
rm -rf "$APP_DIR"
rm -f "$ZIP_PATH"
rm -f "$DMG_PATH"
rm -f "$DMG_RAW_PATH"
rm -f "$NOTARY_ZIP_PATH"
rm -f "$ENTITLEMENTS_FILE"
rm -rf "$DMG_STAGING_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$RESOURCES_DIR"

swift build --package-path "$ROOT"
cp "$BUILD_DIR/$APP_NAME" "$EXECUTABLE"
chmod +x "$EXECUTABLE"
if [[ -d "$ROOT/Sources/OpenWhisper/Resources" ]]; then
  cp -R "$ROOT/Sources/OpenWhisper/Resources/." "$RESOURCES_DIR/"
fi
swift "$ROOT/scripts/render_app_icon.swift" "$ICONSET_DIR"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0">'
  printf '%s\n' '<dict>'
  printf '%s\n' '  <key>CFBundleDevelopmentRegion</key>'
  printf '%s\n' '  <string>en</string>'
  printf '%s\n' '  <key>CFBundleLocalizations</key>'
  printf '%s\n' '  <array>'
  printf '%s\n' '    <string>en</string>'
  printf '%s\n' '    <string>zh-Hans</string>'
  printf '%s\n' '  </array>'
  printf '%s\n' '  <key>CFBundleAllowMixedLocalizations</key>'
  printf '%s\n' '  <true/>'
  printf '%s\n' '  <key>CFBundleExecutable</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundleIdentifier</key>'
  printf '  <string>%s</string>\n' "$OPENWHISPER_BUNDLE_ID"
  printf '%s\n' '  <key>CFBundleIconFile</key>'
  printf '%s\n' '  <string>AppIcon</string>'
  printf '%s\n' '  <key>CFBundleInfoDictionaryVersion</key>'
  printf '%s\n' '  <string>6.0</string>'
  printf '%s\n' '  <key>CFBundleDisplayName</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundleName</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundlePackageType</key>'
  printf '%s\n' '  <string>APPL</string>'
  printf '%s\n' '  <key>CFBundleShortVersionString</key>'
  printf '  <string>%s</string>\n' "$OPENWHISPER_VERSION"
  printf '%s\n' '  <key>CFBundleVersion</key>'
  printf '  <string>%s</string>\n' "$OPENWHISPER_BUILD"
  printf '%s\n' '  <key>LSMinimumSystemVersion</key>'
  printf '  <string>%s</string>\n' "$OPENWHISPER_MIN_MACOS"
  printf '%s\n' '  <key>NSMicrophoneUsageDescription</key>'
  printf '%s\n' '  <string>OpenWhisper records short dictation clips and sends them through its own ChatGPT account session.</string>'
  printf '%s\n' '  <key>NSPrincipalClass</key>'
  printf '%s\n' '  <string>NSApplication</string>'
  printf '%s\n' '</dict>'
  printf '%s\n' '</plist>'
} >"$PLIST"

{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0">'
  printf '%s\n' '<dict>'
  printf '%s\n' '  <key>com.apple.security.device.audio-input</key>'
  printf '%s\n' '  <true/>'
  printf '%s\n' '</dict>'
  printf '%s\n' '</plist>'
} >"$ENTITLEMENTS_FILE"

SIGNING_IDENTITY="$(resolve_signing_identity)"
CODESIGN_ARGS=(--force)
if [[ -n "$SIGNING_IDENTITY" ]]; then
  CODESIGN_ARGS+=(--sign "$SIGNING_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS_FILE")
  if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    CODESIGN_ARGS+=(--timestamp)
  else
    CODESIGN_ARGS+=(--timestamp=none)
  fi
  SIGNING_SUMMARY="$SIGNING_IDENTITY"
elif [[ "$ALLOW_ADHOC_SIGNING" == "1" ]]; then
  CODESIGN_ARGS+=(
    --sign -
    --options runtime
    --requirements "$ADHOC_DESIGNATED_REQUIREMENT"
    --entitlements "$ENTITLEMENTS_FILE"
  )
  SIGNING_SUMMARY="ad-hoc"
else
  echo "No Apple Development or Developer ID Application signing identity is available." >&2
  echo "OpenWhisper's Accessibility repair flow relies on TCC recognizing the packaged app." >&2
  echo "Ad-hoc signing often opens System Settings without creating a toggleable OpenWhisper row." >&2
  echo "Install a stable code-signing identity, or rerun with OPENWHISPER_ALLOW_ADHOC_SIGNING=1 only if you explicitly accept that broken repair path." >&2
  exit 1
fi

/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_DIR" >/dev/null
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
  if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
    echo "A Developer ID Application identity is required for this release channel." >&2
    exit 1
  fi
  if [[ -z "$EXPECTED_TEAM_ID" ]]; then
    echo "OPENWHISPER_TEAM_ID is required for Developer ID release packaging." >&2
    exit 1
  fi

  SIGNATURE_DETAILS="$(/usr/bin/codesign -dvvv "$APP_DIR" 2>&1)"
  if [[ "$SIGNATURE_DETAILS" != *"Authority=Developer ID Application:"* ]]; then
    echo "Release signing must use a Developer ID Application certificate." >&2
    exit 1
  fi
  if [[ "$SIGNATURE_DETAILS" != *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]]; then
    echo "Release signing Team ID does not match OPENWHISPER_TEAM_ID." >&2
    exit 1
  fi
fi

if [[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "-" ]]; then
  ASSESSMENT_OUTPUT="$(/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_DIR" 2>&1 || true)"
  if grep -q "CSSMERR_TP_CERT_REVOKED" <<<"$ASSESSMENT_OUTPUT"; then
    if [[ "$ALLOW_ADHOC_SIGNING" == "1" ]]; then
      /usr/bin/codesign --remove-signature "$APP_DIR"
      /usr/bin/codesign \
        --force \
        --sign - \
        --options runtime \
        --requirements "$ADHOC_DESIGNATED_REQUIREMENT" \
        --entitlements "$ENTITLEMENTS_FILE" \
        "$APP_DIR" >/dev/null
      SIGNING_SUMMARY="ad-hoc with stable local designated requirement (stable identity was revoked)"
    else
      echo "The selected code-signing identity is revoked according to Gatekeeper:" >&2
      echo "$ASSESSMENT_OUTPUT" >&2
      echo "Renew the Apple Development certificate, or rerun with OPENWHISPER_ALLOW_ADHOC_SIGNING=1 only for local debugging." >&2
      rm -rf "$APP_DIR"
      exit 1
    fi
  fi
fi

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ "$REQUIRE_DEVELOPER_ID" != "1" ]]; then
    echo "Notarization requires OPENWHISPER_REQUIRE_DEVELOPER_ID=1." >&2
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "OPENWHISPER_NOTARY_PROFILE is required for notarization." >&2
    exit 1
  fi

  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARY_ZIP_PATH"
  /usr/bin/xcrun notarytool submit \
    "$NOTARY_ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$APP_DIR"
  /usr/bin/xcrun stapler validate "$APP_DIR"
  rm -f "$NOTARY_ZIP_PATH"
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
/usr/bin/hdiutil makehybrid \
  -hfs \
  -hfs-volume-name "$APP_NAME" \
  -o "$DMG_RAW_PATH" \
  "$DMG_STAGING_DIR" >/dev/null
/usr/bin/hdiutil convert "$DMG_RAW_PATH" -format UDZO -o "$DMG_PATH" >/dev/null

if [[ "$NOTARIZE" == "1" ]]; then
  /usr/bin/xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$DMG_PATH"
  /usr/bin/xcrun stapler validate "$DMG_PATH"
  /usr/sbin/spctl --assess --type execute --verbose=4 "$APP_DIR"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
fi

{
  cd "$ROOT/dist"
  /usr/bin/shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")"
} >"$SHA256_PATH.tmp"
mv "$SHA256_PATH.tmp" "$SHA256_PATH"

rm -rf "$DMG_STAGING_DIR"
rm -rf "$ICONSET_DIR"
rm -f "$ENTITLEMENTS_FILE"
rm -f "$DMG_RAW_PATH"
rm -f "$NOTARY_ZIP_PATH"

echo "Packaged $APP_DIR"
echo "Signed with $SIGNING_SUMMARY"
echo "Created $ZIP_PATH"
echo "Created $DMG_PATH"
echo "Created $SHA256_PATH"
