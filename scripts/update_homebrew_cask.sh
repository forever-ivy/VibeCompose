#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

MANIFEST="${VIBECOMPOSE_RELEASE_MANIFEST_PATH:-$ROOT/dist/release-manifest.json}"
CASK_SOURCE="$ROOT/packaging/homebrew/Casks/vibecompose.rb"
CASK="${VIBECOMPOSE_CASK_OUTPUT_PATH:-$CASK_SOURCE}"

[[ -f "$MANIFEST" ]] || {
  echo "Missing release manifest: $MANIFEST" >&2
  exit 1
}
[[ -f "$CASK_SOURCE" ]] || {
  echo "Missing Homebrew Cask template: $CASK_SOURCE" >&2
  exit 1
}

MANIFEST_VERSION="$(/usr/bin/plutil -extract release.version raw -o - "$MANIFEST")"
ZIP_KIND="$(/usr/bin/plutil -extract artifacts.0.kind raw -o - "$MANIFEST")"
ZIP_SHA256="$(/usr/bin/plutil -extract artifacts.0.sha256 raw -o - "$MANIFEST")"
ZIP_DOWNLOAD_URL="$(/usr/bin/plutil -extract artifacts.0.downloadURL raw -o - "$MANIFEST")"

[[ "$MANIFEST_VERSION" == "$VIBECOMPOSE_VERSION" ]] || {
  echo "Manifest version does not match version.env." >&2
  exit 1
}
[[ "$ZIP_KIND" == "zip" ]] || {
  echo "The first release-manifest artifact must be the ZIP." >&2
  exit 1
}
[[ "$ZIP_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Release ZIP SHA-256 is invalid." >&2
  exit 1
}
[[ "$ZIP_SHA256" != "0000000000000000000000000000000000000000000000000000000000000000" ]] || {
  echo "Release ZIP SHA-256 must not use the unreleased fail-closed value." >&2
  exit 1
}
[[ "$ZIP_DOWNLOAD_URL" == https://* \
  && "$ZIP_DOWNLOAD_URL" != *"@"* \
  && "$ZIP_DOWNLOAD_URL" != *"?"* \
  && "$ZIP_DOWNLOAD_URL" != *"#"* \
  && "$ZIP_DOWNLOAD_URL" != *'"'* \
  && "$ZIP_DOWNLOAD_URL" != *"\\"* ]] || {
  echo "Release ZIP URL must be a credential-free HTTPS URL." >&2
  exit 1
}

TEMPORARY_CASK="$CASK.tmp"
trap 'rm -f "$TEMPORARY_CASK"' EXIT
mkdir -p "$(dirname "$CASK")"
python3 - "$CASK_SOURCE" "$TEMPORARY_CASK" \
  "$VIBECOMPOSE_VERSION" "$ZIP_SHA256" "$ZIP_DOWNLOAD_URL" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
version, sha256, download_url = sys.argv[3:]
text = source.read_text(encoding="utf-8")

replacements = (
    (r'^  version ".*"$', f'  version "{version}"'),
    (r'^  sha256 ".*"$', f'  sha256 "{sha256}"'),
    (r'^  url ".*"$', f'  url "{download_url}"'),
)
for pattern, replacement in replacements:
    text, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Expected exactly one Cask field matching {pattern}")

destination.write_text(text, encoding="utf-8")
PY

grep -q "version \"$VIBECOMPOSE_VERSION\"" "$TEMPORARY_CASK"
grep -q "sha256 \"$ZIP_SHA256\"" "$TEMPORARY_CASK"
grep -Fq "url \"$ZIP_DOWNLOAD_URL\"" "$TEMPORARY_CASK"
if grep -q "sha256 :no_check" "$TEMPORARY_CASK"; then
  echo "Homebrew Cask must not disable checksum verification." >&2
  exit 1
fi

mv "$TEMPORARY_CASK" "$CASK"
trap - EXIT
echo "Updated $CASK with release ZIP URL and SHA-256."
