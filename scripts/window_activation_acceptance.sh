#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$VIBEWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
OUT_ROOT="$ROOT/dist/window-activation-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"
INSTALL_FIRST=0

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_FIRST=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--install]" >&2
  exit 64
fi

cleanup() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -d "$APP_DIR" ]]; then
    /usr/bin/open "$APP_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"
if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
  "$ROOT/scripts/install_app.sh" >/dev/null
fi
[[ -x "$APP_DIR/Contents/MacOS/$APP_NAME" ]] || {
  echo "Missing installed app: $APP_DIR" >&2
  exit 1
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
for _ in {1..60}; do
  if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

/usr/bin/open -n "$APP_DIR" --args --open-settings --settings-pane=general
for _ in {1..60}; do
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

/usr/bin/xcrun swift \
  "$ROOT/scripts/verify_window_activation.swift" \
  "$VIBEWHISPER_BUNDLE_ID" \
  "$OUT_DIR/evidence.json" \
  | tee "$OUT_DIR/verification.txt"

cat >"$OUT_DIR/summary.md" <<SUMMARY
# VibeWhisper Window Activation Acceptance

- Installed app: \`$APP_DIR\`
- Settings-open policy: regular, with the packaged App Icon available to Dock
- Yellow button: minimizes the Settings window and restores it through AppKit
- Last-window close: keeps the Dock identity available while the menu bar entry remains active
SUMMARY

trap - EXIT
cleanup
for _ in {1..60}; do
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Window activation acceptance artifacts: $OUT_DIR"
    echo "Installed app and menu bar entry left running: $APP_DIR"
    exit 0
  fi
  sleep 0.1
done
echo "Installed app did not remain running: $APP_DIR" >&2
exit 1
