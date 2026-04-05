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


def make_change(tmp_path: Path, name: str, spec_content: str | None = None) -> Path:
    change_dir = tmp_path / "openspec" / "changes" / name
    change_dir.mkdir(parents=True)
    (change_dir / ".openspec.yaml").write_text("schema: spec-driven\ncreated: 2024-01-01\n")
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
    assert not (tmp_path / "openspec" / "changes" / "mychange").exists()
    assert (tmp_path / "openspec" / "changes" / "archive" / "mychange").exists()


def test_archive_skip_specs(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange", _SPEC_WITH_ADDED)
    rc = cmd_archive("mychange", yes=True, skip_specs=True)
    assert rc == 0
    specs_dir = tmp_path / "openspec" / "specs"
    assert not specs_dir.exists()


def test_archive_integrates_added_specs(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange", _SPEC_WITH_ADDED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    target = tmp_path / "openspec" / "specs" / "cap-a" / "spec.md"
    assert target.exists()
    content = target.read_text()
    assert "## Requirements" in content


def test_archive_integrates_removed_specs(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    # Create existing spec first
    existing = tmp_path / "openspec" / "specs" / "cap-a"
    existing.mkdir(parents=True)
    (existing / "spec.md").write_text("# old spec\n")
    make_change(tmp_path, "mychange", _SPEC_WITH_REMOVED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    assert not existing.exists()


def test_archive_missing_change(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "openspec" / "changes").mkdir(parents=True)
    rc = cmd_archive("ghost", yes=True)
    assert rc == 1


def test_archive_cancel(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange")
    monkeypatch.setattr("builtins.input", lambda _: "n")
    rc = cmd_archive("mychange")
    assert rc == 0
    assert (tmp_path / "openspec" / "changes" / "mychange").exists()
