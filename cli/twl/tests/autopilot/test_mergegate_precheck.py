"""Unit tests for MergeGateOperationsMixin._run_merge() PRECHECK + conflict branches.

Covers #875 failure categories driven by MVP flag #872 (PRECHECK):
  - C2 (merge_conflict): `gh pr merge --squash` 失敗時に stderr が conflict を示すと
    failure.reason=merge_conflict, status=conflict が記録される
  - C4 (branch_protection): DEV_AUTOPILOT_MERGEABILITY_PRECHECK=true + gh pr view の
    mergeStateStatus ∈ {UNSTABLE, BLOCKED, BEHIND} で fail-fast (failure.reason=branch_protection_*)

C1 (poll_timeout) は test_orchestrator_stagnation.py でカバー済み、
C3 (merge-ready race) / C5 (inject_exhausted) / C6 (LLM stall) は bats / observer 手順側担当。
"""
from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

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
        issue="875",
        pr_number="900",
        branch="feat/875-bats-six-category",
        autopilot_dir=autopilot_dir,
        scripts_root=scripts_root,
    )


def _mock_run_sequence(results: list[MagicMock]) -> MagicMock:
    """subprocess.run の side_effect で順次 MagicMock を返す iterator."""
    it = iter(results)
    return MagicMock(side_effect=lambda *a, **kw: next(it))


class TestPrecheckBranchProtection:
    """C4: DEV_AUTOPILOT_MERGEABILITY_PRECHECK=true で branch protection fail-fast."""

    @pytest.mark.parametrize("state,expected_reason", [
        ("UNSTABLE", "branch_protection_unstable"),
        ("BLOCKED", "branch_protection_blocked"),
        ("BEHIND", "branch_protection_behind"),
    ])
    def test_precheck_blocks_protected_state(
        self, gate: MergeGate, state: str, expected_reason: str, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", "true")
        precheck_result = MagicMock(returncode=0, stdout=json.dumps({"mergeStateStatus": state}))

        with patch("twl.autopilot.mergegate_ops.subprocess.run", return_value=precheck_result) as mock_run, \
             patch("twl.autopilot.mergegate_ops._state_write") as mock_write:
            ret = gate._run_merge([])

        assert ret is False
        # precheck のみが呼ばれ、gh pr merge には進まない
        assert mock_run.call_count == 1
        call_args = mock_run.call_args_list[0].args[0]
        assert call_args[:4] == ["gh", "pr", "view", gate.pr_number]
        assert "mergeStateStatus" in call_args
        # _state_write が failed + 正しい reason で呼ばれる
        mock_write.assert_called_once()
        kwargs = mock_write.call_args.kwargs
        assert kwargs["status"] == "failed"
        failure_payload = json.loads(kwargs["failure"])
        assert failure_payload["reason"] == expected_reason
        assert failure_payload["step"] == "merge-gate-precheck"

    def test_precheck_skipped_when_flag_off(
        self, gate: MergeGate, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.delenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", raising=False)
        ready_result = MagicMock(returncode=0, stdout="", stderr="")
        merge_result = MagicMock(returncode=0, stdout="", stderr="")

        call_log: list[list[str]] = []

        def _fake(cmd: list[str], **kw):  # noqa: ANN001
            call_log.append(cmd)
            if "ready" in cmd:
                return ready_result
            return merge_result

        with patch("twl.autopilot.mergegate_ops.subprocess.run", side_effect=_fake):
            ret = gate._run_merge([])

        assert ret is True
        # precheck スキップ、gh pr ready → gh pr merge の順で呼ばれる
        assert len(call_log) == 2
        assert call_log[0][:3] == ["gh", "pr", "ready"]
        assert call_log[1][:3] == ["gh", "pr", "merge"]

    def test_precheck_clean_proceeds_to_merge(
        self, gate: MergeGate, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """CLEAN 等 OK 状態なら precheck を通過して merge 実行."""
        monkeypatch.setenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", "true")
        precheck_result = MagicMock(returncode=0, stdout=json.dumps({"mergeStateStatus": "CLEAN"}))
        ready_result = MagicMock(returncode=0, stdout="", stderr="")
        merge_result = MagicMock(returncode=0, stdout="", stderr="")

        with patch(
            "twl.autopilot.mergegate_ops.subprocess.run",
            new=_mock_run_sequence([precheck_result, ready_result, merge_result]),
        ):
            ret = gate._run_merge([])

        assert ret is True


class TestMergeConflictClassification:
    """C2: gh pr merge --squash 失敗を conflict vs merge_failed に分類."""

    @pytest.mark.parametrize("stderr_msg", [
        "this branch has conflicts",
        "Pull request is not mergeable: conflict",
        "merge conflict detected",
    ])
    def test_merge_conflict_records_conflict_reason(
        self, gate: MergeGate, stderr_msg: str, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.delenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", raising=False)
        ready_result = MagicMock(returncode=0, stdout="", stderr="")
        merge_result = MagicMock(returncode=1, stdout="", stderr=stderr_msg)

        def _fake(cmd: list[str], **kw):  # noqa: ANN001
            if "ready" in cmd:
                return ready_result
            return merge_result

        with patch("twl.autopilot.mergegate_ops.subprocess.run", side_effect=_fake), \
             patch("twl.autopilot.mergegate_ops._state_write") as mock_write:
            ret = gate._run_merge([])

        assert ret is False
        mock_write.assert_called_once()
        kwargs = mock_write.call_args.kwargs
        assert kwargs["status"] == "conflict"
        failure_payload = json.loads(kwargs["failure"])
        assert failure_payload["reason"] == "merge_conflict"
        assert failure_payload["step"] == "merge-gate"

    def test_non_conflict_failure_records_merge_failed(
        self, gate: MergeGate, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.delenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", raising=False)
        ready_result = MagicMock(returncode=0, stdout="", stderr="")
        merge_result = MagicMock(
            returncode=1, stdout="", stderr="GraphQL: Required status check \"build\" is pending."
        )

        def _fake(cmd: list[str], **kw):  # noqa: ANN001
            if "ready" in cmd:
                return ready_result
            return merge_result

        with patch("twl.autopilot.mergegate_ops.subprocess.run", side_effect=_fake), \
             patch("twl.autopilot.mergegate_ops._state_write") as mock_write:
            ret = gate._run_merge([])

        assert ret is False
        mock_write.assert_called_once()
        kwargs = mock_write.call_args.kwargs
        assert kwargs["status"] == "failed"
        failure_payload = json.loads(kwargs["failure"])
        assert failure_payload["reason"] == "merge_failed"

    def test_credentials_masked_in_failure_details(
        self, gate: MergeGate, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.delenv("DEV_AUTOPILOT_MERGEABILITY_PRECHECK", raising=False)
        ready_result = MagicMock(returncode=0, stdout="", stderr="")
        merge_result = MagicMock(
            returncode=1, stdout="",
            stderr="auth failed with ghp_abcdef123456 not mergeable conflict",
        )

        def _fake(cmd: list[str], **kw):  # noqa: ANN001
            if "ready" in cmd:
                return ready_result
            return merge_result

        with patch("twl.autopilot.mergegate_ops.subprocess.run", side_effect=_fake), \
             patch("twl.autopilot.mergegate_ops._state_write") as mock_write:
            gate._run_merge([])

        failure_payload = json.loads(mock_write.call_args.kwargs["failure"])
        assert "ghp_abcdef123456" not in failure_payload["details"]
        assert "ghp_***MASKED***" in failure_payload["details"]
