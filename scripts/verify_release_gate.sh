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
APPCAST="${OPENWHISPER_SPARKLE_APPCAST_PATH:-$ROOT/dist/appcast.xml}"
CAPABILITY_POLICY="${OPENWHISPER_CAPABILITY_POLICY_PATH:-$ROOT/dist/provider-capabilities.json}"

[[ -n "$EXPECTED_TEAM_ID" ]] || {
  echo "OPENWHISPER_TEAM_ID is required for the commercial release gate." >&2
  exit 1
}
[[ -d "$APP" && -f "$DMG" && -f "$MANIFEST" ]] || {
  echo "Missing signed release artifacts or release manifest." >&2
  exit 1
}

swift "$ROOT/scripts/verify_dependency_licenses.swift" \
  --root "$ROOT" \
  --app-resources "$APP/Contents/Resources"
python3 "$ROOT/scripts/verify_repository_hygiene.py"

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
ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
[[ "$ENTITLEMENTS" != *"com.apple.security.cs.disable-library-validation"* ]] || {
  echo "Commercial release must not disable hardened-runtime library validation." >&2
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
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
EXECUTABLE="$APP/Contents/MacOS/$OPENWHISPER_APP_NAME"
[[ -d "$SPARKLE_FRAMEWORK" ]] || {
  echo "Sparkle.framework is not embedded in the signed app." >&2
  exit 1
}
SPARKLE_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$SPARKLE_FRAMEWORK/Resources/Info.plist")"
[[ "$SPARKLE_VERSION" == "2.9.4" ]] || {
  echo "Commercial release requires the pinned Sparkle 2.9.4 framework." >&2
  exit 1
}
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

PRO_PREVIEW_ENABLED="$(/usr/bin/plutil -extract OWProPreviewEnabled raw -o - "$PLIST" 2>/dev/null || true)"
[[ "$PRO_PREVIEW_ENABLED" == "false" ]] || {
  echo "Commercial release must disable the private Pro preview." >&2
  exit 1
}
if ! LICENSE_PUBLIC_KEY="$(/usr/bin/plutil -extract OWLicensePublicEDKey raw -o - "$PLIST" 2>/dev/null)"; then
  echo "Commercial release is missing OWLicensePublicEDKey." >&2
  exit 1
fi
[[ "$LICENSE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || {
  echo "Commercial license verification key is not a 32-byte base64 Ed25519 key." >&2
  exit 1
}

[[ -f "$CAPABILITY_POLICY" && ! -L "$CAPABILITY_POLICY" ]] || {
  echo "Missing regular signed provider capability policy: $CAPABILITY_POLICY" >&2
  exit 1
}
"$ROOT/scripts/verify_provider_capability_policy.swift" \
  --policy "$CAPABILITY_POLICY" \
  --public-key "$CAPABILITY_PUBLIC_KEY" \
  --build "$OPENWHISPER_BUILD"

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
  "<sparkle:version>$OPENWHISPER_BUILD</sparkle:version>|sparkle:version=\"$OPENWHISPER_BUILD\"" \
  "$APPCAST" || {
    echo "Sparkle appcast build does not match the release build." >&2
    exit 1
  }
ZIP_DOWNLOAD_URL="$(/usr/bin/plutil -extract artifacts.0.downloadURL raw -o - "$MANIFEST")"
grep -Fq "$ZIP_DOWNLOAD_URL" "$APPCAST" || {
  echo "Sparkle appcast download URL does not match the release manifest." >&2
  exit 1
}
"$ROOT/scripts/verify_sparkle_appcast.swift" \
  --appcast "$APPCAST" \
  --archive "$ROOT/dist/$(/usr/bin/plutil -extract artifacts.0.fileName raw -o - "$MANIFEST")" \
  --manifest "$MANIFEST" \
  --public-key "$PUBLIC_KEY"

echo "OpenWhisper commercial release gate passed."
