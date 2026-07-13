#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
OUT_ROOT="$ROOT/dist/permission-surface-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openwhisper-permission-surface.XXXXXX")"
SNAPSHOT="$OUT_DIR/settings-account.png"
OCR_OUTPUT="$OUT_DIR/ocr.txt"
LAUNCH_LOG="$OUT_DIR/launch.log"

INSTALL_FIRST=0
if [[ "${1:-}" == "--install" ]]; then
  INSTALL_FIRST=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--install]" >&2
  exit 64
fi

wait_for_app_exit() {
  local attempt
  for attempt in {1..50}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_installed_app() {
  local attempt
  for attempt in {1..50}; do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

restore_normal_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  wait_for_app_exit >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
  if [[ -d "$APP_DIR" ]]; then
    /usr/bin/open "$APP_DIR" >/dev/null 2>&1 || true
  fi
}
trap restore_normal_app EXIT

mkdir -p "$OUT_DIR"

if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh"
  "$ROOT/scripts/install_app.sh"
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing installed app binary at $APP_BINARY" >&2
  echo "Run: $0 --install" >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
if ! wait_for_app_exit; then
  echo "Timed out waiting for the previous $APP_NAME process to exit" >&2
  exit 1
fi

TEMP_SNAPSHOT="$TMP_DIR/settings-account.png"
TEMP_LOG="$TMP_DIR/launch.log"
if ! /usr/bin/open -W -n \
  --stdout "$TEMP_LOG" \
  --stderr "$TEMP_LOG" \
  "$APP_DIR" \
  --args \
  --open-settings \
  --settings-pane=account \
  --settings-snapshot-size=900x625 \
  --settings-snapshot-output "$TEMP_SNAPSHOT"
then
  echo "Installed permission surface launch failed" >&2
  cat "$TEMP_LOG" >&2 || true
  exit 1
fi

if [[ ! -s "$TEMP_SNAPSHOT" ]]; then
  echo "Installed permission surface did not produce a snapshot" >&2
  cat "$TEMP_LOG" >&2 || true
  exit 1
fi

cp "$TEMP_SNAPSHOT" "$SNAPSHOT"
cp "$TEMP_LOG" "$LAUNCH_LOG"
/usr/bin/xcrun swift \
  "$ROOT/scripts/verify_permission_surface.swift" \
  "$SNAPSHOT" \
  --text-output "$OCR_OUTPUT" \
  | tee "$OUT_DIR/verification.txt"

/usr/bin/open "$APP_DIR"
if ! wait_for_installed_app; then
  echo "Installed app did not remain running after permission acceptance." >&2
  exit 1
fi

RUNNING_PID="$(pgrep -x "$APP_NAME" | sed -n '1p')"
cat >"$OUT_DIR/summary.md" <<SUMMARY
# OpenWhisper Installed Permission Surface Acceptance

- Run ID: \`$RUN_ID\`
- Installed app: \`$APP_DIR\`
- Surface: Settings → Account
- Required UI result: Microphone and Accessibility both render as granted
- Snapshot: \`settings-account.png\`
- OCR evidence: \`ocr.txt\`
- Verification: \`verification.txt\`
- Final live state: normal installed OpenWhisper relaunched and left running as PID \`$RUNNING_PID\`

The snapshot process uses OpenWhisper's privacy-isolated acceptance mode, so it
does not read account credentials, History, Recovery, terminology, or user
configuration. Permission state remains live and is read by the installed app.
This is a deterministic installed-surface precheck; clean-TCC prompt order and
interactive permission changes still require native GUI acceptance.
SUMMARY

echo "Permission surface artifacts: $OUT_DIR"
echo "Installed app left running: $APP_DIR (PID $RUNNING_PID)"

trap - EXIT
rm -rf "$TMP_DIR"
