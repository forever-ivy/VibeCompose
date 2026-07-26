#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$VIBECOMPOSE_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
OUT_ROOT="$ROOT/dist/accessibility-visual-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibecompose-accessibility-visual.XXXXXX")"

INSTALL_FIRST=0
if [[ "${1:-}" == "--install" ]]; then
  INSTALL_FIRST=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--install]" >&2
  exit 64
fi

cleanup() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
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

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing installed app binary at $APP_BINARY" >&2
  echo "Run: $0 --install" >&2
  exit 1
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

capture_profile() {
  local surface="$1"
  local open_argument="$2"
  local snapshot_argument="$3"
  local detail_kind="${4:-}"
  local detail_value="${5:-}"
  local profile="$6"
  local increase_contrast="off"
  local output_file="$surface-$profile.png"
  local temporary_file="$TMP_DIR/$output_file"
  local temporary_log_file="$TMP_DIR/$surface-$profile.log"
  local log_file="$OUT_DIR/$surface-$profile.log"

  if [[ "$profile" == "increase-contrast" ]]; then
    increase_contrast="on"
  elif [[ "$profile" != "baseline" ]]; then
    echo "Unknown accessibility visual profile: $profile" >&2
    exit 64
  fi

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if ! wait_for_app_exit; then
    echo "Timed out waiting for the previous $APP_NAME process to exit" >&2
    exit 1
  fi
  sleep 1

  local args=(
    "$open_argument"
    "--$snapshot_argument"
    "$temporary_file"
    "--visual-acceptance-reduce-motion=off"
    "--visual-acceptance-increase-contrast=$increase_contrast"
  )
  case "$detail_kind" in
    settings)
      args+=(
        "--settings-pane=$detail_value"
        "--settings-snapshot-size=900x625"
      )
      ;;
    onboarding)
      args+=("--onboarding-step=$detail_value")
      ;;
    "")
      ;;
    *)
      echo "Unknown accessibility visual surface kind: $detail_kind" >&2
      exit 64
      ;;
  esac

  local launch_succeeded=0
  local launch_attempt
  for launch_attempt in 1 2 3; do
    rm -f "$temporary_file"
    : >"$temporary_log_file"
    if /usr/bin/open -W -n \
      --stdout "$temporary_log_file" \
      --stderr "$temporary_log_file" \
      "$APP_DIR" \
      --args \
      "${args[@]}"
    then
      launch_succeeded=1
      break
    fi
    sleep 2
  done

  if [[ "$launch_succeeded" != "1" ]]; then
    echo "$surface/$profile could not launch after 3 attempts" >&2
    cat "$temporary_log_file" >&2 || true
    exit 1
  fi

  if [[ ! -s "$temporary_file" ]]; then
    echo "$surface/$profile did not produce a snapshot" >&2
    cat "$temporary_log_file" >&2 || true
    exit 1
  fi
  cp "$temporary_file" "$OUT_DIR/$output_file"
  cp "$temporary_log_file" "$log_file"
}

capture_surface() {
  local surface="$1"
  local open_argument="$2"
  local snapshot_argument="$3"
  local detail_kind="${4:-}"
  local detail_value="${5:-}"

  capture_profile \
    "$surface" \
    "$open_argument" \
    "$snapshot_argument" \
    "$detail_kind" \
    "$detail_value" \
    "baseline"
  capture_profile \
    "$surface" \
    "$open_argument" \
    "$snapshot_argument" \
    "$detail_kind" \
    "$detail_value" \
    "increase-contrast"
}

capture_surface \
  "settings-general" \
  "--open-settings" \
  "settings-snapshot-output" \
  "settings" \
  "general"
capture_surface \
  "settings-account" \
  "--open-settings" \
  "settings-snapshot-output" \
  "settings" \
  "account"
capture_surface \
  "settings-dictation" \
  "--open-settings" \
  "settings-snapshot-output" \
  "settings" \
  "dictation"
capture_surface \
  "settings-appearance" \
  "--open-settings" \
  "settings-snapshot-output" \
  "settings" \
  "appearance"
capture_surface \
  "settings-ai-polish" \
  "--open-settings" \
  "settings-snapshot-output" \
  "settings" \
  "ai-polish"
capture_surface \
  "settings-context" \
  "--open-settings" \
  "settings-snapshot-output" \
  "settings" \
  "context"
capture_surface \
  "settings-privacy" \
  "--open-settings" \
  "settings-snapshot-output" \
  "settings" \
  "privacy"
capture_surface \
  "settings-advanced" \
  "--open-settings" \
  "settings-snapshot-output" \
  "settings" \
  "advanced"

capture_surface \
  "onboarding-welcome" \
  "--open-onboarding" \
  "onboarding-snapshot-output" \
  "onboarding" \
  "welcome"
capture_surface \
  "onboarding-connect" \
  "--open-onboarding" \
  "onboarding-snapshot-output" \
  "onboarding" \
  "connect"
capture_surface \
  "onboarding-microphone" \
  "--open-onboarding" \
  "onboarding-snapshot-output" \
  "onboarding" \
  "microphone"
capture_surface \
  "onboarding-practice" \
  "--open-onboarding" \
  "onboarding-snapshot-output" \
  "onboarding" \
  "practice"

capture_surface \
  "history" \
  "--open-history" \
  "history-snapshot-output"
capture_surface \
  "terminology" \
  "--open-terminology" \
  "terminology-snapshot-output"
capture_surface \
  "quick-add" \
  "--open-quick-add" \
  "quick-add-snapshot-output"

swift "$ROOT/scripts/verify_accessibility_visual_acceptance.swift" \
  "$OUT_DIR" | tee "$OUT_DIR/verification.txt"

trap - EXIT
rm -rf "$TMP_DIR"

/usr/bin/open "$APP_DIR"
if ! wait_for_installed_app; then
  echo "Installed app did not remain running after launch: $APP_DIR" >&2
  exit 1
fi
RUNNING_PID="$(pgrep -x "$APP_NAME" | sed -n '1p')"

cat >"$OUT_DIR/summary.md" <<SUMMARY
# VibeCompose Accessibility Visual Acceptance

- Run ID: \`$RUN_ID\`
- Installed app: \`$APP_BINARY\`
- Surfaces: five canonical Settings panes plus legacy deep-link aliases, four Onboarding steps, History, Terminology, Quick Add
- Profiles: baseline and forced app-specific Increase Contrast
- Validation: normalized 2x capture geometry, visible logical-pixel difference, non-decreasing local edge contrast
- Diagnostics: whole-image luminance spread is recorded but is not used as the contrast gate
- Privacy: snapshot mode uses default configuration and empty in-memory user data
- Final live state: normal installed app relaunched and left running as PID \`$RUNNING_PID\`

Each surface has:

- \`<surface>-baseline.png\`
- \`<surface>-increase-contrast.png\`
- matching transient launch logs
- aggregate \`verification.txt\`

This proves deterministic installed-app rendering of VibeCompose's
high-contrast treatment. It does not replace official Computer Use keyboard,
VoiceOver speech-output, focus, timing, or permission interaction acceptance.
SUMMARY

echo "Accessibility visual acceptance artifacts: $OUT_DIR"
echo "Installed app left running: $APP_DIR (PID $RUNNING_PID)"
