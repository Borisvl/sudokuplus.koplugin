#!/usr/bin/env python3
"""Verify the exact structure and generated contents of a Sudoku+ release ZIP."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
import zipfile


PLUGIN_ROOT = "sudokuplus.koplugin"
LEGAL_FILES = {"LICENSE", "COPYING.GPL-3.0", "THIRD_PARTY_NOTICES"}
CANONICAL_LICENSE_HASHES = {
    "LICENSE": "57c8ff33c9c0cfc3ef00e650a1cc910d7ee479a8bc509f6c9209a7c2a11399d6",
    "COPYING.GPL-3.0": "8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903",
    "COPYING.FDL-1.3": "d024962f1f4966c102b40d9fd9cc834a3f0b3c1397b41444b7cd7925640dc929",
}


def fail(message: str) -> None:
    raise SystemExit(f"release package: {message}")


def expected_files(source_root: Path) -> set[str]:
    result = subprocess.run(
        ["git", "-C", str(source_root), "ls-files", "-z", PLUGIN_ROOT],
        check=True,
        capture_output=True,
    )
    paths = {path.decode() for path in result.stdout.split(b"\0") if path}
    paths.update(f"{PLUGIN_ROOT}/{name}" for name in LEGAL_FILES)
    return paths


def safe_name(name: str) -> bool:
    path = PurePosixPath(name)
    return (
        name != ""
        and "\\" not in name
        and not name.startswith("/")
        and path.parts
        and path.parts[0] == PLUGIN_ROOT
        and ".." not in path.parts
        and "." not in path.parts
    )


def verify_translations(archive: zipfile.ZipFile, names: set[str], msgfmt: str) -> None:
    po_names = sorted(name for name in names if name.endswith(".po"))
    for po_name in po_names:
        mo_name = po_name[:-3] + ".mo"
        if mo_name not in names:
            fail(f"missing compiled translation {mo_name}")
        with tempfile.TemporaryDirectory(prefix="sudoku-msgfmt-") as temp_dir:
            po_path = Path(temp_dir, "catalog.po")
            mo_path = Path(temp_dir, "catalog.mo")
            po_path.write_bytes(archive.read(po_name))
            subprocess.run(
                [msgfmt, "--check", f"--output-file={mo_path}", str(po_path)],
                check=True,
                capture_output=True,
            )
            if mo_path.read_bytes() != archive.read(mo_name):
                fail(f"compiled translation is stale: {mo_name}")


def verify(args: argparse.Namespace) -> None:
    archive_path = Path(args.archive).resolve()
    source_root = Path(args.source_root).resolve()
    if not archive_path.is_file():
        fail(f"archive does not exist: {archive_path}")
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", args.expected_version):
        fail("expected version is not a stable semantic version")
    for filename, expected_hash in CANONICAL_LICENSE_HASHES.items():
        path = source_root / filename
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected_hash:
            fail(f"{filename} is not the pinned canonical license text")

    with zipfile.ZipFile(archive_path) as archive:
        infos = archive.infolist()
        raw_names = [info.filename for info in infos]
        if len(raw_names) != len(set(raw_names)):
            fail("archive contains duplicate member names")
        if archive.testzip() is not None:
            fail("archive CRC verification failed")
        for info in infos:
            if not safe_name(info.filename):
                fail(f"unsafe archive member: {info.filename}")
            mode = (info.external_attr >> 16) & 0xFFFF
            if mode and not stat.S_ISREG(mode):
                fail(f"archive member is not a regular file: {info.filename}")
            if info.is_dir():
                fail(f"archive contains an unexpected directory entry: {info.filename}")

        names = set(raw_names)
        expected = expected_files(source_root)
        if names != expected:
            missing = sorted(expected - names)
            extra = sorted(names - expected)
            fail(f"archive manifest mismatch; missing={missing}, extra={extra}")

        for name in names:
            relative = name.removeprefix(f"{PLUGIN_ROOT}/")
            source_path = source_root / (relative if relative in LEGAL_FILES else name)
            if source_path.is_symlink() or not source_path.is_file():
                fail(f"package source is not a regular file: {source_path}")
            if archive.read(name) != source_path.read_bytes():
                fail(f"packaged {name} differs from its repository source")

        entrypoint = archive.read(f"{PLUGIN_ROOT}/_meta.lua").decode("utf-8")
        if 'require("sudokuplus.metadata")' not in entrypoint:
            fail("root metadata entrypoint must use sudokuplus.metadata")
        metadata = archive.read(f"{PLUGIN_ROOT}/sudokuplus/metadata.lua").decode("utf-8")
        name_matches = re.findall(r'\bname\s*=\s*"([^"]+)"', metadata)
        version_matches = re.findall(r'\bversion\s*=\s*"([^"]+)"', metadata)
        if name_matches != ["sudokuplus"]:
            fail("metadata plugin name must be sudokuplus")
        if version_matches != [args.expected_version]:
            fail("metadata version does not match expected version")

        license_text = archive.read(f"{PLUGIN_ROOT}/LICENSE").decode("utf-8")
        notices = archive.read(f"{PLUGIN_ROOT}/THIRD_PARTY_NOTICES").decode("utf-8")
        gpl_text = archive.read(f"{PLUGIN_ROOT}/COPYING.GPL-3.0").decode("utf-8")
        if "GNU AFFERO GENERAL PUBLIC LICENSE" not in license_text or "Remote Network Interaction" not in license_text:
            fail("LICENSE is not the complete AGPLv3 text")
        if "Copyright (c) 2025 Samuel Huang" not in notices or "HoDoKu" not in notices:
            fail("third-party notices are incomplete")
        if "GNU GENERAL PUBLIC LICENSE" not in gpl_text or "Use with the GNU Affero" not in gpl_text:
            fail("COPYING.GPL-3.0 is not the complete GPLv3 text")

        forbidden_suffixes = (".bak", ".log", ".swp", ".tmp", "~")
        for name in names:
            if name.endswith(forbidden_suffixes) or "/.DS_Store" in name:
                fail(f"temporary file present in archive: {name}")

        verify_translations(archive, names, args.msgfmt)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--msgfmt", default=os.environ.get("MSGFMT", "msgfmt"))
    verify(parser.parse_args())


if __name__ == "__main__":
    main()
