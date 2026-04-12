"""Integration tests for MergeGate.execute() phase-review guard invocation.

Covers:
  MergeGate.execute() が _check_phase_review_guard を呼び出すことを確認する統合テスト。
"""

from __future__ import annotations

import contextlib
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from twl.autopilot.mergegate import MergeGate, MergeGateError


# ---------------------------------------------------------------------------
# MergeGate.execute() 統合: phase-review guard が呼ばれること
# ---------------------------------------------------------------------------


def _base_patches(stack: contextlib.ExitStack) -> None:
    """execute() の外部依存をすべてモックする。ExitStack 経由で使用する。"""
    stack.enter_context(patch("os.getcwd", return_value="/home/user/projects/main"))
    stack.enter_context(patch("twl.autopilot.mergegate._check_worker_window_guard"))
    stack.enter_context(patch("twl.autopilot.mergegate._state_read", return_value="merge-ready"))
    stack.enter_context(patch("twl.autopilot.mergegate._state_write"))
    stack.enter_context(patch("twl.autopilot.mergegate._board_update"))
    stack.enter_context(patch("twl.autopilot.mergegate._detect_repo_mode", return_value="standard"))
    stack.enter_context(patch("subprocess.run", return_value=MagicMock(returncode=0, stdout="")))


class TestMergeGateExecuteIntegration:
    """execute() が _check_phase_review_guard を呼び出すことを確認する統合テスト。"""

    def test_execute_calls_phase_review_guard(
        self, gate: MergeGate
    ) -> None:
        """execute() は _check_phase_review_guard（またはメソッド相当）を呼び出す。"""
        with contextlib.ExitStack() as stack:
            _base_patches(stack)
            stack.enter_context(patch.object(MergeGate, "_verify_and_close_issue", return_value=True))
            mock_guard = stack.enter_context(
                patch("twl.autopilot.mergegate._check_phase_review_guard")
            )
            gate.execute()
            mock_guard.assert_called_once()

    def test_execute_rejects_when_phase_review_guard_raises(
        self, gate: MergeGate, autopilot_dir: Path
    ) -> None:
        """phase-review checkpoint 不在時、execute() は MergeGateError を送出する。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        with contextlib.ExitStack() as stack:
            _base_patches(stack)
            with pytest.raises((MergeGateError, SystemExit)):
                gate.execute()

    def test_execute_force_continues_when_phase_review_checkpoint_missing(
        self, gate_force: MergeGate, autopilot_dir: Path
    ) -> None:
        """--force 時は checkpoint 不在でも execute() が続行する。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        with contextlib.ExitStack() as stack:
            _base_patches(stack)
            stack.enter_context(patch.object(MergeGate, "_verify_and_close_issue", return_value=True))
            gate_force.execute()
