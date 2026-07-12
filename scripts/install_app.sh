#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/product.env"

SOURCE_APP="$ROOT/dist/$OPENWHISPER_APP_NAME.app"
TARGET_APP="/Applications/$OPENWHISPER_APP_NAME.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
fi

pkill -x "$OPENWHISPER_APP_NAME" >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"

echo "Installed $TARGET_APP"
