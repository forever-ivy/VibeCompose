#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
OUT_ROOT="$ROOT/dist/feedback-mode-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"

INSTALL_FIRST=0
FINAL_LAUNCH=1
for argument in "$@"; do
  case "$argument" in
    --install)
      INSTALL_FIRST=1
      ;;
    --no-final-launch)
      FINAL_LAUNCH=0
      ;;
    *)
      echo "Usage: $0 [--install] [--no-final-launch]" >&2
      exit 64
      ;;
  esac
done

mkdir -p "$OUT_DIR"

if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
  "$ROOT/scripts/install_app.sh" >/dev/null
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing installed app binary at $APP_BINARY" >&2
  exit 1
fi

OPEN_PID=""

cleanup() {
  if [[ -n "$OPEN_PID" ]] \
    && kill -0 "$OPEN_PID" >/dev/null 2>&1; then
    kill "$OPEN_PID" >/dev/null 2>&1 || true
  fi
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_app_exit() {
  local attempt
  for attempt in {1..80}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_app_start() {
  local attempt
  for attempt in {1..80}; do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

capture_mode() {
  local label="$1"
  local mode="$2"
  local state="$3"
  local reduce_motion="$4"
  local capture_png="$5"
  local debug_file="$OUT_DIR/$label.json"
  local log_file="$OUT_DIR/$label.log"
  local temporary_debug
  local temporary_png=""
  local temporary_log

  temporary_debug="$(mktemp "${TMPDIR:-/tmp}/openwhisper-feedback-debug.XXXXXX")"
  temporary_log="$(mktemp "${TMPDIR:-/tmp}/openwhisper-feedback-log.XXXXXX")"
  rm -f "$temporary_debug"

  local launch_args=(
    --overlay-demo-state "$state"
    --visual-feedback-mode "$mode"
    --feedback-surface-debug-output "$temporary_debug"
    --visual-acceptance-reduce-motion "$reduce_motion"
    --visual-acceptance-increase-contrast off
  )

  if [[ "$capture_png" == "1" ]]; then
    temporary_png="$(mktemp "${TMPDIR:-/tmp}/openwhisper-feedback-png.XXXXXX")"
    rm -f "$temporary_png"
    launch_args+=(
      --visual-acceptance-output "$temporary_png"
    )
  fi

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if ! wait_for_app_exit; then
    echo "Timed out waiting for $APP_NAME to exit" >&2
    exit 1
  fi

  /usr/bin/open -W -n -g \
    --stdout "$temporary_log" \
    --stderr "$temporary_log" \
    "$APP_DIR" \
    --args \
    "${launch_args[@]}" &
  OPEN_PID=$!

  local attempt
  for attempt in {1..80}; do
    if [[ -s "$temporary_debug" ]] \
      && {
        [[ "$capture_png" == "0" ]] \
          || [[ -s "$temporary_png" ]];
      }; then
      break
    fi
    sleep 0.1
  done

  if [[ ! -s "$temporary_debug" ]]; then
    echo "Missing feedback debug output for $label" >&2
    cat "$temporary_log" >&2 || true
    exit 1
  fi
  cp "$temporary_debug" "$debug_file"
  cp "$temporary_log" "$log_file"

  if [[ "$capture_png" == "1" ]]; then
    if [[ ! -s "$temporary_png" ]]; then
      echo "Missing feedback PNG for $label" >&2
      cat "$temporary_log" >&2 || true
      exit 1
    fi
    cp "$temporary_png" "$OUT_DIR/$label.png"
  fi

  wait "$OPEN_PID" >/dev/null 2>&1 || true
  OPEN_PID=""
  rm -f "$temporary_debug" "$temporary_log"
  if [[ -n "$temporary_png" ]]; then
    rm -f "$temporary_png"
  fi
}

capture_mode \
  "01-refined-processing" \
  "refined-hud" \
  "processing" \
  "off" \
  "1"
capture_mode \
  "02-blue-processing" \
  "blue-signal-frame" \
  "processing" \
  "off" \
  "1"
capture_mode \
  "03-blue-processing-reduced-motion" \
  "blue-signal-frame" \
  "processing" \
  "on" \
  "0"
capture_mode \
  "04-blue-copied" \
  "blue-signal-frame" \
  "copied" \
  "off" \
  "1"
capture_mode \
  "05-hidden-recording" \
  "hidden" \
  "recording" \
  "off" \
  "0"
capture_mode \
  "06-hidden-copied" \
  "hidden" \
  "copied" \
  "off" \
  "0"

python3 - "$OUT_DIR" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def load(name):
    return json.loads((root / f"{name}.json").read_text())

refined = load("01-refined-processing")
assert refined["mode"] == "refinedHUD"
assert refined["refinedHUDIsVisible"] is True
assert refined["blueSignalFrameIsVisible"] is False
assert refined["escapeCancellationIsActive"] is True

blue = load("02-blue-processing")
assert blue["mode"] == "blueSignalFrame"
assert blue["refinedHUDIsVisible"] is False
assert blue["blueSignalFrameIsVisible"] is True
assert blue["escapeCancellationIsActive"] is True
assert blue["blueSignalAnimationIsActive"] is True

blue_reduced = load("03-blue-processing-reduced-motion")
assert blue_reduced["blueSignalFrameIsVisible"] is True
assert blue_reduced["blueSignalAnimationIsActive"] is False

blue_copied = load("04-blue-copied")
assert blue_copied["blueSignalFrameIsVisible"] is True
assert blue_copied["refinedHUDIsVisible"] is True
assert blue_copied["escapeCancellationIsActive"] is False

hidden_recording = load("05-hidden-recording")
assert hidden_recording["mode"] == "hidden"
assert hidden_recording["refinedHUDIsVisible"] is False
assert hidden_recording["blueSignalFrameIsVisible"] is False
assert hidden_recording["escapeCancellationIsActive"] is True

hidden_copied = load("06-hidden-copied")
assert hidden_copied["refinedHUDIsVisible"] is False
assert hidden_copied["blueSignalFrameIsVisible"] is False
assert hidden_copied["escapeCancellationIsActive"] is False

for image_name in (
    "01-refined-processing.png",
    "02-blue-processing.png",
    "04-blue-copied.png",
):
    image_path = root / image_name
    assert image_path.stat().st_size > 1000, image_name

(root / "verification.txt").write_text(
    "Refined HUD, Blue Signal Frame, Hidden, Retry/cancel semantics, "
    "and Blue Signal Reduce Motion acceptance passed.\n"
)
PY

if [[ "$FINAL_LAUNCH" == "1" ]]; then
  /usr/bin/open "$APP_DIR"
  if ! wait_for_app_start; then
    echo "Installed app did not remain running: $APP_DIR" >&2
    exit 1
  fi
fi

cat >"$OUT_DIR/summary.md" <<SUMMARY
# OpenWhisper Feedback Mode Acceptance

- Installed app: \`$APP_DIR\`
- Modes: Refined HUD, Blue Signal Frame, Hidden
- States: Processing, Copied, Recording
- Accessibility: explicit Reduce Motion on/off evidence
- Verification: \`verification.txt\`
- Final normal launch requested: \`$FINAL_LAUNCH\`

SUMMARY

trap - EXIT
if [[ "$FINAL_LAUNCH" == "0" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

echo "Feedback mode acceptance artifacts: $OUT_DIR"
