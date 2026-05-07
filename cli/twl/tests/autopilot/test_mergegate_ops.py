"""Unit tests for MergeGateOperationsMixin._run_merge() gh pr ready call (#1500).

AC1: _run_merge に gh pr ready が追加されること。
AC2: gh pr ready 呼び出しの mock 検証。
"""
from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest

from twl.autopilot.mergegate import MergeGate


@pytest.fixture
def gate(tmp_path: Path) -> MergeGate:
    autopilot_dir = tmp_path / ".autopilot"
    (autopilot_dir / "issues").mkdir(parents=True)
    (autopilot_dir / "checkpoints").mkdir()
    scripts_root = tmp_path / "scripts"
    scripts_root.mkdir()
    return MergeGate(
        issue="1500",
        pr_number="1498",
        branch="fix/1500-fixmergegateops-autopilot-path-gh-pr-r",
        autopilot_dir=autopilot_dir,
        scripts_root=scripts_root,
    )


class TestRunMergeGhPrReady:
    """AC1/AC2: _run_merge は gh pr merge 直前に gh pr ready を呼び出す。"""

    def test_ac1_gh_pr_ready_called_before_merge(
        self, gate: MergeGate, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """AC1: gh pr merge 直前に gh pr ready が呼ばれること。"""
        monkeypatch.delenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", raising=False)

        ready_result = MagicMock(returncode=0, stdout="", stderr="")
        merge_result = MagicMock(returncode=0, stdout="", stderr="")

        call_log: list[list[str]] = []

        def _fake_run(cmd: list[str], **kwargs):  # noqa: ANN001
            call_log.append(cmd)
            if "ready" in cmd:
                return ready_result
            return merge_result

        with patch("twl.autopilot.mergegate_ops.subprocess.run", side_effect=_fake_run):
            result = gate._run_merge([])

        assert result is True
        # gh pr ready が呼ばれていること
        ready_calls = [c for c in call_log if "ready" in c]
        assert len(ready_calls) == 1, f"gh pr ready が呼ばれていない: calls={call_log}"
        # gh pr ready が gh pr merge より先に呼ばれていること
        ready_idx = next(i for i, c in enumerate(call_log) if "ready" in c)
        merge_idx = next(i for i, c in enumerate(call_log) if "merge" in c)
        assert ready_idx < merge_idx, "gh pr ready が gh pr merge より後に呼ばれている"

    def test_ac2_gh_pr_ready_fail_raises(
        self, gate: MergeGate, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """AC2: gh pr ready 失敗時は fail-fast し gh pr merge を呼ばない。"""
        monkeypatch.delenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", raising=False)

        ready_result = MagicMock(returncode=1, stdout="", stderr="some error")
        merge_result = MagicMock(returncode=0, stdout="", stderr="")

        call_log: list[list[str]] = []

        def _fake_run(cmd: list[str], **kwargs):  # noqa: ANN001
            call_log.append(cmd)
            if "ready" in cmd:
                return ready_result
            return merge_result

        with patch("twl.autopilot.mergegate_ops.subprocess.run", side_effect=_fake_run), \
             patch("twl.autopilot.mergegate_ops._state_write"):
            result = gate._run_merge([])

        assert result is False, "gh pr ready 失敗時は False を返すべき"
        merge_calls = [c for c in call_log if "merge" in c]
        assert len(merge_calls) == 0, f"gh pr ready 失敗後に gh pr merge が呼ばれた: calls={call_log}"

    def test_ac2_gh_pr_ready_idempotent_already_ready(
        self, gate: MergeGate, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """AC2: PR が既に ready 状態でも gh pr ready は no-op (returncode=0) で継続する。"""
        monkeypatch.delenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", raising=False)

        # "already ready" → returncode=0 と扱う
        ready_result = MagicMock(returncode=0, stdout="", stderr="Pull request #1498 is already ready for review")
        merge_result = MagicMock(returncode=0, stdout="", stderr="")

        call_log: list[list[str]] = []

        def _fake_run(cmd: list[str], **kwargs):  # noqa: ANN001
            call_log.append(cmd)
            if "ready" in cmd:
                return ready_result
            return merge_result

        with patch("twl.autopilot.mergegate_ops.subprocess.run", side_effect=_fake_run):
            result = gate._run_merge([])

        assert result is True
        ready_calls = [c for c in call_log if "ready" in c]
        assert len(ready_calls) == 1, "already ready でも gh pr ready は呼ばれるべき"
        merge_calls = [c for c in call_log if "merge" in c]
        assert len(merge_calls) == 1, "already ready でも gh pr merge は呼ばれるべき"
