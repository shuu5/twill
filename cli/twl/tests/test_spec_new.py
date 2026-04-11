"""Tests for src/twl/spec/new.py"""

import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.new import cmd_new


def make_project(tmp_path: Path) -> Path:
    ds = tmp_path / "deltaspec"
    (ds / "changes").mkdir(parents=True)
    (ds / "config.yaml").write_text("schema: spec-driven\ncontext: {}\n", encoding="utf-8")
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


def test_auto_init_without_deltaspec(tmp_path, monkeypatch):
    # deltaspec/ が存在せず origin/main にも nested root がない場合は auto-init して成功する
    monkeypatch.chdir(tmp_path)
    # Explicitly mock git ls-tree to return no nested roots (safe to auto-init)
    with patch("twl.spec.new.subprocess.run", return_value=_mock_git_ls_tree_with_nested(returncode=0, lines=["README.md"])):
        rc = cmd_new("my-change")
    assert rc == 0
    assert (tmp_path / "deltaspec" / "config.yaml").exists()
    assert (tmp_path / "deltaspec" / "changes" / "my-change").is_dir()


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


# ---------------------------------------------------------------------------
# Auto-init suppression guard tests (AC-1, issue #485)
# ---------------------------------------------------------------------------

def _mock_git_ls_tree_with_nested(returncode=0, lines=None):
    """Helper: return a mock subprocess.CompletedProcess for git ls-tree."""
    if lines is None:
        lines = [
            "plugins/twl/deltaspec/config.yaml",
            "cli/twl/deltaspec/config.yaml",
            "README.md",
        ]
    mock = MagicMock()
    mock.returncode = returncode
    mock.stdout = "\n".join(lines) + "\n"
    return mock


def test_new_auto_init_suppressed_when_nested_root_exists(tmp_path, monkeypatch):
    """nested root が origin/main に存在する場合 auto-init を発動しない（AC-1 Phase 1）。"""
    monkeypatch.chdir(tmp_path)
    # Simulate git ls-tree returning nested deltaspec/config.yaml entries
    with patch("twl.spec.new.subprocess.run", return_value=_mock_git_ls_tree_with_nested()):
        rc = cmd_new("issue-999")
    assert rc == 1, "Should fail when nested deltaspec roots exist in origin/main"
    assert not (tmp_path / "deltaspec").exists(), "deltaspec/ must NOT be created"


def test_new_auto_init_suppressed_error_message(tmp_path, monkeypatch, capsys):
    """エラーメッセージに rebase hint が含まれること（AC-1 Phase 1）。"""
    monkeypatch.chdir(tmp_path)
    with patch("twl.spec.new.subprocess.run", return_value=_mock_git_ls_tree_with_nested()):
        cmd_new("issue-999")
    captured = capsys.readouterr()
    assert "nested deltaspec root" in captured.err
    assert "origin/main" in captured.err
    assert "rebase" in captured.err or "git rebase" in captured.err


def test_new_auto_init_allowed_with_env_var(tmp_path, monkeypatch):
    """TWL_SPEC_ALLOW_AUTO_INIT=1 設定時は nested root があっても auto-init する（AC-1 Phase 2）。"""
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("TWL_SPEC_ALLOW_AUTO_INIT", "1")
    with patch("twl.spec.new.subprocess.run", return_value=_mock_git_ls_tree_with_nested()):
        rc = cmd_new("issue-999")
    assert rc == 0, "Should succeed with TWL_SPEC_ALLOW_AUTO_INIT=1"
    assert (tmp_path / "deltaspec" / "config.yaml").exists()
    assert (tmp_path / "deltaspec" / "changes" / "issue-999").is_dir()


def test_new_auto_init_fallback_when_git_ls_tree_fails(tmp_path, monkeypatch, capsys):
    """git ls-tree 失敗時（offline 等）は WARN を出して従来の auto-init にフォールバックする。"""
    monkeypatch.chdir(tmp_path)
    # Simulate git ls-tree failure (non-zero exit code)
    with patch("twl.spec.new.subprocess.run", return_value=_mock_git_ls_tree_with_nested(returncode=128)):
        rc = cmd_new("issue-999")
    assert rc == 0, "Should fall back to auto-init when git ls-tree fails"
    assert (tmp_path / "deltaspec" / "config.yaml").exists()
    captured = capsys.readouterr()
    assert "[WARN]" in captured.err, "Should print WARN when git ls-tree fails"
