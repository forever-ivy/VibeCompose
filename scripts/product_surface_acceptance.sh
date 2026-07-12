#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
OUT_ROOT="$ROOT/dist/product-surface-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openwhisper-product-surfaces.XXXXXX")"

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
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"

if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh" >/dev/null
  "$ROOT/scripts/install_app.sh" >/dev/null
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing installed app binary at $APP_BINARY" >&2
  echo "Run: $ROOT/scripts/product_surface_acceptance.sh --install" >&2
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

capture_surface() {
  local launch_mode="$1"
  local snapshot_argument="$2"
  local output_file="$3"
  local temporary_file="$TMP_DIR/$output_file"

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if ! wait_for_app_exit; then
    echo "Timed out waiting for the previous $APP_NAME process to exit" >&2
    exit 1
  fi

  /usr/bin/open -W -n "$APP_DIR" --args \
    "--open-$launch_mode" \
    "--$snapshot_argument" \
    "$temporary_file"

  if [[ ! -s "$temporary_file" ]]; then
    echo "$launch_mode did not produce a product surface snapshot" >&2
    exit 1
  fi
  cp "$temporary_file" "$OUT_DIR/$output_file"
}

capture_surface "history" "history-snapshot-output" "01-history.png"
capture_surface "terminology" "terminology-snapshot-output" "02-terminology.png"
capture_surface "quick-add" "quick-add-snapshot-output" "03-quick-add.png"

swift "$ROOT/scripts/verify_product_surfaces.swift" \
  "$OUT_DIR/01-history.png" \
  "$OUT_DIR/02-terminology.png" \
  "$OUT_DIR/03-quick-add.png" | tee "$OUT_DIR/verification.txt"

trap - EXIT
rm -rf "$TMP_DIR"

/usr/bin/open "$APP_DIR"
if ! wait_for_installed_app; then
  echo "Installed app did not remain running after launch: $APP_DIR" >&2
  exit 1
fi
RUNNING_PID="$(pgrep -x "$APP_NAME" | sed -n '1p')"

cat >"$OUT_DIR/summary.md" <<SUMMARY
# OpenWhisper Product Surface Acceptance

- Run ID: \`$RUN_ID\`
- App: \`$APP_BINARY\`
- Capture: installed-app self-rendered window snapshots through local temporary files
- Surfaces: History, Terminology, Quick Add
- Final live state: normal installed app relaunched and left running as PID \`$RUNNING_PID\`
- Evidence:
  - \`01-history.png\`
  - \`02-terminology.png\`
  - \`03-quick-add.png\`
  - \`verification.txt\`

SUMMARY

echo "Product surface acceptance artifacts: $OUT_DIR"
echo "Installed app left running: $APP_DIR (PID $RUNNING_PID)"
