#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCKFILE="$ROOT/skills-lock.json"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vibecompose-dev-skills.XXXXXX")"

trap 'rm -rf "$TEMP_ROOT"' EXIT

python3 - "$ROOT" "$LOCKFILE" "$TEMP_ROOT" <<'PY'
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


root = Path(sys.argv[1])
lockfile = Path(sys.argv[2])
temp_root = Path(sys.argv[3])
manifest = json.loads(lockfile.read_text(encoding="utf-8"))
entries = manifest.get("skills", {})
repository_locks = manifest.get("repositories", {})
if not entries:
    raise SystemExit("skills-lock.json does not contain any skills")

staging = temp_root / "skills"
staging.mkdir()
repositories = {}

for name, entry in sorted(entries.items()):
    source = entry["source"]
    skill_path = Path(entry["skillPath"])
    expected_hash = entry["computedHash"]
    checkout = repositories.get(source)
    if checkout is None:
        checkout = temp_root / source.replace("/", "__")
        revision = repository_locks.get(source, {}).get("revision")
        if not revision:
            raise SystemExit(f"Missing pinned revision for {source}")
        print(f"Cloning {source} at {revision}...")
        subprocess.run(
            ["git", "clone", "--filter=blob:none", f"https://github.com/{source}.git", str(checkout)],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(checkout), "checkout", "--detach", revision],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        repositories[source] = checkout

    source_file = checkout / skill_path
    if not source_file.is_file():
        raise SystemExit(f"Missing skill file for {name}: {entry['skillPath']}")
    actual_hash = hashlib.sha256(source_file.read_bytes()).hexdigest()
    if actual_hash != expected_hash:
        raise SystemExit(
            f"Hash mismatch for {name}: expected {expected_hash}, got {actual_hash}"
        )

    source_directory = source_file.parent
    target_directory = staging / name
    shutil.copytree(source_directory, target_directory, symlinks=True)

destination = root / ".agents" / "skills"
destination.parent.mkdir(parents=True, exist_ok=True)
if destination.exists() or destination.is_symlink():
    if destination.is_symlink() or not destination.is_dir():
        raise SystemExit(f"Refusing to replace non-directory: {destination}")
    shutil.rmtree(destination)
shutil.move(str(staging), str(destination))

claude_skills = root / ".claude" / "skills"
claude_skills.mkdir(parents=True, exist_ok=True)
for name in sorted(entries):
    link = claude_skills / name
    if link.is_symlink() or link.is_file():
        link.unlink()
    elif link.exists():
        raise SystemExit(f"Refusing to replace non-symlink: {link}")
    target = Path(os.path.relpath(destination / name, claude_skills))
    link.symlink_to(target)

print(f"Restored {len(entries)} skills under {destination}")
print(f"Created {len(entries)} symlinks under {claude_skills}")
PY
