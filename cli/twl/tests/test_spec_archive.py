"""Tests for src/twl/spec/archive.py"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.archive import cmd_archive

_SPEC_WITH_ADDED = """\
## ADDED Requirements

### Requirement: Foo
The system SHALL do foo.

#### Scenario: Basic
- **WHEN** x
- **THEN** y
"""

_SPEC_WITH_REMOVED = """\
## REMOVED Requirements
"""

_SPEC_WITH_MODIFIED = """\
## MODIFIED Requirements

### Requirement: Bar
The system SHALL do bar.
"""

_SPEC_WITH_ADDED_AND_MODIFIED = """\
## ADDED Requirements

### Requirement: Foo
The system SHALL do foo.

## MODIFIED Requirements

### Requirement: Bar
The system SHALL do bar.
"""


def make_change(tmp_path: Path, name: str, spec_content: str | None = None) -> Path:
    change_dir = tmp_path / "deltaspec" / "changes" / name
    change_dir.mkdir(parents=True)
    (change_dir / ".deltaspec.yaml").write_text("schema: spec-driven\ncreated: 2024-01-01\n")
    if spec_content:
        specs_dir = change_dir / "specs" / "cap-a"
        specs_dir.mkdir(parents=True)
        (specs_dir / "spec.md").write_text(spec_content)
    return change_dir


def test_archive_moves_directory(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange")
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    assert not (tmp_path / "deltaspec" / "changes" / "mychange").exists()
    assert (tmp_path / "deltaspec" / "changes" / "archive" / "mychange").exists()


def test_archive_skip_specs(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange", _SPEC_WITH_ADDED)
    rc = cmd_archive("mychange", yes=True, skip_specs=True)
    assert rc == 0
    specs_dir = tmp_path / "deltaspec" / "specs"
    assert not specs_dir.exists()


def test_archive_integrates_added_specs(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange", _SPEC_WITH_ADDED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    target = tmp_path / "deltaspec" / "specs" / "cap-a" / "spec.md"
    assert target.exists()
    content = target.read_text()
    assert "## Requirements" in content


def test_archive_integrates_removed_specs(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    # Create existing spec first
    existing = tmp_path / "deltaspec" / "specs" / "cap-a"
    existing.mkdir(parents=True)
    (existing / "spec.md").write_text("# old spec\n")
    make_change(tmp_path, "mychange", _SPEC_WITH_REMOVED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    assert not existing.exists()


def test_archive_missing_change(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "deltaspec" / "changes").mkdir(parents=True)
    rc = cmd_archive("ghost", yes=True)
    assert rc == 1


def test_archive_modified_appends_to_existing(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    # Create existing spec first
    existing_dir = tmp_path / "deltaspec" / "specs" / "cap-a"
    existing_dir.mkdir(parents=True)
    (existing_dir / "spec.md").write_text("## Requirements\n\n### Requirement: Existing\nOld content.\n")
    make_change(tmp_path, "mychange", _SPEC_WITH_MODIFIED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    content = (existing_dir / "spec.md").read_text()
    assert "Old content." in content
    assert "The system SHALL do bar." in content


def test_archive_added_and_modified_both_reflected(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange", _SPEC_WITH_ADDED_AND_MODIFIED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    target = tmp_path / "deltaspec" / "specs" / "cap-a" / "spec.md"
    assert target.exists()
    content = target.read_text()
    assert "The system SHALL do foo." in content
    assert "The system SHALL do bar." in content


def test_archive_cancel(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange")
    monkeypatch.setattr("builtins.input", lambda _: "n")
    rc = cmd_archive("mychange")
    assert rc == 0
    assert (tmp_path / "deltaspec" / "changes" / "mychange").exists()
