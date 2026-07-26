#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ANSI_ESCAPE_PATTERN = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
SWIFT_TESTING_FAILURE_PATTERNS = (
    re.compile(
        r"^\s*(?:\S+\s+)?Test .+ recorded an issue at .+$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^\s*(?:\S+\s+)?(?:Test|Suite) .+ failed after .+ "
        r"with \d+ issues?\.?\s*$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^\s*(?:\S+\s+)?Test run with .+ failed after .+$",
        re.IGNORECASE,
    ),
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Fail closed when swift test reports Swift Testing issues even "
            "if the toolchain incorrectly exits with status zero."
        )
    )
    parser.add_argument(
        "--command-status",
        required=True,
        type=int,
        help="Exit status returned by the swift test process.",
    )
    parser.add_argument("log", type=Path, help="Captured swift test output.")
    return parser.parse_args()


def failure_lines(contents: str) -> list[str]:
    failures: list[str] = []
    for raw_line in contents.splitlines():
        line = ANSI_ESCAPE_PATTERN.sub("", raw_line)
        if any(pattern.match(line) for pattern in SWIFT_TESTING_FAILURE_PATTERNS):
            failures.append(line.strip())
    return failures


def main() -> int:
    arguments = parse_arguments()
    if arguments.command_status != 0:
        print(
            "swift test exited with status "
            f"{arguments.command_status}.",
            file=sys.stderr,
        )
        return 1

    try:
        contents = arguments.log.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        print(f"Could not read swift test log: {error}", file=sys.stderr)
        return 1

    failures = failure_lines(contents)
    if failures:
        print(
            "swift test output contains Swift Testing failure markers:",
            file=sys.stderr,
        )
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Swift test output verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
