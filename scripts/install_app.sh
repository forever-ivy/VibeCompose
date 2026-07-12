#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

SOURCE_APP="$ROOT/dist/$OPENWHISPER_APP_NAME.app"
TARGET_APP="/Applications/$OPENWHISPER_APP_NAME.app"
STAGED_APP="/Applications/.$OPENWHISPER_APP_NAME.install.$$.app"
BACKUP_APP="/Applications/.$OPENWHISPER_APP_NAME.backup.$$.app"
REQUIRE_GATEKEEPER="${OPENWHISPER_INSTALL_REQUIRE_GATEKEEPER:-0}"

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
  local executable="$app/Contents/MacOS/$OPENWHISPER_APP_NAME"
  local bundle_id=""
  local version=""
  local architectures=""

  [[ -f "$plist" && -x "$executable" ]] || {
    echo "Invalid OpenWhisper bundle layout: $app" >&2
    return 1
  }

  bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist")"
  version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist")"
  [[ "$bundle_id" == "$OPENWHISPER_BUNDLE_ID" ]] || {
    echo "Bundle identifier mismatch: expected $OPENWHISPER_BUNDLE_ID, got $bundle_id" >&2
    return 1
  }
  [[ "$version" == "$OPENWHISPER_VERSION" ]] || {
    echo "Version mismatch: expected $OPENWHISPER_VERSION, got $version" >&2
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
    /usr/sbin/spctl --assess --type execute --verbose=4 "$app"
  fi
}

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
fi

rm -rf "$STAGED_APP" "$BACKUP_APP"
/usr/bin/ditto "$SOURCE_APP" "$STAGED_APP"
validate_app "$STAGED_APP"

pkill -x "$OPENWHISPER_APP_NAME" >/dev/null 2>&1 || true

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
