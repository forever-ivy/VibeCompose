#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
OUT_ROOT="$ROOT/dist/settings-bilingual-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openwhisper-settings-bilingual.XXXXXX")"
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
[[ -x "$APP_DIR/Contents/MacOS/$APP_NAME" ]] || {
  echo "Missing installed app: $APP_DIR" >&2
  exit 1
}

wait_for_exit() {
  local attempt
  for attempt in {1..60}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

capture() {
  local language="$1"
  local pane="$2"
  local profile="$3"
  local size="$4"
  local requested_width="${size%x*}"
  local requested_height="${size#*x}"
  local output="$OUT_DIR/settings-$pane-$language-$profile.png"
  local temporary="$TMP_DIR/$(basename "$output")"
  local log="$OUT_DIR/settings-$pane-$language-$profile.log"
  local temporary_log="$TMP_DIR/settings-$pane-$language-$profile.log"

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  wait_for_exit || {
    echo "Timed out waiting for $APP_NAME to exit" >&2
    exit 1
  }
  local launch_succeeded=0
  local launch_attempt
  for launch_attempt in 1 2 3; do
    rm -f "$temporary"
    : >"$temporary_log"
    if /usr/bin/open -W -n \
      --stdout "$temporary_log" \
      --stderr "$temporary_log" \
      "$APP_DIR" \
      --args \
      --open-settings \
      "--settings-pane=$pane" \
      "--settings-snapshot-size=$size" \
      "--settings-snapshot-language=$language" \
      --settings-snapshot-output "$temporary"
    then
      launch_succeeded=1
      break
    fi
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    wait_for_exit || true
    sleep 2
  done
  [[ "$launch_succeeded" == "1" ]] || {
    echo "Bilingual Settings launch failed after 3 attempts: $pane/$language" >&2
    cat "$temporary_log" >&2 || true
    exit 1
  }
  [[ -s "$temporary" ]] || {
    echo "Missing bilingual Settings snapshot: $pane/$language" >&2
    cat "$temporary_log" >&2 || true
    exit 1
  }
  cp "$temporary" "$output"
  cp "$temporary_log" "$log"
  local width height
  width="$(/usr/bin/sips -g pixelWidth "$output" | awk '/pixelWidth:/ {print $2}')"
  height="$(/usr/bin/sips -g pixelHeight "$output" | awk '/pixelHeight:/ {print $2}')"
  [[ "$width" -ge "$requested_width" && "$height" -ge "$requested_height" ]] || {
    echo "Unexpected Settings snapshot size: $output ($width x $height)" >&2
    exit 1
  }
}

panes=(general dictation context appearance advanced)
profiles=(minimum default wide)
sizes=(900x620 980x680 1180x760)
for profile_index in "${!profiles[@]}"; do
  profile="${profiles[$profile_index]}"
  size="${sizes[$profile_index]}"
  for pane in "${panes[@]}"; do
    capture zh-Hans "$pane" "$profile" "$size"
    capture en "$pane" "$profile" "$size"
    zh_hash="$(/usr/bin/shasum -a 256 "$OUT_DIR/settings-$pane-zh-Hans-$profile.png" | awk '{print $1}')"
    en_hash="$(/usr/bin/shasum -a 256 "$OUT_DIR/settings-$pane-en-$profile.png" | awk '{print $1}')"
    [[ "$zh_hash" != "$en_hash" ]] || {
      echo "Chinese and English snapshots are identical for pane: $pane/$profile" >&2
      exit 1
    }
  done
done

cat >"$OUT_DIR/summary.md" <<SUMMARY
# OpenWhisper Bilingual Settings Acceptance

- Installed app: \`$APP_DIR\`
- Window profiles: minimum \`900 × 620\`, default \`980 × 680\`, and wide \`1180 × 760\`
- Languages: Simplified Chinese and English
- Panes: General, Input & Output, Context & Privacy, Appearance & Feedback, Advanced
- Rule: language is injected only into the privacy-isolated snapshot harness;
  the product language switch remains Settings → General.

Each PNG is an installed-app self-rendered snapshot. Chinese and English pairs
must differ, retain valid geometry, and are intended for overlap inspection.
SUMMARY

trap - EXIT
rm -rf "$TMP_DIR"
/usr/bin/open "$APP_DIR"
for attempt in {1..60}; do
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Bilingual Settings acceptance artifacts: $OUT_DIR"
    echo "Installed app left running: $APP_DIR"
    exit 0
  fi
  sleep 0.1
done
echo "Installed app did not remain running: $APP_DIR" >&2
exit 1
