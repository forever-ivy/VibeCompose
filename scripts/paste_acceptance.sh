#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"

APP_NAME="$OPENWHISPER_APP_NAME"
APP_DIR="/Applications/$APP_NAME.app"
OUT_ROOT="$ROOT/dist/paste-acceptance"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$RUN_ID"
EVIDENCE="$OUT_DIR/textedit.json"
TEMP_EVIDENCE="${TMPDIR:-/tmp}/openwhisper-paste-acceptance-$RUN_ID.json"

cleanup() {
  rm -f "$TEMP_EVIDENCE"
  if [[ -d "$APP_DIR" ]] && ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    /usr/bin/open "$APP_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

INSTALL_FIRST=0
if [[ "${1:-}" == "--install" ]]; then
  INSTALL_FIRST=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--install]" >&2
  exit 64
fi

mkdir -p "$OUT_DIR"
rm -f "$TEMP_EVIDENCE"

if [[ "$INSTALL_FIRST" == "1" ]]; then
  "$ROOT/scripts/package_app.sh"
  "$ROOT/scripts/install_app.sh"
fi

if [[ ! -x "$APP_DIR/Contents/MacOS/$APP_NAME" ]]; then
  echo "Missing installed app: $APP_DIR" >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
/usr/bin/open -W -n "$APP_DIR" --args \
  --paste-acceptance \
  --paste-acceptance-output "$TEMP_EVIDENCE"

if [[ ! -s "$TEMP_EVIDENCE" ]]; then
  echo "Paste acceptance did not produce evidence: $TEMP_EVIDENCE" >&2
  exit 1
fi
cp "$TEMP_EVIDENCE" "$EVIDENCE"

python3 - "$EVIDENCE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
print(
    "TextEdit paste acceptance: "
    f"passed={data.get('passed')} "
    f"status={data.get('resultStatus')} "
    f"clipboard={data.get('clipboardState')} "
    f"observed={data.get('expectedTextObserved')}"
)
if not data.get("passed"):
    print(data.get("error") or "Unknown paste acceptance failure", file=sys.stderr)
    raise SystemExit(1)
PY

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
cat >"$OUT_DIR/summary.md" <<SUMMARY
# OpenWhisper Installed Paste Acceptance

- Run ID: \`$RUN_ID\`
- Installed app: \`$APP_DIR\`
- Target: isolated TextEdit process and temporary document
- Required outcome: \`inserted_verified\`
- Required clipboard result: previous sentinel restored only after verification
- Evidence: \`textedit.json\`
- Final live state: normal installed OpenWhisper relaunched and left running as PID \`$RUNNING_PID\`

This is an installed-binary precheck. It does not replace the required official
Computer Use Notes/TextEdit/Terminal and focus-change interaction matrix.
SUMMARY

echo "Paste acceptance artifacts: $OUT_DIR"
echo "Installed app left running: $APP_DIR (PID $RUNNING_PID)"

trap - EXIT
rm -f "$TEMP_EVIDENCE"
