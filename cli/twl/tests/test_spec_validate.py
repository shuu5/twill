"""Tests for src/twl/spec/validate.py"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.validate import cmd_coverage, cmd_validate

_VALID_SPEC = """\
## ADDED Requirements

### Requirement: Foo
The system SHALL do foo.

#### Scenario: Basic foo
- **WHEN** foo is requested
- **THEN** foo happens
"""

_MISSING_DELTA_HDR = """\
### Requirement: Foo
The system SHALL do foo.

#### Scenario: Basic foo
- **WHEN** x
- **THEN** y
"""

_MISSING_SHALL = """\
## ADDED Requirements

### Requirement: Foo
The system does foo.

#### Scenario: Basic foo
- **WHEN** x
- **THEN** y
"""

_MISSING_SCENARIO = """\
## ADDED Requirements

### Requirement: Foo
The system SHALL do foo.
"""


def make_change(tmp_path: Path, name: str, spec_content: str | None = None) -> Path:
    ds = tmp_path / "deltaspec"
    change_dir = ds / "changes" / name
    specs_dir = change_dir / "specs" / "cap-a"
    specs_dir.mkdir(parents=True)
    if spec_content is not None:
        (specs_dir / "spec.md").write_text(spec_content)
    config = ds / "config.yaml"
    if not config.exists():
        config.write_text("schema: spec-driven\ncontext: {}\n", encoding="utf-8")
    return change_dir


def test_valid_spec_passes(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "good", _VALID_SPEC)
    rc = cmd_validate("good")
    assert rc == 0
    assert "1 passed" in capsys.readouterr().out


def test_missing_delta_header(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "bad", _MISSING_DELTA_HDR)
    rc = cmd_validate("bad")
    assert rc == 1
    assert "0 passed" in capsys.readouterr().out


def test_missing_shall_must(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "noshall", _MISSING_SHALL)
    rc = cmd_validate("noshall")
    assert rc == 1


def test_missing_scenario(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "nosc", _MISSING_SCENARIO)
    rc = cmd_validate("nosc")
    assert rc == 1


def test_validate_all(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "good", _VALID_SPEC)
    make_change(tmp_path, "bad", _MISSING_DELTA_HDR)
    rc = cmd_validate(validate_all=True)
    assert rc == 1
    out = capsys.readouterr().out
    assert "1 passed" in out
    assert "1 failed" in out


def test_validate_json_output(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "jtest", _VALID_SPEC)
    rc = cmd_validate("jtest", json_mode=True)
    assert rc == 0
    data = json.loads(capsys.readouterr().out)
    assert data["summary"]["totals"]["passed"] == 1
    assert data["summary"]["totals"]["failed"] == 0
    assert data["items"][0]["valid"] is True


def _make_deltaspec_root(tmp_path: Path) -> None:
    """Create deltaspec/config.yaml marker in tmp_path."""
    ds = tmp_path / "deltaspec"
    ds.mkdir(exist_ok=True)
    config = ds / "config.yaml"
    if not config.exists():
        config.write_text("schema: spec-driven\ncontext: {}\n", encoding="utf-8")


def test_validate_no_specs_dir(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    # Change with no specs dir — passes vacuously
    (tmp_path / "deltaspec" / "changes" / "empty").mkdir(parents=True)
    _make_deltaspec_root(tmp_path)
    rc = cmd_validate("empty")
    assert rc == 0


def test_validate_missing_change(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "deltaspec" / "changes").mkdir(parents=True)
    _make_deltaspec_root(tmp_path)
    # Missing change just warns, doesn't error out, but total=0
    rc = cmd_validate("ghost")
    assert rc == 0  # 0 failed out of 0


# --- cmd_coverage tests ---


def _make_coverage_fixture(tmp_path: Path, invariant_ids: list[str], referenced_ids: list[str]) -> None:
    """Create architecture/domain/contexts/ctx.md and deltaspec/specs/spec.md for coverage testing."""
    ctx_dir = tmp_path / "architecture" / "domain" / "contexts"
    ctx_dir.mkdir(parents=True)
    lines = ["# Context\n\n| ID | 不変条件 | 概要 |\n|----|----|----|\n"]
    for inv_id in invariant_ids:
        lines.append(f"| **{inv_id}** | some invariant | desc |\n")
    (ctx_dir / "ctx.md").write_text("".join(lines))

    specs_dir = tmp_path / "deltaspec" / "specs"
    specs_dir.mkdir(parents=True)
    spec_lines = ["# Spec\n\n"]
    for ref_id in referenced_ids:
        spec_lines.append(f"- 不変条件 {ref_id} が成立する\n")
    (specs_dir / "spec.md").write_text("".join(spec_lines))

    # Ensure deltaspec root marker exists
    (tmp_path / "deltaspec").mkdir(exist_ok=True)
    config = tmp_path / "deltaspec" / "config.yaml"
    if not config.exists():
        config.write_text("schema: spec-driven\ncontext: {}\n", encoding="utf-8")


def test_coverage_all_covered(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _make_coverage_fixture(tmp_path, ["A", "B"], ["A", "B"])
    rc = cmd_coverage()
    assert rc == 0
    out = capsys.readouterr().out
    assert "2/2 covered" in out
    assert "WARNING" not in out


def test_coverage_missing_reference(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    _make_coverage_fixture(tmp_path, ["A", "B", "C"], ["A"])
    rc = cmd_coverage()
    assert rc == 0  # WARNING only, exit code 0
    out = capsys.readouterr().out
    assert "1/3 covered" in out
    assert "WARNING" in out
    assert "不変条件 B" in out
    assert "不変条件 C" in out
