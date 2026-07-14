#!/usr/bin/env python3
"""Fail-closed OpenWhisper productization readiness audit.

The source stage validates that the repository contains the release controls
needed to pursue a commercial build. The commercial stages additionally
require operator, brand, beta, installed-app, signing, hosting, and release
configuration evidence. No secret values are written to the report.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as dt
import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import urllib.parse
from dataclasses import asdict, dataclass
from typing import Any


EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
SEMVER_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$")
TEAM_ID_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
ZERO_SHA256 = "0" * 64
PLACEHOLDER_MARKERS = (
    "REPLACE",
    "TODO",
    "TBD",
    "CHANGEME",
    "YOUR_",
    "SET_",
)


@dataclass
class Gate:
    identifier: str
    passed: bool
    detail: str


class Audit:
    def __init__(self) -> None:
        self.gates: list[Gate] = []

    def add(self, identifier: str, passed: bool, detail: str) -> None:
        self.gates.append(Gate(identifier, passed, detail))

    @property
    def passed(self) -> bool:
        return all(gate.passed for gate in self.gates)


def load_simple_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([A-Z][A-Z0-9_]*)=([A-Za-z0-9._/@:+-]+)", line)
        if not match:
            raise ValueError(f"Unsafe environment entry at {path}:{number}")
        key, value = match.groups()
        if key in values:
            raise ValueError(f"Duplicate environment key {key} in {path}")
        values[key] = value
    return values


def load_json(path: pathlib.Path, maximum_bytes: int = 256 * 1024) -> dict[str, Any]:
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"{path} must be a regular non-symlink file")
    if metadata.st_size <= 0 or metadata.st_size > maximum_bytes:
        raise ValueError(f"{path} must contain 1–{maximum_bytes} bytes")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def canonical_https(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    parsed = urllib.parse.urlsplit(value)
    return (
        parsed.scheme == "https"
        and bool(parsed.hostname)
        and not parsed.hostname.endswith(".invalid")
        and parsed.username is None
        and parsed.password is None
        and not parsed.fragment
        and urllib.parse.urlunsplit(parsed) == value
    )


def real_string(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    normalized = value.strip()
    uppercased = normalized.upper()
    return (
        not any(marker in uppercased for marker in PLACEHOLDER_MARKERS)
        and "example.invalid" not in normalized.lower()
    )


def valid_email(value: Any) -> bool:
    return (
        real_string(value)
        and EMAIL_PATTERN.fullmatch(value) is not None
        and not value.lower().endswith(".invalid")
    )


def parse_date(value: Any) -> dt.datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def environment_present(name: str) -> bool:
    return bool(os.environ.get(name, "").strip())


def valid_public_key(name: str) -> bool:
    value = os.environ.get(name, "").strip()
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


def require_fields(
    audit: Audit,
    identifier: str,
    value: dict[str, Any],
    fields: tuple[str, ...],
) -> None:
    missing = [field for field in fields if not real_string(value.get(field))]
    audit.add(
        identifier,
        not missing,
        "all required fields present" if not missing else f"missing: {', '.join(missing)}",
    )


def audit_source(root: pathlib.Path, audit: Audit) -> tuple[dict[str, str], dict[str, str]]:
    product_path = root / "product.env"
    version_path = root / "version.env"
    try:
        product = load_simple_env(product_path)
        version = load_simple_env(version_path)
        audit.add("source.identity-env", True, "strict product/version data parsed")
    except Exception as error:
        audit.add("source.identity-env", False, str(error))
        return {}, {}

    audit.add(
        "source.canonical-identity",
        product.get("OPENWHISPER_APP_NAME") == "OpenWhisper"
        and product.get("OPENWHISPER_BUNDLE_ID") == "app.openwhisper.mac"
        and product.get("OPENWHISPER_REPOSITORY") == "forever-ivy/openwhisper",
        "product identity matches the current repository contract",
    )
    current_version = version.get("OPENWHISPER_VERSION", "")
    audit.add(
        "source.semantic-version",
        SEMVER_PATTERN.fullmatch(current_version) is not None
        and version.get("OPENWHISPER_BUILD", "").isdigit()
        and int(version.get("OPENWHISPER_BUILD", "0")) > 0,
        f"version={current_version or 'missing'} build={version.get('OPENWHISPER_BUILD', 'missing')}",
    )

    required_files = (
        "LICENSE",
        "SECURITY.md",
        "CHANGELOG.md",
        "docs/legal/privacy-policy.md",
        "docs/legal/privacy-policy.zh-CN.md",
        "docs/legal/terms-of-use.md",
        "docs/legal/terms-of-use.zh-CN.md",
        "docs/legal/refund-policy.md",
        "docs/legal/refund-policy.zh-CN.md",
        "docs/support/support-policy.md",
        "docs/support/support-policy.zh-CN.md",
        "scripts/verify_release_gate.sh",
        "scripts/verify_remote_release_assets.sh",
        "scripts/archive_release_candidate.sh",
        "scripts/restore_release_candidate.sh",
        "scripts/release_commercial.sh",
        "scripts/verify_productization_readiness.py",
        ".github/workflows/release.yml",
    )
    missing_files = [path for path in required_files if not (root / path).is_file()]
    audit.add(
        "source.release-files",
        not missing_files,
        "required release controls present"
        if not missing_files
        else f"missing: {', '.join(missing_files)}",
    )

    english_notes = root / "docs" / "releases" / f"v{current_version}.md"
    chinese_notes = root / "docs" / "releases" / f"v{current_version}.zh-CN.md"
    audit.add(
        "source.bilingual-release-notes",
        english_notes.is_file() and chinese_notes.is_file(),
        f"{english_notes.name} and {chinese_notes.name}",
    )
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    audit.add(
        "source.changelog-version",
        f"## {current_version}" in changelog,
        "current version is represented in CHANGELOG.md",
    )

    workflow_path = root / ".github" / "workflows" / "release.yml"
    workflow = workflow_path.read_text(encoding="utf-8") if workflow_path.is_file() else ""
    workflow_requirements = (
        "runs-on: macos-26",
        "environment: production",
        "34e114876b0b11c390a56381ad16ebd13914f8d5",
        "ea165f8d65b6e75b540449e92b4886f43607fa02",
        "d3f86a106a0bac45b974a628896c90dbdf5c8093",
        "prepare_run_id",
        "/usr/bin/base64 -D",
        "load_version_env",
        "scripts/archive_release_candidate.sh",
        "scripts/restore_release_candidate.sh",
        "scripts/release_commercial.sh prepare",
        "scripts/release_commercial.sh finalize",
    )
    missing_workflow_controls = [
        value for value in workflow_requirements if value not in workflow
    ]
    audit.add(
        "source.release-workflow",
        not missing_workflow_controls,
        "pinned macOS 26 production workflow"
        if not missing_workflow_controls
        else f"missing controls: {', '.join(missing_workflow_controls)}",
    )
    unsafe_workflow_controls = (
        "source version.env",
        "base64 --decode",
    )
    present_unsafe_controls = [
        value for value in unsafe_workflow_controls if value in workflow
    ]
    audit.add(
        "source.release-workflow-data-safety",
        not present_unsafe_controls,
        "workflow does not execute repository environment data"
        if not present_unsafe_controls
        else f"unsafe controls: {', '.join(present_unsafe_controls)}",
    )

    executable_scripts = (
        "scripts/archive_release_candidate.sh",
        "scripts/release_commercial.sh",
        "scripts/restore_release_candidate.sh",
        "scripts/verify_remote_release_assets.sh",
    )
    mode_errors: list[str] = []
    for relative_path in executable_scripts:
        path = root / relative_path
        try:
            metadata = path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or not metadata.st_mode & stat.S_IXUSR
            ):
                mode_errors.append(relative_path)
        except OSError:
            mode_errors.append(relative_path)
    audit.add(
        "source.release-script-modes",
        not mode_errors,
        "release entry points are owner-executable"
        if not mode_errors
        else f"not executable: {', '.join(mode_errors)}",
    )

    examples = (
        root / "release" / "commercial-operator.example.json",
        root / "release" / "beta-metrics.example.json",
        root / "release" / "installed-acceptance.example.json",
    )
    example_errors: list[str] = []
    for path in examples:
        try:
            value = load_json(path)
            if value.get("status") != "template" or value.get("schemaVersion") != 1:
                example_errors.append(f"{path.name} is not a schemaVersion 1 template")
        except Exception as error:
            example_errors.append(str(error))
    audit.add(
        "source.release-templates",
        not example_errors,
        "release evidence templates parse"
        if not example_errors
        else "; ".join(example_errors),
    )

    brand_record = root / "release" / "brand-clearance.json"
    try:
        brand = load_json(brand_record)
        status_value = brand.get("status")
        audit.add(
            "source.brand-status-recorded",
            brand.get("schemaVersion") == 1
            and brand.get("productName") == product.get("OPENWHISPER_APP_NAME")
            and status_value in {"blocked", "approved"},
            f"brand clearance status={status_value}",
        )
    except Exception as error:
        audit.add("source.brand-status-recorded", False, str(error))

    tracked_release_files = run(root, "git", "ls-files", "release")
    sensitive_tracked_files: list[str] = []
    if tracked_release_files.returncode == 0:
        for raw_path in tracked_release_files.stdout.splitlines():
            path = raw_path.lower()
            if (
                path == "release/production.env"
                or path.startswith("release/private/")
                or path.startswith("release/secrets/")
                or path.endswith((".key", ".p8", ".p12", ".pem"))
            ):
                sensitive_tracked_files.append(raw_path)
    audit.add(
        "source.no-production-secrets",
        not sensitive_tracked_files,
        "production release secrets are not tracked"
        if not sensitive_tracked_files
        else f"tracked sensitive paths: {', '.join(sensitive_tracked_files)}",
    )

    gitignore = (root / ".gitignore").read_text(encoding="utf-8")
    required_ignores = (
        "/release/production.env",
        "/release/private/",
        "/release/secrets/",
        "/release/*.key",
        "/release/*.p8",
        "/release/*.p12",
        "/release/*.pem",
    )
    missing_ignores = [value for value in required_ignores if value not in gitignore]
    audit.add(
        "source.release-secret-ignores",
        not missing_ignores,
        "release secret paths are explicitly ignored"
        if not missing_ignores
        else f"missing ignores: {', '.join(missing_ignores)}",
    )
    return product, version


def audit_operator(root: pathlib.Path, audit: Audit) -> None:
    path = root / "release" / "commercial-operator.json"
    try:
        value = load_json(path)
    except Exception as error:
        audit.add("commercial.operator", False, str(error))
        return
    require_fields(
        audit,
        "commercial.operator-fields",
        value,
        (
            "legalName",
            "tradingName",
            "jurisdiction",
            "legalAddress",
            "checkoutProvider",
            "merchantOfRecord",
        ),
    )
    emails = ("legalEmail", "privacyEmail", "supportEmail")
    audit.add(
        "commercial.operator-emails",
        all(valid_email(value.get(field)) for field in emails),
        "legal, privacy, and support contacts are valid email addresses",
    )
    urls = (
        "operatorURL",
        "privacyURL",
        "termsURL",
        "refundURL",
        "supportURL",
        "securityURL",
        "checkoutURL",
    )
    audit.add(
        "commercial.operator-urls",
        all(canonical_https(value.get(field)) for field in urls),
        "operator, policy, support, security, and checkout URLs use canonical HTTPS",
    )
    audit.add(
        "commercial.operator-approved",
        value.get("schemaVersion") == 1
        and value.get("status") == "approved"
        and real_string(value.get("legalName"))
        and real_string(value.get("tradingName"))
        and parse_date(value.get("effectiveAt")) is not None,
        f"operator status={value.get('status')}",
    )


def audit_brand(root: pathlib.Path, audit: Audit, product_name: str) -> None:
    path = root / "release" / "brand-clearance.json"
    try:
        value = load_json(path)
    except Exception as error:
        audit.add("commercial.brand", False, str(error))
        return
    reviewed_at = parse_date(value.get("reviewedAt"))
    age = (
        dt.datetime.now(dt.timezone.utc) - reviewed_at
        if reviewed_at is not None
        else None
    )
    checks = value.get("checks")
    checks_pass = isinstance(checks, dict) and all(
        checks.get(name) is True
        for name in ("trademark", "domains", "appStore", "github", "social")
    )
    conflicts = value.get("conflicts")
    audit.add(
        "commercial.brand-approved",
        value.get("schemaVersion") == 1
        and value.get("status") == "approved"
        and value.get("productName") == product_name
        and real_string(value.get("reviewer"))
        and real_string(value.get("decision"))
        and reviewed_at is not None
        and age is not None
        and dt.timedelta(0) <= age <= dt.timedelta(days=180)
        and checks_pass
        and conflicts == [],
        f"brand status={value.get('status')} conflicts={len(conflicts) if isinstance(conflicts, list) else 'invalid'}",
    )


def audit_metrics(root: pathlib.Path, audit: Audit) -> None:
    path = root / "release" / "beta-metrics.json"
    try:
        value = load_json(path)
    except Exception as error:
        audit.add("commercial.beta-metrics", False, str(error))
        return
    thresholds = {
        "participants": (30, lambda actual, minimum: actual >= minimum),
        "firstSuccessRate": (0.95, lambda actual, minimum: actual >= minimum),
        "retrySuccessRate": (0.99, lambda actual, minimum: actual >= minimum),
        "crashFreeSessionRate": (0.995, lambda actual, minimum: actual >= minimum),
        "wrongTargetPasteCount": (0, lambda actual, expected: actual == expected),
        "openP0Blockers": (0, lambda actual, expected: actual == expected),
        "openP1Blockers": (0, lambda actual, expected: actual == expected),
    }
    failures: list[str] = []
    for field, (threshold, predicate) in thresholds.items():
        actual = value.get(field)
        if not isinstance(actual, (int, float)) or isinstance(actual, bool):
            failures.append(f"{field}=invalid")
        elif not predicate(actual, threshold):
            failures.append(f"{field}={actual}")
    for field in ("firstSuccessRate", "retrySuccessRate", "crashFreeSessionRate"):
        actual = value.get(field)
        if isinstance(actual, (int, float)) and not isinstance(actual, bool):
            if not 0 <= actual <= 1:
                failures.append(f"{field}=outside-0...1")
    measured_at = parse_date(value.get("measuredAt"))
    age = (
        dt.datetime.now(dt.timezone.utc) - measured_at
        if measured_at is not None
        else None
    )
    audit.add(
        "commercial.beta-metrics",
        value.get("schemaVersion") == 1
        and value.get("status") == "approved"
        and not failures
        and measured_at is not None
        and age is not None
        and dt.timedelta(0) <= age <= dt.timedelta(days=180)
        and real_string(value.get("evidenceLocation")),
        "beta thresholds satisfied" if not failures else ", ".join(failures),
    )


def audit_acceptance(root: pathlib.Path, audit: Audit) -> None:
    path = root / "release" / "installed-acceptance.json"
    try:
        value = load_json(path)
    except Exception as error:
        audit.add("commercial.installed-acceptance", False, str(error))
        return
    checks = value.get("checks")
    required_checks = (
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
    failed_checks = (
        [name for name in required_checks if not isinstance(checks, dict) or checks.get(name) is not True]
    )
    evidence = value.get("evidence")
    required_evidence_ids = {
        "installed-interaction",
        "accessibility",
        "compatibility",
        "update-rollback",
    }
    evidence_ids: set[str] = set()
    evidence_valid = isinstance(evidence, list) and len(evidence) >= 4
    if evidence_valid:
        for item in evidence:
            observed_at = parse_date(item.get("observedAt")) if isinstance(item, dict) else None
            age = (
                dt.datetime.now(dt.timezone.utc) - observed_at
                if observed_at is not None
                else None
            )
            if not isinstance(item, dict) or not all(
                (
                    real_string(item.get("id")),
                    real_string(item.get("observer")),
                    observed_at is not None,
                    age is not None
                    and dt.timedelta(0) <= age <= dt.timedelta(days=90),
                    isinstance(item.get("sha256"), str)
                    and SHA256_PATTERN.fullmatch(item["sha256"]) is not None,
                    item.get("sha256") != ZERO_SHA256,
                )
            ):
                evidence_valid = False
                break
            if item["id"] in evidence_ids:
                evidence_valid = False
                break
            evidence_ids.add(item["id"])
        evidence_valid = evidence_valid and required_evidence_ids.issubset(evidence_ids)
    audit.add(
        "commercial.installed-acceptance",
        value.get("schemaVersion") == 1
        and value.get("status") == "approved"
        and value.get("installedApp") == "/Applications/OpenWhisper.app"
        and not failed_checks
        and evidence_valid,
        "all installed-app checks and evidence present"
        if not failed_checks and evidence_valid
        else f"missing/failed checks: {', '.join(failed_checks) or 'evidence'}",
    )


def audit_environment(root: pathlib.Path, audit: Audit, phase: str) -> None:
    required_values = [
        "OPENWHISPER_TEAM_ID",
        "OPENWHISPER_RELEASE_BASE_URL",
        "OPENWHISPER_SPARKLE_FEED_URL",
        "OPENWHISPER_SPARKLE_PUBLIC_ED_KEY",
        "OPENWHISPER_CAPABILITY_POLICY_URL",
        "OPENWHISPER_CAPABILITY_PUBLIC_ED_KEY",
        "OPENWHISPER_LICENSE_PUBLIC_ED_KEY",
    ]
    if phase == "prebuild":
        required_values.extend(
            (
                "OPENWHISPER_CODESIGN_IDENTITY",
                "OPENWHISPER_NOTARY_PROFILE",
                "OPENWHISPER_SPARKLE_PRIVATE_KEY_FILE",
                "OPENWHISPER_CAPABILITY_PRIVATE_KEY_FILE",
                "OPENWHISPER_CAPABILITY_POLICY_REVISION",
                "OPENWHISPER_CAPABILITY_POLICY_EXPIRES_AT",
            )
        )
    missing = [name for name in required_values if not environment_present(name)]
    audit.add(
        "commercial.release-environment",
        not missing,
        "required release environment present"
        if not missing
        else f"missing: {', '.join(missing)}",
    )
    audit.add(
        "commercial.team-id",
        TEAM_ID_PATTERN.fullmatch(os.environ.get("OPENWHISPER_TEAM_ID", "")) is not None,
        "Team ID uses the Apple 10-character format"
        if TEAM_ID_PATTERN.fullmatch(os.environ.get("OPENWHISPER_TEAM_ID", ""))
        else "Team ID is missing or does not use the Apple 10-character format",
    )
    url_names = (
        "OPENWHISPER_RELEASE_BASE_URL",
        "OPENWHISPER_SPARKLE_FEED_URL",
        "OPENWHISPER_CAPABILITY_POLICY_URL",
    )
    release_urls_valid = all(
        canonical_https(os.environ.get(name)) for name in url_names
    )
    audit.add(
        "commercial.release-urls",
        release_urls_valid,
        "artifact, appcast, and capability hosts use canonical HTTPS"
        if release_urls_valid
        else "one or more artifact, appcast, or capability URLs are missing or invalid",
    )
    public_key_names = (
        "OPENWHISPER_SPARKLE_PUBLIC_ED_KEY",
        "OPENWHISPER_CAPABILITY_PUBLIC_ED_KEY",
        "OPENWHISPER_LICENSE_PUBLIC_ED_KEY",
    )
    public_keys_valid = all(valid_public_key(name) for name in public_key_names)
    public_key_values = [os.environ.get(name, "").strip() for name in public_key_names]
    audit.add(
        "commercial.public-keys",
        public_keys_valid and len(set(public_key_values)) == len(public_key_values),
        "Sparkle, capability, and license public keys are valid and distinct"
        if public_keys_valid and len(set(public_key_values)) == len(public_key_values)
        else "Sparkle, capability, and license public keys must be valid and distinct",
    )
    if phase == "prebuild":
        revision = os.environ.get("OPENWHISPER_CAPABILITY_POLICY_REVISION", "")
        expires_at = parse_date(
            os.environ.get("OPENWHISPER_CAPABILITY_POLICY_EXPIRES_AT", "")
        )
        now = dt.datetime.now(dt.timezone.utc)
        audit.add(
            "commercial.capability-policy-window",
            revision.isdigit()
            and int(revision) > 0
            and expires_at is not None
            and now < expires_at <= now + dt.timedelta(days=31),
            "capability policy revision is positive and expiry is within 31 days",
        )

        private_key_names = (
            "OPENWHISPER_SPARKLE_PRIVATE_KEY_FILE",
            "OPENWHISPER_CAPABILITY_PRIVATE_KEY_FILE",
        )
        private_key_errors: list[str] = []
        resolved_private_paths: list[pathlib.Path] = []
        for name in private_key_names:
            raw_path = os.environ.get(name, "").strip()
            if not raw_path:
                private_key_errors.append(f"{name}=missing")
                continue
            path = pathlib.Path(raw_path)
            try:
                metadata = path.lstat()
                resolved_path = path.resolve(strict=True)
                if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                    private_key_errors.append(f"{name}=unsafe")
                elif metadata.st_size <= 0:
                    private_key_errors.append(f"{name}=empty")
                elif stat.S_IMODE(metadata.st_mode) & 0o077:
                    private_key_errors.append(f"{name}=permissions")
                elif resolved_path == root or root in resolved_path.parents:
                    private_key_errors.append(f"{name}=inside-repository")
                else:
                    resolved_private_paths.append(resolved_path)
            except OSError:
                private_key_errors.append(f"{name}=unreadable")
        if len(set(resolved_private_paths)) != len(resolved_private_paths):
            private_key_errors.append("private-key-files=not-distinct")
        audit.add(
            "commercial.private-key-files",
            not private_key_errors,
            "private release keys are distinct owner-only files outside the repository"
            if not private_key_errors
            else ", ".join(private_key_errors),
        )


def audit_git(root: pathlib.Path, audit: Audit, version: str, require_tag: bool) -> None:
    status_result = run(root, "git", "status", "--porcelain")
    audit.add(
        "commercial.clean-worktree",
        status_result.returncode == 0 and not status_result.stdout.strip(),
        "Git worktree is clean"
        if status_result.returncode == 0 and not status_result.stdout.strip()
        else "Git worktree contains uncommitted changes",
    )
    remote_result = run(root, "git", "remote", "get-url", "origin")
    audit.add(
        "commercial.canonical-remote",
        remote_result.returncode == 0
        and remote_result.stdout.strip().rstrip("/").endswith("forever-ivy/openwhisper.git"),
        remote_result.stdout.strip() or remote_result.stderr.strip(),
    )
    if require_tag:
        head = run(root, "git", "rev-parse", "HEAD")
        tag = run(root, "git", "rev-list", "-n", "1", f"v{version}")
        audit.add(
            "commercial.release-tag",
            head.returncode == 0
            and tag.returncode == 0
            and head.stdout.strip() == tag.stdout.strip(),
            f"v{version} points at the release commit",
        )


def audit_final_artifacts(
    root: pathlib.Path,
    audit: Audit,
    product: dict[str, str],
    version: dict[str, str],
) -> None:
    app_name = product.get("OPENWHISPER_APP_NAME", "OpenWhisper")
    current_version = version.get("OPENWHISPER_VERSION", "")
    architecture = os.uname().machine
    paths = (
        root / "dist" / f"{app_name}.app",
        root / "dist" / f"{app_name}-{current_version}-macos-{architecture}.zip",
        root / "dist" / f"{app_name}-{current_version}-macos-{architecture}.dmg",
        root / "dist" / "release-manifest.json",
        root / "dist" / "appcast.xml",
        root / "dist" / "provider-capabilities.json",
    )
    missing: list[str] = []
    for index, path in enumerate(paths):
        try:
            metadata = path.lstat()
            valid_type = (
                stat.S_ISDIR(metadata.st_mode)
                if index == 0
                else stat.S_ISREG(metadata.st_mode)
            )
            if stat.S_ISLNK(metadata.st_mode) or not valid_type:
                missing.append(str(path.relative_to(root)))
        except OSError:
            missing.append(str(path.relative_to(root)))
    audit.add(
        "commercial.release-artifacts",
        not missing,
        "commercial artifacts present" if not missing else f"missing: {', '.join(missing)}",
    )
    cask_path = pathlib.Path(
        os.environ.get(
            "OPENWHISPER_CASK_PATH",
            str(root / "packaging" / "homebrew" / "Casks" / "openwhisper.rb"),
        )
    )
    try:
        metadata = cask_path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise ValueError("Cask must be a regular non-symlink file")
        cask = cask_path.read_text(encoding="utf-8")
    except Exception as error:
        audit.add(
            "commercial.cask-published-values",
            False,
            f"{cask_path}: {error}",
        )
        return

    manifest_path = root / "dist" / "release-manifest.json"
    try:
        manifest = load_json(manifest_path)
        artifacts = manifest.get("artifacts")
        zip_artifact = (
            artifacts[0]
            if isinstance(artifacts, list)
            and artifacts
            and isinstance(artifacts[0], dict)
            else {}
        )
        expected_version = current_version
        release = manifest.get("release")
        manifest_matches = (
            isinstance(release, dict)
            and release.get("version") == expected_version
            and release.get("build") == version.get("OPENWHISPER_BUILD")
            and zip_artifact.get("kind") == "zip"
            and isinstance(zip_artifact.get("sha256"), str)
            and SHA256_PATTERN.fullmatch(zip_artifact["sha256"]) is not None
            and zip_artifact.get("sha256") != ZERO_SHA256
            and canonical_https(zip_artifact.get("downloadURL"))
        )
    except Exception:
        manifest_matches = False
        zip_artifact = {}
    audit.add(
        "commercial.cask-published-values",
        manifest_matches
        and f'version "{expected_version}"' in cask
        and f'sha256 "{zip_artifact.get("sha256", "")}"' in cask
        and f'url "{zip_artifact.get("downloadURL", "")}"' in cask
        and ZERO_SHA256 not in cask
        and "sha256 :no_check" not in cask,
        "Homebrew Cask contains the manifest version, URL, and exact nonzero SHA-256"
        if manifest_matches
        and f'version "{expected_version}"' in cask
        and f'sha256 "{zip_artifact.get("sha256", "")}"' in cask
        and f'url "{zip_artifact.get("downloadURL", "")}"' in cask
        and ZERO_SHA256 not in cask
        and "sha256 :no_check" not in cask
        else "Homebrew Cask does not match a valid final release manifest",
    )


def write_report(
    output: pathlib.Path | None,
    stage: str,
    phase: str,
    audit: Audit,
) -> None:
    report = {
        "schemaVersion": 1,
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "stage": stage,
        "phase": phase,
        "passed": audit.passed,
        "gates": [asdict(gate) for gate in audit.gates],
    }
    data = json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name(f".{output.name}.tmp")
        temporary.write_text(data, encoding="utf-8")
        temporary.chmod(0o600)
        temporary.replace(output)
    print(data, end="")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent.parent)
    parser.add_argument("--stage", choices=("source", "commercial"), default="source")
    parser.add_argument("--phase", choices=("prebuild", "final"), default="prebuild")
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()

    root = args.root.resolve()
    audit = Audit()
    product, version = audit_source(root, audit)

    if args.stage == "commercial":
        audit_operator(root, audit)
        audit_brand(root, audit, product.get("OPENWHISPER_APP_NAME", "OpenWhisper"))
        audit_metrics(root, audit)
        audit_environment(root, audit, args.phase)
        audit_git(
            root,
            audit,
            version.get("OPENWHISPER_VERSION", ""),
            require_tag=args.phase == "final",
        )
        if args.phase == "final":
            audit_acceptance(root, audit)
            audit_final_artifacts(root, audit, product, version)

    write_report(args.output, args.stage, args.phase, audit)
    return 0 if audit.passed else 1


if __name__ == "__main__":
    sys.exit(main())
