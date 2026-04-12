"""Integration tests for MergeGate.execute() phase-review guard invocation.

Covers:
  MergeGate.execute() が _check_phase_review_guard を呼び出すことを確認する統合テスト。
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from twl.autopilot.mergegate import MergeGate, MergeGateError


# ---------------------------------------------------------------------------
# MergeGate.execute() 統合: phase-review guard が呼ばれること
# ---------------------------------------------------------------------------


class TestMergeGateExecuteIntegration:
    """execute() が _check_phase_review_guard を呼び出すことを確認する統合テスト。"""

    def _patch_execute_base(self) -> list:
        """execute() の外部依存をすべてモックするパッチリスト。"""
        return [
            patch("os.getcwd", return_value="/home/user/projects/main"),
            patch("twl.autopilot.mergegate._check_worker_window_guard"),
            patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"),
            patch("twl.autopilot.mergegate._state_write"),
            patch("twl.autopilot.mergegate._board_update"),
            patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"),
            patch.object(MergeGate, "_verify_and_close_issue", return_value=True),
            patch(
                "subprocess.run",
                return_value=MagicMock(returncode=0, stdout=""),
            ),
        ]

    def test_execute_calls_phase_review_guard(
        self, gate: MergeGate
    ) -> None:
        """execute() は _check_phase_review_guard（またはメソッド相当）を呼び出す。"""
        with patch("twl.autopilot.mergegate._check_phase_review_guard") as mock_guard, \
             patch("os.getcwd", return_value="/home/user/projects/main"), \
             patch("twl.autopilot.mergegate._check_worker_window_guard"), \
             patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"), \
             patch("twl.autopilot.mergegate._state_write"), \
             patch("twl.autopilot.mergegate._board_update"), \
             patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"), \
             patch.object(MergeGate, "_verify_and_close_issue", return_value=True), \
             patch("subprocess.run", return_value=MagicMock(returncode=0, stdout="")):
            gate.execute()
            mock_guard.assert_called_once()

    def test_execute_rejects_when_phase_review_guard_raises(
        self, gate: MergeGate, autopilot_dir: Path
    ) -> None:
        """phase-review checkpoint 不在時、execute() は MergeGateError を送出する。"""
        # checkpoint を作成しない（不在状態）
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        with patch("os.getcwd", return_value="/home/user/projects/main"), \
             patch("twl.autopilot.mergegate._check_worker_window_guard"), \
             patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"), \
             patch("twl.autopilot.mergegate._state_write"), \
             patch("twl.autopilot.mergegate._board_update"), \
             patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"), \
             patch("subprocess.run", return_value=MagicMock(returncode=0, stdout="")):
            with pytest.raises((MergeGateError, SystemExit)):
                gate.execute()

    def test_execute_force_continues_when_phase_review_checkpoint_missing(
        self, gate_force: MergeGate, autopilot_dir: Path
    ) -> None:
        """--force 時は checkpoint 不在でも execute() が続行する。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        with patch("os.getcwd", return_value="/home/user/projects/main"), \
             patch("twl.autopilot.mergegate._check_worker_window_guard"), \
             patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"), \
             patch("twl.autopilot.mergegate._state_write"), \
             patch("twl.autopilot.mergegate._board_update"), \
             patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"), \
             patch.object(MergeGate, "_verify_and_close_issue", return_value=True), \
             patch("subprocess.run", return_value=MagicMock(returncode=0, stdout="")):
            # Should not raise
            gate_force.execute()
