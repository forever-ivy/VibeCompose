#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/product.env"

APP="$ROOT/dist/$OPENWHISPER_APP_NAME.app"
PLIST="$APP/Contents/Info.plist"

"$ROOT/scripts/package_app.sh" >/dev/null

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

echo "Packaged app metadata looks correct."
