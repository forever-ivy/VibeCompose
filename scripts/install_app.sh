#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

SOURCE_APP="$ROOT/dist/$VIBECOMPOSE_APP_NAME.app"
TARGET_APP="/Applications/$VIBECOMPOSE_APP_NAME.app"
STAGED_APP="/Applications/.$VIBECOMPOSE_APP_NAME.install.$$.app"
BACKUP_APP="/Applications/.$VIBECOMPOSE_APP_NAME.backup.$$.app"
REQUIRE_GATEKEEPER="${VIBECOMPOSE_INSTALL_REQUIRE_GATEKEEPER:-0}"
EXPECTED_TEAM_ID="${VIBECOMPOSE_TEAM_ID:-}"

cleanup() {
  rm -rf "$STAGED_APP"
  if [[ -d "$BACKUP_APP" && ! -d "$TARGET_APP" ]]; then
    mv "$BACKUP_APP" "$TARGET_APP" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

validate_app() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  local executable="$app/Contents/MacOS/$VIBECOMPOSE_APP_NAME"
  local bundle_id=""
  local version=""
  local build=""
  local architectures=""
  local signature_details=""

  [[ -f "$plist" && -x "$executable" ]] || {
    echo "Invalid VibeCompose bundle layout: $app" >&2
    return 1
  }

  bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist")"
  version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist")"
  build="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$plist")"
  [[ "$bundle_id" == "$VIBECOMPOSE_BUNDLE_ID" ]] || {
    echo "Bundle identifier mismatch: expected $VIBECOMPOSE_BUNDLE_ID, got $bundle_id" >&2
    return 1
  }
  [[ "$version" == "$VIBECOMPOSE_VERSION" ]] || {
    echo "Version mismatch: expected $VIBECOMPOSE_VERSION, got $version" >&2
    return 1
  }
  [[ "$build" == "$VIBECOMPOSE_BUILD" ]] || {
    echo "Build mismatch: expected $VIBECOMPOSE_BUILD, got $build" >&2
    return 1
  }

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  architectures="$(/usr/bin/lipo -archs "$executable")"
  case " $architectures " in
    *" $(uname -m) "*)
      ;;
    *)
      echo "Installed app does not contain the current architecture $(uname -m): $architectures" >&2
      return 1
      ;;
  esac

  if [[ "$REQUIRE_GATEKEEPER" == "1" ]]; then
    [[ -n "$EXPECTED_TEAM_ID" ]] || {
      echo "VIBECOMPOSE_TEAM_ID is required when Gatekeeper installation is enforced." >&2
      return 1
    }
    signature_details="$(/usr/bin/codesign -dvvv "$app" 2>&1)"
    [[ "$signature_details" == *"Authority=Developer ID Application:"* ]] || {
      echo "Gatekeeper installation requires a Developer ID Application signature." >&2
      return 1
    }
    [[ "$signature_details" == *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]] || {
      echo "Installed app Team ID does not match VIBECOMPOSE_TEAM_ID." >&2
      return 1
    }
    /usr/sbin/spctl --assess --type execute --verbose=4 "$app"
  fi
}

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
fi

# Strip Finder/FileProvider detritus that can reappear after copy into
# /Applications (or Desktop/iCloud paths). codesign --verify --deep --strict
# rejects com.apple.FinderInfo even when the signature itself is intact.
strip_codesign_hostile_xattrs() {
  local app="$1"
  # Prefer a clean copy path first; then scrub anything Finder re-applies.
  /usr/bin/xattr -cr "$app" >/dev/null 2>&1 || true
  # UF_HIDDEN on BuiltInSkills/* makes FileManager.skipsHiddenFiles (and some
  # acceptance tooling) miss SKILL.md after install under Desktop/iCloud paths.
  /usr/bin/chflags -R nouchg,noschg,nohidden "$app" >/dev/null 2>&1 || true
  /usr/bin/find "$app" \( -type f -o -type d \) -print0 2>/dev/null \
    | while IFS= read -r -d '' path; do
        /usr/bin/xattr -d com.apple.FinderInfo "$path" >/dev/null 2>&1 || true
        /usr/bin/xattr -d com.apple.fileprovider.fpfs#P "$path" >/dev/null 2>&1 || true
        /usr/bin/xattr -d com.apple.fileprovider.detached#P "$path" >/dev/null 2>&1 || true
      done
}

rm -rf "$STAGED_APP" "$BACKUP_APP"
# Copy without resource forks / extended attributes so Sparkle nested XPC
# bundles don't pick up FinderInfo that codesign will reject.
/usr/bin/ditto --norsrc --noextattr --noqtn "$SOURCE_APP" "$STAGED_APP"
strip_codesign_hostile_xattrs "$STAGED_APP"
validate_app "$STAGED_APP"

pkill -x "$VIBECOMPOSE_APP_NAME" >/dev/null 2>&1 || true

if [[ -d "$TARGET_APP" ]]; then
  mv "$TARGET_APP" "$BACKUP_APP"
fi

if ! mv "$STAGED_APP" "$TARGET_APP"; then
  echo "Atomic installation failed; restoring the previous app." >&2
  rm -rf "$TARGET_APP"
  if [[ -d "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$TARGET_APP"
  fi
  exit 1
fi

# Finder can re-tag the bundle the moment it lands under /Applications.
strip_codesign_hostile_xattrs "$TARGET_APP"

if ! validate_app "$TARGET_APP"; then
  echo "Installed bundle verification failed; restoring the previous app." >&2
  rm -rf "$TARGET_APP"
  if [[ -d "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$TARGET_APP"
  fi
  exit 1
fi

rm -rf "$BACKUP_APP"
trap - EXIT

echo "Installed $TARGET_APP"
