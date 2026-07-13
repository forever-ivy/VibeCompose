#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
import urllib.parse
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXCLUDED_DIRECTORIES = {".git", ".build", "dist"}
TEXT_SUFFIXES = {
    ".entitlements",
    ".html",
    ".json",
    ".md",
    ".mjs",
    ".plist",
    ".py",
    ".sh",
    ".strings",
    ".swift",
    ".toml",
    ".xml",
    ".yml",
    ".yaml",
}
TEXT_FILENAMES = {
    ".editorconfig",
    ".gitignore",
    "LICENSE",
    "Package.resolved",
    "product.env",
    "version.env",
}

LEGACY_MARKERS = (
    "Chat" + "Type",
    "chat" + "-type",
    "chat" + "type",
    "me.longbiaochen." + "chat" + "type",
    "Voice" + "Dex",
    "voice" + "dex",
)

LOCALIZATION_CALL_PATTERN = re.compile(
    r'L10n\.(?:text|format)\(\s*"((?:\\.|[^"\\])*)"',
    re.DOTALL,
)
STRINGS_KEY_PATTERN = re.compile(
    r'^"((?:\\.|[^"\\])*)"\s*=',
    re.MULTILINE,
)
MARKDOWN_LINK_PATTERN = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
SECRET_PATTERNS = (
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
    re.compile(r"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\b"),
    re.compile(
        "-----BEGIN "
        + r"(?:RSA |EC |OPENSSH )?"
        + "PRIVATE KEY-----"
    ),
)
PRIVATE_KEY_FILENAME_PATTERN = re.compile(
    r"(?:^|[-_.])(?:license|signing)[-_.]?private(?:[-_.]|$)",
    re.IGNORECASE,
)


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def is_excluded(path: Path) -> bool:
    return any(part in EXCLUDED_DIRECTORIES for part in path.relative_to(ROOT).parts)


def text_files() -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and not is_excluded(path)
        and (path.suffix in TEXT_SUFFIXES or path.name in TEXT_FILENAMES)
    )


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def unescape_source_string(value: str) -> str:
    return (
        value.replace(r"\"", '"')
        .replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace(r"\\", "\\")
    )


def verify_canonical_identity(paths: list[Path]) -> list[str]:
    failures: list[str] = []
    for path in paths:
        contents = read_text(path)
        for marker in LEGACY_MARKERS:
            if marker.casefold() in contents.casefold():
                failures.append(
                    f"{relative(path)} contains legacy product marker {marker!r}"
                )
    return failures


def verify_no_committed_secrets(paths: list[Path]) -> list[str]:
    failures: list[str] = []
    for path in paths:
        contents = read_text(path)
        for pattern in SECRET_PATTERNS:
            match = pattern.search(contents)
            if match is None:
                continue
            line = contents.count("\n", 0, match.start()) + 1
            failures.append(
                f"{relative(path)}:{line} matches secret pattern "
                f"{pattern.pattern!r}"
            )
    return failures


def verify_no_private_key_artifacts() -> list[str]:
    failures: list[str] = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or is_excluded(path):
            continue
        if PRIVATE_KEY_FILENAME_PATTERN.search(path.name):
            failures.append(
                f"{relative(path)} looks like a private signing-key artifact"
            )
    return failures


def verify_localization() -> list[str]:
    failures: list[str] = []
    source_root = ROOT / "Sources" / "OpenWhisper"
    strings_path = (
        source_root
        / "Resources"
        / "zh-Hans.lproj"
        / "Localizable.strings"
    )

    localized_keys_raw = STRINGS_KEY_PATTERN.findall(read_text(strings_path))
    localized_key_counts = Counter(
        unescape_source_string(key) for key in localized_keys_raw
    )
    duplicate_keys = sorted(
        key for key, count in localized_key_counts.items() if count > 1
    )
    failures.extend(
        f"{relative(strings_path)} defines duplicate key {key!r}"
        for key in duplicate_keys
    )

    required_keys: set[str] = set()
    for path in source_root.rglob("*.swift"):
        for match in LOCALIZATION_CALL_PATTERN.finditer(read_text(path)):
            required_keys.add(unescape_source_string(match.group(1)))

    missing_keys = sorted(required_keys - set(localized_key_counts))
    failures.extend(
        f"{relative(strings_path)} is missing literal L10n key {key!r}"
        for key in missing_keys
    )
    return failures


def markdown_target(raw_target: str) -> str | None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1].strip()
    if not target or target.startswith(("#", "http://", "https://", "mailto:")):
        return None

    if " " in target:
        target = target.split(" ", 1)[0]
    target = urllib.parse.unquote(target.split("#", 1)[0])
    return target or None


def verify_markdown_links() -> list[str]:
    failures: list[str] = []
    for path in sorted(ROOT.rglob("*.md")):
        if is_excluded(path):
            continue
        contents = read_text(path)
        for match in MARKDOWN_LINK_PATTERN.finditer(contents):
            target = markdown_target(match.group(1))
            if target is None:
                continue
            resolved = (path.parent / target).resolve()
            if resolved.exists():
                continue
            line = contents.count("\n", 0, match.start()) + 1
            failures.append(
                f"{relative(path)}:{line} links to missing local target {target!r}"
            )
    return failures


def main() -> int:
    paths = text_files()
    failures = [
        *verify_canonical_identity(paths),
        *verify_no_committed_secrets(paths),
        *verify_no_private_key_artifacts(),
        *verify_localization(),
        *verify_markdown_links(),
    ]

    if failures:
        print("Repository hygiene verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(
        "Repository hygiene verification passed "
        "(canonical identity, secret/private-key patterns, localization "
        "literals, local Markdown links)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
