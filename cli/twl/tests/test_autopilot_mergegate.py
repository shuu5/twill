"""Tests for twl.autopilot.mergegate.

Covers:
  - MergeGate.from_env() validation (AC1)
  - execute(): normal merge flow — state transitions, worktree/branch cleanup (AC1)
  - reject(): state transition to failed + retry_count (AC1)
  - reject_final(): state transition to failed (no retry) (AC1)
  - Guard: worktrees/ path guard (invariant B/C) (AC1)
  - Guard: status=running guard (invariant C) (AC1)
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest

from twl.autopilot.mergegate import MergeGate, MergeGateError


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
def scripts_root(tmp_path: Path) -> Path:
    d = tmp_path / "scripts"
    d.mkdir()
    return d


@pytest.fixture
def gate(autopilot_dir: Path, scripts_root: Path) -> MergeGate:
    return MergeGate(
        issue="42",
        pr_number="101",
        branch="feat/42-some-feature",
        finding_summary="Critical bug found",
        fix_instructions="Fix the bug in foo.py",
        autopilot_dir=autopilot_dir,
        scripts_root=scripts_root,
    )


# ---------------------------------------------------------------------------
# from_env()
# ---------------------------------------------------------------------------


class TestFromEnv:
    def test_valid_env(self, monkeypatch):
        monkeypatch.setenv("ISSUE", "5")
        monkeypatch.setenv("PR_NUMBER", "10")
        monkeypatch.setenv("BRANCH", "feat/5-test")
        monkeypatch.delenv("REPO_OWNER", raising=False)
        monkeypatch.delenv("REPO_NAME", raising=False)
        gate = MergeGate.from_env()
        assert gate.issue == "5"
        assert gate.pr_number == "10"
        assert gate.branch == "feat/5-test"

    def test_invalid_issue(self, monkeypatch):
        monkeypatch.setenv("ISSUE", "abc")
        monkeypatch.setenv("PR_NUMBER", "10")
        monkeypatch.setenv("BRANCH", "feat/5")
        with pytest.raises(MergeGateError, match="不正なISSUE"):
            MergeGate.from_env()

    def test_invalid_pr_number(self, monkeypatch):
        monkeypatch.setenv("ISSUE", "5")
        monkeypatch.setenv("PR_NUMBER", "xyz")
        monkeypatch.setenv("BRANCH", "feat/5")
        with pytest.raises(MergeGateError, match="不正なPR_NUMBER"):
            MergeGate.from_env()

    def test_invalid_branch(self, monkeypatch):
        monkeypatch.setenv("ISSUE", "5")
        monkeypatch.setenv("PR_NUMBER", "10")
        monkeypatch.setenv("BRANCH", "feat/5 bad branch!")
        with pytest.raises(MergeGateError, match="不正なBRANCH"):
            MergeGate.from_env()

    def test_invalid_repo_owner(self, monkeypatch):
        monkeypatch.setenv("ISSUE", "5")
        monkeypatch.setenv("PR_NUMBER", "10")
        monkeypatch.setenv("BRANCH", "feat/5")
        monkeypatch.setenv("REPO_OWNER", "bad owner!")
        monkeypatch.setenv("REPO_NAME", "repo")
        with pytest.raises(MergeGateError, match="不正な REPO_OWNER"):
            MergeGate.from_env()


# ---------------------------------------------------------------------------
# Worktree guard
# ---------------------------------------------------------------------------


class TestWorktreeGuard:
    def test_rejects_worktrees_path(self, gate):
        with patch("os.getcwd", return_value="/home/user/projects/repo/worktrees/feat/42"):
            with patch("twl.autopilot.mergegate._check_worker_window_guard"):
                with patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"):
                    with pytest.raises(MergeGateError, match="worktrees/ 配下"):
                        gate.execute()


# ---------------------------------------------------------------------------
# Worker window guard
# ---------------------------------------------------------------------------


class TestWorkerWindowGuard:
    def test_rejects_ap_window(self, gate):
        with patch("os.getcwd", return_value="/home/user/projects/repo/main"):
            with patch(
                "subprocess.run",
                return_value=MagicMock(returncode=0, stdout="ap-#42\n"),
            ):
                with patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"):
                    with pytest.raises(MergeGateError, match="autopilot Worker"):
                        gate.execute()


# ---------------------------------------------------------------------------
# execute() — merge transitions (AC1)
# ---------------------------------------------------------------------------


class TestExecute:
    def _patch_execute(self, gate, *, merge_ok=True, autopilot_status="merge-ready"):
        patches = [
            patch("os.getcwd", return_value="/home/user/projects/repo/main"),
            patch("twl.autopilot.mergegate._check_worker_window_guard"),
            patch("twl.autopilot.mergegate._state_read", return_value=autopilot_status),
            patch("twl.autopilot.mergegate._state_write"),
            patch("twl.autopilot.mergegate._board_update"),
            patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"),
        ]
        # Mock subprocess.run for gh pr merge
        def fake_run(cmd, **kwargs):
            if "gh" in cmd and "merge" in cmd:
                return MagicMock(returncode=0 if merge_ok else 1, stderr="merge error")
            # git commands
            return MagicMock(returncode=0, stdout="")
        patches.append(patch("subprocess.run", side_effect=fake_run))
        return patches

    def test_successful_merge_calls_state_write_done(self, gate, autopilot_dir):
        with patch("os.getcwd", return_value="/home/user/projects/main"):
            with patch("twl.autopilot.mergegate._check_worker_window_guard"):
                with patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"):
                    with patch("twl.autopilot.mergegate._state_write") as mock_sw:
                        with patch("twl.autopilot.mergegate._board_update"):
                            with patch("twl.autopilot.mergegate._detect_repo_mode",
                                       return_value="standard"):
                                with patch("subprocess.run",
                                           return_value=MagicMock(returncode=0, stdout="")):
                                    gate.execute()
                                    # Should write status=done
                                    calls_kwargs = [
                                        {k: v for k, v in call_args.kwargs.items()}
                                        for call_args in mock_sw.call_args_list
                                    ]
                                    statuses = [kw.get("status") for kw in calls_kwargs]
                                    assert "done" in statuses

    def test_merge_failure_exits_with_1(self, gate):
        with patch("os.getcwd", return_value="/home/user/projects/main"):
            with patch("twl.autopilot.mergegate._check_worker_window_guard"):
                with patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"):
                    with patch("twl.autopilot.mergegate._state_write"):
                        with patch("twl.autopilot.mergegate._detect_repo_mode",
                                   return_value="standard"):
                            def fake_run(cmd, **kwargs):
                                if "gh" in cmd and "merge" in cmd:
                                    return MagicMock(returncode=1, stderr="merge error")
                                return MagicMock(returncode=0, stdout="")
                            with patch("subprocess.run", side_effect=fake_run):
                                with pytest.raises(SystemExit) as exc_info:
                                    gate.execute()
                                assert exc_info.value.code == 1

    def test_running_status_raises_error(self, gate):
        with patch("os.getcwd", return_value="/home/user/projects/main"):
            with patch("twl.autopilot.mergegate._check_worker_window_guard"):
                with patch("twl.autopilot.mergegate._state_read", return_value="running"):
                    with pytest.raises(MergeGateError, match="status=running"):
                        gate.execute()

    def test_autopilot_detected_skips_cleanup(self, gate, autopilot_dir):
        """When issue JSON exists, cleanup is delegated to Pilot."""
        issue_json = autopilot_dir / "issues" / "issue-42.json"
        issue_json.write_text('{"status": "merge-ready"}')

        with patch("os.getcwd", return_value="/home/user/projects/main"):
            with patch("twl.autopilot.mergegate._check_worker_window_guard"):
                with patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"):
                    with patch("twl.autopilot.mergegate._state_write"):
                        with patch("twl.autopilot.mergegate._board_update"):
                            with patch("twl.autopilot.mergegate._detect_repo_mode",
                                       return_value="standard"):
                                with patch("subprocess.run",
                                           return_value=MagicMock(returncode=0, stdout="")):
                                    # Should not raise
                                    gate.execute()


# ---------------------------------------------------------------------------
# reject() — 1st rejection (AC1)
# ---------------------------------------------------------------------------


class TestReject:
    def test_reject_writes_failed_with_retry_count(self, gate):
        with patch("twl.autopilot.mergegate._state_write") as mock_sw:
            with patch("twl.autopilot.mergegate.MergeGate._kill_worker_window"):
                gate.reject()
                # Check that failure JSON has retry_count=1
                call_kwargs = mock_sw.call_args.kwargs
                failure_data = json.loads(call_kwargs["failure"])
                assert failure_data["reason"] == "merge_gate_rejected"
                assert failure_data["retry_count"] == 1
                assert failure_data["fix_instructions"] == gate.fix_instructions

    def test_reject_transitions_to_failed(self, gate):
        with patch("twl.autopilot.mergegate._state_write") as mock_sw:
            with patch("twl.autopilot.mergegate.MergeGate._kill_worker_window"):
                gate.reject()
                call_kwargs = mock_sw.call_args.kwargs
                assert call_kwargs["status"] == "failed"

    def test_reject_kills_worker_window(self, gate):
        with patch("twl.autopilot.mergegate._state_write"):
            with patch("twl.autopilot.mergegate.MergeGate._kill_worker_window") as mock_kill:
                gate.reject()
                mock_kill.assert_called_once()


# ---------------------------------------------------------------------------
# reject_final() — 2nd rejection (AC1)
# ---------------------------------------------------------------------------


class TestRejectFinal:
    def test_reject_final_writes_failed_no_retry(self, gate):
        with patch("twl.autopilot.mergegate._state_write") as mock_sw:
            with patch("twl.autopilot.mergegate.MergeGate._kill_worker_window"):
                gate.reject_final()
                call_kwargs = mock_sw.call_args.kwargs
                failure_data = json.loads(call_kwargs["failure"])
                assert failure_data["reason"] == "merge_gate_rejected_final"
                assert failure_data["retry_count"] == 2
                # No fix_instructions in final rejection
                assert "fix_instructions" not in failure_data

    def test_reject_final_transitions_to_failed(self, gate):
        with patch("twl.autopilot.mergegate._state_write") as mock_sw:
            with patch("twl.autopilot.mergegate.MergeGate._kill_worker_window"):
                gate.reject_final()
                call_kwargs = mock_sw.call_args.kwargs
                assert call_kwargs["status"] == "failed"

    def test_reject_final_kills_worker_window(self, gate):
        with patch("twl.autopilot.mergegate._state_write"):
            with patch("twl.autopilot.mergegate.MergeGate._kill_worker_window") as mock_kill:
                gate.reject_final()
                mock_kill.assert_called_once()


# ---------------------------------------------------------------------------
# Cross-repo flag
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# _gh_issue_state / _verify_and_close_issue (Issue #137)
# ---------------------------------------------------------------------------


class TestGhIssueState:
    def test_returns_closed(self, gate):
        with patch("subprocess.run",
                   return_value=MagicMock(returncode=0, stdout="CLOSED\n")):
            assert gate._gh_issue_state([]) == "CLOSED"

    def test_returns_open(self, gate):
        with patch("subprocess.run",
                   return_value=MagicMock(returncode=0, stdout="OPEN\n")):
            assert gate._gh_issue_state([]) == "OPEN"

    def test_returns_empty_on_error(self, gate):
        with patch("subprocess.run",
                   return_value=MagicMock(returncode=1, stdout="", stderr="err")):
            assert gate._gh_issue_state([]) == ""


class TestVerifyAndCloseIssue:
    def test_already_closed(self, gate):
        with patch.object(gate, "_gh_issue_state", return_value="CLOSED"):
            assert gate._verify_and_close_issue([]) is True

    def test_open_then_close_success(self, gate):
        # First call OPEN, then CLOSED after close
        states = iter(["OPEN", "CLOSED"])
        with patch.object(gate, "_gh_issue_state", side_effect=lambda _f: next(states)):
            with patch("subprocess.run",
                       return_value=MagicMock(returncode=0, stderr="")):
                assert gate._verify_and_close_issue([]) is True

    def test_open_then_close_failure(self, gate):
        with patch.object(gate, "_gh_issue_state", return_value="OPEN"):
            with patch("subprocess.run",
                       return_value=MagicMock(returncode=1, stderr="forbidden")):
                assert gate._verify_and_close_issue([]) is False

    def test_open_close_ok_but_still_open(self, gate):
        states = iter(["OPEN", "OPEN"])
        with patch.object(gate, "_gh_issue_state", side_effect=lambda _f: next(states)):
            with patch("subprocess.run",
                       return_value=MagicMock(returncode=0, stderr="")):
                assert gate._verify_and_close_issue([]) is False

    def test_state_query_fails_returns_true(self, gate):
        """When state query fails (gh unavailable), skip verify — return True."""
        with patch.object(gate, "_gh_issue_state", return_value=""):
            assert gate._verify_and_close_issue([]) is True


class TestExecuteWithIssueVerify:
    """execute() tests exercising the verify-and-close Issue #137 logic."""

    def _base_patches(self, gate, verify_result):
        """Helper returning context managers for common execute() patching."""
        return [
            patch("os.getcwd", return_value="/home/user/projects/main"),
            patch("twl.autopilot.mergegate._check_worker_window_guard"),
            patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"),
            patch("twl.autopilot.mergegate._board_update"),
            patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"),
            patch.object(MergeGate, "_verify_and_close_issue", return_value=verify_result),
        ]

    def test_merge_ok_and_issue_closed_writes_done(self, gate):
        with patch("os.getcwd", return_value="/home/user/projects/main"), \
             patch("twl.autopilot.mergegate._check_worker_window_guard"), \
             patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"), \
             patch("twl.autopilot.mergegate._state_write") as mock_sw, \
             patch("twl.autopilot.mergegate._board_update") as mock_board, \
             patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"), \
             patch.object(MergeGate, "_verify_and_close_issue", return_value=True), \
             patch("subprocess.run",
                   return_value=MagicMock(returncode=0, stdout="")):
            gate.execute()
            statuses = [c.kwargs.get("status") for c in mock_sw.call_args_list]
            assert "done" in statuses
            mock_board.assert_called_once()

    def test_merge_ok_but_issue_close_fails_writes_failed_and_exit2(self, gate):
        with patch("os.getcwd", return_value="/home/user/projects/main"), \
             patch("twl.autopilot.mergegate._check_worker_window_guard"), \
             patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"), \
             patch("twl.autopilot.mergegate._state_write") as mock_sw, \
             patch("twl.autopilot.mergegate._board_update") as mock_board, \
             patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"), \
             patch.object(MergeGate, "_verify_and_close_issue", return_value=False), \
             patch("subprocess.run",
                   return_value=MagicMock(returncode=0, stdout="")):
            with pytest.raises(SystemExit) as exc:
                gate.execute()
            assert exc.value.code == 2
            # Last _state_write must be status=failed with required failure fields
            last_kwargs = mock_sw.call_args_list[-1].kwargs
            assert last_kwargs["status"] == "failed"
            failure = json.loads(last_kwargs["failure"])
            assert failure["reason"] == "issue_not_closed_after_merge"
            assert failure["step"] == "merge-gate-issue-close"
            assert failure["pr"] == 101
            assert "message" in failure
            assert "timestamp" in failure
            # Board must NOT transition to Done
            mock_board.assert_not_called()

    def test_merge_ok_does_not_skip_verify_when_closed(self, gate):
        """Regression: execute must call _verify_and_close_issue after successful merge."""
        with patch("os.getcwd", return_value="/home/user/projects/main"), \
             patch("twl.autopilot.mergegate._check_worker_window_guard"), \
             patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"), \
             patch("twl.autopilot.mergegate._state_write"), \
             patch("twl.autopilot.mergegate._board_update"), \
             patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"), \
             patch.object(MergeGate, "_verify_and_close_issue",
                          return_value=True) as mock_verify, \
             patch("subprocess.run",
                   return_value=MagicMock(returncode=0, stdout="")):
            gate.execute()
            mock_verify.assert_called_once()


class TestGhRepoFlag:
    def test_no_repo_args_no_flag(self, autopilot_dir, scripts_root):
        gate = MergeGate(
            issue="1", pr_number="2", branch="feat/1",
            autopilot_dir=autopilot_dir, scripts_root=scripts_root,
        )
        assert gate._gh_repo_flag() == []

    def test_with_repo_args_builds_flag(self, autopilot_dir, scripts_root):
        gate = MergeGate(
            issue="1", pr_number="2", branch="feat/1",
            repo_owner="myorg", repo_name="myrepo",
            autopilot_dir=autopilot_dir, scripts_root=scripts_root,
        )
        assert gate._gh_repo_flag() == ["-R", "myorg/myrepo"]
