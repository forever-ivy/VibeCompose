#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$VIBECOMPOSE_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
OUT_ROOT="$ROOT/dist/paste-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"
INSTALL_FIRST=0
TARGET_MODE="all"
TEMP_EVIDENCE=()

usage() {
  echo "Usage: $0 [--install] [--target textedit|terminal|all]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_FIRST=1
      shift
      ;;
    --target)
      [[ $# -ge 2 ]] || {
        usage
        exit 64
      }
      TARGET_MODE="$2"
      shift 2
      ;;
    --target=*)
      TARGET_MODE="${1#--target=}"
      shift
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

case "$TARGET_MODE" in
  all)
    TARGETS=(textedit terminal)
    ;;
  textedit|terminal)
    TARGETS=("$TARGET_MODE")
    ;;
  *)
    usage
    exit 64
    ;;
esac

cleanup() {
  for evidence in "${TEMP_EVIDENCE[@]:-}"; do
    [[ -n "$evidence" ]] && rm -f "$evidence"
  done
  if [[ -d "$APP_DIR" ]] && ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    /usr/bin/open "$APP_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"

if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh"
  "$ROOT/scripts/install_app.sh"
fi

if [[ ! -x "$APP_DIR/Contents/MacOS/$APP_NAME" ]]; then
  echo "Missing installed app: $APP_DIR" >&2
  exit 1
fi

for target in "${TARGETS[@]}"; do
  evidence="$OUT_DIR/$target.json"
  temp_evidence="${TMPDIR:-/tmp}/vibecompose-paste-acceptance-$RUN_ID-$target.json"
  TEMP_EVIDENCE+=("$temp_evidence")
  rm -f "$temp_evidence"

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -W -n "$APP_DIR" --args \
    --paste-acceptance \
    --paste-acceptance-target "$target" \
    --paste-acceptance-output "$temp_evidence"

  if [[ ! -s "$temp_evidence" ]]; then
    echo "Paste acceptance did not produce evidence for $target: $temp_evidence" >&2
    exit 1
  fi
  cp "$temp_evidence" "$evidence"

  python3 - "$evidence" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
print(
    f"{data.get('targetApplication')} paste acceptance: "
    f"passed={data.get('passed')} "
    f"status={data.get('resultStatus')} "
    f"clipboard={data.get('clipboardState')} "
    f"ax_observed={data.get('expectedTextObserved')} "
    f"execution_proof={data.get('executionProofObserved')} "
    f"original_clipboard_restored={data.get('originalClipboardRestored')}"
)
if not data.get("passed"):
    print(data.get("error") or "Unknown paste acceptance failure", file=sys.stderr)
    raise SystemExit(1)
PY
done

/usr/bin/open "$APP_DIR"
for _ in {1..50}; do
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "Installed app did not remain running after paste acceptance." >&2
  exit 1
fi

RUNNING_PID="$(pgrep -x "$APP_NAME" | sed -n '1p')"
{
  cat <<SUMMARY
# VibeCompose Installed Paste Acceptance

- Run ID: \`$RUN_ID\`
- Installed app: \`$APP_DIR\`
- Targets: \`${TARGETS[*]}\`
- TextEdit requirement: exact AX transition to \`inserted_verified\`
- Terminal requirement: isolated no-history shell executes only a generated
  marker command, proving dispatch; verified insertion restores the sentinel,
  while unverifiable dispatch retains the transcript as designed
- Clipboard: the complete pre-acceptance snapshot is restored after each target
- Final live state: normal installed VibeCompose relaunched and left running as PID \`$RUNNING_PID\`

Evidence:
SUMMARY
  for target in "${TARGETS[@]}"; do
    echo "- \`$target.json\`"
  done
  cat <<'SUMMARY'

The Terminal process uses a fresh HOME/ZDOTDIR with history disabled and is
terminated after the proof file is observed. This automated installed-binary
matrix does not mutate a user's Terminal session. Notes remains a separate
manual acceptance surface because it has no equivalent disposable document
store and must not inspect or modify personal notes during automation.
SUMMARY
} >"$OUT_DIR/summary.md"

echo "Paste acceptance artifacts: $OUT_DIR"
echo "Installed app left running: $APP_DIR (PID $RUNNING_PID)"

trap - EXIT
cleanup
