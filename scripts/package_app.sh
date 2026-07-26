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

swift "$ROOT/scripts/verify_dependency_licenses.swift" \
  --root "$ROOT"
python3 "$ROOT/scripts/verify_repository_hygiene.py"

: "${VIBECOMPOSE_APP_NAME:?VIBECOMPOSE_APP_NAME is required}"
: "${VIBECOMPOSE_BUNDLE_ID:?VIBECOMPOSE_BUNDLE_ID is required}"
: "${VIBECOMPOSE_MIN_MACOS:?VIBECOMPOSE_MIN_MACOS is required}"
: "${VIBECOMPOSE_VERSION:?VIBECOMPOSE_VERSION is required}"
: "${VIBECOMPOSE_BUILD:?VIBECOMPOSE_BUILD is required}"

APP_NAME="$VIBECOMPOSE_APP_NAME"
BUILD_CONFIGURATION="${VIBECOMPOSE_BUILD_CONFIGURATION:-debug}"
case "$BUILD_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "VIBECOMPOSE_BUILD_CONFIGURATION must be debug or release." >&2
    exit 1
    ;;
esac
BUILD_DIR="$ROOT/.build/$BUILD_CONFIGURATION"
# Assemble and codesign under /tmp first. Desktop/iCloud File Provider re-applies
# FinderInfo/fpfs xattrs on nested Sparkle XPC bundles mid-sign, which fails with
# "resource fork, Finder information, or similar detritus not allowed". The final
# signed app is published into dist/ after verification.
PACKAGE_WORK_DIR="$(/usr/bin/mktemp -d /tmp/vibecompose-package.XXXXXX)"
cleanup_package_work_dir() {
  rm -rf "$PACKAGE_WORK_DIR"
}
trap cleanup_package_work_dir EXIT
DIST_APP_DIR="$ROOT/dist/$APP_NAME.app"
DIST_PUBLISH_DIR="$ROOT/dist/.${APP_NAME}.publish"
APP_DIR="$PACKAGE_WORK_DIR/$APP_NAME.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_NAME"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
PLIST="$APP_DIR/Contents/Info.plist"
SPARKLE_FRAMEWORK_SOURCE="$BUILD_DIR/Sparkle.framework"
SPARKLE_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"
ICONSET_DIR="$PACKAGE_WORK_DIR/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
ICON_SOURCE="$ROOT/packaging/assets/VibeComposeLogoSource.png"
STATUS_ICON_FILE="$RESOURCES_DIR/StatusBarLogoTemplate.png"
ENTITLEMENTS_FILE="$PACKAGE_WORK_DIR/VibeCompose.entitlements"
SIGNING_IDENTITY="${VIBECOMPOSE_CODESIGN_IDENTITY:-}"
ALLOW_ADHOC_SIGNING="${VIBECOMPOSE_ALLOW_ADHOC_SIGNING:-0}"
REQUIRE_DEVELOPER_ID="${VIBECOMPOSE_REQUIRE_DEVELOPER_ID:-0}"
EXPECTED_TEAM_ID="${VIBECOMPOSE_TEAM_ID:-}"
NOTARIZE="${VIBECOMPOSE_NOTARIZE:-0}"
NOTARY_PROFILE="${VIBECOMPOSE_NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${VIBECOMPOSE_NOTARY_KEYCHAIN:-}"
SPARKLE_FEED_URL="${VIBECOMPOSE_SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${VIBECOMPOSE_SPARKLE_PUBLIC_ED_KEY:-}"
CAPABILITY_POLICY_URL="${VIBECOMPOSE_CAPABILITY_POLICY_URL:-}"
CAPABILITY_PUBLIC_ED_KEY="${VIBECOMPOSE_CAPABILITY_PUBLIC_ED_KEY:-}"
ADHOC_DESIGNATED_REQUIREMENT="=designated => identifier \"$VIBECOMPOSE_BUNDLE_ID\""

strip_codesign_hostile_xattrs() {
  local app="$1"
  /usr/bin/xattr -cr "$app" >/dev/null 2>&1 || true
  /usr/bin/chflags -R nouchg,noschg,nohidden "$app" >/dev/null 2>&1 || true
  /usr/bin/find "$app" \( -type f -o -type d \) -print0 2>/dev/null \
    | while IFS= read -r -d '' path; do
        /usr/bin/xattr -d com.apple.FinderInfo "$path" >/dev/null 2>&1 || true
        /usr/bin/xattr -d com.apple.fileprovider.fpfs#P "$path" >/dev/null 2>&1 || true
        /usr/bin/xattr -d com.apple.fileprovider.detached#P "$path" >/dev/null 2>&1 || true
      done
}

resolve_signing_identity() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    printf '%s\n' "$SIGNING_IDENTITY"
    return
  fi

  local resolved
  # Use the fingerprint so duplicate certificate names cannot select a revoked cert.
  # A release must never select Apple Development merely because it sorts first.
  if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    resolved="$(security find-identity -v -p codesigning 2>/dev/null | awk '$0 !~ /CSSMERR_/ && /Developer ID Application:/ { print $2; exit }')"
    printf '%s\n' "$resolved"
    return
  fi

  resolved="$(security find-identity -v -p codesigning 2>/dev/null | awk '$0 !~ /CSSMERR_/ && /Apple Development:/ { print $2; exit }')"
  if [[ -n "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return
  fi

  resolved="$(security find-identity -v -p codesigning 2>/dev/null | awk '$0 !~ /CSSMERR_/ && /Developer ID Application:/ { print $2; exit }')"
  printf '%s\n' "$resolved"
}

ARCH="$(uname -m)"
ZIP_PATH="$ROOT/dist/${APP_NAME}-${VIBECOMPOSE_VERSION}-macos-${ARCH}.zip"
DMG_PATH="$ROOT/dist/${APP_NAME}-${VIBECOMPOSE_VERSION}-macos-${ARCH}.dmg"
SHA256_PATH="$ROOT/dist/SHA256SUMS"
DMG_STAGING_DIR="$ROOT/dist/.dmg-staging"
DMG_RAW_PATH="$ROOT/dist/.${APP_NAME}-${VIBECOMPOSE_VERSION}-macos-${ARCH}.raw.dmg"
NOTARY_ZIP_PATH="$ROOT/dist/.${APP_NAME}-${VIBECOMPOSE_VERSION}-notary.zip"
APP_NOTARIZATION_RESULT="$ROOT/dist/notarization-app.json"
DMG_NOTARIZATION_RESULT="$ROOT/dist/notarization-dmg.json"

if [[ "$REQUIRE_DEVELOPER_ID" == "1" && "$BUILD_CONFIGURATION" != "release" ]]; then
  echo "Developer ID release packaging requires VIBECOMPOSE_BUILD_CONFIGURATION=release." >&2
  exit 1
fi

mkdir -p "$ROOT/dist"
rm -rf "$DIST_APP_DIR"
rm -rf "$DIST_PUBLISH_DIR"
rm -rf "$APP_DIR"
rm -f "$ZIP_PATH"
rm -f "$DMG_PATH"
rm -f "$DMG_RAW_PATH"
rm -f "$NOTARY_ZIP_PATH"
rm -f \
  "$APP_NOTARIZATION_RESULT" \
  "$APP_NOTARIZATION_RESULT.tmp" \
  "$DMG_NOTARIZATION_RESULT" \
  "$DMG_NOTARIZATION_RESULT.tmp"
rm -f "$ENTITLEMENTS_FILE"
rm -rf "$DMG_STAGING_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

swift build \
  --package-path "$ROOT" \
  --configuration "$BUILD_CONFIGURATION"
cp "$BUILD_DIR/$APP_NAME" "$EXECUTABLE"
chmod +x "$EXECUTABLE"
if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "SwiftPM did not produce Sparkle.framework at $SPARKLE_FRAMEWORK_SOURCE." >&2
  exit 1
fi
# Copy without resource forks / extended attributes. Sparkle's SPM binary zip
# can carry Finder/FileProvider xattrs that make codesign reject nested XPC
# bundles with "resource fork, Finder information, or similar detritus not
# allowed". Plain `ditto` + `xattr -cr` is not enough for those attributes.
/usr/bin/ditto --norsrc --noextattr --noqtn \
  "$SPARKLE_FRAMEWORK_SOURCE" \
  "$SPARKLE_FRAMEWORK"
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
  /usr/bin/install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$EXECUTABLE"
fi
if [[ -d "$ROOT/Sources/VibeCompose/Resources" ]]; then
  cp -R "$ROOT/Sources/VibeCompose/Resources/." "$RESOURCES_DIR/"
  # Desktop/iCloud File Provider can stamp UF_HIDDEN on nested resources after
  # copy. Clear it so runtime FileManager enumeration (and Finder) see SKILL.md.
  /usr/bin/chflags -R nouchg,noschg,nohidden "$RESOURCES_DIR" >/dev/null 2>&1 || true
fi
swift "$ROOT/scripts/verify_dependency_licenses.swift" \
  --root "$ROOT" \
  --app-resources "$RESOURCES_DIR"
swift "$ROOT/scripts/render_app_icon.swift" \
  "$ICON_SOURCE" \
  "$ICONSET_DIR" \
  "$STATUS_ICON_FILE"
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
  printf '  <string>%s</string>\n' "$VIBECOMPOSE_BUNDLE_ID"
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
  printf '  <string>%s</string>\n' "$VIBECOMPOSE_VERSION"
  printf '%s\n' '  <key>CFBundleVersion</key>'
  printf '  <string>%s</string>\n' "$VIBECOMPOSE_BUILD"
  printf '%s\n' '  <key>LSMinimumSystemVersion</key>'
  printf '  <string>%s</string>\n' "$VIBECOMPOSE_MIN_MACOS"
  printf '%s\n' '  <key>NSMicrophoneUsageDescription</key>'
  printf '%s\n' '  <string>VibeCompose records short dictation clips and sends them through its own ChatGPT account session.</string>'
  printf '%s\n' '  <key>NSPrincipalClass</key>'
  printf '%s\n' '  <string>NSApplication</string>'
  printf '%s\n' '</dict>'
  printf '%s\n' '</plist>'
} >"$PLIST"

if [[ -n "$SPARKLE_FEED_URL" || -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  if [[ -z "$SPARKLE_FEED_URL" || -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "Sparkle feed URL and public EdDSA key must be configured together." >&2
    exit 1
  fi
  if [[ "$SPARKLE_FEED_URL" != https://* \
    || "$SPARKLE_FEED_URL" == *"@"* \
    || "$SPARKLE_FEED_URL" == *[[:space:]\<\>\"\'\\]* ]]; then
    echo "VIBECOMPOSE_SPARKLE_FEED_URL must be a credential-free HTTPS URL." >&2
    exit 1
  fi
  if [[ ! "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "VIBECOMPOSE_SPARKLE_PUBLIC_ED_KEY must be a 32-byte base64 Ed25519 public key." >&2
    exit 1
  fi
  /usr/bin/plutil -insert SUFeedURL -string "$SPARKLE_FEED_URL" "$PLIST"
  /usr/bin/plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$PLIST"
fi

if [[ "$REQUIRE_DEVELOPER_ID" == "1" \
  && ( -z "$SPARKLE_FEED_URL" || -z "$SPARKLE_PUBLIC_ED_KEY" ) ]]; then
  echo "Developer ID release packaging requires Sparkle feed and public-key configuration." >&2
  exit 1
fi

if [[ -n "$CAPABILITY_POLICY_URL" || -n "$CAPABILITY_PUBLIC_ED_KEY" ]]; then
  if [[ -z "$CAPABILITY_POLICY_URL" || -z "$CAPABILITY_PUBLIC_ED_KEY" ]]; then
    echo "Provider capability policy URL and public Ed25519 key must be configured together." >&2
    exit 1
  fi
  if [[ "$CAPABILITY_POLICY_URL" != https://* \
    || "$CAPABILITY_POLICY_URL" == *"@"* \
    || "$CAPABILITY_POLICY_URL" == *"?"* \
    || "$CAPABILITY_POLICY_URL" == *"#"* \
    || "$CAPABILITY_POLICY_URL" == *[[:space:]\<\>\"\'\\]* ]]; then
    echo "VIBECOMPOSE_CAPABILITY_POLICY_URL must be a credential-free HTTPS URL without query or fragment." >&2
    exit 1
  fi
  if [[ ! "$CAPABILITY_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "VIBECOMPOSE_CAPABILITY_PUBLIC_ED_KEY must be a 32-byte base64 Ed25519 public key." >&2
    exit 1
  fi
  /usr/bin/plutil -insert OWCapabilityPolicyURL -string "$CAPABILITY_POLICY_URL" "$PLIST"
  /usr/bin/plutil -insert OWCapabilityPublicEDKey -string "$CAPABILITY_PUBLIC_ED_KEY" "$PLIST"
fi

if [[ "$REQUIRE_DEVELOPER_ID" == "1" \
  && ( -z "$CAPABILITY_POLICY_URL" || -z "$CAPABILITY_PUBLIC_ED_KEY" ) ]]; then
  echo "Developer ID release packaging requires signed provider capability policy configuration." >&2
  exit 1
fi

/usr/bin/plutil -insert SUEnableAutomaticChecks -bool false "$PLIST"
/usr/bin/plutil -insert SUAutomaticallyUpdate -bool false "$PLIST"
/usr/bin/plutil -insert SUAllowsAutomaticUpdates -bool false "$PLIST"
/usr/bin/plutil -insert SUScheduledCheckInterval -integer 86400 "$PLIST"

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
/usr/bin/plutil -lint "$ENTITLEMENTS_FILE" >/dev/null

SIGNING_IDENTITY="$(resolve_signing_identity)"
CODESIGN_ARGS=(--force)

enable_adhoc_library_validation_exception() {
  /usr/libexec/PlistBuddy \
    -c "Delete :com.apple.security.cs.disable-library-validation" \
    "$ENTITLEMENTS_FILE" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.security.cs.disable-library-validation bool true" \
    "$ENTITLEMENTS_FILE"
}

sign_sparkle_components() {
  local identity="$1"
  local timestamp_mode="$2"
  local common_args=(
    --force
    --sign "$identity"
    --options runtime
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime
  )

  if [[ "$timestamp_mode" == "timestamp" ]]; then
    common_args+=(--timestamp)
  else
    common_args+=(--timestamp=none)
  fi

  local sparkle_version_dir="$SPARKLE_FRAMEWORK/Versions/B"
  local component=""
  for component in \
    "$sparkle_version_dir/XPCServices/Downloader.xpc" \
    "$sparkle_version_dir/XPCServices/Installer.xpc" \
    "$sparkle_version_dir/Updater.app" \
    "$sparkle_version_dir/Autoupdate" \
    "$SPARKLE_FRAMEWORK"; do
    [[ -e "$component" ]] || {
      echo "Sparkle signing component is missing: $component" >&2
      return 1
    }
    /usr/bin/codesign "${common_args[@]}" "$component" >/dev/null
  done
}

submit_for_notarization() {
  local artifact="$1"
  local result_path="$2"
  local label="$3"
  local temporary_result="$result_path.tmp"
  local status=""
  local submission_id=""

  rm -f "$temporary_result"
  if ! /usr/bin/xcrun notarytool submit \
    "$artifact" \
    "${NOTARY_AUTH_ARGUMENTS[@]}" \
    --wait \
    --output-format json >"$temporary_result"; then
    rm -f "$temporary_result"
    echo "$label notarization submission failed." >&2
    return 1
  fi
  chmod 0600 "$temporary_result"
  if ! python3 -m json.tool "$temporary_result" >/dev/null \
    || ! status="$(/usr/bin/plutil -extract status raw -o - "$temporary_result")" \
    || ! submission_id="$(/usr/bin/plutil -extract id raw -o - "$temporary_result")"; then
    rm -f "$temporary_result"
    echo "$label notarization returned malformed JSON evidence." >&2
    return 1
  fi
  [[ "$status" == "Accepted" ]] || {
    rm -f "$temporary_result"
    echo "$label notarization was not accepted." >&2
    return 1
  }
  [[ "$submission_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
    rm -f "$temporary_result"
    echo "$label notarization returned an invalid submission ID." >&2
    return 1
  }
  mv "$temporary_result" "$result_path"
}

if [[ -n "$SIGNING_IDENTITY" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    enable_adhoc_library_validation_exception
  fi
  if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    sign_sparkle_components "$SIGNING_IDENTITY" timestamp
  else
    sign_sparkle_components "$SIGNING_IDENTITY" none
  fi
  CODESIGN_ARGS+=(--sign "$SIGNING_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS_FILE")
  if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    CODESIGN_ARGS+=(--timestamp)
  else
    CODESIGN_ARGS+=(--timestamp=none)
  fi
  SIGNING_SUMMARY="$SIGNING_IDENTITY"
elif [[ "$ALLOW_ADHOC_SIGNING" == "1" ]]; then
  enable_adhoc_library_validation_exception
  sign_sparkle_components - none
  CODESIGN_ARGS+=(
    --sign -
    --options runtime
    --requirements "$ADHOC_DESIGNATED_REQUIREMENT"
    --entitlements "$ENTITLEMENTS_FILE"
  )
  SIGNING_SUMMARY="ad-hoc"
else
  echo "No Apple Development or Developer ID Application signing identity is available." >&2
  echo "VibeCompose's Accessibility repair flow relies on TCC recognizing the packaged app." >&2
  echo "Ad-hoc signing often opens System Settings without creating a toggleable VibeCompose row." >&2
  echo "Install a stable code-signing identity, or rerun with VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 only if you explicitly accept that broken repair path." >&2
  exit 1
fi

strip_codesign_hostile_xattrs "$APP_DIR"
/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_DIR" >/dev/null
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
  if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
    echo "A Developer ID Application identity is required for this release channel." >&2
    exit 1
  fi
  if [[ -z "$EXPECTED_TEAM_ID" ]]; then
    echo "VIBECOMPOSE_TEAM_ID is required for Developer ID release packaging." >&2
    exit 1
  fi

  SIGNATURE_DETAILS="$(/usr/bin/codesign -dvvv "$APP_DIR" 2>&1)"
  if [[ "$SIGNATURE_DETAILS" != *"Authority=Developer ID Application:"* ]]; then
    echo "Release signing must use a Developer ID Application certificate." >&2
    exit 1
  fi
  if [[ "$SIGNATURE_DETAILS" != *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]]; then
    echo "Release signing Team ID does not match VIBECOMPOSE_TEAM_ID." >&2
    exit 1
  fi
fi

if [[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "-" ]]; then
  ASSESSMENT_OUTPUT="$(/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_DIR" 2>&1 || true)"
  if grep -q "CSSMERR_TP_CERT_REVOKED" <<<"$ASSESSMENT_OUTPUT"; then
    if [[ "$ALLOW_ADHOC_SIGNING" == "1" ]]; then
      /usr/bin/codesign --remove-signature "$APP_DIR"
      rm -rf "$SPARKLE_FRAMEWORK"
      /usr/bin/ditto --norsrc --noextattr --noqtn \
        "$SPARKLE_FRAMEWORK_SOURCE" \
        "$SPARKLE_FRAMEWORK"
      sign_sparkle_components - none
      enable_adhoc_library_validation_exception
      /usr/bin/codesign \
        --force \
        --sign - \
        --options runtime \
        --requirements "$ADHOC_DESIGNATED_REQUIREMENT" \
        --entitlements "$ENTITLEMENTS_FILE" \
        "$APP_DIR" >/dev/null
      /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
      SIGNING_SUMMARY="ad-hoc with stable local designated requirement (stable identity was revoked)"
    else
      echo "The selected code-signing identity is revoked according to Gatekeeper:" >&2
      echo "$ASSESSMENT_OUTPUT" >&2
      echo "Renew the Apple Development certificate, or rerun with VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 only for local debugging." >&2
      rm -rf "$APP_DIR"
      exit 1
    fi
  fi
fi

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ "$REQUIRE_DEVELOPER_ID" != "1" ]]; then
    echo "Notarization requires VIBECOMPOSE_REQUIRE_DEVELOPER_ID=1." >&2
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "VIBECOMPOSE_NOTARY_PROFILE is required for notarization." >&2
    exit 1
  fi

  NOTARY_AUTH_ARGUMENTS=(--keychain-profile "$NOTARY_PROFILE")
  if [[ -n "$NOTARY_KEYCHAIN" ]]; then
    [[ -f "$NOTARY_KEYCHAIN" && ! -L "$NOTARY_KEYCHAIN" ]] || {
      echo "VIBECOMPOSE_NOTARY_KEYCHAIN must name a regular keychain file." >&2
      exit 1
    }
    NOTARY_AUTH_ARGUMENTS+=(--keychain "$NOTARY_KEYCHAIN")
  fi

  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARY_ZIP_PATH"
  submit_for_notarization \
    "$NOTARY_ZIP_PATH" \
    "$APP_NOTARIZATION_RESULT" \
    "VibeCompose.app"
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
  submit_for_notarization \
    "$DMG_PATH" \
    "$DMG_NOTARIZATION_RESULT" \
    "VibeCompose DMG"
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

VIBECOMPOSE_RELEASE_ARCHITECTURE="$ARCH" \
  "$ROOT/scripts/generate_release_metadata.sh" >/dev/null

# Publish through a non-bundle path and rename it atomically. Copying directly
# into a visible `.app` path lets Desktop File Provider attach FinderInfo to
# nested Sparkle bundles before verification can run.
rm -rf "$DIST_APP_DIR"
rm -rf "$DIST_PUBLISH_DIR"
/usr/bin/ditto --norsrc --noextattr --noqtn "$APP_DIR" "$DIST_PUBLISH_DIR"
# Publishing onto Desktop can re-apply UF_HIDDEN via File Provider; clear it
# before the final rename so installed BuiltInSkills remain enumerable.
/usr/bin/chflags -R nouchg,noschg,nohidden "$DIST_PUBLISH_DIR" >/dev/null 2>&1 || true
mv "$DIST_PUBLISH_DIR" "$DIST_APP_DIR"
strip_codesign_hostile_xattrs "$DIST_APP_DIR"
# The Desktop File Provider may restore FinderInfo between the scrub above and
# this verification. Validate a metadata-free copy under /tmp; install_app.sh
# performs the same scrub again at the authoritative /Applications path.
DIST_VERIFY_APP="$PACKAGE_WORK_DIR/${APP_NAME}-published.app"
rm -rf "$DIST_VERIFY_APP"
/usr/bin/ditto --norsrc --noextattr --noqtn \
  "$DIST_APP_DIR" \
  "$DIST_VERIFY_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  "$DIST_VERIFY_APP" >/dev/null

rm -rf "$DMG_STAGING_DIR"
rm -rf "$ICONSET_DIR"
rm -f "$ENTITLEMENTS_FILE"
rm -f "$DMG_RAW_PATH"
rm -f "$NOTARY_ZIP_PATH"

echo "Packaged $DIST_APP_DIR"
echo "Build configuration: $BUILD_CONFIGURATION"
echo "Signed with $SIGNING_SUMMARY"
echo "Created $ZIP_PATH"
echo "Created $DMG_PATH"
echo "Created $SHA256_PATH"
echo "Created $ROOT/dist/release-manifest.json"
if [[ "$NOTARIZE" == "1" ]]; then
  echo "Created $APP_NOTARIZATION_RESULT"
  echo "Created $DMG_NOTARIZATION_RESULT"
fi
