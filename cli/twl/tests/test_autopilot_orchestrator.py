"""Tests for twl.autopilot.orchestrator — Phase report, summary, and plan parsing.

Focus on pure logic (no tmux/gh/cld required):
  - get_phase_issues: plan.yaml parsing
  - generate_summary: summary from issue files
  - PhaseOrchestrator._generate_phase_report
  - resolve_repos_config
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from twl.autopilot.orchestrator import (
    PhaseOrchestrator,
    generate_summary,
    get_phase_issues,
    resolve_repos_config,
    OrchestratorError,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    return d


@pytest.fixture
def plan_file(tmp_path: Path) -> Path:
    return tmp_path / "plan.yaml"


def _write_plan(plan_file: Path, content: str) -> None:
    plan_file.write_text(content, encoding="utf-8")


def _write_issue(autopilot_dir: Path, issue_num: str, status: str) -> None:
    data = {
        "issue": int(issue_num),
        "status": status,
        "branch": f"feat/{issue_num}-test",
        "pr": None,
        "pr_number": "",
        "window": f"ap-#{issue_num}",
        "started_at": "2024-01-01T00:00:00Z",
        "updated_at": "2024-01-01T00:00:00Z",
        "current_step": "",
        "retry_count": 0,
        "fix_instructions": None,
        "merged_at": None,
        "files_changed": [],
        "failure": None,
        "changed_files": [],
        "is_quick": False,
    }
    (autopilot_dir / "issues" / f"issue-{issue_num}.json").write_text(
        json.dumps(data), encoding="utf-8"
    )


# ===========================================================================
# get_phase_issues — plan parsing
# ===========================================================================


class TestGetPhaseIssues:
    def test_legacy_format_single_issue(self, plan_file: Path) -> None:
        _write_plan(plan_file, """
phases:
  - phase: 1
    - 42
  - phase: 2
    - 43
""")
        result = get_phase_issues(1, str(plan_file))
        assert "_default:42" in result

    def test_legacy_format_multiple_issues(self, plan_file: Path) -> None:
        _write_plan(plan_file, """
phases:
  - phase: 1
    - 10
    - 11
    - 12
""")
        result = get_phase_issues(1, str(plan_file))
        assert set(result) == {"_default:10", "_default:11", "_default:12"}

    def test_cross_repo_format(self, plan_file: Path) -> None:
        _write_plan(plan_file, """
phases:
  - phase: 1
    - { number: 42, repo: lpd }
    - { number: 50, repo: twill }
""")
        result = get_phase_issues(1, str(plan_file))
        assert "lpd:42" in result
        assert "twill:50" in result

    def test_phase_not_found_returns_empty(self, plan_file: Path) -> None:
        _write_plan(plan_file, """
phases:
  - phase: 1
    - 42
""")
        result = get_phase_issues(99, str(plan_file))
        assert result == []

    def test_second_phase_isolated(self, plan_file: Path) -> None:
        _write_plan(plan_file, """
phases:
  - phase: 1
    - 10
  - phase: 2
    - 20
    - 21
""")
        result1 = get_phase_issues(1, str(plan_file))
        result2 = get_phase_issues(2, str(plan_file))
        assert result1 == ["_default:10"]
        assert set(result2) == {"_default:20", "_default:21"}

    def test_mixed_format(self, plan_file: Path) -> None:
        """Test plan with both cross-repo and legacy formats."""
        _write_plan(plan_file, """
phases:
  - phase: 1
    - { number: 42, repo: lpd }
    - 10
""")
        result = get_phase_issues(1, str(plan_file))
        assert "lpd:42" in result
        assert "_default:10" in result


# ===========================================================================
# resolve_repos_config
# ===========================================================================


class TestResolveReposConfig:
    def test_empty_returns_empty(self) -> None:
        assert resolve_repos_config("") == {}

    def test_valid_json(self) -> None:
        repos_json = '{"lpd": {"owner": "shuu5", "name": "lpd", "path": "/home/user/lpd"}}'
        result = resolve_repos_config(repos_json)
        assert result["lpd"]["owner"] == "shuu5"
        assert result["lpd"]["name"] == "lpd"

    def test_invalid_json_returns_empty(self) -> None:
        result = resolve_repos_config("{invalid json}")
        assert result == {}

    def test_multiple_repos(self) -> None:
        repos_json = json.dumps({
            "lpd": {"owner": "shuu5", "name": "lpd", "path": "/lpd"},
            "twill": {"owner": "shuu5", "name": "twill", "path": "/twill"},
        })
        result = resolve_repos_config(repos_json)
        assert set(result.keys()) == {"lpd", "twill"}


# ===========================================================================
# generate_summary
# ===========================================================================


class TestGenerateSummary:
    def test_empty_issues_dir(self, autopilot_dir: Path) -> None:
        result = generate_summary(str(autopilot_dir))
        assert result["signal"] == "SUMMARY"
        assert result["total"] == 0
        assert result["results"]["done"]["count"] == 0

    def test_all_done(self, autopilot_dir: Path) -> None:
        for n in ("1", "2", "3"):
            _write_issue(autopilot_dir, n, "done")
        result = generate_summary(str(autopilot_dir))
        assert result["total"] == 3
        assert result["results"]["done"]["count"] == 3
        assert result["results"]["failed"]["count"] == 0

    def test_mixed_statuses(self, autopilot_dir: Path) -> None:
        _write_issue(autopilot_dir, "1", "done")
        _write_issue(autopilot_dir, "2", "failed")
        _write_issue(autopilot_dir, "3", "running")
        result = generate_summary(str(autopilot_dir))
        assert result["total"] == 3
        assert result["results"]["done"]["count"] == 1
        assert result["results"]["failed"]["count"] == 1
        assert result["results"]["skipped"]["count"] == 1

    def test_issues_list_contents(self, autopilot_dir: Path) -> None:
        _write_issue(autopilot_dir, "5", "done")
        _write_issue(autopilot_dir, "7", "failed")
        result = generate_summary(str(autopilot_dir))
        assert 5 in result["results"]["done"]["issues"]
        assert 7 in result["results"]["failed"]["issues"]

    def test_missing_issues_dir_raises(self, tmp_path: Path) -> None:
        nonexistent = str(tmp_path / "nonexistent")
        with pytest.raises(OrchestratorError, match="issues directory not found"):
            generate_summary(nonexistent)


# ===========================================================================
# PhaseOrchestrator._generate_phase_report
# ===========================================================================


class TestGeneratePhaseReport:
    def _make_orchestrator(self, autopilot_dir: Path, tmp_path: Path) -> PhaseOrchestrator:
        return PhaseOrchestrator(
            plan_file=str(tmp_path / "plan.yaml"),
            phase=1,
            session_file=str(tmp_path / "session.json"),
            project_dir=str(tmp_path),
            autopilot_dir=str(autopilot_dir),
            scripts_root=tmp_path / "scripts",
        )

    def test_empty_issue_list(self, autopilot_dir: Path, tmp_path: Path) -> None:
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        report = orch._generate_phase_report([])
        assert report["signal"] == "PHASE_COMPLETE"
        assert report["phase"] == 1
        assert report["results"]["done"] == []
        assert report["results"]["failed"] == []

    def test_done_issue(self, autopilot_dir: Path, tmp_path: Path) -> None:
        _write_issue(autopilot_dir, "1", "done")
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        report = orch._generate_phase_report(["1"])
        assert 1 in report["results"]["done"]
        assert report["results"]["failed"] == []

    def test_failed_issue(self, autopilot_dir: Path, tmp_path: Path) -> None:
        _write_issue(autopilot_dir, "2", "failed")
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        report = orch._generate_phase_report(["2"])
        assert 2 in report["results"]["failed"]
        assert report["results"]["done"] == []

    def test_mixed_issues(self, autopilot_dir: Path, tmp_path: Path) -> None:
        _write_issue(autopilot_dir, "1", "done")
        _write_issue(autopilot_dir, "2", "failed")
        _write_issue(autopilot_dir, "3", "running")
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        report = orch._generate_phase_report(["1", "2", "3"])
        assert 1 in report["results"]["done"]
        assert 2 in report["results"]["failed"]
        assert 3 in report["results"]["skipped"]

    def test_changed_files_collected(self, autopilot_dir: Path, tmp_path: Path) -> None:
        # Write issue with changed_files
        data = {
            "issue": 5, "status": "done", "branch": "feat/5",
            "pr": None, "pr_number": "", "window": "ap-#5",
            "started_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
            "current_step": "", "retry_count": 0,
            "fix_instructions": None, "merged_at": None,
            "files_changed": [], "failure": None,
            "changed_files": ["src/foo.py", "src/bar.py"],
            "is_quick": False,
        }
        (autopilot_dir / "issues" / "issue-5.json").write_text(
            json.dumps(data), encoding="utf-8"
        )
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        report = orch._generate_phase_report(["5"])
        assert "src/foo.py" in report["changed_files"]
        assert "src/bar.py" in report["changed_files"]


# ===========================================================================
# PhaseOrchestrator._nudge_command_for_pattern
# ===========================================================================


class TestNudgeCommandForPattern:
    def _make_orchestrator(self, autopilot_dir: Path, tmp_path: Path) -> PhaseOrchestrator:
        return PhaseOrchestrator(
            plan_file=str(tmp_path / "plan.yaml"),
            phase=1,
            session_file=str(tmp_path / "session.json"),
            project_dir=str(tmp_path),
            autopilot_dir=str(autopilot_dir),
            scripts_root=tmp_path / "scripts",
        )

    def test_setup_chain_complete_pattern(self, autopilot_dir: Path, tmp_path: Path) -> None:
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        cmd = orch._nudge_command_for_pattern("setup chain 完了。次のステップ...", "1", "_default:1")
        assert cmd == "/twl:workflow-test-ready #1"

    def test_proposal_complete_pattern(self, autopilot_dir: Path, tmp_path: Path) -> None:
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        cmd = orch._nudge_command_for_pattern(">>> 提案完了 <<<", "1", "_default:1")
        assert cmd == ""

    def test_no_pattern_returns_none(self, autopilot_dir: Path, tmp_path: Path) -> None:
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        cmd = orch._nudge_command_for_pattern("some random output...", "1", "_default:1")
        assert cmd is None

    def test_test_ready_complete_pattern(self, autopilot_dir: Path, tmp_path: Path) -> None:
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        cmd = orch._nudge_command_for_pattern("テスト準備が完了しました", "1", "_default:1")
        assert cmd == "/twl:workflow-pr-verify #1"

    def test_pr_merge_complete_pattern(self, autopilot_dir: Path, tmp_path: Path) -> None:
        orch = self._make_orchestrator(autopilot_dir, tmp_path)
        cmd = orch._nudge_command_for_pattern("PR マージ完了", "1", "_default:1")
        assert cmd == ""

