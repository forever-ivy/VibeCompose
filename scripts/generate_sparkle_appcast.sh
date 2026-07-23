#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/scripts/lib/load_env.sh"
load_product_env "$ROOT/product.env"
load_version_env "$ROOT/version.env"

ARCH="$(uname -m)"
ZIP="$ROOT/dist/${VIBEWHISPER_APP_NAME}-${VIBEWHISPER_VERSION}-macos-${ARCH}.zip"
MANIFEST="${VIBEWHISPER_RELEASE_MANIFEST_PATH:-$ROOT/dist/release-manifest.json}"
CHANNEL="${VIBEWHISPER_SPARKLE_CHANNEL:-stable}"
KEY_ACCOUNT="${VIBEWHISPER_SPARKLE_KEY_ACCOUNT:-vibewhisper}"
PRIVATE_KEY_FILE="${VIBEWHISPER_SPARKLE_PRIVATE_KEY_FILE:-}"
PUBLIC_KEY="${VIBEWHISPER_SPARKLE_PUBLIC_ED_KEY:-}"

case "$CHANNEL" in
  stable|beta|alpha)
    ;;
  *)
    echo "VIBEWHISPER_SPARKLE_CHANNEL must be stable, beta, or alpha." >&2
    exit 1
    ;;
esac

if [[ "$CHANNEL" == "stable" ]]; then
  APPCAST="$ROOT/dist/appcast.xml"
else
  APPCAST="$ROOT/dist/appcast-$CHANNEL.xml"
fi
APPCAST="${VIBEWHISPER_SPARKLE_APPCAST_PATH:-$APPCAST}"

[[ -f "$ZIP" && ! -L "$ZIP" && -f "$MANIFEST" && ! -L "$MANIFEST" ]] || {
  echo "Generate release artifacts and release-manifest.json before creating an appcast." >&2
  exit 1
}
[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || {
  echo "VIBEWHISPER_SPARKLE_PUBLIC_ED_KEY must contain the matching 32-byte base64 public key." >&2
  exit 1
}

GENERATOR="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$GENERATOR" ]]; then
  GENERATOR="$(find "$ROOT/.build/artifacts" -type f -path '*/Sparkle/bin/generate_appcast' -perm -111 -print -quit 2>/dev/null || true)"
fi
[[ -n "$GENERATOR" && -x "$GENERATOR" ]] || {
  echo "Sparkle generate_appcast is unavailable. Resolve the pinned Swift package first." >&2
  exit 1
}

MANIFEST_VERSION="$(/usr/bin/plutil -extract release.version raw -o - "$MANIFEST")"
MANIFEST_BUILD="$(/usr/bin/plutil -extract release.build raw -o - "$MANIFEST")"
ZIP_FILE_NAME="$(/usr/bin/plutil -extract artifacts.0.fileName raw -o - "$MANIFEST")"
ZIP_DOWNLOAD_URL="$(/usr/bin/plutil -extract artifacts.0.downloadURL raw -o - "$MANIFEST")"
[[ "$MANIFEST_VERSION" == "$VIBEWHISPER_VERSION" \
  && "$MANIFEST_BUILD" == "$VIBEWHISPER_BUILD" \
  && "$ZIP_FILE_NAME" == "$(basename "$ZIP")" \
  && "$ZIP_DOWNLOAD_URL" == https://* \
  && "$ZIP_DOWNLOAD_URL" != *"@"* ]] || {
  echo "Release manifest is not suitable for a signed Sparkle appcast." >&2
  exit 1
}

DOWNLOAD_URL_PREFIX="${ZIP_DOWNLOAD_URL%/*}/"
WORK_DIR="$ROOT/dist/.sparkle-appcast-$CHANNEL"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT
CACHE_HOME="$WORK_DIR/home"
mkdir -p "$CACHE_HOME/Library/Caches"

/usr/bin/ditto "$ZIP" "$WORK_DIR/$(basename "$ZIP")"
if [[ -f "$APPCAST" && ! -L "$APPCAST" ]]; then
  /usr/bin/ditto "$APPCAST" "$WORK_DIR/appcast.xml"
fi

RELEASE_NOTES="$ROOT/docs/releases/v${VIBEWHISPER_VERSION}.md"
if [[ -f "$RELEASE_NOTES" && ! -L "$RELEASE_NOTES" ]]; then
  /usr/bin/ditto \
    "$RELEASE_NOTES" \
    "$WORK_DIR/${VIBEWHISPER_APP_NAME}-${VIBEWHISPER_VERSION}-macos-${ARCH}.md"
fi

GENERATOR_ARGS=(
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --link "https://github.com/$VIBEWHISPER_REPOSITORY"
  --maximum-versions 5
  --maximum-deltas 3
  --versions "$VIBEWHISPER_BUILD"
  -o appcast.xml
)
if [[ "$CHANNEL" != "stable" ]]; then
  GENERATOR_ARGS+=(--channel "$CHANNEL")
fi

if [[ -n "$PRIVATE_KEY_FILE" ]]; then
  [[ -f "$PRIVATE_KEY_FILE" && ! -L "$PRIVATE_KEY_FILE" ]] || {
    echo "VIBEWHISPER_SPARKLE_PRIVATE_KEY_FILE must be a regular, non-symlink file." >&2
    exit 1
  }
  PRIVATE_KEY_MODE="$(/usr/bin/stat -f '%Lp' "$PRIVATE_KEY_FILE")"
  if (( (8#$PRIVATE_KEY_MODE & 8#077) != 0 )); then
    echo "Sparkle private key file must not be accessible by group or other users." >&2
    exit 1
  fi
  GENERATOR_ARGS+=(--ed-key-file "$PRIVATE_KEY_FILE")
else
  GENERATOR_ARGS+=(--account "$KEY_ACCOUNT")
fi

(
  cd "$WORK_DIR"
  HOME="$CACHE_HOME" \
  CFFIXED_USER_HOME="$CACHE_HOME" \
  TMPDIR="$WORK_DIR" \
    "$GENERATOR" "${GENERATOR_ARGS[@]}" "$WORK_DIR"
)

GENERATED_APPCAST="$WORK_DIR/appcast.xml"
[[ -f "$GENERATED_APPCAST" ]] || {
  echo "Sparkle did not generate an appcast." >&2
  exit 1
}
/usr/bin/xmllint --noout "$GENERATED_APPCAST"
grep -q 'sparkle:edSignature="' "$GENERATED_APPCAST" || {
  echo "Generated appcast does not contain an EdDSA archive signature." >&2
  exit 1
}
grep -Fq "$ZIP_DOWNLOAD_URL" "$GENERATED_APPCAST" || {
  echo "Generated appcast does not contain the release download URL." >&2
  exit 1
}
"$ROOT/scripts/verify_sparkle_appcast.swift" \
  --appcast "$GENERATED_APPCAST" \
  --archive "$ZIP" \
  --manifest "$MANIFEST" \
  --public-key "$PUBLIC_KEY"

mkdir -p "$(dirname "$APPCAST")"
/usr/bin/ditto "$GENERATED_APPCAST" "$APPCAST.tmp"
chmod 0644 "$APPCAST.tmp"
mv "$APPCAST.tmp" "$APPCAST"

trap - EXIT
rm -rf "$WORK_DIR"
echo "Generated signed Sparkle appcast: $APPCAST"
