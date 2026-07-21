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

for path in "$ARCHIVE_PATH" "$CHECKSUM_PATH"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "Missing or unsafe candidate input: $path" >&2
    exit 1
  }
done

read -r EXPECTED_SHA256 CHECKSUM_FILE EXTRA <"$CHECKSUM_PATH"
CHECKSUM_FILE="${CHECKSUM_FILE#\\*}"
if [[ ! "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ \
  || "$CHECKSUM_FILE" != "$(basename "$ARCHIVE_PATH")" \
  || -n "${EXTRA:-}" ]]; then
  echo "Candidate checksum file is malformed or names another archive." >&2
  exit 1
fi

ACTUAL_SHA256="$(/usr/bin/shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || {
  echo "Signed release candidate SHA-256 mismatch." >&2
  exit 1
}

python3 - "$ARCHIVE_PATH" <<'PY'
import pathlib
import sys
import zipfile

archive = pathlib.Path(sys.argv[1])
root_name = "OpenWhisper-release-candidate"
maximum_entries = 20_000
maximum_uncompressed_bytes = 4 * 1024 * 1024 * 1024

with zipfile.ZipFile(archive) as candidate:
    entries = candidate.infolist()
    if not entries or len(entries) > maximum_entries:
        raise SystemExit("Candidate archive has an invalid entry count.")
    total = 0
    for entry in entries:
        name = entry.filename
        path = pathlib.PurePosixPath(name)
        if (
            not name
            or name.startswith("/")
            or "\\" in name
            or ".." in path.parts
            or not path.parts
            or path.parts[0] not in {root_name, "__MACOSX"}
        ):
            raise SystemExit(f"Unsafe candidate archive entry: {name!r}")
        total += entry.file_size
        if total > maximum_uncompressed_bytes:
            raise SystemExit("Candidate archive exceeds the extraction byte limit.")
PY

TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/openwhisper-restore.XXXXXX")"
EXTRACTED_ROOT="$TEMPORARY_DIRECTORY/OpenWhisper-release-candidate"
STAGED_DIST="$ROOT/.openwhisper-dist-restore.$$"
BACKUP_DIST="$ROOT/.openwhisper-dist-backup.$$"
TARGET_DIST="$ROOT/dist"
RESTORE_COMMITTED=0
trap '
  rm -rf "$TEMPORARY_DIRECTORY" "$STAGED_DIST"
  if [[ "$RESTORE_COMMITTED" != "1" && -d "$BACKUP_DIST" && ! -e "$TARGET_DIST" ]]; then
    mv "$BACKUP_DIST" "$TARGET_DIST"
  fi
  rm -rf "$BACKUP_DIST"
' EXIT

umask 077
/usr/bin/ditto -x -k "$ARCHIVE_PATH" "$TEMPORARY_DIRECTORY"

[[ -d "$EXTRACTED_ROOT" \
  && ! -L "$EXTRACTED_ROOT" \
  && -d "$EXTRACTED_ROOT/dist" \
  && ! -L "$EXTRACTED_ROOT/dist" \
  && -f "$EXTRACTED_ROOT/candidate-metadata.json" \
  && ! -L "$EXTRACTED_ROOT/candidate-metadata.json" ]] || {
  echo "Candidate archive is missing its fixed root, dist tree, or metadata." >&2
  exit 1
}

python3 - \
  "$EXTRACTED_ROOT" \
  "$OPENWHISPER_REPOSITORY" \
  "$OPENWHISPER_APP_NAME" \
  "$OPENWHISPER_BUNDLE_ID" \
  "$OPENWHISPER_VERSION" \
  "$OPENWHISPER_BUILD" \
  "$(uname -m)" \
  "$(git -C "$ROOT" rev-parse HEAD)" <<'PY'
import hashlib
import json
import os
import pathlib
import re
import sys
import urllib.parse

(
    extracted_root,
    repository,
    app_name,
    bundle_id,
    version,
    build,
    architecture,
    source_commit,
) = sys.argv[1:]

root = pathlib.Path(extracted_root).resolve(strict=True)
metadata_path = root / "candidate-metadata.json"
dist = root / "dist"

for path in root.rglob("*"):
    if path.is_symlink():
        resolved = path.resolve(strict=False)
        if resolved != root and root not in resolved.parents:
            raise SystemExit(f"Candidate symlink escapes its root: {path}")

metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
if not isinstance(metadata, dict) or metadata.get("schemaVersion") != 1:
    raise SystemExit("Candidate metadata schema is invalid.")
if metadata.get("sourceCommit") != source_commit:
    raise SystemExit("Candidate source commit does not match the checked-out release commit.")
if re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", source_commit) is None:
    raise SystemExit("The checked-out source commit is not a full Git object ID.")
if metadata.get("repository") != repository:
    raise SystemExit("Candidate repository identity mismatch.")
if metadata.get("product") != {
    "name": app_name,
    "bundleIdentifier": bundle_id,
}:
    raise SystemExit("Candidate product identity mismatch.")
if metadata.get("release") != {
    "version": version,
    "build": build,
    "architecture": architecture,
}:
    raise SystemExit("Candidate release identity mismatch.")

manifest_path = dist / "release-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
release = manifest.get("release")
product = manifest.get("product")
if not isinstance(release, dict) or (
    release.get("version"),
    release.get("build"),
    release.get("architecture"),
) != (version, build, architecture):
    raise SystemExit("Candidate release manifest version/build/architecture mismatch.")
if not isinstance(product, dict) or (
    product.get("name"),
    product.get("bundleIdentifier"),
    product.get("repository"),
) != (app_name, bundle_id, repository):
    raise SystemExit("Candidate release manifest product identity mismatch.")

artifacts = manifest.get("artifacts")
if not isinstance(artifacts, list) or len(artifacts) != 2:
    raise SystemExit("Candidate release manifest must contain ZIP and DMG artifacts.")

expected_names = {
    "zip": f"{app_name}-{version}-macos-{architecture}.zip",
    "dmg": f"{app_name}-{version}-macos-{architecture}.dmg",
}
seen_kinds = set()
for artifact in artifacts:
    if not isinstance(artifact, dict):
        raise SystemExit("Candidate artifact metadata is invalid.")
    kind = artifact.get("kind")
    name = artifact.get("fileName")
    if kind not in expected_names or name != expected_names[kind] or kind in seen_kinds:
        raise SystemExit("Candidate artifact kind or filename mismatch.")
    seen_kinds.add(kind)
    artifact_path = dist / name
    if artifact_path.is_symlink() or not artifact_path.is_file():
        raise SystemExit(f"Candidate artifact is missing or unsafe: {name}")
    size = artifact_path.stat().st_size
    digest = hashlib.sha256()
    with artifact_path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    if artifact.get("byteCount") != size or artifact.get("sha256") != digest.hexdigest():
        raise SystemExit(f"Candidate artifact hash or byte count mismatch: {name}")
    url = artifact.get("downloadURL")
    if not isinstance(url, str):
        raise SystemExit("Candidate artifact download URL is missing.")
    parsed = urllib.parse.urlsplit(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
        or urllib.parse.urlunsplit(parsed) != url
    ):
        raise SystemExit("Candidate artifact download URL is not canonical HTTPS.")

required = (
    dist / f"{app_name}.app",
    dist / "appcast.xml",
    dist / "provider-capabilities.json",
    dist / "notarization-app.json",
    dist / "notarization-dmg.json",
    dist / "release-candidate-readiness.json",
    dist / "SHA256SUMS",
    dist / "openwhisper.rb",
)
for path in required:
    if path.name == f"{app_name}.app":
        valid = path.is_dir() and not path.is_symlink()
    else:
        valid = path.is_file() and not path.is_symlink()
    if not valid:
        raise SystemExit(f"Candidate is missing required release evidence: {path.name}")

readiness_path = dist / "release-candidate-readiness.json"
readiness = json.loads(readiness_path.read_text(encoding="utf-8"))
if (
    not isinstance(readiness, dict)
    or readiness.get("schemaVersion") != 1
    or readiness.get("phase") != "candidate"
    or readiness.get("passed") is not True
    or readiness.get("sourceCommit") != source_commit
    or readiness.get("release") != {"version": version, "build": build}
):
    raise SystemExit("Candidate readiness report is invalid or for another source commit.")

notarization_ids = set()
for name in ("notarization-app.json", "notarization-dmg.json"):
    receipt = json.loads((dist / name).read_text(encoding="utf-8"))
    submission_id = receipt.get("id") if isinstance(receipt, dict) else None
    if (
        not isinstance(receipt, dict)
        or receipt.get("status") != "Accepted"
        or not isinstance(submission_id, str)
        or re.fullmatch(
            r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
            submission_id,
        ) is None
        or submission_id in notarization_ids
    ):
        raise SystemExit(f"Candidate notarization result is invalid: {name}")
    notarization_ids.add(submission_id)
PY

rm -rf "$STAGED_DIST" "$BACKUP_DIST"
/usr/bin/ditto "$EXTRACTED_ROOT/dist" "$STAGED_DIST"
if [[ -e "$TARGET_DIST" ]]; then
  mv "$TARGET_DIST" "$BACKUP_DIST"
fi
mv "$STAGED_DIST" "$TARGET_DIST"
RESTORE_COMMITTED=1
rm -rf "$BACKUP_DIST"

echo "Restored verified signed release candidate to $TARGET_DIST"
