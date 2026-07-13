#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
OUT_ROOT="$ROOT/dist/accessibility-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openwhisper-accessibility.XXXXXX")"

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

capture_audit() {
  local surface="$1"
  local open_argument="$2"
  local pane="${3:-}"
  local temporary_file="$TMP_DIR/$surface.json"

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  wait_for_app_exit

  local args=(
    "$open_argument"
    "--accessibility-audit-output"
    "$temporary_file"
  )
  if [[ -n "$pane" ]]; then
    args+=("--settings-pane" "$pane")
  fi

  /usr/bin/open -W -n "$APP_DIR" --args "${args[@]}"

  if [[ ! -s "$temporary_file" ]]; then
    echo "$surface did not produce accessibility evidence" >&2
    exit 1
  fi
  cp "$temporary_file" "$OUT_DIR/$surface.json"
}

capture_audit "settings-account" "--open-settings" "account"
capture_audit "settings-dictation" "--open-settings" "dictation"
capture_audit "settings-ai-polish" "--open-settings" "ai-polish"
capture_audit "settings-paste" "--open-settings" "paste"
capture_audit "settings-privacy" "--open-settings" "privacy"
capture_audit "settings-advanced" "--open-settings" "advanced"
capture_audit "onboarding" "--open-onboarding"
capture_audit "history" "--open-history"
capture_audit "terminology" "--open-terminology"
capture_audit "quick-add" "--open-quick-add"

python3 - "$OUT_DIR" <<'PY' | tee "$OUT_DIR/verification.txt"
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
expected = {
    "settings-account",
    "settings-dictation",
    "settings-ai-polish",
    "settings-paste",
    "settings-privacy",
    "settings-advanced",
    "onboarding",
    "history",
    "terminology",
    "quick-add",
}

failed = []
for surface in sorted(expected):
    path = root / f"{surface}.json"
    data = json.loads(path.read_text())
    passed = bool(data.get("passed"))
    actionables = int(data.get("actionableCount", 0))
    missing = data.get("missingActionableNames") or []
    print(
        f"{surface}: passed={passed} "
        f"nodes={data.get('nodeCount')} "
        f"actionable={actionables} "
        f"missing_names={len(missing)}"
    )
    if data.get("surface") != surface or not passed or actionables < 1 or missing:
        failed.append(surface)

if failed:
    print(
        "Accessibility acceptance failed: " + ", ".join(failed),
        file=sys.stderr,
    )
    raise SystemExit(1)

print("OpenWhisper accessibility structure acceptance passed.")
PY

trap - EXIT
rm -rf "$TMP_DIR"

/usr/bin/open "$APP_DIR"
for _ in {1..50}; do
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "Installed app did not remain running after accessibility acceptance." >&2
  exit 1
fi

RUNNING_PID="$(pgrep -x "$APP_NAME" | sed -n '1p')"
cat >"$OUT_DIR/summary.md" <<SUMMARY
# OpenWhisper Accessibility Structure Acceptance

- Run ID: \`$RUN_ID\`
- Installed app: \`$APP_DIR\`
- Surfaces: six Settings panes, Onboarding, History, Terminology, Quick Add
- Validation: SwiftUI enhanced accessibility tree, actionable names, non-empty control surface
- Privacy: capture mode uses default configuration and empty in-memory user data
- Final live state: normal installed OpenWhisper relaunched and left running as PID \`$RUNNING_PID\`

This installed-app structure audit is a repeatable precheck. It does not replace
official Computer Use keyboard navigation, VoiceOver speech-output, focus,
timing, or permission interaction acceptance.
SUMMARY

echo "Accessibility acceptance artifacts: $OUT_DIR"
echo "Installed app left running: $APP_DIR (PID $RUNNING_PID)"
