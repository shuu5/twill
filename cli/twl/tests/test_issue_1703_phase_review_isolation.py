"""Tests for Issue #1703: phase-review checkpoint per-Worker isolation.

Regression tests for cross-Worker checkpoint pollution in parallel autopilot execution.

AC1: phase-review.json checkpoint を Worker 単位 isolate
  - CheckpointManager.read() に issue_number 引数を追加
  - checkpoint read CLI に --issue-number フラグを追加
  - per-issue ファイルが存在する場合、shared ファイルより優先される

AC2: cross-pollution detection (regression test)
  - 並列 Worker 間で checkpoint 結果が contaminate されない
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from twl.autopilot.checkpoint import (
    CheckpointManager,
    CheckpointArgError,
    main,
    _parse_read_args,
)


@pytest.fixture
def ckpt_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot" / "checkpoints"
    d.mkdir(parents=True)
    return d


@pytest.fixture
def mgr(ckpt_dir: Path) -> CheckpointManager:
    return CheckpointManager(checkpoint_dir=ckpt_dir)


# ---------------------------------------------------------------------------
# AC1: CheckpointManager.read() per-issue isolation
# ---------------------------------------------------------------------------


class TestCheckpointReadIsolation:
    """AC1: CheckpointManager.read() should support issue_number for per-Worker isolation."""

    def test_ac1_checkpoint_read_method_has_issue_number_parameter(self) -> None:
        """CheckpointManager.read() must accept issue_number parameter.

        RED: Currently read() doesn't have issue_number param.
        After fix: read(step, field, issue_number="N") reads checkpoints/{step}-{N}.json
        """
        import inspect

        sig = inspect.signature(CheckpointManager.read)
        assert "issue_number" in sig.parameters, (
            "AC #1 未実装: CheckpointManager.read に issue_number 引数が存在しない。"
            "per-issue checkpoint ファイルを読み込めない。"
        )

    def test_ac1_read_with_issue_number_reads_per_issue_file(
        self, tmp_path: Path
    ) -> None:
        """When per-issue file exists, read(issue_number=N) returns per-issue content.

        RED: Currently read() always reads {step}.json (shared file).
        After fix: read(issue_number="1692") reads phase-review-1692.json first.
        """
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)

        # Write per-issue PASS checkpoint for Worker B (#1692)
        mgr.write(step="phase-review", status="PASS", findings=[], issue_number="1692")

        # Write shared FAIL checkpoint (simulating Worker A's cross-pollution)
        mgr.write(
            step="phase-review",
            status="FAIL",
            findings=[
                {
                    "severity": "WARNING",
                    "category": "ac_missing",
                    "message": "Worker A: AC not met",
                }
            ],
        )

        # Read with issue_number=1692 → should return PASS (per-issue), not FAIL (shared)
        result = mgr.read(step="phase-review", field="status", issue_number="1692")
        assert result == "PASS", (
            f"AC #1 未実装: issue_number='1692' で read() を呼ぶと shared file の 'FAIL' が返る。"
            f"per-issue file 'phase-review-1692.json' の 'PASS' が返るべき。実際: {result!r}"
        )

    def test_ac1_read_with_issue_number_falls_back_to_shared_when_per_issue_absent(
        self, mgr: CheckpointManager
    ) -> None:
        """When per-issue file is absent, read(issue_number=N) falls back to shared file.

        Backward compatibility: if per-issue file doesn't exist, shared file is used.
        """
        # Write only shared checkpoint (no per-issue)
        mgr.write(step="phase-review", status="PASS")

        # Read with issue_number → should fall back to shared and return PASS
        result = mgr.read(step="phase-review", field="status", issue_number="999")
        assert result == "PASS", (
            f"AC #1 後方互換: per-issue file 不在時は shared file にフォールバックすべき。"
            f"実際: {result!r}"
        )

    def test_ac1_read_cli_accepts_issue_number_flag(self) -> None:
        """CLI checkpoint read should accept --issue-number flag.

        RED: Currently _parse_read_args does not parse --issue-number.
        After fix: --issue-number "1692" sets issue_number="1692" in result.
        """
        try:
            result = _parse_read_args(
                [
                    "--step",
                    "phase-review",
                    "--field",
                    "status",
                    "--issue-number",
                    "1692",
                ]
            )
            assert result.get("issue_number") == "1692", (
                f"AC #1 未実装: --issue-number は parse されるが issue_number キーが"
                f"返り値に含まれない: {result}"
            )
        except SystemExit:
            raise AssertionError(
                "AC #1 未実装: checkpoint read CLI が --issue-number 引数を認識せず"
                " Unknown argument エラーで exit した"
            )


# ---------------------------------------------------------------------------
# AC2: cross-pollution regression
# ---------------------------------------------------------------------------


class TestCrossPolluionRegression:
    """AC2: Parallel Worker checkpoint isolation regression tests.

    Simulates the Wave U.audit-fix-H incident: 5 Workers, cross-pollution caused
    all PRs to be rejected even though individual reviews were PASS.
    """

    def test_ac2_worker_b_read_not_polluted_by_worker_a_per_issue_write(
        self, tmp_path: Path
    ) -> None:
        """Worker A writing FAIL per-issue must not affect Worker B's per-issue read.

        Scenario:
          - Worker A (#1691): writes phase-review-1691.json with FAIL
          - Worker B (#1692): writes phase-review-1692.json with PASS
          - Worker B reads phase-review-1692.json → PASS (no pollution from A)

        This test verifies the fundamental isolation guarantee.
        """
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)

        # Worker A: FAIL with CRITICAL finding
        mgr.write(
            step="phase-review",
            status="FAIL",
            findings=[
                {
                    "severity": "CRITICAL",
                    "confidence": 90,
                    "message": "Worker A: critical issue found",
                }
            ],
            issue_number="1691",
        )

        # Worker B: PASS
        mgr.write(step="phase-review", status="PASS", findings=[], issue_number="1692")

        # Worker B reads its own checkpoint → PASS (not affected by A)
        result_b = mgr.read(step="phase-review", field="status", issue_number="1692")
        assert result_b == "PASS", (
            f"AC #2 回帰: Worker B (#1692) が Worker A (#1691) の FAIL に pollute された。"
            f"Worker B の read 結果: {result_b!r}"
        )

    def test_ac2_shared_fail_does_not_affect_per_issue_pass_read(
        self, tmp_path: Path
    ) -> None:
        """Shared phase-review.json FAIL must not affect per-issue PASS read.

        Simulates the actual incident: shared file gets overwritten with FAIL,
        but per-issue file exists with PASS → per-issue should win.

        RED: Currently read() always reads shared file, ignoring issue_number.
        """
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        ckpt_dir.mkdir(parents=True)
        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)

        # Write per-issue PASS for Worker B
        mgr.write(step="phase-review", status="PASS", findings=[], issue_number="1692")

        # Simulate cross-pollution: shared file gets overwritten with FAIL (another Worker)
        shared_file = ckpt_dir / "phase-review.json"
        shared_file.write_text(
            json.dumps(
                {
                    "step": "phase-review",
                    "status": "FAIL",
                    "findings": [
                        {
                            "severity": "WARNING",
                            "category": "ac_missing",
                            "message": "CROSS-POLLUTED: AC missing from another Worker",
                        }
                    ],
                    "critical_count": 0,
                    "findings_summary": "0 CRITICAL, 1 WARNING",
                    "timestamp": "2026-05-12T00:00:00Z",
                },
                ensure_ascii=False,
            )
        )

        # Worker B reads with its issue_number → should get PASS (per-issue), not FAIL (shared)
        result = mgr.read(step="phase-review", field="status", issue_number="1692")
        assert result == "PASS", (
            f"AC #2 回帰: shared file の FAIL が per-issue PASS を上書きした。"
            f"per-issue file が存在する場合は shared file を無視すべき。実際: {result!r}"
        )

    def test_ac2_five_parallel_workers_no_cross_pollution(
        self, tmp_path: Path
    ) -> None:
        """5 parallel Workers (Wave U.audit-fix-H incident simulation).

        All 5 Workers have PASS checkpoints. Each should read its own checkpoint.
        No cross-pollution: reading Worker N's checkpoint returns PASS.
        """
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)

        issue_numbers = ["1691", "1692", "1693", "1694", "1699"]

        # All Workers write PASS per-issue checkpoints
        for issue_num in issue_numbers:
            mgr.write(
                step="phase-review", status="PASS", findings=[], issue_number=issue_num
            )

        # Simulate last Worker somehow writing FAIL to shared (cross-pollution scenario)
        (ckpt_dir / "phase-review.json").write_text(
            json.dumps(
                {
                    "step": "phase-review",
                    "status": "FAIL",
                    "findings": [
                        {
                            "severity": "CRITICAL",
                            "confidence": 90,
                            "message": "Shared FAIL: cross-pollution",
                        }
                    ],
                    "critical_count": 1,
                    "findings_summary": "1 CRITICAL, 0 WARNING",
                    "timestamp": "2026-05-12T00:00:00Z",
                },
                ensure_ascii=False,
            )
        )

        # Each Worker reads its own checkpoint → all should be PASS
        for issue_num in issue_numbers:
            result = mgr.read(
                step="phase-review", field="status", issue_number=issue_num
            )
            assert result == "PASS", (
                f"AC #2 回帰: Worker #{issue_num} が shared FAIL に pollute された。"
                f"5 Workers 並列シミュレーション。実際: {result!r}"
            )
