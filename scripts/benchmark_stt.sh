#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT_DIR/scripts/lib/load_env.sh"
load_product_env "$ROOT_DIR/product.env"

APP_BIN="/Applications/$VIBEWHISPER_APP_NAME.app/Contents/MacOS/$VIBEWHISPER_APP_NAME"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <audio-file-1> [audio-file-2 ...]"
  echo "Example: $0 ~/bench/3s.wav ~/bench/10s.wav ~/bench/30s.wav"
  exit 1
fi

if [[ ! -x "$APP_BIN" ]]; then
  "$ROOT_DIR/scripts/package_app.sh" >/dev/null
  "$ROOT_DIR/scripts/install_app.sh" >/dev/null
fi

audio_csv=""
for path in "$@"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing audio file: $path" >&2
    exit 1
  fi
  if [[ -n "$audio_csv" ]]; then
    audio_csv+=","
  fi
  audio_csv+="$(python3 - <<'PY' "$path"
import os, sys
print(os.path.abspath(sys.argv[1]), end="")
PY
)"
done

VIBEWHISPER_BENCHMARK=1 \
VIBEWHISPER_BENCHMARK_AUDIO_FILES="$audio_csv" \
VIBEWHISPER_BENCHMARK_RUNS="${VIBEWHISPER_BENCHMARK_RUNS:-5}" \
"$APP_BIN"
