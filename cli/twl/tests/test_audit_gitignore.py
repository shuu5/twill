"""Tests for .gitignore and deps.yaml requirements (issue-642).

Covers:
- .gitignore への .audit/ 追加: .audit/ が gitignore で除外されているか
- deps.yaml への audit.py エントリ追加: loom --check が通るか

Scenarios from: spec.md Requirement: .gitignore への .audit/ 追加 / deps.yaml への audit.py エントリ追加
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest


# ---------------------------------------------------------------------------
# Project root detection
# ---------------------------------------------------------------------------

def _find_repo_root() -> Path:
    """Find the git repo root from the test file's location."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True,
            cwd=str(Path(__file__).parent),
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except Exception:
        pass
    return Path(__file__).parent.parent.parent.parent.parent


# ===========================================================================
# Requirement: .gitignore への .audit/ 追加
# ===========================================================================


class TestGitignoreAuditDir:
    """Scenario: .audit/ の gitignore 確認"""

    def test_audit_dir_in_gitignore(self) -> None:
        """WHEN .audit/ ディレクトリが作成される
        THEN git status に untracked として表示されない（gitignore によって除外される）"""
        repo_root = _find_repo_root()
        gitignore_candidates = [
            repo_root / ".gitignore",
            Path(__file__).parent.parent.parent.parent.parent / ".gitignore",
        ]

        gitignore_content = ""
        for candidate in gitignore_candidates:
            if candidate.is_file():
                gitignore_content = candidate.read_text(encoding="utf-8")
                break

        if not gitignore_content:
            pytest.skip("No .gitignore found — cannot verify .audit/ exclusion")

        # .audit/ must appear in .gitignore
        lines = gitignore_content.splitlines()
        matching_lines = [
            line.strip() for line in lines
            if line.strip() in (".audit/", ".audit", "/.audit/", "/.audit")
        ]
        assert matching_lines, \
            f".audit/ not found in .gitignore. Current entries: {lines[:20]}"

    def test_audit_dir_not_tracked_by_git(self, tmp_path: Path) -> None:
        """Edge case: git check-ignore で .audit/ が除外されることを確認"""
        repo_root = _find_repo_root()
        audit_candidate = repo_root / ".audit"

        result = subprocess.run(
            ["git", "check-ignore", "-q", ".audit/"],
            capture_output=True,
            text=True,
            cwd=str(repo_root),
        )
        # Exit code 0 means the path IS ignored (matched by .gitignore)
        # Exit code 1 means NOT ignored
        assert result.returncode == 0, \
            f".audit/ is NOT excluded by .gitignore (git check-ignore returned {result.returncode}). " \
            f"Add '.audit/' to .gitignore in the repo root."


# ===========================================================================
# Requirement: deps.yaml への audit.py エントリ追加
# ===========================================================================


class TestDepsYamlAuditEntry:
    """Scenario: deps.yaml の audit.py エントリ"""

    def _find_deps_yaml(self) -> Path | None:
        """Find the main twl plugin deps.yaml (not test-fixture)."""
        # Primary: plugins/twl/deps.yaml relative to repo root
        repo_root = _find_repo_root()
        primary = repo_root / "plugins" / "twl" / "deps.yaml"
        if primary.is_file():
            return primary

        # Fallback: test file parent traversal
        candidate = Path(__file__).parent.parent.parent.parent.parent / "plugins" / "twl" / "deps.yaml"
        if candidate.is_file():
            return candidate

        return None

    def test_audit_py_entry_in_deps_yaml(self) -> None:
        """WHEN loom --check が実行される
        THEN audit.py が deps.yaml に登録されておりチェックが通る"""
        deps_yaml = self._find_deps_yaml()
        if deps_yaml is None:
            pytest.skip("deps.yaml not found")

        content = deps_yaml.read_text(encoding="utf-8")
        assert "audit" in content, \
            f"'audit' not found in {deps_yaml}. " \
            f"The audit.py module must be registered in deps.yaml."

    def test_audit_py_path_in_deps_yaml(self) -> None:
        """Edge case: deps.yaml に audit.py のパスエントリが存在する"""
        deps_yaml = self._find_deps_yaml()
        if deps_yaml is None:
            pytest.skip("deps.yaml not found")

        content = deps_yaml.read_text(encoding="utf-8")
        # Check for audit.py reference (either as path or as module name)
        has_audit_py = "audit.py" in content or (
            "audit" in content and "autopilot" in content
        )
        assert has_audit_py, \
            f"audit.py module not found in deps.yaml. " \
            f"Expected an entry referencing 'audit.py' in the autopilot section."
