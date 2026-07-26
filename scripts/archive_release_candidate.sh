#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

ARCHIVE_PATH="${1:-}"
CHECKSUM_PATH="${2:-}"
if [[ -z "$ARCHIVE_PATH" || -z "$CHECKSUM_PATH" ]]; then
  echo "Usage: $0 ARCHIVE_PATH CHECKSUM_PATH" >&2
  exit 64
fi

ARCH="$(uname -m)"
CASK_PATH="${VIBECOMPOSE_CASK_PATH:-$ROOT/dist/vibecompose.rb}"
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"

declare -a REQUIRED_PATHS=(
  "$ROOT/dist/$VIBECOMPOSE_APP_NAME.app"
  "$ROOT/dist/${VIBECOMPOSE_APP_NAME}-${VIBECOMPOSE_VERSION}-macos-${ARCH}.zip"
  "$ROOT/dist/${VIBECOMPOSE_APP_NAME}-${VIBECOMPOSE_VERSION}-macos-${ARCH}.dmg"
  "$ROOT/dist/release-manifest.json"
  "$ROOT/dist/appcast.xml"
  "$ROOT/dist/provider-capabilities.json"
  "$ROOT/dist/notarization-app.json"
  "$ROOT/dist/notarization-dmg.json"
  "$ROOT/dist/release-candidate-readiness.json"
  "$ROOT/dist/SHA256SUMS"
  "$CASK_PATH"
)

for path in "${REQUIRED_PATHS[@]}"; do
  [[ -e "$path" && ! -L "$path" ]] || {
    echo "Missing or unsafe release-candidate input: $path" >&2
    exit 1
  }
done

for output in "$ARCHIVE_PATH" "$CHECKSUM_PATH"; do
  if [[ -L "$output" || -d "$output" ]]; then
    echo "Refusing unsafe candidate output path: $output" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$output")"
done

TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/vibecompose-candidate.XXXXXX")"
STAGE_ROOT="$TEMPORARY_DIRECTORY/VibeCompose-release-candidate"
TEMPORARY_ARCHIVE="$TEMPORARY_DIRECTORY/candidate.zip"
TEMPORARY_CHECKSUM="$TEMPORARY_DIRECTORY/candidate.sha256"
trap 'rm -rf "$TEMPORARY_DIRECTORY"' EXIT

umask 077
/usr/bin/ditto \
  "$ROOT/dist/$VIBECOMPOSE_APP_NAME.app" \
  "$STAGE_ROOT/dist/$VIBECOMPOSE_APP_NAME.app"

for file in \
  "$ROOT/dist/${VIBECOMPOSE_APP_NAME}-${VIBECOMPOSE_VERSION}-macos-${ARCH}.zip" \
  "$ROOT/dist/${VIBECOMPOSE_APP_NAME}-${VIBECOMPOSE_VERSION}-macos-${ARCH}.dmg" \
  "$ROOT/dist/release-manifest.json" \
  "$ROOT/dist/appcast.xml" \
  "$ROOT/dist/provider-capabilities.json" \
  "$ROOT/dist/notarization-app.json" \
  "$ROOT/dist/notarization-dmg.json" \
  "$ROOT/dist/release-candidate-readiness.json" \
  "$ROOT/dist/SHA256SUMS"; do
  /usr/bin/ditto "$file" "$STAGE_ROOT/dist/$(basename "$file")"
done
/usr/bin/ditto "$CASK_PATH" "$STAGE_ROOT/dist/vibecompose.rb"

python3 - \
  "$STAGE_ROOT/candidate-metadata.json" \
  "$SOURCE_COMMIT" \
  "$VIBECOMPOSE_REPOSITORY" \
  "$VIBECOMPOSE_APP_NAME" \
  "$VIBECOMPOSE_BUNDLE_ID" \
  "$VIBECOMPOSE_VERSION" \
  "$VIBECOMPOSE_BUILD" \
  "$ARCH" \
  "${GITHUB_RUN_ID:-local}" \
  "${GITHUB_RUN_ATTEMPT:-local}" <<'PY'
import datetime as dt
import json
import pathlib
import re
import sys

(
    output,
    source_commit,
    repository,
    app_name,
    bundle_id,
    version,
    build,
    architecture,
    run_id,
    run_attempt,
) = sys.argv[1:]

if re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", source_commit) is None:
    raise SystemExit("The candidate source commit is not a full Git object ID.")

metadata = {
    "schemaVersion": 1,
    "createdAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "sourceCommit": source_commit,
    "repository": repository,
    "product": {
        "name": app_name,
        "bundleIdentifier": bundle_id,
    },
    "release": {
        "version": version,
        "build": build,
        "architecture": architecture,
    },
    "workflow": {
        "runID": run_id,
        "runAttempt": run_attempt,
    },
}
path = pathlib.Path(output)
path.write_text(
    json.dumps(metadata, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
path.chmod(0o600)
PY

/usr/bin/ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$STAGE_ROOT" \
  "$TEMPORARY_ARCHIVE"

ARCHIVE_SHA256="$(/usr/bin/shasum -a 256 "$TEMPORARY_ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$(basename "$ARCHIVE_PATH")" >"$TEMPORARY_CHECKSUM"
chmod 0600 "$TEMPORARY_ARCHIVE" "$TEMPORARY_CHECKSUM"

mv -f "$TEMPORARY_ARCHIVE" "$ARCHIVE_PATH"
mv -f "$TEMPORARY_CHECKSUM" "$CHECKSUM_PATH"

echo "Archived signed release candidate: $ARCHIVE_PATH"
echo "Candidate SHA-256: $ARCHIVE_SHA256"
