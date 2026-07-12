#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

MANIFEST="${OPENWHISPER_RELEASE_MANIFEST_PATH:-$ROOT/dist/release-manifest.json}"
CASK="$ROOT/packaging/homebrew/Casks/openwhisper.rb"

[[ -f "$MANIFEST" ]] || {
  echo "Missing release manifest: $MANIFEST" >&2
  exit 1
}
[[ -f "$CASK" ]] || {
  echo "Missing Homebrew Cask: $CASK" >&2
  exit 1
}

MANIFEST_VERSION="$(/usr/bin/plutil -extract release.version raw -o - "$MANIFEST")"
ZIP_KIND="$(/usr/bin/plutil -extract artifacts.0.kind raw -o - "$MANIFEST")"
ZIP_SHA256="$(/usr/bin/plutil -extract artifacts.0.sha256 raw -o - "$MANIFEST")"

[[ "$MANIFEST_VERSION" == "$OPENWHISPER_VERSION" ]] || {
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

TEMPORARY_CASK="$CASK.tmp"
trap 'rm -f "$TEMPORARY_CASK"' EXIT
/usr/bin/sed \
  -e "s/^  version \".*\"$/  version \"$OPENWHISPER_VERSION\"/" \
  -e "s/^  sha256 \".*\"$/  sha256 \"$ZIP_SHA256\"/" \
  "$CASK" >"$TEMPORARY_CASK"

grep -q "version \"$OPENWHISPER_VERSION\"" "$TEMPORARY_CASK"
grep -q "sha256 \"$ZIP_SHA256\"" "$TEMPORARY_CASK"
if grep -q "sha256 :no_check" "$TEMPORARY_CASK"; then
  echo "Homebrew Cask must not disable checksum verification." >&2
  exit 1
fi

mv "$TEMPORARY_CASK" "$CASK"
trap - EXIT
echo "Updated $CASK with release ZIP SHA-256."
