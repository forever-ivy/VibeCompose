#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

APP="$ROOT/dist/$VIBEWHISPER_APP_NAME.app"
DMG="$ROOT/dist/${VIBEWHISPER_APP_NAME}-${VIBEWHISPER_VERSION}-macos-$(uname -m).dmg"
MANIFEST="${VIBEWHISPER_RELEASE_MANIFEST_PATH:-$ROOT/dist/release-manifest.json}"
CASK="${VIBEWHISPER_CASK_PATH:-$ROOT/packaging/homebrew/Casks/vibewhisper.rb}"
EXPECTED_TEAM_ID="${VIBEWHISPER_TEAM_ID:-}"
APPCAST="${VIBEWHISPER_SPARKLE_APPCAST_PATH:-$ROOT/dist/appcast.xml}"
CAPABILITY_POLICY="${VIBEWHISPER_CAPABILITY_POLICY_PATH:-$ROOT/dist/provider-capabilities.json}"
APP_NOTARIZATION_RESULT="${VIBEWHISPER_APP_NOTARIZATION_RESULT_PATH:-$ROOT/dist/notarization-app.json}"
DMG_NOTARIZATION_RESULT="${VIBEWHISPER_DMG_NOTARIZATION_RESULT_PATH:-$ROOT/dist/notarization-dmg.json}"

verify_developer_id_runtime_signature() {
  local code_path="$1"
  local label="$2"
  local details

  /usr/bin/codesign --verify --strict --verbose=2 "$code_path"
  details="$(/usr/bin/codesign -d --verbose=4 "$code_path" 2>&1)"
  [[ "$details" == *"Authority=Developer ID Application:"* ]] || {
    echo "$label is not signed with Developer ID Application." >&2
    exit 1
  }
  [[ "$details" == *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]] || {
    echo "$label Team ID does not match VIBEWHISPER_TEAM_ID." >&2
    exit 1
  }
  [[ "$details" == *"Timestamp="* ]] || {
    echo "$label is missing a trusted signing timestamp." >&2
    exit 1
  }
  grep -Eq '^CodeDirectory .*flags=.*\(runtime\)' <<<"$details" || {
    echo "$label is missing the Hardened Runtime code-signing flag." >&2
    exit 1
  }
}

validate_notarization_result() {
  local result_path="$1"
  local label="$2"
  local status=""
  local submission_id=""

  [[ -f "$result_path" && ! -L "$result_path" ]] || {
    echo "Missing regular $label notarization result: $result_path" >&2
    exit 1
  }
  python3 -m json.tool "$result_path" >/dev/null
  status="$(/usr/bin/plutil -extract status raw -o - "$result_path")"
  submission_id="$(/usr/bin/plutil -extract id raw -o - "$result_path")"
  [[ "$status" == "Accepted" ]] || {
    echo "$label notarization result is not Accepted." >&2
    exit 1
  }
  [[ "$submission_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
    echo "$label notarization result has an invalid submission ID." >&2
    exit 1
  }
}

[[ -n "$EXPECTED_TEAM_ID" ]] || {
  echo "VIBEWHISPER_TEAM_ID is required for the signed release gate." >&2
  exit 1
}
[[ -d "$APP" && -f "$DMG" && -f "$MANIFEST" ]] || {
  echo "Missing signed release artifacts or release manifest." >&2
  exit 1
}
[[ -f "$CASK" && ! -L "$CASK" ]] || {
  echo "Missing regular Homebrew Cask release file: $CASK" >&2
  exit 1
}

swift "$ROOT/scripts/verify_dependency_licenses.swift" \
  --root "$ROOT" \
  --app-resources "$APP/Contents/Resources"
python3 "$ROOT/scripts/verify_repository_hygiene.py"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
verify_developer_id_runtime_signature "$APP" "VibeWhisper.app"
ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
[[ "$ENTITLEMENTS" != *"com.apple.security.cs.disable-library-validation"* ]] || {
  echo "Signed release must not disable hardened-runtime library validation." >&2
  exit 1
}

/usr/bin/xcrun stapler validate "$APP"
/usr/bin/xcrun stapler validate "$DMG"
validate_notarization_result "$APP_NOTARIZATION_RESULT" "App"
validate_notarization_result "$DMG_NOTARIZATION_RESULT" "DMG"
APP_NOTARIZATION_ID="$(/usr/bin/plutil -extract id raw -o - "$APP_NOTARIZATION_RESULT")"
DMG_NOTARIZATION_ID="$(/usr/bin/plutil -extract id raw -o - "$DMG_NOTARIZATION_RESULT")"
[[ "$APP_NOTARIZATION_ID" != "$DMG_NOTARIZATION_ID" ]] || {
  echo "App and DMG notarization evidence must use distinct submissions." >&2
  exit 1
}
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP"
/usr/sbin/spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "$DMG"

MANIFEST_VERSION="$(/usr/bin/plutil -extract release.version raw -o - "$MANIFEST")"
MANIFEST_BUILD="$(/usr/bin/plutil -extract release.build raw -o - "$MANIFEST")"
ZIP_FILENAME="$(/usr/bin/plutil -extract artifacts.0.fileName raw -o - "$MANIFEST")"
ZIP_SHA256="$(/usr/bin/plutil -extract artifacts.0.sha256 raw -o - "$MANIFEST")"
ZIP_DOWNLOAD_URL="$(/usr/bin/plutil -extract artifacts.0.downloadURL raw -o - "$MANIFEST")"
DMG_FILENAME="$(/usr/bin/plutil -extract artifacts.1.fileName raw -o - "$MANIFEST")"
DMG_DOWNLOAD_URL="$(/usr/bin/plutil -extract artifacts.1.downloadURL raw -o - "$MANIFEST")"
[[ "$MANIFEST_VERSION" == "$VIBEWHISPER_VERSION" ]] || {
  echo "Release manifest version mismatch." >&2
  exit 1
}
[[ "$MANIFEST_BUILD" == "$VIBEWHISPER_BUILD" ]] || {
  echo "Release manifest build mismatch." >&2
  exit 1
}
if [[ -n "${VIBEWHISPER_RELEASE_BASE_URL:-}" ]]; then
  EXPECTED_RELEASE_BASE_URL="${VIBEWHISPER_RELEASE_BASE_URL%/}"
  [[ "$ZIP_DOWNLOAD_URL" == "$EXPECTED_RELEASE_BASE_URL/$ZIP_FILENAME" \
    && "$DMG_DOWNLOAD_URL" == "$EXPECTED_RELEASE_BASE_URL/$DMG_FILENAME" ]] || {
    echo "Release manifest artifact URLs do not match VIBEWHISPER_RELEASE_BASE_URL." >&2
    exit 1
  }
fi
grep -q "version \"$VIBEWHISPER_VERSION\"" "$CASK"
grep -q "sha256 \"$ZIP_SHA256\"" "$CASK"
grep -Fq "url \"$ZIP_DOWNLOAD_URL\"" "$CASK"
if grep -q "sha256 :no_check" "$CASK"; then
  echo "Homebrew Cask checksum verification is disabled." >&2
  exit 1
fi

PLIST="$APP/Contents/Info.plist"
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
EXECUTABLE="$APP/Contents/MacOS/$VIBEWHISPER_APP_NAME"
[[ -d "$SPARKLE_FRAMEWORK" ]] || {
  echo "Sparkle.framework is not embedded in the signed app." >&2
  exit 1
}
SPARKLE_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$SPARKLE_FRAMEWORK/Resources/Info.plist")"
[[ "$SPARKLE_VERSION" == "2.9.4" ]] || {
  echo "Signed release requires the pinned Sparkle 2.9.4 framework." >&2
  exit 1
}
SPARKLE_VERSION_DIRECTORY="$SPARKLE_FRAMEWORK/Versions/B"
for component in \
  "$SPARKLE_VERSION_DIRECTORY/XPCServices/Downloader.xpc" \
  "$SPARKLE_VERSION_DIRECTORY/XPCServices/Installer.xpc" \
  "$SPARKLE_VERSION_DIRECTORY/Updater.app" \
  "$SPARKLE_VERSION_DIRECTORY/Autoupdate" \
  "$SPARKLE_FRAMEWORK"; do
  [[ -e "$component" ]] || {
    echo "Signed Sparkle component is missing: $component" >&2
    exit 1
  }
  verify_developer_id_runtime_signature \
    "$component" \
    "Sparkle component $(basename "$component")"
done
/usr/bin/otool -L "$EXECUTABLE" \
  | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle' || {
    echo "The signed app is not linked against Sparkle.framework." >&2
    exit 1
  }
/usr/bin/otool -l "$EXECUTABLE" \
  | awk '
      $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
      in_rpath && $1 == "path" {
        if ($2 == "@executable_path/../Frameworks") {
          found = 1
        }
        in_rpath = 0
      }
      END { exit(found ? 0 : 1) }
    ' || {
      echo "The signed app is missing its Frameworks runtime search path." >&2
      exit 1
    }

if ! FEED_URL="$(/usr/bin/plutil -extract SUFeedURL raw -o - "$PLIST" 2>/dev/null)"; then
  echo "Signed updater feed is not configured (missing SUFeedURL)." >&2
  exit 1
fi
if ! PUBLIC_KEY="$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$PLIST" 2>/dev/null)"; then
  echo "Signed updater verification key is not configured (missing SUPublicEDKey)." >&2
  exit 1
fi
[[ "$FEED_URL" == https://* && "$FEED_URL" != *"@"* ]] || {
  echo "Signed updater feed must use credential-free HTTPS." >&2
  exit 1
}
[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || {
  echo "Signed updater public key is not a 32-byte base64 Ed25519 key." >&2
  exit 1
}
if [[ -n "${VIBEWHISPER_SPARKLE_FEED_URL:-}" \
  && "$FEED_URL" != "$VIBEWHISPER_SPARKLE_FEED_URL" ]]; then
  echo "Signed updater feed does not match the configured production feed." >&2
  exit 1
fi
if [[ -n "${VIBEWHISPER_SPARKLE_PUBLIC_ED_KEY:-}" \
  && "$PUBLIC_KEY" != "$VIBEWHISPER_SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "Signed updater public key does not match the configured production key." >&2
  exit 1
fi

if ! CAPABILITY_POLICY_URL="$(/usr/bin/plutil -extract OWCapabilityPolicyURL raw -o - "$PLIST" 2>/dev/null)"; then
  echo "Signed provider capability policy is not configured (missing OWCapabilityPolicyURL)." >&2
  exit 1
fi
if ! CAPABILITY_PUBLIC_KEY="$(/usr/bin/plutil -extract OWCapabilityPublicEDKey raw -o - "$PLIST" 2>/dev/null)"; then
  echo "Signed provider capability policy key is not configured (missing OWCapabilityPublicEDKey)." >&2
  exit 1
fi
[[ "$CAPABILITY_POLICY_URL" == https://* \
  && "$CAPABILITY_POLICY_URL" != *"@"* \
  && "$CAPABILITY_POLICY_URL" != *"?"* \
  && "$CAPABILITY_POLICY_URL" != *"#"* ]] || {
  echo "Signed provider capability policy must use credential-free HTTPS without query or fragment." >&2
  exit 1
}
[[ "$CAPABILITY_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || {
  echo "Signed provider capability policy key is not a 32-byte base64 Ed25519 key." >&2
  exit 1
}
if [[ -n "${VIBEWHISPER_CAPABILITY_POLICY_URL:-}" \
  && "$CAPABILITY_POLICY_URL" != "$VIBEWHISPER_CAPABILITY_POLICY_URL" ]]; then
  echo "Provider capability policy URL does not match the production configuration." >&2
  exit 1
fi
if [[ -n "${VIBEWHISPER_CAPABILITY_PUBLIC_ED_KEY:-}" \
  && "$CAPABILITY_PUBLIC_KEY" != "$VIBEWHISPER_CAPABILITY_PUBLIC_ED_KEY" ]]; then
  echo "Provider capability public key does not match the production configuration." >&2
  exit 1
fi

[[ -f "$CAPABILITY_POLICY" && ! -L "$CAPABILITY_POLICY" ]] || {
  echo "Missing regular signed provider capability policy: $CAPABILITY_POLICY" >&2
  exit 1
}
"$ROOT/scripts/verify_provider_capability_policy.swift" \
  --policy "$CAPABILITY_POLICY" \
  --public-key "$CAPABILITY_PUBLIC_KEY" \
  --build "$VIBEWHISPER_BUILD"

[[ -f "$APPCAST" && ! -L "$APPCAST" ]] || {
  echo "Missing regular signed Sparkle appcast: $APPCAST" >&2
  exit 1
}
/usr/bin/xmllint --noout "$APPCAST"
grep -q 'sparkle:edSignature="' "$APPCAST" || {
  echo "Sparkle appcast has no EdDSA archive signature." >&2
  exit 1
}
grep -Eq \
  "<sparkle:version>$VIBEWHISPER_BUILD</sparkle:version>|sparkle:version=\"$VIBEWHISPER_BUILD\"" \
  "$APPCAST" || {
    echo "Sparkle appcast build does not match the release build." >&2
    exit 1
  }
grep -Fq "$ZIP_DOWNLOAD_URL" "$APPCAST" || {
  echo "Sparkle appcast download URL does not match the release manifest." >&2
  exit 1
}
"$ROOT/scripts/verify_sparkle_appcast.swift" \
  --appcast "$APPCAST" \
  --archive "$ROOT/dist/$(/usr/bin/plutil -extract artifacts.0.fileName raw -o - "$MANIFEST")" \
  --manifest "$MANIFEST" \
  --public-key "$PUBLIC_KEY"

echo "VibeWhisper signed release gate passed."
