#!/usr/bin/env python3
"""Validate and aggregate privacy-bounded Community Pilot evidence.

The input schemas intentionally contain only enums, buckets, and random cohort
codes. The generated report never includes row-level evidence or cohort codes.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import stat
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = 1
MAX_INPUT_BYTES = 5_000_000

PARTICIPANT_FIELDS = (
    "cohort_code",
    "consent_status",
    "target_segment",
    "enrollment_status",
    "author_outcome",
    "creator_first_success_duration",
)

OBSERVATION_FIELDS = (
    "cohort_code",
    "study_week",
    "run_kind",
    "task_category",
    "skill_source",
    "resolution",
    "selection_identity_match",
    "switcher_duration",
    "first_use_duration",
    "result_available",
    "result_action",
    "result_edited",
    "validator_outcome",
    "target_outcome",
    "failure_class",
)

INCIDENT_FIELDS = (
    "incident_code",
    "study_week",
    "severity",
    "incident_class",
    "status",
)

COHORT_CODE_PATTERN = re.compile(r"^P-[A-Z0-9]{6,12}$")
INCIDENT_CODE_PATTERN = re.compile(r"^I-[A-Z0-9]{6,12}$")

PARTICIPANT_VALUES = {
    "consent_status": {"yes", "no"},
    "target_segment": {
        "developer",
        "knowledge-worker",
        "community-author",
    },
    "enrollment_status": {
        "invited",
        "consented",
        "active",
        "withdrawn",
        "completed",
    },
    "author_outcome": {
        "not_attempted",
        "started",
        "qualified",
        "failed_quality_gate",
    },
    "creator_first_success_duration": {
        "under_5m",
        "5_to_15m",
        "15_to_30m",
        "over_30m",
        "not_attempted",
        "not_completed",
    },
}

OBSERVATION_VALUES = {
    "study_week": {"W0", "W1", "W2", "W3", "W4"},
    "run_kind": {"direct", "non-direct"},
    "task_category": {
        "dictation",
        "developer",
        "communication",
        "rewrite",
        "professional-template",
    },
    "skill_source": {"built-in", "curated", "local-created", "imported"},
    "resolution": {"next-run", "app-default", "global-default", "safe-fallback"},
    "selection_identity_match": {"yes", "no", "not-applicable"},
    "switcher_duration": {
        "under_1s",
        "1_to_3s",
        "3_to_10s",
        "over_10s",
        "not_used",
    },
    "first_use_duration": {
        "under_3m",
        "3_to_5m",
        "5_to_10m",
        "over_10m",
        "not_achieved",
        "not_first_use",
    },
    "result_available": {"yes", "no"},
    "result_action": {"replace", "paste", "copy", "cancel"},
    "result_edited": {"yes", "no", "not-applicable"},
    "validator_outcome": {"passed", "fallback", "not-run"},
    "target_outcome": {
        "verified",
        "paste-dispatched",
        "copy-only",
        "not-applicable",
    },
    "failure_class": {
        "none",
        "wrong-skill",
        "context",
        "validator",
        "target",
        "provider",
        "usability",
    },
}

INCIDENT_VALUES = {
    "study_week": {"W0", "W1", "W2", "W3", "W4"},
    "severity": {"critical", "high", "medium", "low"},
    "incident_class": {
        "private-content",
        "executable-skill",
        "unauthorized-context",
        "wrong-target",
        "credential",
        "provider",
        "usability",
    },
    "status": {"open", "mitigated", "closed"},
}

SWITCHER_ORDER = ("under_1s", "1_to_3s", "3_to_10s", "over_10s")
FIRST_USE_ORDER = (
    "under_3m",
    "3_to_5m",
    "5_to_10m",
    "over_10m",
    "not_achieved",
)
CREATOR_ORDER = ("under_5m", "5_to_15m", "15_to_30m", "over_30m")
APPLIED_ACTIONS = {"replace", "paste", "copy"}


class PilotDataError(ValueError):
    """Raised when Pilot evidence violates the bounded schema."""


def _validate_input_file(path: Path) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise PilotDataError(f"missing input file: {path}") from error

    if stat.S_ISLNK(metadata.st_mode):
        raise PilotDataError(f"symbolic-link input is not allowed: {path}")
    if not stat.S_ISREG(metadata.st_mode):
        raise PilotDataError(f"input must be a regular file: {path}")
    if metadata.st_size > MAX_INPUT_BYTES:
        raise PilotDataError(f"input exceeds {MAX_INPUT_BYTES} bytes: {path}")


def _read_csv(path: Path, expected_fields: tuple[str, ...]) -> list[dict[str, str]]:
    _validate_input_file(path)
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        actual_fields = tuple(reader.fieldnames or ())
        if actual_fields != expected_fields:
            raise PilotDataError(
                f"{path.name} has fields {actual_fields}; expected {expected_fields}"
            )

        rows: list[dict[str, str]] = []
        for row_number, raw_row in enumerate(reader, start=2):
            if None in raw_row:
                raise PilotDataError(f"{path.name}:{row_number} has extra columns")
            row = {
                field: (raw_row.get(field) or "").strip()
                for field in expected_fields
            }
            if not any(row.values()):
                continue
            missing = [field for field, value in row.items() if not value]
            if missing:
                raise PilotDataError(
                    f"{path.name}:{row_number} has empty fields: {', '.join(missing)}"
                )
            rows.append(row)
        return rows


def _require_allowed_values(
    rows: Iterable[dict[str, str]],
    allowed: dict[str, set[str]],
    source_name: str,
) -> None:
    for row_number, row in enumerate(rows, start=2):
        for field, values in allowed.items():
            if row[field] not in values:
                raise PilotDataError(
                    f"{source_name}:{row_number} has invalid {field}: {row[field]}"
                )


def _validate_participants(rows: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    _require_allowed_values(rows, PARTICIPANT_VALUES, "participants")
    participants: dict[str, dict[str, str]] = {}
    for row_number, row in enumerate(rows, start=2):
        code = row["cohort_code"]
        if not COHORT_CODE_PATTERN.fullmatch(code):
            raise PilotDataError(
                f"participants:{row_number} has invalid random cohort code"
            )
        if code in participants:
            raise PilotDataError(f"participants:{row_number} duplicates a cohort code")
        if row["consent_status"] == "no" and row["enrollment_status"] in {
            "consented",
            "active",
            "completed",
        }:
            raise PilotDataError(
                f"participants:{row_number} marks a non-consenting participant active"
            )
        if row["consent_status"] == "yes" and row["enrollment_status"] == "invited":
            raise PilotDataError(
                f"participants:{row_number} has consent but remains only invited"
            )
        if row["author_outcome"] == "qualified" and row[
            "creator_first_success_duration"
        ] not in CREATOR_ORDER:
            raise PilotDataError(
                f"participants:{row_number} lacks a bounded Creator success duration"
            )
        if row["author_outcome"] == "not_attempted" and row[
            "creator_first_success_duration"
        ] != "not_attempted":
            raise PilotDataError(
                f"participants:{row_number} has Creator timing without an attempt"
            )
        participants[code] = row
    return participants


def _validate_observations(
    rows: list[dict[str, str]],
    participants: dict[str, dict[str, str]],
) -> None:
    _require_allowed_values(rows, OBSERVATION_VALUES, "observations")
    first_use_codes: set[str] = set()
    for row_number, row in enumerate(rows, start=2):
        participant = participants.get(row["cohort_code"])
        if participant is None:
            raise PilotDataError(
                f"observations:{row_number} references an unknown cohort code"
            )
        if participant["consent_status"] != "yes":
            raise PilotDataError(
                f"observations:{row_number} records a participant without consent"
            )
        if row["run_kind"] == "direct":
            if row["selection_identity_match"] != "not-applicable":
                raise PilotDataError(
                    f"observations:{row_number} gives Direct a Skill identity result"
                )
        elif row["selection_identity_match"] == "not-applicable":
            raise PilotDataError(
                f"observations:{row_number} omits non-Direct identity verification"
            )

        if row["result_available"] == "no":
            if row["result_action"] != "cancel":
                raise PilotDataError(
                    f"observations:{row_number} applies a missing result"
                )
            if row["result_edited"] != "not-applicable":
                raise PilotDataError(
                    f"observations:{row_number} edits a missing result"
                )
            if row["validator_outcome"] != "not-run":
                raise PilotDataError(
                    f"observations:{row_number} validates a missing result"
                )
            if row["target_outcome"] != "not-applicable":
                raise PilotDataError(
                    f"observations:{row_number} records delivery for a missing result"
                )
        else:
            if row["result_edited"] == "not-applicable":
                raise PilotDataError(
                    f"observations:{row_number} omits the Preview edit outcome"
                )
            if row["validator_outcome"] == "not-run":
                raise PilotDataError(
                    f"observations:{row_number} omits Validator outcome"
                )

        action = row["result_action"]
        target = row["target_outcome"]
        if action == "cancel" and target != "not-applicable":
            raise PilotDataError(
                f"observations:{row_number} delivers a cancelled result"
            )
        if action == "copy" and target != "copy-only":
            raise PilotDataError(
                f"observations:{row_number} must classify Copy as copy-only"
            )
        if action == "replace" and target != "verified":
            raise PilotDataError(
                f"observations:{row_number} records an unverified replacement"
            )
        if action == "paste" and target not in {"verified", "paste-dispatched"}:
            raise PilotDataError(
                f"observations:{row_number} has an invalid Paste target outcome"
            )

        if row["first_use_duration"] != "not_first_use":
            code = row["cohort_code"]
            if code in first_use_codes:
                raise PilotDataError(
                    f"observations:{row_number} duplicates a first-use outcome"
                )
            first_use_codes.add(code)
            if (
                row["first_use_duration"] == "not_achieved"
                and row["result_action"] != "cancel"
            ):
                raise PilotDataError(
                    f"observations:{row_number} applies a first use marked not achieved"
                )


def _validate_incidents(rows: list[dict[str, str]]) -> None:
    _require_allowed_values(rows, INCIDENT_VALUES, "incidents")
    seen: set[str] = set()
    for row_number, row in enumerate(rows, start=2):
        code = row["incident_code"]
        if not INCIDENT_CODE_PATTERN.fullmatch(code):
            raise PilotDataError(f"incidents:{row_number} has invalid incident code")
        if code in seen:
            raise PilotDataError(f"incidents:{row_number} duplicates an incident code")
        seen.add(code)


def _rate(numerator: int, denominator: int) -> float | None:
    if denominator <= 0:
        return None
    return round(numerator / denominator, 4)


def _gate(value: object, target: str, passed: bool) -> dict[str, object]:
    return {"value": value, "target": target, "passed": passed}


def _upper_median_label(
    values: Iterable[str],
    order: tuple[str, ...],
) -> tuple[str | None, int | None]:
    index_by_value = {value: index for index, value in enumerate(order)}
    indexes = sorted(index_by_value[value] for value in values if value in index_by_value)
    if not indexes:
        return None, None
    index = indexes[len(indexes) // 2]
    return order[index], index


def _is_successful_non_direct(row: dict[str, str]) -> bool:
    return (
        row["run_kind"] == "non-direct"
        and row["result_available"] == "yes"
        and row["result_action"] in APPLIED_ACTIONS
        and row["failure_class"] == "none"
    )


def evaluate_pilot(
    participant_rows: list[dict[str, str]],
    observation_rows: list[dict[str, str]],
    incident_rows: list[dict[str, str]],
) -> dict[str, object]:
    participants = _validate_participants(participant_rows)
    _validate_observations(observation_rows, participants)
    _validate_incidents(incident_rows)

    consented = {
        code: row
        for code, row in participants.items()
        if row["consent_status"] == "yes"
    }
    consented_count = len(consented)
    non_direct = [row for row in observation_rows if row["run_kind"] == "non-direct"]
    successful_non_direct = [row for row in non_direct if _is_successful_non_direct(row)]

    week_successes: dict[str, Counter[str]] = defaultdict(Counter)
    for row in successful_non_direct:
        week_successes[row["study_week"]][row["cohort_code"]] += 1

    week1_valid = len(week_successes["W1"])
    week1_effective = sum(count >= 3 for count in week_successes["W1"].values())
    week4_effective = sum(count >= 3 for count in week_successes["W4"].values())
    week1_retention = _rate(week1_effective, consented_count)
    week4_retention = _rate(week4_effective, consented_count)

    qualified_authors = [
        row for row in consented.values() if row["author_outcome"] == "qualified"
    ]
    creator_median, creator_median_index = _upper_median_label(
        (row["creator_first_success_duration"] for row in qualified_authors),
        CREATOR_ORDER,
    )

    available_results = [
        row for row in non_direct if row["result_available"] == "yes"
    ]
    applied_results = [
        row for row in available_results if row["result_action"] in APPLIED_ACTIONS
    ]
    application_rate = _rate(len(applied_results), len(available_results))
    wrong_skill_rate = _rate(
        sum(row["failure_class"] == "wrong-skill" for row in non_direct),
        len(non_direct),
    )

    curated_validator_rows = [
        row
        for row in non_direct
        if row["skill_source"] in {"built-in", "curated"}
        and row["validator_outcome"] in {"passed", "fallback"}
    ]
    fallback_rate = _rate(
        sum(row["validator_outcome"] == "fallback" for row in curated_validator_rows),
        len(curated_validator_rows),
    )

    identity_rows = [
        row
        for row in non_direct
        if row["selection_identity_match"] in {"yes", "no"}
    ]
    identity_rate = _rate(
        sum(row["selection_identity_match"] == "yes" for row in identity_rows),
        len(identity_rows),
    )

    preview_cancel_rate = _rate(
        sum(row["result_action"] == "cancel" for row in available_results),
        len(available_results),
    )
    preview_edit_rate = _rate(
        sum(row["result_edited"] == "yes" for row in available_results),
        len(available_results),
    )
    target_failure_rate = _rate(
        sum(row["failure_class"] == "target" for row in non_direct),
        len(non_direct),
    )

    switcher_median, switcher_median_index = _upper_median_label(
        (row["switcher_duration"] for row in non_direct),
        SWITCHER_ORDER,
    )
    first_use_rows = [
        row
        for row in non_direct
        if row["first_use_duration"] != "not_first_use"
    ]
    first_use_codes = {row["cohort_code"] for row in first_use_rows}
    first_use_median, first_use_median_index = _upper_median_label(
        (row["first_use_duration"] for row in first_use_rows),
        FIRST_USE_ORDER,
    )

    critical_incidents = sum(
        row["severity"] == "critical" for row in incident_rows
    )
    non_built_in_users = {
        row["cohort_code"]
        for row in successful_non_direct
        if row["skill_source"] != "built-in"
    }
    non_built_in_adoption = _rate(len(non_built_in_users), consented_count)

    pilot_exit_gates = {
        "participant_count": _gate(
            consented_count,
            "30–50 consented participants",
            30 <= consented_count <= 50,
        ),
        "week1_valid_participants": _gate(
            week1_valid,
            "at least 20 with a valid W1 non-Direct application",
            week1_valid >= 20,
        ),
        "non_direct_runs": _gate(
            len(non_direct),
            "at least 300",
            len(non_direct) >= 300,
        ),
        "qualified_external_authors": _gate(
            len(qualified_authors),
            "at least 5",
            len(qualified_authors) >= 5,
        ),
        "final_application_rate": _gate(
            application_rate,
            "at least 0.70",
            application_rate is not None and application_rate >= 0.70,
        ),
        "wrong_skill_rate": _gate(
            wrong_skill_rate,
            "at most 0.03",
            wrong_skill_rate is not None and wrong_skill_rate <= 0.03,
        ),
        "curated_validator_fallback_rate": _gate(
            fallback_rate,
            "at most 0.05",
            fallback_rate is not None and fallback_rate <= 0.05,
        ),
        "selection_identity_success_rate": _gate(
            identity_rate,
            "at least 0.97",
            identity_rate is not None and identity_rate >= 0.97,
        ),
        "preview_cancel_rate": _gate(
            preview_cancel_rate,
            "at most 0.20",
            preview_cancel_rate is not None and preview_cancel_rate <= 0.20,
        ),
        "switcher_upper_median": _gate(
            switcher_median,
            "1_to_3s or faster",
            switcher_median_index is not None and switcher_median_index <= 1,
        ),
        "first_use_upper_median": _gate(
            first_use_median,
            "3_to_5m or faster",
            first_use_median_index is not None and first_use_median_index <= 1,
        ),
        "first_use_coverage": _gate(
            len(first_use_codes),
            "exactly one first-use outcome per consented participant",
            consented_count > 0 and len(first_use_codes) == consented_count,
        ),
        "creator_upper_median": _gate(
            creator_median,
            "5_to_15m or faster",
            creator_median_index is not None and creator_median_index <= 1,
        ),
        "week1_effective_retention": _gate(
            week1_retention,
            "at least 0.40",
            week1_retention is not None and week1_retention >= 0.40,
        ),
        "week4_effective_retention": _gate(
            week4_retention,
            "at least 0.20",
            week4_retention is not None and week4_retention >= 0.20,
        ),
        "critical_incidents": _gate(
            critical_incidents,
            "exactly 0",
            critical_incidents == 0,
        ),
    }
    automated_gates_passed = all(
        bool(gate["passed"]) for gate in pilot_exit_gates.values()
    )

    if not observation_rows:
        status = "not_started"
    elif automated_gates_passed:
        status = "automated_gates_passed_manual_review_required"
    else:
        status = "continue_pilot"

    return {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "status": status,
        "automatedPilotExitGatesPassed": automated_gates_passed,
        "inputCounts": {
            "participantRows": len(participant_rows),
            "consentedParticipants": consented_count,
            "observationRows": len(observation_rows),
            "incidentRows": len(incident_rows),
        },
        "pilotExitGates": pilot_exit_gates,
        "observationMetrics": {
            "previewEditRate": preview_edit_rate,
            "targetFailureRate": target_failure_rate,
            "taskCategoryCounts": dict(
                sorted(Counter(row["task_category"] for row in non_direct).items())
            ),
            "resultActionCounts": dict(
                sorted(Counter(row["result_action"] for row in non_direct).items())
            ),
            "failureClassCounts": dict(
                sorted(Counter(row["failure_class"] for row in non_direct).items())
            ),
        },
        "registrySignals": {
            "nonBuiltInAdoptionRate": {
                "value": non_built_in_adoption,
                "goThreshold": 0.25,
                "thresholdMet": (
                    non_built_in_adoption is not None
                    and non_built_in_adoption >= 0.25
                ),
            },
            "qualifiedExternalAuthors": len(qualified_authors),
            "criticalIncidents": critical_incidents,
            "decision": "product_owner_review_required",
        },
        "manualReviewRequired": [
            "core scenario sample sufficiency",
            "W4 use is not dominated by one built-in Skill",
            "uninstall and disable reasons",
            "interview interpretation of edits, cancellations, and trust",
            "moderation, maintenance, and Registry ownership",
        ],
        "privacy": {
            "rowLevelEvidenceIncluded": False,
            "cohortCodesIncluded": False,
            "contentFieldsAccepted": False,
            "inputSchemasAreEnumAndBucketOnly": True,
        },
    }


def _write_csv(path: Path, fields: tuple[str, ...], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="vibecompose-community-pilot-") as directory:
        root = Path(directory)
        participant_path = root / "participants.csv"
        observation_path = root / "observations.csv"
        incident_path = root / "incidents.csv"

        participant_rows: list[dict[str, str]] = []
        observation_rows: list[dict[str, str]] = []
        categories = tuple(sorted(OBSERVATION_VALUES["task_category"]))
        for participant_index in range(30):
            code = f"P-{participant_index:06d}"
            is_author = participant_index < 5
            participant_rows.append(
                {
                    "cohort_code": code,
                    "consent_status": "yes",
                    "target_segment": (
                        "community-author" if is_author else "developer"
                    ),
                    "enrollment_status": "active",
                    "author_outcome": "qualified" if is_author else "not_attempted",
                    "creator_first_success_duration": (
                        "5_to_15m" if is_author else "not_attempted"
                    ),
                }
            )
            for run_index in range(10):
                observation_rows.append(
                    {
                        "cohort_code": code,
                        "study_week": "W1" if run_index < 5 else "W4",
                        "run_kind": "non-direct",
                        "task_category": categories[run_index % len(categories)],
                        "skill_source": (
                            "local-created" if run_index == 0 else "built-in"
                        ),
                        "resolution": "next-run",
                        "selection_identity_match": "yes",
                        "switcher_duration": "1_to_3s",
                        "first_use_duration": (
                            "under_3m" if run_index == 0 else "not_first_use"
                        ),
                        "result_available": "yes",
                        "result_action": "paste",
                        "result_edited": "no",
                        "validator_outcome": "passed",
                        "target_outcome": "paste-dispatched",
                        "failure_class": "none",
                    }
                )

        _write_csv(participant_path, PARTICIPANT_FIELDS, participant_rows)
        _write_csv(observation_path, OBSERVATION_FIELDS, observation_rows)
        _write_csv(incident_path, INCIDENT_FIELDS, [])

        participants = _read_csv(participant_path, PARTICIPANT_FIELDS)
        observations = _read_csv(observation_path, OBSERVATION_FIELDS)
        incidents = _read_csv(incident_path, INCIDENT_FIELDS)
        passing = evaluate_pilot(participants, observations, incidents)
        if not passing["automatedPilotExitGatesPassed"]:
            raise AssertionError("valid aggregate fixture did not pass automated gates")
        if passing["privacy"]["cohortCodesIncluded"]:
            raise AssertionError("aggregate report leaked cohort codes")

        _write_csv(
            incident_path,
            INCIDENT_FIELDS,
            [
                {
                    "incident_code": "I-000001",
                    "study_week": "W2",
                    "severity": "critical",
                    "incident_class": "wrong-target",
                    "status": "closed",
                }
            ],
        )
        blocked = evaluate_pilot(
            participants,
            observations,
            _read_csv(incident_path, INCIDENT_FIELDS),
        )
        if blocked["automatedPilotExitGatesPassed"]:
            raise AssertionError("critical incident did not block Pilot exit")

        invalid_path = root / "invalid.csv"
        invalid_path.write_text("email,transcript_text\nuser@example.com,secret\n")
        try:
            _read_csv(invalid_path, OBSERVATION_FIELDS)
        except PilotDataError:
            pass
        else:
            raise AssertionError("content-bearing schema was accepted")

    print("Community Pilot summarizer self-test passed.")


def _write_report(path: Path, report_text: str) -> None:
    if path.exists():
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or stat.S_ISDIR(metadata.st_mode):
            raise PilotDataError(f"unsafe output destination: {path}")
    parent = path.parent
    if not parent.is_dir() or parent.is_symlink():
        raise PilotDataError(f"output parent must be a regular directory: {parent}")

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".vibecompose-community-pilot-",
        suffix=".json",
        dir=parent,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(report_text)
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate and aggregate privacy-bounded Community Pilot CSV files."
    )
    parser.add_argument("--participants", type=Path)
    parser.add_argument("--observations", type=Path)
    parser.add_argument("--incidents", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.self_test:
            self_test()
            return 0

        missing = [
            name
            for name in ("participants", "observations", "incidents")
            if getattr(arguments, name) is None
        ]
        if missing:
            raise PilotDataError(
                "missing required arguments: "
                + ", ".join(f"--{name}" for name in missing)
            )

        participant_rows = _read_csv(arguments.participants, PARTICIPANT_FIELDS)
        observation_rows = _read_csv(arguments.observations, OBSERVATION_FIELDS)
        incident_rows = _read_csv(arguments.incidents, INCIDENT_FIELDS)
        report = evaluate_pilot(
            participant_rows,
            observation_rows,
            incident_rows,
        )
        report_text = json.dumps(
            report,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ) + "\n"
        if arguments.output is None:
            sys.stdout.write(report_text)
        else:
            _write_report(arguments.output, report_text)
        return 0
    except (OSError, PilotDataError) as error:
        print(f"Community Pilot evidence error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
