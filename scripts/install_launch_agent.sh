#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_BINARY="/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME"
PLIST="$HOME/Library/LaunchAgents/$OPENWHISPER_BUNDLE_ID.plist"

if [[ ! -x "$APP_BINARY" ]]; then
  "$ROOT/scripts/install_app.sh" >/dev/null
fi

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$OPENWHISPER_BUNDLE_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BINARY</string>
  </array>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/OpenWhisper.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/OpenWhisper.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"
echo "Installed launch agent at $PLIST"
