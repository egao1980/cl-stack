#!/usr/bin/env python3
"""Scan tests/corpus for disallowed licenses and missing PROVENANCE rows.

Exit 0 on clean corpus / successful --self-test. Exit 1 on policy violations.
See docs/LICENSE-POLICY.md (false-positive process).
"""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

ALLOWED_SPDX = frozenset(
    {
        "MIT",
        "BSD-2-Clause",
        "BSD-3-Clause",
        "Apache-2.0",
        "Unlicense",
        "0BSD",
        "CC0-1.0",
        "CC0",
    }
)

# Strong markers only — bare "GPL" is too noisy (policy docs, reject vectors).
LICENSE_MARKERS = (
    re.compile(r"(?i)SPDX-License-Identifier:\s*[^\n]*\b(?:AGPL|LGPL|GPL)\b"),
    re.compile(r"(?i)\bGNU\s+(?:Affero\s+|Lesser\s+)?General\s+Public\s+License\b"),
    re.compile(r"(?i)\b(?:AGPL|LGPL|GPL)-\d"),
    re.compile(r"(?i)^\s*License:\s*(?:AGPL|LGPL|GPL)\b", re.MULTILINE),
)

PROVENANCE_ROW = re.compile(
    r"^\|\s*`(?P<path>[^`]+)`\s*\|\s*(?P<source>[^|]*)\|\s*(?P<commit>[^|]*)\|\s*(?P<spdx>[^|]*)\|",
    re.MULTILINE,
)

META_NAMES = frozenset({"README.md", "PROVENANCE.md", "LICENSE-SCAN-EXCEPTIONS"})
TEXT_SUFFIXES = frozenset(
    {
        ".txt",
        ".lisp",
        ".json",
        ".md",
        ".yml",
        ".yaml",
        ".xml",
        ".html",
        ".csv",
        ".http",
        ".sh",
        ".py",
        ".c",
        ".h",
        ".rs",
        ".go",
        ".java",
    }
)


def corpus_root(repo: Path) -> Path:
    return repo / "tests" / "corpus"


def load_exceptions(root: Path) -> set[str]:
    path = root / "LICENSE-SCAN-EXCEPTIONS"
    if not path.is_file():
        return set()
    out: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        out.add(line.split("#", 1)[0].strip())
    return out


def parse_provenance(root: Path) -> dict[str, str]:
    path = root / "PROVENANCE.md"
    if not path.is_file():
        raise SystemExit(f"missing {path.relative_to(root.parent.parent)}")
    text = path.read_text(encoding="utf-8")
    rows: dict[str, str] = {}
    for m in PROVENANCE_ROW.finditer(text):
        rel = m.group("path").strip().lstrip("./")
        spdx = m.group("spdx").strip()
        if rel.lower() == "path":
            continue
        rows[rel] = spdx
    return rows


def iter_fixture_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        if p.name in META_NAMES and p.parent == root:
            continue
        if p.name == "LICENSE-SCAN-EXCEPTIONS":
            continue
        # Only fixtures under <domain>/<slice>/
        try:
            rel_parts = p.relative_to(root).parts
        except ValueError:
            continue
        if len(rel_parts) < 3:
            continue
        files.append(p)
    return files


def read_scan_text(path: Path) -> str | None:
    if path.suffix.lower() in TEXT_SUFFIXES or path.suffix == "":
        try:
            return path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            return f"<<unreadable: {exc}>>"
    # Binaries: scan first 8 KiB as latin-1 for embedded license strings.
    try:
        raw = path.read_bytes()[:8192]
    except OSError as exc:
        return f"<<unreadable: {exc}>>"
    return raw.decode("latin-1", errors="replace")


def check_markers(path: Path, text: str, exceptions: set[str], root: Path) -> list[str]:
    rel = path.relative_to(root).as_posix()
    if rel in exceptions:
        return []
    hits: list[str] = []
    for rx in LICENSE_MARKERS:
        if rx.search(text):
            hits.append(f"{rel}: disallowed license marker ({rx.pattern})")
            break
    return hits


def check_corpus(root: Path) -> list[str]:
    errors: list[str] = []
    exceptions = load_exceptions(root)
    provenance = parse_provenance(root)
    files = iter_fixture_files(root)

    if not files:
        errors.append("no fixture files under tests/corpus/<domain>/<slice>/")

    for rel, spdx in provenance.items():
        # Strip markdown italics / backticks noise
        spdx_tok = spdx.split()[0] if spdx else ""
        if spdx_tok and spdx_tok not in ALLOWED_SPDX:
            errors.append(f"PROVENANCE.md: {rel}: SPDX {spdx_tok!r} not on allowlist")

    for path in files:
        rel = path.relative_to(root).as_posix()
        if rel not in provenance:
            errors.append(f"{rel}: missing PROVENANCE.md row")
        text = read_scan_text(path)
        if text is not None:
            errors.extend(check_markers(path, text, exceptions, root))
    return errors


def write_tree(base: Path, files: dict[str, str]) -> None:
    for rel, body in files.items():
        p = base / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")


def self_test() -> int:
    """Deliberate bad fixtures must fail; clean tree must pass."""
    failures = 0

    def expect_fail(label: str, files: dict[str, str]) -> None:
        nonlocal failures
        with tempfile.TemporaryDirectory(prefix="corpus-lic-") as tmp:
            root = Path(tmp)
            write_tree(root, files)
            errs = check_corpus(root)
            if not errs:
                print(f"SELF-TEST FAIL ({label}): expected errors, got clean", file=sys.stderr)
                failures += 1
            else:
                print(f"SELF-TEST OK ({label}): {len(errs)} error(s) as expected")

    def expect_pass(label: str, files: dict[str, str]) -> None:
        nonlocal failures
        with tempfile.TemporaryDirectory(prefix="corpus-lic-") as tmp:
            root = Path(tmp)
            write_tree(root, files)
            errs = check_corpus(root)
            if errs:
                print(f"SELF-TEST FAIL ({label}): {errs}", file=sys.stderr)
                failures += 1
            else:
                print(f"SELF-TEST OK ({label})")

    provenance_hdr = (
        "# Corpus provenance\n\n"
        "| Path | Source URL | Commit/tag | SPDX | Notes |\n"
        "|------|------------|------------|------|-------|\n"
    )
    clean = {
        "PROVENANCE.md": (
            provenance_hdr
            + "| `http/demo/vectors.lisp` | _(original)_ | — | MIT | ok |\n"
        ),
        "http/demo/vectors.lisp": ";; MIT synthetic\n(:ok t)\n",
    }
    expect_pass("clean tree", clean)

    bad_gpl = dict(clean)
    bad_gpl["http/demo/vectors.lisp"] = (
        ";; SPDX-License-Identifier: GPL-3.0-only\n(:evil t)\n"
    )
    expect_fail("GPL SPDX marker", bad_gpl)

    missing = {
        "PROVENANCE.md": provenance_hdr
        + "| `http/demo/other.lisp` | _(original)_ | — | MIT | |\n",
        "http/demo/vectors.lisp": ";; orphan\n",
    }
    expect_fail("missing provenance row", missing)

    bad_spdx = {
        "PROVENANCE.md": (
            provenance_hdr
            + "| `http/demo/vectors.lisp` | upstream | v1 | GPL-3.0 | no |\n"
        ),
        "http/demo/vectors.lisp": ";; no marker in body\n",
    }
    expect_fail("PROVENANCE SPDX not allowlisted", bad_spdx)

    if failures:
        print(f"self-test: {failures} case(s) failed", file=sys.stderr)
        return 1
    print("self-test: all cases passed")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="corpus root (default: <repo>/tests/corpus)",
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="repository root",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run deliberate bad-fixture cases (must detect failures)",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    root = args.root if args.root is not None else corpus_root(args.repo.resolve())
    if not root.is_dir():
        print(f"error: corpus root missing: {root}", file=sys.stderr)
        return 1

    errors = check_corpus(root)
    if errors:
        print("corpus license check FAILED:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"corpus license check OK ({root})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
