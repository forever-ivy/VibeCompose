#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
OUT_ROOT="$ROOT/dist/visual-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"

INSTALL_FIRST=0
if [[ "${1:-}" == "--install" ]]; then
  INSTALL_FIRST=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--install]" >&2
  exit 64
fi

mkdir -p "$OUT_DIR"

if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
  "$ROOT/scripts/install_app.sh" >/dev/null
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing installed app binary at $APP_BINARY" >&2
  echo "Run: $ROOT/scripts/visual_acceptance.sh --install" >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

OPEN_PID=""

cleanup() {
  if [[ -n "$OPEN_PID" ]] && kill -0 "$OPEN_PID" >/dev/null 2>&1; then
    kill "$OPEN_PID" >/dev/null 2>&1 || true
  fi
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

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

if ! wait_for_app_exit; then
  echo "Timed out waiting for the previous $APP_NAME process to exit" >&2
  exit 1
fi
sleep 1

capture_state() {
  local state="$1"
  local output_file="$2"
  local log_file="$OUT_DIR/openwhisper-overlay-demo-$state.log"
  local launch_log_file
  local self_capture_file
  launch_log_file="$(mktemp "${TMPDIR:-/tmp}/openwhisper-overlay-demo-$state.XXXXXX")"
  self_capture_file="$(mktemp "${TMPDIR:-/tmp}/openwhisper-overlay-snapshot-$state.XXXXXX")"
  rm -f "$self_capture_file"

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if ! wait_for_app_exit; then
    echo "Timed out waiting for the previous $APP_NAME demo process to exit" >&2
    exit 1
  fi
  sleep 1
  open -W -n -g \
    --stdout "$launch_log_file" \
    --stderr "$launch_log_file" \
    "$APP_DIR" \
    --args \
    --overlay-demo-state "$state" \
    --visual-acceptance-output "$self_capture_file" &
  OPEN_PID=$!

  local attempt
  for attempt in {1..30}; do
    if [[ -s "$self_capture_file" ]]; then
      break
    fi
    sleep 0.1
  done

  if [[ -s "$self_capture_file" ]]; then
    cp "$self_capture_file" "$OUT_DIR/$output_file"
  else
    local window_id
    window_id="$(swift "$ROOT/scripts/find_visual_acceptance_window.swift" "$APP_NAME" 5)"
    screencapture -x -l "$window_id" "$OUT_DIR/$output_file"
  fi
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  wait "$OPEN_PID" >/dev/null 2>&1 || true
  OPEN_PID=""
  cp "$launch_log_file" "$log_file"
  rm -f "$launch_log_file"
  rm -f "$self_capture_file"
}

capture_state "recording" "01-recording.png"
capture_state "processing" "02-processing.png"
capture_state "result" "03-result.png"
capture_state "error" "04-error.png"
capture_state "retryable-error" "05-retryable-error.png"

trap - EXIT

swift "$ROOT/scripts/verify_visual_acceptance.swift" \
  "$OUT_DIR/01-recording.png" \
  "$OUT_DIR/02-processing.png" \
  "$OUT_DIR/03-result.png" \
  "$OUT_DIR/04-error.png" \
  "$OUT_DIR/05-retryable-error.png" | tee "$OUT_DIR/verification.txt"

/usr/bin/open "$APP_DIR"
if ! wait_for_installed_app; then
  echo "Installed app did not remain running after launch: $APP_DIR" >&2
  exit 1
fi

RUNNING_PID="$(pgrep -x "$APP_NAME" | sed -n '1p')"

cat >"$OUT_DIR/summary.md" <<SUMMARY
# OpenWhisper Visual Acceptance

- Run ID: \`$RUN_ID\`
- App: \`$APP_BINARY\`
- Demo flag: \`--overlay-demo-state\`
- Capture: installed-app self-rendered HUD PNG, with CoreGraphics + \`screencapture -l\` fallback
- Final live state: normal installed app relaunched and left running as PID \`$RUNNING_PID\`
- Evidence:
  - \`01-recording.png\`
  - \`02-processing.png\`
  - \`03-result.png\`
  - \`04-error.png\`
  - \`05-retryable-error.png\`
  - \`verification.txt\`
  - \`openwhisper-overlay-demo-*.log\`

SUMMARY

echo "Visual acceptance artifacts: $OUT_DIR"
echo "Installed app left running: $APP_DIR (PID $RUNNING_PID)"
