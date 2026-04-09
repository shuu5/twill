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

_SPEC_WITH_MODIFIED = """\
## MODIFIED Requirements

### Requirement: Foo
The system SHALL do foo updated.

#### Scenario: Basic
- **WHEN** x
- **THEN** y updated
"""

_SPEC_WITH_REMOVED = """\
## REMOVED Requirements
"""

_SPEC_WITH_MODIFIED_BAR = """\
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


def make_change_flat(tmp_path: Path, name: str, spec_content: str | None = None, cap_name: str = "cap-a") -> Path:
    """Create a change with flat spec format (cap-a.md instead of cap-a/spec.md)."""
    change_dir = tmp_path / "deltaspec" / "changes" / name
    change_dir.mkdir(parents=True)
    (change_dir / ".deltaspec.yaml").write_text("schema: spec-driven\ncreated: 2024-01-01\n")
    if spec_content:
        specs_dir = change_dir / "specs"
        specs_dir.mkdir(parents=True)
        (specs_dir / f"{cap_name}.md").write_text(spec_content)
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
    # New baseline specs are created as flat files (consistent with existing baselines)
    flat_target = tmp_path / "deltaspec" / "specs" / "cap-a.md"
    assert flat_target.exists()
    content = flat_target.read_text()
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
    assert "The system SHALL do foo updated." in content


def test_archive_added_and_modified_both_reflected(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange", _SPEC_WITH_ADDED_AND_MODIFIED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    # New specs default to flat format since #247
    target = tmp_path / "deltaspec" / "specs" / "cap-a.md"
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


# --- Flat spec format tests ---


def test_archive_flat_added_creates_flat_spec(tmp_path, monkeypatch, capsys):
    """Flat change spec (cap-a.md) with ADDED creates flat baseline spec."""
    monkeypatch.chdir(tmp_path)
    make_change_flat(tmp_path, "mychange", _SPEC_WITH_ADDED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    flat_target = tmp_path / "deltaspec" / "specs" / "cap-a.md"
    assert flat_target.exists(), "Flat baseline spec should be created"
    content = flat_target.read_text()
    assert "## Requirements" in content
    assert "## ADDED Requirements" not in content


def test_archive_flat_added_appends_to_existing_flat_spec(tmp_path, monkeypatch, capsys):
    """Flat change spec with ADDED appends to existing flat baseline spec."""
    monkeypatch.chdir(tmp_path)
    existing = tmp_path / "deltaspec" / "specs" / "cap-a.md"
    existing.parent.mkdir(parents=True)
    existing.write_text("## Requirements\n\n### Requirement: Old\nOld SHALL exist.\n")
    make_change_flat(tmp_path, "mychange", _SPEC_WITH_ADDED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    content = existing.read_text()
    assert "Old SHALL exist." in content
    assert "SHALL do foo" in content


def test_archive_flat_modified_applies_to_existing_flat_spec(tmp_path, monkeypatch, capsys):
    """Flat change spec with MODIFIED appends to existing flat baseline spec."""
    monkeypatch.chdir(tmp_path)
    existing = tmp_path / "deltaspec" / "specs" / "cap-a.md"
    existing.parent.mkdir(parents=True)
    existing.write_text("## Requirements\n\n### Requirement: Old\nOld SHALL exist.\n")
    make_change_flat(tmp_path, "mychange", _SPEC_WITH_MODIFIED_BAR)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    content = existing.read_text()
    assert "Old SHALL exist." in content  # existing content preserved (#248)
    assert "The system SHALL do bar." in content  # modified content appended


def test_archive_flat_modified_warns_when_no_baseline(tmp_path, monkeypatch, capsys):
    """Flat change spec with MODIFIED warns when no baseline spec exists."""
    monkeypatch.chdir(tmp_path)
    make_change_flat(tmp_path, "mychange", _SPEC_WITH_MODIFIED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    captured = capsys.readouterr()
    assert "skipped" in captured.err


def test_archive_flat_removed_deletes_flat_spec(tmp_path, monkeypatch, capsys):
    """Flat change spec with REMOVED deletes existing flat baseline spec."""
    monkeypatch.chdir(tmp_path)
    existing = tmp_path / "deltaspec" / "specs" / "cap-a.md"
    existing.parent.mkdir(parents=True)
    existing.write_text("## Requirements\n\nOld SHALL exist.\n")
    make_change_flat(tmp_path, "mychange", _SPEC_WITH_REMOVED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    assert not existing.exists(), "Flat baseline spec should be deleted"


def test_archive_subdir_removed_still_works(tmp_path, monkeypatch, capsys):
    """Existing subdir-format REMOVED still removes the directory (backward compat)."""
    monkeypatch.chdir(tmp_path)
    existing = tmp_path / "deltaspec" / "specs" / "cap-a"
    existing.mkdir(parents=True)
    (existing / "spec.md").write_text("# old spec\n")
    make_change(tmp_path, "mychange", _SPEC_WITH_REMOVED)
    rc = cmd_archive("mychange", yes=True)
    assert rc == 0
    assert not existing.exists()
