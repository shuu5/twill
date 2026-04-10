"""Tests for src/twl/spec/new.py"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.new import cmd_new


def make_project(tmp_path: Path) -> Path:
    (tmp_path / "deltaspec" / "changes").mkdir(parents=True)
    return tmp_path


def test_creates_change_directory(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    rc = cmd_new("my-change")
    assert rc == 0
    change_dir = tmp_path / "deltaspec" / "changes" / "my-change"
    assert change_dir.is_dir()
    deltaspec_yaml = change_dir / ".deltaspec.yaml"
    assert deltaspec_yaml.exists()
    content = deltaspec_yaml.read_text()
    assert "schema: spec-driven" in content
    assert "created:" in content


def test_rejects_uppercase(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    rc = cmd_new("MyChange")
    assert rc == 1


def test_rejects_spaces(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    rc = cmd_new("my change")
    assert rc == 1


def test_rejects_duplicate(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    cmd_new("dup")
    rc = cmd_new("dup")
    assert rc == 1


def test_accepts_numbers_and_hyphens(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    rc = cmd_new("feat-123")
    assert rc == 0


def test_error_without_deltaspec(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    rc = cmd_new("my-change")
    assert rc == 1


def test_issue_name_adds_issue_field(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    rc = cmd_new("issue-123")
    assert rc == 0
    content = (tmp_path / "deltaspec" / "changes" / "issue-123" / ".deltaspec.yaml").read_text()
    assert "issue: 123" in content
    assert "name: issue-123" in content
    assert "status: pending" in content


def test_non_issue_name_no_issue_field(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    rc = cmd_new("add-user-auth")
    assert rc == 0
    content = (tmp_path / "deltaspec" / "changes" / "add-user-auth" / ".deltaspec.yaml").read_text()
    assert "issue:" not in content
    assert "name: add-user-auth" in content


def test_issue_name_large_number(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    rc = cmd_new("issue-1234")
    assert rc == 0
    content = (tmp_path / "deltaspec" / "changes" / "issue-1234" / ".deltaspec.yaml").read_text()
    assert "issue: 1234" in content


def test_non_issue_pattern_no_field(tmp_path, monkeypatch):
    monkeypatch.chdir(make_project(tmp_path))
    rc = cmd_new("fix-issue-tracker")
    assert rc == 0
    content = (tmp_path / "deltaspec" / "changes" / "fix-issue-tracker" / ".deltaspec.yaml").read_text()
    assert "issue:" not in content
