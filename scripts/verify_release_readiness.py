#!/usr/bin/env python3
"""Fail-closed candidate and public-release readiness checks.

This audit deliberately separates build integrity from product evidence. The
candidate phase validates release configuration without exposing secrets. The
public phase requires fresh brand, installed-app, and privacy-bounded Beta
evidence tied to the exact source and update archive.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import tempfile
import urllib.parse
from dataclasses import asdict, dataclass
from typing import Any


MAX_JSON_BYTES = 1024 * 1024
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
COMMIT_PATTERN = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
TEAM_ID_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
ZERO_SHA256 = "0" * 64
PLACEHOLDER_MARKERS = (
    "REPLACE",
    "TODO",
    "TBD",
    "CHANGEME",
    "YOUR_",
    "SET_",
)

REQUIRED_INSTALLED_CHECKS = (
    "installedApplicationsPath",
    "developerIDSignature",
    "notarizedAndStapled",
    "cleanTCCOnboarding",
    "defaultF5StartStop",
    "customHotkeyStartStop",
    "escapeCancel",
    "inlineCloseCancel",
    "retryReentry",
    "textEditVerifiedInsert",
    "notesDelivery",
    "thirdPartyEditorDelivery",
    "selectionStableReplace",
    "selectionChangedCopyOnly",
    "settingsKeyboard",
    "onboardingKeyboard",
    "historyKeyboard",
    "terminologyKeyboard",
    "voiceOver",
    "reduceMotion",
    "increaseContrast",
    "multiDisplay",
    "fullScreen",
    "spaces",
    "stageManager",
    "updateFromPrevious",
    "interruptedUpdate",
    "invalidUpdateSignature",
    "downgradeRejected",
    "rollbackAfterFailedRelaunch",
    "uninstall",
)

REQUIRED_INSTALLED_EVIDENCE = {
    "installed-interaction",
    "accessibility",
    "compatibility",
    "update-rollback",
}

PILOT_GATE_TARGETS = {
    "participant_count": "30–50 consented participants",
    "week1_valid_participants": "at least 20 with a valid W1 non-Direct application",
    "non_direct_runs": "at least 300",
    "qualified_external_authors": "at least 5",
    "final_application_rate": "at least 0.70",
    "wrong_skill_rate": "at most 0.03",
    "curated_validator_fallback_rate": "at most 0.05",
    "selection_identity_success_rate": "at least 0.97",
    "preview_cancel_rate": "at most 0.20",
    "switcher_upper_median": "1_to_3s or faster",
    "first_use_upper_median": "3_to_5m or faster",
    "first_use_coverage": "exactly one first-use outcome per consented participant",
    "creator_upper_median": "5_to_15m or faster",
    "week1_effective_retention": "at least 0.40",
    "week4_effective_retention": "at least 0.20",
    "critical_incidents": "exactly 0",
}
REQUIRED_PILOT_GATES = set(PILOT_GATE_TARGETS)

PILOT_MANUAL_REVIEW_REQUIRED = [
    "core scenario sample sufficiency",
    "W4 use is not dominated by one built-in Skill",
    "uninstall and disable reasons",
    "interview interpretation of edits, cancellations, and trust",
    "moderation, maintenance, and Registry ownership",
]

REQUIRED_BETA_REVIEW = (
    "coreScenarioSampleSufficiency",
    "w4SkillConcentrationReviewed",
    "uninstallAndDisableReasonsReviewed",
    "interviewInterpretationReviewed",
    "noUnresolvedCriticalIncidents",
)

REQUIRED_CANDIDATE_REPORT_GATES = {
    "source.identity",
    "configuration.required-values",
    "configuration.team-id",
    "configuration.public-urls",
    "configuration.public-keys",
    "configuration.provider-policy-window",
    "configuration.private-keys",
    "configuration.notary-keychain",
    "configuration.build-configuration",
    "source.commit",
    "source.clean-worktree",
    "source.canonical-remote",
}


@dataclass
class Gate:
    identifier: str
    passed: bool
    detail: str


class Audit:
    def __init__(self) -> None:
        self.gates: list[Gate] = []
        self.evidence_digests: dict[str, str] = {}

    def add(self, identifier: str, passed: bool, detail: str) -> None:
        self.gates.append(Gate(identifier, passed, detail))

    @property
    def passed(self) -> bool:
        return bool(self.gates) and all(gate.passed for gate in self.gates)


def load_simple_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([A-Z][A-Z0-9_]*)=([A-Za-z0-9._/@:+-]+)", line)
        if match is None:
            raise ValueError(f"unsafe environment entry at {path}:{number}")
        name, value = match.groups()
        if name in values:
            raise ValueError(f"duplicate environment key {name} in {path}")
        values[name] = value
    return values


def load_json(path: pathlib.Path, maximum_bytes: int = MAX_JSON_BYTES) -> dict[str, Any]:
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"{path} must be a regular non-symlink file")
    if metadata.st_size <= 0 or metadata.st_size > maximum_bytes:
        raise ValueError(f"{path} must contain 1–{maximum_bytes} bytes")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_date(value: Any) -> dt.datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(dt.timezone.utc)


def is_recent(value: Any, now: dt.datetime, maximum_age_days: int) -> bool:
    parsed = parse_date(value)
    if parsed is None:
        return False
    age = now - parsed
    return dt.timedelta(0) <= age <= dt.timedelta(days=maximum_age_days)


def real_string(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    normalized = value.strip()
    uppercased = normalized.upper()
    return (
        not any(marker in uppercased for marker in PLACEHOLDER_MARKERS)
        and "example.invalid" not in normalized.lower()
    )


def bounded_real_string(value: Any, maximum_characters: int = 512) -> bool:
    return (
        real_string(value)
        and len(value) <= maximum_characters
        and "\n" not in value
        and "\r" not in value
        and "\0" not in value
    )


def canonical_public_https(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    if any(character.isspace() for character in value) or any(
        character in value for character in ('<', '>', '"', "'", "\\")
    ):
        return False
    parsed = urllib.parse.urlsplit(value)
    hostname = (parsed.hostname or "").lower()
    return (
        parsed.scheme == "https"
        and bool(hostname)
        and hostname not in {"localhost", "127.0.0.1", "::1"}
        and not hostname.endswith((".invalid", ".example", ".localhost", ".local"))
        and parsed.username is None
        and parsed.password is None
        and not parsed.query
        and not parsed.fragment
        and urllib.parse.urlunsplit(parsed) == value
    )


def valid_public_key(value: str) -> bool:
    try:
        return len(base64.b64decode(value, validate=True)) == 32
    except (ValueError, binascii.Error):
        return False


def run(root: pathlib.Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments,
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )


def audit_identity(
    root: pathlib.Path,
    audit: Audit,
) -> tuple[dict[str, str], dict[str, str]]:
    try:
        product = load_simple_env(root / "product.env")
        version = load_simple_env(root / "version.env")
    except (OSError, ValueError) as error:
        audit.add("source.identity", False, str(error))
        return {}, {}

    required_product = (
        "VIBEWHISPER_APP_NAME",
        "VIBEWHISPER_BUNDLE_ID",
        "VIBEWHISPER_REPOSITORY",
    )
    required_version = ("VIBEWHISPER_VERSION", "VIBEWHISPER_BUILD")
    missing = [
        name
        for name in required_product
        if not real_string(product.get(name))
    ] + [
        name
        for name in required_version
        if not real_string(version.get(name))
    ]
    audit.add(
        "source.identity",
        not missing,
        "strict product and version identity parsed"
        if not missing
        else f"missing identity keys: {', '.join(missing)}",
    )
    return product, version


def audit_environment(root: pathlib.Path, audit: Audit, phase: str) -> None:
    public_names = (
        "VIBEWHISPER_TEAM_ID",
        "VIBEWHISPER_RELEASE_BASE_URL",
        "VIBEWHISPER_SPARKLE_FEED_URL",
        "VIBEWHISPER_SPARKLE_PUBLIC_ED_KEY",
        "VIBEWHISPER_CAPABILITY_POLICY_URL",
        "VIBEWHISPER_CAPABILITY_PUBLIC_ED_KEY",
    )
    candidate_names = (
        "VIBEWHISPER_CODESIGN_IDENTITY",
        "VIBEWHISPER_NOTARY_PROFILE",
        "VIBEWHISPER_SPARKLE_PRIVATE_KEY_FILE",
        "VIBEWHISPER_CAPABILITY_PRIVATE_KEY_FILE",
        "VIBEWHISPER_CAPABILITY_POLICY_REVISION",
        "VIBEWHISPER_CAPABILITY_POLICY_EXPIRES_AT",
        "VIBEWHISPER_BUILD_CONFIGURATION",
    )
    required_names = public_names + (candidate_names if phase == "candidate" else ())
    missing = [name for name in required_names if not os.environ.get(name, "").strip()]
    audit.add(
        "configuration.required-values",
        not missing,
        "required release values are present"
        if not missing
        else f"missing values: {', '.join(missing)}",
    )

    team_id = os.environ.get("VIBEWHISPER_TEAM_ID", "").strip()
    audit.add(
        "configuration.team-id",
        TEAM_ID_PATTERN.fullmatch(team_id) is not None,
        "Apple Team ID has the required 10-character form",
    )

    url_names = (
        "VIBEWHISPER_RELEASE_BASE_URL",
        "VIBEWHISPER_SPARKLE_FEED_URL",
        "VIBEWHISPER_CAPABILITY_POLICY_URL",
    )
    invalid_urls = [
        name
        for name in url_names
        if not canonical_public_https(os.environ.get(name, ""))
    ]
    audit.add(
        "configuration.public-urls",
        not invalid_urls,
        "artifact, appcast, and provider-policy URLs are canonical public HTTPS"
        if not invalid_urls
        else f"invalid URLs: {', '.join(invalid_urls)}",
    )

    key_names = (
        "VIBEWHISPER_SPARKLE_PUBLIC_ED_KEY",
        "VIBEWHISPER_CAPABILITY_PUBLIC_ED_KEY",
    )
    public_keys = [os.environ.get(name, "").strip() for name in key_names]
    public_keys_valid = all(valid_public_key(value) for value in public_keys)
    audit.add(
        "configuration.public-keys",
        public_keys_valid and len(set(public_keys)) == len(public_keys),
        "Sparkle and provider-policy Ed25519 public keys are valid and distinct",
    )

    if phase != "candidate":
        return

    build_configuration = os.environ.get(
        "VIBEWHISPER_BUILD_CONFIGURATION",
        "",
    ).strip()
    audit.add(
        "configuration.build-configuration",
        build_configuration == "release",
        "Developer ID candidate uses the optimized release build configuration",
    )

    revision = os.environ.get("VIBEWHISPER_CAPABILITY_POLICY_REVISION", "")
    expires_at = parse_date(
        os.environ.get("VIBEWHISPER_CAPABILITY_POLICY_EXPIRES_AT", "")
    )
    now = dt.datetime.now(dt.timezone.utc)
    policy_window_valid = (
        revision.isdigit()
        and int(revision) > 0
        and expires_at is not None
        and now < expires_at <= now + dt.timedelta(days=31)
    )
    audit.add(
        "configuration.provider-policy-window",
        policy_window_valid,
        "provider-policy revision is positive and expiry is within 31 days",
    )

    private_key_names = (
        "VIBEWHISPER_SPARKLE_PRIVATE_KEY_FILE",
        "VIBEWHISPER_CAPABILITY_PRIVATE_KEY_FILE",
    )
    private_paths: list[pathlib.Path] = []
    private_errors: list[str] = []
    for name in private_key_names:
        raw_path = os.environ.get(name, "").strip()
        if not raw_path:
            private_errors.append(f"{name}=missing")
            continue
        path = pathlib.Path(raw_path)
        try:
            metadata = path.lstat()
            resolved = path.resolve(strict=True)
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                private_errors.append(f"{name}=unsafe-type")
            elif metadata.st_size <= 0:
                private_errors.append(f"{name}=empty")
            elif stat.S_IMODE(metadata.st_mode) & 0o077:
                private_errors.append(f"{name}=permissions")
            elif resolved == root or root in resolved.parents:
                private_errors.append(f"{name}=inside-repository")
            else:
                private_paths.append(resolved)
        except OSError:
            private_errors.append(f"{name}=unreadable")
    if len(set(private_paths)) != len(private_paths):
        private_errors.append("private-key-files=not-distinct")
    audit.add(
        "configuration.private-keys",
        not private_errors,
        "private keys are distinct owner-only regular files outside the repository"
        if not private_errors
        else ", ".join(private_errors),
    )

    notary_keychain = os.environ.get("VIBEWHISPER_NOTARY_KEYCHAIN", "").strip()
    if not notary_keychain:
        audit.add(
            "configuration.notary-keychain",
            True,
            "default keychain lookup selected",
        )
        return
    keychain_path = pathlib.Path(notary_keychain)
    try:
        metadata = keychain_path.lstat()
        valid_keychain = stat.S_ISREG(metadata.st_mode) and not stat.S_ISLNK(
            metadata.st_mode
        )
    except OSError:
        valid_keychain = False
    audit.add(
        "configuration.notary-keychain",
        valid_keychain,
        "dedicated notary keychain is a regular non-symlink file",
    )


def audit_git(
    root: pathlib.Path,
    audit: Audit,
    repository: str,
    version: str,
    require_tag: bool,
) -> str:
    head = run(root, "git", "rev-parse", "HEAD")
    source_commit = head.stdout.strip() if head.returncode == 0 else ""
    audit.add(
        "source.commit",
        COMMIT_PATTERN.fullmatch(source_commit) is not None,
        "release source is a full Git commit",
    )

    status = run(root, "git", "status", "--porcelain", "--untracked-files=all")
    audit.add(
        "source.clean-worktree",
        status.returncode == 0 and not status.stdout.strip(),
        "Git worktree is clean"
        if status.returncode == 0 and not status.stdout.strip()
        else "Git worktree contains uncommitted files",
    )

    remote = run(root, "git", "remote", "get-url", "origin")
    remote_value = remote.stdout.strip()
    expected_remotes = {
        f"https://github.com/{repository}",
        f"https://github.com/{repository}.git",
        f"git@github.com:{repository}.git",
        f"ssh://git@github.com/{repository}.git",
    }
    audit.add(
        "source.canonical-remote",
        remote.returncode == 0 and remote_value in expected_remotes,
        "origin matches the product repository",
    )

    if require_tag:
        tag = run(root, "git", "rev-parse", f"refs/tags/v{version}^{{commit}}")
        audit.add(
            "source.release-tag",
            tag.returncode == 0 and tag.stdout.strip() == source_commit,
            f"v{version} points at the exact release commit",
        )
    return source_commit


def record_evidence_digest(audit: Audit, identifier: str, path: pathlib.Path) -> None:
    audit.evidence_digests[identifier] = sha256_file(path)


def audit_candidate_readiness_report(
    root: pathlib.Path,
    audit: Audit,
    version: str,
    build: str,
    source_commit: str,
    now: dt.datetime,
) -> None:
    path = root / "dist" / "release-candidate-readiness.json"
    try:
        report = load_json(path)
        record_evidence_digest(audit, "candidateReadiness", path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        audit.add("evidence.candidate-readiness", False, str(error))
        return
    gates = report.get("gates")
    gate_ids: set[str] = set()
    gates_valid = isinstance(gates, list) and bool(gates)
    if gates_valid:
        for gate in gates:
            if (
                not isinstance(gate, dict)
                or set(gate) != {"identifier", "passed", "detail"}
                or not bounded_real_string(gate.get("identifier"), 128)
                or not bounded_real_string(gate.get("detail"))
                or gate.get("passed") is not True
                or gate["identifier"] in gate_ids
            ):
                gates_valid = False
                break
            gate_ids.add(gate["identifier"])
        gates_valid = gates_valid and REQUIRED_CANDIDATE_REPORT_GATES.issubset(
            gate_ids
        )
    passed = (
        set(report)
        == {
            "schemaVersion",
            "generatedAt",
            "phase",
            "passed",
            "sourceCommit",
            "release",
            "evidenceDigests",
            "gates",
        }
        and report.get("schemaVersion") == 1
        and report.get("phase") == "candidate"
        and report.get("passed") is True
        and report.get("sourceCommit") == source_commit
        and report.get("release") == {"version": version, "build": build}
        and report.get("evidenceDigests") == {}
        and is_recent(report.get("generatedAt"), now, 45)
        and gates_valid
    )
    audit.add(
        "evidence.candidate-readiness",
        passed,
        "candidate configuration report is complete and matches this source"
        if passed
        else "candidate readiness report is missing, incomplete, stale, or mismatched",
    )


def audit_notarization_receipts(root: pathlib.Path, audit: Audit) -> None:
    submission_ids: set[str] = set()
    errors: list[str] = []
    for identifier, filename in (
        ("appNotarization", "notarization-app.json"),
        ("dmgNotarization", "notarization-dmg.json"),
    ):
        path = root / "dist" / filename
        try:
            receipt = load_json(path, maximum_bytes=64 * 1024)
            record_evidence_digest(audit, identifier, path)
        except (OSError, ValueError, json.JSONDecodeError):
            errors.append(f"{filename}=missing-or-invalid")
            continue
        submission_id = receipt.get("id")
        if (
            receipt.get("status") != "Accepted"
            or not isinstance(submission_id, str)
            or re.fullmatch(
                r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                submission_id,
            )
            is None
            or submission_id in submission_ids
        ):
            errors.append(f"{filename}=not-accepted-or-invalid-id")
            continue
        submission_ids.add(submission_id)
    audit.add(
        "evidence.notarization-receipts",
        not errors and len(submission_ids) == 2,
        "App and DMG have distinct Accepted Apple notarization receipts"
        if not errors and len(submission_ids) == 2
        else ", ".join(errors) or "notarization submission IDs are not distinct",
    )


def audit_brand(
    audit: Audit,
    path: pathlib.Path,
    product_name: str,
    now: dt.datetime,
) -> None:
    try:
        value = load_json(path)
        record_evidence_digest(audit, "brandClearance", path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        audit.add("evidence.brand-clearance", False, str(error))
        return
    checks = value.get("checks")
    required_checks = {"trademark", "domains", "appStore", "github", "social"}
    checks_pass = (
        isinstance(checks, dict)
        and set(checks) == required_checks
        and all(checks.get(name) is True for name in required_checks)
    )
    conflicts = value.get("conflicts")
    passed = (
        set(value)
        == {
            "schemaVersion",
            "status",
            "productName",
            "reviewedAt",
            "reviewer",
            "checks",
            "conflicts",
            "decision",
        }
        and
        value.get("schemaVersion") == 1
        and value.get("status") == "approved"
        and value.get("productName") == product_name
        and bounded_real_string(value.get("reviewer"), 128)
        and bounded_real_string(value.get("decision"))
        and is_recent(value.get("reviewedAt"), now, 180)
        and checks_pass
        and conflicts == []
    )
    audit.add(
        "evidence.brand-clearance",
        passed,
        "brand clearance is approved, complete, conflict-free, and fresh"
        if passed
        else f"brand status={value.get('status')}; public naming remains blocked",
    )


def audit_public_contacts(
    root: pathlib.Path,
    audit: Audit,
    path: pathlib.Path,
    now: dt.datetime,
) -> None:
    try:
        value = load_json(path)
        record_evidence_digest(audit, "publicContacts", path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        audit.add("evidence.public-contacts", False, str(error))
        audit.add(
            "source.public-contact-policy",
            False,
            "approved public contact evidence is unavailable",
        )
        return

    expected_fields = {
        "schemaVersion",
        "status",
        "reviewedAt",
        "reviewer",
        "supportURL",
        "securityURL",
        "privacyContactURL",
        "legalContactURL",
        "supportOwner",
        "securityOwner",
        "privacyOwner",
        "decision",
    }
    url_fields = (
        "supportURL",
        "securityURL",
        "privacyContactURL",
        "legalContactURL",
    )
    owner_fields = ("supportOwner", "securityOwner", "privacyOwner")
    urls_valid = all(canonical_public_https(value.get(name)) for name in url_fields)
    owners_valid = all(
        bounded_real_string(value.get(name), 128) for name in owner_fields
    )
    evidence_passed = (
        set(value) == expected_fields
        and value.get("schemaVersion") == 1
        and value.get("status") == "approved"
        and is_recent(value.get("reviewedAt"), now, 180)
        and bounded_real_string(value.get("reviewer"), 128)
        and urls_valid
        and value.get("securityURL") != value.get("supportURL")
        and owners_valid
        and value.get("decision") == "approved-for-public-release"
    )
    audit.add(
        "evidence.public-contacts",
        evidence_passed,
        "public support, security, privacy, and legal contacts are approved"
        if evidence_passed
        else "public contact evidence is missing, stale, placeholder, or unapproved",
    )

    policy_bindings = {
        "supportURL": (
            root / "docs/support/support-policy.md",
            root / "docs/support/support-policy.zh-CN.md",
        ),
        "securityURL": (root / "SECURITY.md",),
        "privacyContactURL": (
            root / "docs/legal/privacy-policy.md",
            root / "docs/legal/privacy-policy.zh-CN.md",
        ),
        "legalContactURL": (
            root / "docs/legal/terms-of-use.md",
            root / "docs/legal/terms-of-use.zh-CN.md",
        ),
    }
    policy_errors: list[str] = []
    private_alpha_markers = ("private alpha", "private-alpha", "私有 alpha", "私有alpha")
    for field, document_paths in policy_bindings.items():
        expected_url = value.get(field)
        for document_path in document_paths:
            try:
                metadata = document_path.lstat()
                if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                    raise ValueError("unsafe type")
                if metadata.st_size <= 0 or metadata.st_size > 512 * 1024:
                    raise ValueError("unsafe size")
                document = document_path.read_text(encoding="utf-8")
            except (OSError, UnicodeError, ValueError):
                policy_errors.append(f"{document_path.name}=missing-or-unsafe")
                continue
            lowered = document.lower()
            if not isinstance(expected_url, str) or expected_url not in document:
                policy_errors.append(f"{document_path.name}=contact-mismatch")
            if any(marker in lowered for marker in private_alpha_markers):
                policy_errors.append(f"{document_path.name}=private-alpha-copy")
    audit.add(
        "source.public-contact-policy",
        evidence_passed and not policy_errors,
        "bilingual public policies expose the approved contact surfaces"
        if evidence_passed and not policy_errors
        else ", ".join(policy_errors)
        or "public contact evidence has not been approved",
    )


def audit_installed_acceptance(
    audit: Audit,
    path: pathlib.Path,
    version: str,
    build: str,
    source_commit: str,
    zip_sha256: str,
    now: dt.datetime,
) -> None:
    try:
        value = load_json(path)
        record_evidence_digest(audit, "installedAcceptance", path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        audit.add("evidence.installed-acceptance", False, str(error))
        return

    release = value.get("release")
    release_matches = isinstance(release, dict) and release == {
        "version": version,
        "build": build,
        "sourceCommit": source_commit,
        "artifactSha256": zip_sha256,
    }
    checks = value.get("checks")
    checks_have_exact_schema = (
        isinstance(checks, dict)
        and set(checks) == set(REQUIRED_INSTALLED_CHECKS)
    )
    failed_checks = [
        name
        for name in REQUIRED_INSTALLED_CHECKS
        if not isinstance(checks, dict) or checks.get(name) is not True
    ]

    evidence = value.get("evidence")
    evidence_ids: set[str] = set()
    evidence_valid = isinstance(evidence, list) and len(evidence) >= 4
    if evidence_valid:
        for item in evidence:
            if not isinstance(item, dict):
                evidence_valid = False
                break
            evidence_id = item.get("id")
            item_sha256 = item.get("sha256")
            item_valid = (
                set(item) == {"id", "observer", "observedAt", "sha256"}
                and bounded_real_string(evidence_id, 128)
                and bounded_real_string(item.get("observer"), 128)
                and is_recent(item.get("observedAt"), now, 90)
                and isinstance(item_sha256, str)
                and SHA256_PATTERN.fullmatch(item_sha256) is not None
                and item_sha256 != ZERO_SHA256
                and evidence_id not in evidence_ids
            )
            if not item_valid:
                evidence_valid = False
                break
            evidence_ids.add(evidence_id)
        evidence_valid = evidence_valid and REQUIRED_INSTALLED_EVIDENCE.issubset(
            evidence_ids
        )

    passed = (
        set(value)
        == {"schemaVersion", "status", "installedApp", "release", "checks", "evidence"}
        and value.get("schemaVersion") == 2
        and value.get("status") == "approved"
        and value.get("installedApp") == "/Applications/VibeWhisper.app"
        and release_matches
        and checks_have_exact_schema
        and not failed_checks
        and evidence_valid
    )
    audit.add(
        "evidence.installed-acceptance",
        passed,
        "installed-app checks and evidence match the exact candidate"
        if passed
        else "installed acceptance is missing, stale, incomplete, or for another candidate",
    )


def pilot_summary_schema_is_exact(summary: dict[str, Any]) -> bool:
    if set(summary) != {
        "schemaVersion",
        "generatedAt",
        "status",
        "automatedPilotExitGatesPassed",
        "inputCounts",
        "pilotExitGates",
        "observationMetrics",
        "registrySignals",
        "manualReviewRequired",
        "privacy",
    }:
        return False

    input_counts = summary.get("inputCounts")
    if (
        not isinstance(input_counts, dict)
        or set(input_counts)
        != {
            "participantRows",
            "consentedParticipants",
            "observationRows",
            "incidentRows",
        }
        or any(type(value) is not int or value < 0 for value in input_counts.values())
    ):
        return False

    pilot_gates = summary.get("pilotExitGates")
    if not isinstance(pilot_gates, dict) or set(pilot_gates) != REQUIRED_PILOT_GATES:
        return False
    for name, target in PILOT_GATE_TARGETS.items():
        gate = pilot_gates.get(name)
        if (
            not isinstance(gate, dict)
            or set(gate) != {"value", "target", "passed"}
            or gate.get("target") != target
            or gate.get("passed") is not True
        ):
            return False

    observation_metrics = summary.get("observationMetrics")
    if not isinstance(observation_metrics, dict) or set(observation_metrics) != {
        "previewEditRate",
        "targetFailureRate",
        "taskCategoryCounts",
        "resultActionCounts",
        "failureClassCounts",
    }:
        return False
    for rate_name in ("previewEditRate", "targetFailureRate"):
        rate = observation_metrics.get(rate_name)
        if rate is not None and (
            isinstance(rate, bool)
            or not isinstance(rate, (int, float))
            or not 0 <= rate <= 1
        ):
            return False
    count_schemas = {
        "taskCategoryCounts": {
            "dictation",
            "developer",
            "communication",
            "rewrite",
            "professional-template",
        },
        "resultActionCounts": {"replace", "paste", "copy", "cancel"},
        "failureClassCounts": {
            "none",
            "wrong-skill",
            "context",
            "validator",
            "target",
            "provider",
            "usability",
        },
    }
    for name, allowed_keys in count_schemas.items():
        counts = observation_metrics.get(name)
        if (
            not isinstance(counts, dict)
            or not set(counts).issubset(allowed_keys)
            or any(type(value) is not int or value < 0 for value in counts.values())
        ):
            return False
    non_direct_runs = pilot_gates["non_direct_runs"].get("value")
    if type(non_direct_runs) is not int or any(
        sum(observation_metrics[name].values()) != non_direct_runs
        for name in count_schemas
    ):
        return False

    registry_signals = summary.get("registrySignals")
    if not isinstance(registry_signals, dict) or set(registry_signals) != {
        "nonBuiltInAdoptionRate",
        "qualifiedExternalAuthors",
        "criticalIncidents",
        "decision",
    }:
        return False
    adoption = registry_signals.get("nonBuiltInAdoptionRate")
    if not isinstance(adoption, dict) or set(adoption) != {
        "value",
        "goThreshold",
        "thresholdMet",
    }:
        return False
    adoption_value = adoption.get("value")
    if adoption_value is not None and (
        isinstance(adoption_value, bool)
        or not isinstance(adoption_value, (int, float))
        or not 0 <= adoption_value <= 1
    ):
        return False
    if (
        adoption.get("goThreshold") != 0.25
        or type(adoption.get("thresholdMet")) is not bool
        or type(registry_signals.get("qualifiedExternalAuthors")) is not int
        or type(registry_signals.get("criticalIncidents")) is not int
        or registry_signals.get("decision") != "product_owner_review_required"
        or summary.get("manualReviewRequired") != PILOT_MANUAL_REVIEW_REQUIRED
    ):
        return False
    expected_adoption_threshold = (
        adoption_value is not None and adoption_value >= 0.25
    )
    if (
        adoption.get("thresholdMet") is not expected_adoption_threshold
        or registry_signals.get("qualifiedExternalAuthors")
        != pilot_gates["qualified_external_authors"].get("value")
        or registry_signals.get("criticalIncidents")
        != pilot_gates["critical_incidents"].get("value")
    ):
        return False
    return True


def pilot_gate_values_are_valid(
    pilot_gates: dict[str, Any],
    input_counts: Any,
) -> bool:
    def numeric(name: str) -> float | None:
        gate = pilot_gates.get(name)
        value = gate.get("value") if isinstance(gate, dict) else None
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        return float(value)

    def label(name: str) -> str | None:
        gate = pilot_gates.get(name)
        value = gate.get("value") if isinstance(gate, dict) else None
        return value if isinstance(value, str) else None

    participant_count = numeric("participant_count")
    week1_valid = numeric("week1_valid_participants")
    non_direct_runs = numeric("non_direct_runs")
    qualified_authors = numeric("qualified_external_authors")
    application_rate = numeric("final_application_rate")
    wrong_skill_rate = numeric("wrong_skill_rate")
    fallback_rate = numeric("curated_validator_fallback_rate")
    identity_rate = numeric("selection_identity_success_rate")
    preview_cancel_rate = numeric("preview_cancel_rate")
    first_use_coverage = numeric("first_use_coverage")
    week1_retention = numeric("week1_effective_retention")
    week4_retention = numeric("week4_effective_retention")
    critical_incidents = numeric("critical_incidents")
    consented_count = (
        input_counts.get("consentedParticipants")
        if isinstance(input_counts, dict)
        else None
    )
    participant_rows = (
        input_counts.get("participantRows")
        if isinstance(input_counts, dict)
        else None
    )
    observation_rows = (
        input_counts.get("observationRows")
        if isinstance(input_counts, dict)
        else None
    )
    incident_rows = (
        input_counts.get("incidentRows")
        if isinstance(input_counts, dict)
        else None
    )

    return all(
        (
            participant_count is not None and 30 <= participant_count <= 50,
            week1_valid is not None and week1_valid >= 20,
            non_direct_runs is not None and non_direct_runs >= 300,
            qualified_authors is not None and qualified_authors >= 5,
            application_rate is not None and application_rate >= 0.70,
            wrong_skill_rate is not None and 0 <= wrong_skill_rate <= 0.03,
            fallback_rate is not None and 0 <= fallback_rate <= 0.05,
            identity_rate is not None and 0.97 <= identity_rate <= 1,
            preview_cancel_rate is not None and 0 <= preview_cancel_rate <= 0.20,
            label("switcher_upper_median") in {"under_1s", "1_to_3s"},
            label("first_use_upper_median") in {"under_3m", "3_to_5m"},
            type(consented_count) is int,
            type(participant_rows) is int
            and participant_rows >= consented_count,
            week1_valid is not None and week1_valid <= consented_count,
            qualified_authors is not None
            and qualified_authors <= consented_count,
            type(observation_rows) is int
            and non_direct_runs is not None
            and observation_rows >= non_direct_runs,
            type(incident_rows) is int
            and critical_incidents is not None
            and incident_rows >= critical_incidents,
            first_use_coverage is not None
            and first_use_coverage == consented_count,
            label("creator_upper_median") in {"under_5m", "5_to_15m"},
            week1_retention is not None and 0.40 <= week1_retention <= 1,
            week4_retention is not None and 0.20 <= week4_retention <= 1,
            critical_incidents == 0,
        )
    )


def audit_community_pilot(
    audit: Audit,
    summary_path: pathlib.Path,
    review_path: pathlib.Path,
    version: str,
    now: dt.datetime,
) -> None:
    summary_error = ""
    try:
        summary = load_json(summary_path)
        summary_sha256 = sha256_file(summary_path)
        record_evidence_digest(audit, "communityPilotSummary", summary_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        summary_error = str(error)
        summary = {}
        summary_sha256 = ""

    pilot_gates = summary.get("pilotExitGates")
    gates_complete = (
        isinstance(pilot_gates, dict)
        and set(pilot_gates) == REQUIRED_PILOT_GATES
        and all(
            isinstance(pilot_gates[name], dict)
            and pilot_gates[name].get("passed") is True
            for name in REQUIRED_PILOT_GATES
        )
        and pilot_gate_values_are_valid(
            pilot_gates,
            summary.get("inputCounts"),
        )
    )
    privacy = summary.get("privacy")
    privacy_bounded = isinstance(privacy, dict) and privacy == {
        "rowLevelEvidenceIncluded": False,
        "cohortCodesIncluded": False,
        "contentFieldsAccepted": False,
        "inputSchemasAreEnumAndBucketOnly": True,
    }
    summary_passed = (
        pilot_summary_schema_is_exact(summary)
        and summary.get("schemaVersion") == 1
        and summary.get("status")
        == "automated_gates_passed_manual_review_required"
        and summary.get("automatedPilotExitGatesPassed") is True
        and is_recent(summary.get("generatedAt"), now, 180)
        and gates_complete
        and privacy_bounded
    )
    audit.add(
        "evidence.community-pilot-summary",
        summary_passed,
        "privacy-bounded Community Pilot automated exit gates passed"
        if summary_passed
        else summary_error
        or "Community Pilot is missing, stale, incomplete, or below an exit gate",
    )

    try:
        review = load_json(review_path)
        record_evidence_digest(audit, "betaReview", review_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        audit.add("evidence.beta-review", False, str(error))
        return
    manual_review = review.get("manualReview")
    review_complete = (
        isinstance(manual_review, dict)
        and set(manual_review) == set(REQUIRED_BETA_REVIEW)
        and all(manual_review.get(name) is True for name in REQUIRED_BETA_REVIEW)
    )
    blockers_clear = (
        type(review.get("openP0Blockers")) is int
        and review.get("openP0Blockers") == 0
        and type(review.get("openP1Blockers")) is int
        and review.get("openP1Blockers") == 0
    )
    review_passed = (
        set(review)
        == {
            "schemaVersion",
            "status",
            "reviewedAt",
            "reviewer",
            "productVersion",
            "communityPilotSummarySha256",
            "fourCompleteWeeks",
            "manualReview",
            "openP0Blockers",
            "openP1Blockers",
            "decision",
            "evidenceReference",
        }
        and review.get("schemaVersion") == 2
        and review.get("status") == "approved"
        and review.get("productVersion") == version
        and review.get("communityPilotSummarySha256") == summary_sha256
        and summary_sha256 != ZERO_SHA256
        and review.get("fourCompleteWeeks") is True
        and review_complete
        and blockers_clear
        and review.get("decision") == "approved-for-public-release-review"
        and bounded_real_string(review.get("reviewer"), 128)
        and bounded_real_string(review.get("evidenceReference"))
        and is_recent(review.get("reviewedAt"), now, 180)
    )
    audit.add(
        "evidence.beta-review",
        review_passed,
        "product owner approved the exact four-week Pilot aggregate for release review"
        if review_passed
        else "Beta manual review is missing, stale, blocked, or does not match the aggregate",
    )


def read_manifest_zip_sha256(
    root: pathlib.Path,
    audit: Audit,
    version: str,
    build: str,
) -> str:
    path = root / "dist" / "release-manifest.json"
    try:
        manifest = load_json(path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        audit.add("artifacts.release-manifest", False, str(error))
        return ""
    release = manifest.get("release")
    artifacts = manifest.get("artifacts")
    zip_artifacts = (
        [item for item in artifacts if isinstance(item, dict) and item.get("kind") == "zip"]
        if isinstance(artifacts, list)
        else []
    )
    zip_sha256 = zip_artifacts[0].get("sha256", "") if len(zip_artifacts) == 1 else ""
    passed = (
        isinstance(release, dict)
        and release.get("version") == version
        and release.get("build") == build
        and isinstance(zip_sha256, str)
        and SHA256_PATTERN.fullmatch(zip_sha256) is not None
        and zip_sha256 != ZERO_SHA256
    )
    audit.add(
        "artifacts.release-manifest",
        passed,
        "release manifest identifies one nonzero ZIP artifact for this release",
    )
    return zip_sha256 if passed else ""


def write_report(
    output: pathlib.Path | None,
    phase: str,
    source_commit: str,
    version: dict[str, str],
    audit: Audit,
) -> None:
    report = {
        "schemaVersion": 1,
        "generatedAt": dt.datetime.now(dt.timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
        "phase": phase,
        "passed": audit.passed,
        "sourceCommit": source_commit,
        "release": {
            "version": version.get("VIBEWHISPER_VERSION", ""),
            "build": version.get("VIBEWHISPER_BUILD", ""),
        },
        "evidenceDigests": dict(sorted(audit.evidence_digests.items())),
        "gates": [asdict(gate) for gate in audit.gates],
    }
    report_text = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if output is not None:
        if output.exists():
            metadata = output.lstat()
            if stat.S_ISLNK(metadata.st_mode) or stat.S_ISDIR(metadata.st_mode):
                raise ValueError(f"unsafe report destination: {output}")
        parent = output.parent
        if not parent.is_dir() or parent.is_symlink():
            raise ValueError(f"report parent must be a regular directory: {parent}")
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{output.name}.",
            dir=parent,
        )
        temporary_path = pathlib.Path(temporary_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(report_text)
            os.chmod(temporary_path, 0o600)
            os.replace(temporary_path, output)
        finally:
            if temporary_path.exists():
                temporary_path.unlink()
    sys.stdout.write(report_text)


def self_test() -> None:
    now = dt.datetime(2026, 7, 18, tzinfo=dt.timezone.utc)
    with tempfile.TemporaryDirectory(prefix="vibewhisper-release-readiness-") as directory:
        root = pathlib.Path(directory)
        source_commit = "a" * 40
        archive_sha256 = "b" * 64
        evidence_sha256 = "c" * 64

        brand_path = root / "brand.json"
        public_contact_path = root / "public-contact.json"
        installed_path = root / "installed.json"
        summary_path = root / "summary.json"
        review_path = root / "review.json"

        brand = {
            "schemaVersion": 1,
            "status": "approved",
            "productName": "VibeWhisper",
            "reviewedAt": "2026-07-18T00:00:00Z",
            "reviewer": "Product owner",
            "checks": {
                "trademark": True,
                "domains": True,
                "appStore": True,
                "github": True,
                "social": True,
            },
            "conflicts": [],
            "decision": "Approved for release review",
        }
        public_contact = {
            "schemaVersion": 1,
            "status": "approved",
            "reviewedAt": "2026-07-18T00:00:00Z",
            "reviewer": "Product owner",
            "supportURL": "https://support.example.com/vibewhisper",
            "securityURL": "https://security.example.com/vibewhisper",
            "privacyContactURL": "https://privacy.example.com/vibewhisper",
            "legalContactURL": "https://legal.example.com/vibewhisper",
            "supportOwner": "Support owner",
            "securityOwner": "Security owner",
            "privacyOwner": "Privacy owner",
            "decision": "approved-for-public-release",
        }
        installed = {
            "schemaVersion": 2,
            "status": "approved",
            "installedApp": "/Applications/VibeWhisper.app",
            "release": {
                "version": "0.1.0",
                "build": "1",
                "sourceCommit": source_commit,
                "artifactSha256": archive_sha256,
            },
            "checks": {name: True for name in REQUIRED_INSTALLED_CHECKS},
            "evidence": [
                {
                    "id": evidence_id,
                    "observer": "Acceptance owner",
                    "observedAt": "2026-07-18T00:00:00Z",
                    "sha256": evidence_sha256,
                }
                for evidence_id in sorted(REQUIRED_INSTALLED_EVIDENCE)
            ],
        }
        summary = {
            "schemaVersion": 1,
            "generatedAt": "2026-07-18T00:00:00Z",
            "status": "automated_gates_passed_manual_review_required",
            "automatedPilotExitGatesPassed": True,
            "inputCounts": {
                "participantRows": 30,
                "consentedParticipants": 30,
                "observationRows": 300,
                "incidentRows": 0,
            },
            "pilotExitGates": {
                "participant_count": {"value": 30, "target": "30–50", "passed": True},
                "week1_valid_participants": {"value": 30, "target": ">=20", "passed": True},
                "non_direct_runs": {"value": 300, "target": ">=300", "passed": True},
                "qualified_external_authors": {"value": 5, "target": ">=5", "passed": True},
                "final_application_rate": {"value": 0.8, "target": ">=0.70", "passed": True},
                "wrong_skill_rate": {"value": 0.0, "target": "<=0.03", "passed": True},
                "curated_validator_fallback_rate": {"value": 0.0, "target": "<=0.05", "passed": True},
                "selection_identity_success_rate": {"value": 1.0, "target": ">=0.97", "passed": True},
                "preview_cancel_rate": {"value": 0.1, "target": "<=0.20", "passed": True},
                "switcher_upper_median": {"value": "1_to_3s", "target": "<=3s", "passed": True},
                "first_use_upper_median": {"value": "3_to_5m", "target": "<=5m", "passed": True},
                "first_use_coverage": {"value": 30, "target": "all", "passed": True},
                "creator_upper_median": {"value": "5_to_15m", "target": "<=15m", "passed": True},
                "week1_effective_retention": {"value": 0.4, "target": ">=0.40", "passed": True},
                "week4_effective_retention": {"value": 0.2, "target": ">=0.20", "passed": True},
                "critical_incidents": {"value": 0, "target": "0", "passed": True},
            },
            "observationMetrics": {
                "previewEditRate": 0.1,
                "targetFailureRate": 0.0,
                "taskCategoryCounts": {"developer": 300},
                "resultActionCounts": {"paste": 300},
                "failureClassCounts": {"none": 300},
            },
            "registrySignals": {
                "nonBuiltInAdoptionRate": {
                    "value": 0.2,
                    "goThreshold": 0.25,
                    "thresholdMet": False,
                },
                "qualifiedExternalAuthors": 5,
                "criticalIncidents": 0,
                "decision": "product_owner_review_required",
            },
            "manualReviewRequired": PILOT_MANUAL_REVIEW_REQUIRED,
            "privacy": {
                "rowLevelEvidenceIncluded": False,
                "cohortCodesIncluded": False,
                "contentFieldsAccepted": False,
                "inputSchemasAreEnumAndBucketOnly": True,
            },
        }
        for gate_name, gate in summary["pilotExitGates"].items():
            gate["target"] = PILOT_GATE_TARGETS[gate_name]

        for path, value in (
            (brand_path, brand),
            (public_contact_path, public_contact),
            (installed_path, installed),
            (summary_path, summary),
        ):
            path.write_text(json.dumps(value) + "\n", encoding="utf-8")

        policy_documents = {
            root / "docs/support/support-policy.md": public_contact["supportURL"],
            root / "docs/support/support-policy.zh-CN.md": public_contact["supportURL"],
            root / "SECURITY.md": public_contact["securityURL"],
            root / "docs/legal/privacy-policy.md": public_contact["privacyContactURL"],
            root / "docs/legal/privacy-policy.zh-CN.md": public_contact["privacyContactURL"],
            root / "docs/legal/terms-of-use.md": public_contact["legalContactURL"],
            root / "docs/legal/terms-of-use.zh-CN.md": public_contact["legalContactURL"],
        }
        for document_path, contact_url in policy_documents.items():
            document_path.parent.mkdir(parents=True, exist_ok=True)
            document_path.write_text(
                f"# Public policy\n\nContact: {contact_url}\n",
                encoding="utf-8",
            )

        review = {
            "schemaVersion": 2,
            "status": "approved",
            "reviewedAt": "2026-07-18T00:00:00Z",
            "reviewer": "Product owner",
            "productVersion": "0.1.0",
            "communityPilotSummarySha256": sha256_file(summary_path),
            "fourCompleteWeeks": True,
            "manualReview": {name: True for name in REQUIRED_BETA_REVIEW},
            "openP0Blockers": 0,
            "openP1Blockers": 0,
            "decision": "approved-for-public-release-review",
            "evidenceReference": "restricted-study-record-2026-07",
        }
        review_path.write_text(json.dumps(review) + "\n", encoding="utf-8")

        (root / "dist").mkdir()
        candidate_report_path = root / "dist" / "release-candidate-readiness.json"
        candidate_report = {
            "schemaVersion": 1,
            "generatedAt": "2026-07-18T00:00:00Z",
            "phase": "candidate",
            "passed": True,
            "sourceCommit": source_commit,
            "release": {"version": "0.1.0", "build": "1"},
            "evidenceDigests": {},
            "gates": [
                {
                    "identifier": identifier,
                    "passed": True,
                    "detail": "self-test",
                }
                for identifier in sorted(REQUIRED_CANDIDATE_REPORT_GATES)
            ],
        }
        candidate_report_path.write_text(
            json.dumps(candidate_report) + "\n",
            encoding="utf-8",
        )

        candidate_report_audit = Audit()
        audit_candidate_readiness_report(
            root,
            candidate_report_audit,
            "0.1.0",
            "1",
            source_commit,
            now,
        )
        if not candidate_report_audit.passed:
            raise AssertionError("valid candidate readiness report did not pass")
        candidate_report["sourceCommit"] = "f" * 40
        candidate_report_path.write_text(
            json.dumps(candidate_report) + "\n",
            encoding="utf-8",
        )
        mismatched_report = Audit()
        audit_candidate_readiness_report(
            root,
            mismatched_report,
            "0.1.0",
            "1",
            source_commit,
            now,
        )
        if mismatched_report.passed:
            raise AssertionError("candidate report for another commit passed")
        candidate_report["sourceCommit"] = source_commit
        candidate_report_path.write_text(
            json.dumps(candidate_report) + "\n",
            encoding="utf-8",
        )

        for filename, submission_id in (
            ("notarization-app.json", "11111111-1111-1111-1111-111111111111"),
            ("notarization-dmg.json", "22222222-2222-2222-2222-222222222222"),
        ):
            (root / "dist" / filename).write_text(
                json.dumps(
                    {
                        "id": submission_id,
                        "status": "Accepted",
                        "message": "Processing complete",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
        notarization_audit = Audit()
        audit_notarization_receipts(root, notarization_audit)
        if not notarization_audit.passed:
            raise AssertionError("valid notarization receipts did not pass")

        passing = Audit()
        audit_brand(passing, brand_path, "VibeWhisper", now)
        audit_public_contacts(root, passing, public_contact_path, now)
        audit_installed_acceptance(
            passing,
            installed_path,
            "0.1.0",
            "1",
            source_commit,
            archive_sha256,
            now,
        )
        audit_community_pilot(passing, summary_path, review_path, "0.1.0", now)
        if not passing.passed:
            raise AssertionError("valid public-release evidence did not pass")

        brand["status"] = "blocked"
        brand_path.write_text(json.dumps(brand) + "\n", encoding="utf-8")
        blocked_brand = Audit()
        audit_brand(blocked_brand, brand_path, "VibeWhisper", now)
        if blocked_brand.passed:
            raise AssertionError("blocked brand evidence passed")

        support_policy = root / "docs/support/support-policy.md"
        original_support_policy = support_policy.read_text(encoding="utf-8")
        support_policy.write_text(
            original_support_policy + "Private alpha only.\n",
            encoding="utf-8",
        )
        stale_policy = Audit()
        audit_public_contacts(root, stale_policy, public_contact_path, now)
        if stale_policy.passed:
            raise AssertionError("private-alpha policy copy passed public readiness")
        support_policy.write_text(original_support_policy, encoding="utf-8")

        installed["release"]["artifactSha256"] = "d" * 64
        installed_path.write_text(json.dumps(installed) + "\n", encoding="utf-8")
        wrong_candidate = Audit()
        audit_installed_acceptance(
            wrong_candidate,
            installed_path,
            "0.1.0",
            "1",
            source_commit,
            archive_sha256,
            now,
        )
        if wrong_candidate.passed:
            raise AssertionError("acceptance for another candidate passed")

        summary["pilotExitGates"]["critical_incidents"]["value"] = 1
        if pilot_gate_values_are_valid(
            summary["pilotExitGates"],
            summary["inputCounts"],
        ):
            raise AssertionError("forged passing flag hid a Critical incident")
        summary["pilotExitGates"]["critical_incidents"]["value"] = 0
        summary["automatedPilotExitGatesPassed"] = False
        summary_path.write_text(json.dumps(summary) + "\n", encoding="utf-8")
        blocked_pilot = Audit()
        audit_community_pilot(
            blocked_pilot,
            summary_path,
            review_path,
            "0.1.0",
            now,
        )
        if blocked_pilot.passed:
            raise AssertionError("failed Pilot aggregate passed")

        symlink_path = root / "symlink.json"
        symlink_path.symlink_to(review_path)
        try:
            load_json(symlink_path)
        except ValueError:
            pass
        else:
            raise AssertionError("symbolic-link evidence was accepted")

        candidate_root = root / "candidate-root"
        key_directory = root / "candidate-keys"
        candidate_root.mkdir()
        key_directory.mkdir()
        sparkle_key = key_directory / "sparkle.key"
        capability_key = key_directory / "capability.key"
        sparkle_key.write_bytes(b"sparkle-private-key")
        capability_key.write_bytes(b"capability-private-key")
        sparkle_key.chmod(0o600)
        capability_key.chmod(0o600)
        candidate_environment = {
            "VIBEWHISPER_TEAM_ID": "ABCDE12345",
            "VIBEWHISPER_RELEASE_BASE_URL": "https://downloads.example.com/vibewhisper/v0.1.0",
            "VIBEWHISPER_SPARKLE_FEED_URL": "https://updates.example.com/stable/appcast.xml",
            "VIBEWHISPER_SPARKLE_PUBLIC_ED_KEY": base64.b64encode(
                bytes(range(32))
            ).decode("ascii"),
            "VIBEWHISPER_CAPABILITY_POLICY_URL": "https://updates.example.com/provider-capabilities.json",
            "VIBEWHISPER_CAPABILITY_PUBLIC_ED_KEY": base64.b64encode(
                bytes(range(1, 33))
            ).decode("ascii"),
            "VIBEWHISPER_CODESIGN_IDENTITY": "Developer ID Application identity",
            "VIBEWHISPER_NOTARY_PROFILE": "vibewhisper-notary",
            "VIBEWHISPER_NOTARY_KEYCHAIN": "",
            "VIBEWHISPER_SPARKLE_PRIVATE_KEY_FILE": str(sparkle_key),
            "VIBEWHISPER_CAPABILITY_PRIVATE_KEY_FILE": str(capability_key),
            "VIBEWHISPER_CAPABILITY_POLICY_REVISION": "1",
            "VIBEWHISPER_CAPABILITY_POLICY_EXPIRES_AT": (
                dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1)
            )
            .isoformat()
            .replace("+00:00", "Z"),
            "VIBEWHISPER_BUILD_CONFIGURATION": "release",
        }
        previous_environment = {
            name: os.environ.get(name) for name in candidate_environment
        }
        try:
            os.environ.update(candidate_environment)
            candidate_audit = Audit()
            audit_environment(candidate_root, candidate_audit, "candidate")
            if not candidate_audit.passed:
                raise AssertionError("valid candidate configuration did not pass")

            os.environ["VIBEWHISPER_CAPABILITY_PUBLIC_ED_KEY"] = os.environ[
                "VIBEWHISPER_SPARKLE_PUBLIC_ED_KEY"
            ]
            reused_key_audit = Audit()
            audit_environment(candidate_root, reused_key_audit, "candidate")
            if reused_key_audit.passed:
                raise AssertionError("reused release public key passed")
        finally:
            for name, previous_value in previous_environment.items():
                if previous_value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = previous_value

    print("Release readiness verifier self-test passed.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate signed-candidate or public-release readiness."
    )
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parent.parent,
    )
    parser.add_argument("--phase", choices=("candidate", "public"))
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        self_test()
        return 0
    if arguments.phase is None:
        parser.error("--phase is required unless --self-test is used")

    root = arguments.root.resolve()
    audit = Audit()
    product, version = audit_identity(root, audit)
    audit_environment(root, audit, arguments.phase)
    source_commit = audit_git(
        root,
        audit,
        product.get("VIBEWHISPER_REPOSITORY", ""),
        version.get("VIBEWHISPER_VERSION", ""),
        require_tag=arguments.phase == "public",
    )

    if arguments.phase == "public":
        current_version = version.get("VIBEWHISPER_VERSION", "")
        current_build = version.get("VIBEWHISPER_BUILD", "")
        zip_sha256 = read_manifest_zip_sha256(
            root,
            audit,
            current_version,
            current_build,
        )
        now = dt.datetime.now(dt.timezone.utc)
        audit_candidate_readiness_report(
            root,
            audit,
            current_version,
            current_build,
            source_commit,
            now,
        )
        audit_notarization_receipts(root, audit)
        brand_path = pathlib.Path(
            os.environ.get(
                "VIBEWHISPER_BRAND_CLEARANCE_PATH",
                root / "release" / "brand-clearance.json",
            )
        )
        installed_path = pathlib.Path(
            os.environ.get(
                "VIBEWHISPER_INSTALLED_ACCEPTANCE_PATH",
                root / "release" / "installed-acceptance.json",
            )
        )
        summary_path = pathlib.Path(
            os.environ.get(
                "VIBEWHISPER_COMMUNITY_PILOT_SUMMARY_PATH",
                root / "release" / "community-pilot-summary.json",
            )
        )
        review_path = pathlib.Path(
            os.environ.get(
                "VIBEWHISPER_BETA_METRICS_PATH",
                root / "release" / "beta-metrics.json",
            )
        )
        public_contact_path = pathlib.Path(
            os.environ.get(
                "VIBEWHISPER_PUBLIC_CONTACT_PATH",
                root / "release" / "public-contact.json",
            )
        )
        audit_brand(audit, brand_path, product.get("VIBEWHISPER_APP_NAME", ""), now)
        audit_public_contacts(root, audit, public_contact_path, now)
        audit_installed_acceptance(
            audit,
            installed_path,
            current_version,
            current_build,
            source_commit,
            zip_sha256,
            now,
        )
        audit_community_pilot(
            audit,
            summary_path,
            review_path,
            current_version,
            now,
        )

    try:
        write_report(
            arguments.output,
            arguments.phase,
            source_commit,
            version,
            audit,
        )
    except (OSError, ValueError) as error:
        print(f"Release readiness report error: {error}", file=sys.stderr)
        return 2
    return 0 if audit.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
