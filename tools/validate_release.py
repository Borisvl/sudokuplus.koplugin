#!/usr/bin/env python3
"""Validate release metadata and extract exact changelog notes."""

from __future__ import annotations

import argparse
from datetime import date
from pathlib import Path
import re


STABLE_VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


def fail(message: str) -> None:
    raise SystemExit(f"release validation: {message}")


def validate_files(tag: str, metadata_path: Path, changelog_path: Path, notes_path: Path) -> None:
    if not tag.startswith("v") or not STABLE_VERSION.fullmatch(tag[1:]):
        fail("tag must match vX.Y.Z without leading zeros or suffixes")
    version = tag[1:]

    metadata = metadata_path.read_text(encoding="utf-8")
    names = re.findall(r'\bname\s*=\s*"([^"]+)"', metadata)
    versions = re.findall(r'\bversion\s*=\s*"([^"]+)"', metadata)
    if names != ["sudokuplus"]:
        fail("metadata name must appear exactly once and equal sudokuplus")
    if versions != [version]:
        fail("metadata version must appear exactly once and match the tag")

    changelog = changelog_path.read_text(encoding="utf-8")
    heading = re.compile(rf"^## \[{re.escape(version)}\] - (\d{{4}}-\d{{2}}-\d{{2}})$", re.MULTILINE)
    matches = list(heading.finditer(changelog))
    if len(matches) != 1:
        fail("changelog must contain exactly one dated section for the tag")
    try:
        date.fromisoformat(matches[0].group(1))
    except ValueError as error:
        fail(f"changelog release date is invalid: {error}")

    body_start = matches[0].end()
    next_heading = re.search(r"^## ", changelog[body_start:], re.MULTILINE)
    body_end = body_start + next_heading.start() if next_heading else len(changelog)
    notes = changelog[body_start:body_end].strip()
    if not notes:
        fail("changelog release section is empty")
    notes_path.write_text(notes + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("tag")
    parser.add_argument("metadata", type=Path)
    parser.add_argument("changelog", type=Path)
    parser.add_argument("notes", type=Path)
    args = parser.parse_args()
    validate_files(args.tag, args.metadata, args.changelog, args.notes)


if __name__ == "__main__":
    main()
