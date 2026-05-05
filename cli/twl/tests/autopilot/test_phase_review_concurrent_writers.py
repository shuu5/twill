"""TDD RED: Concurrent Writer isolation tests for phase-review merge-gate.

AC1: 並列 Worker 環境で merge-gate が他 Worker の finding を読まないことを pytest シナリオで検証する。
N=3 並列 writer 後に各 issue の merge-gate が他 issue の CRITICAL finding で block されないことを assertion する。

RED: これらのテストは per-issue checkpoint isolation (AC2) が実装されるまで fail する。
"""

from __future__ import annotations

import json
import threading
from pathlib import Path

import pytest

from twl.autopilot.mergegate import MergeGate, MergeGateError
from twl.autopilot.mergegate_guards import _check_phase_review_guard


# ---------------------------------------------------------------------------
# AC1: 並列 Worker isolation シナリオ
# ---------------------------------------------------------------------------


class TestConcurrentWriterIsolation:
    """
    Scenario: N=3 並列 Writer 後に各 issue の merge-gate が他 issue の
    CRITICAL finding で block されないことを検証する。

    RED: per-issue checkpoint ファイル (checkpoints/phase-review-{ISSUE_NUMBER}.json)
    が実装されていないため、現在は全 issue が同一の phase-review.json を共有し
    cross-contamination が発生する。
    """

    def _make_issue_autopilot_dir(self, tmp_path: Path, issue_num: str) -> Path:
        """各 issue 用の autopilot dir を作成する。"""
        d = tmp_path / f"issue-{issue_num}" / ".autopilot"
        d.mkdir(parents=True)
        (d / "checkpoints").mkdir()
        return d

    def _write_per_issue_checkpoint(
        self,
        autopilot_dir: Path,
        issue_num: str,
        findings: list[dict],
        status: str = "FAIL",
    ) -> Path:
        """per-issue checkpoint を書き込む。

        AC2 実装後は checkpoints/phase-review-{issue_num}.json に書き込まれる。
        RED 状態では checkpoints/phase-review.json に書き込まれ isolation が機能しない。
        """
        # AC2 実装後: checkpoints/phase-review-{issue_num}.json
        # 現在 (RED): 実装前なので NotImplementedError を送出する
        raise NotImplementedError("AC #1 未実装: per-issue checkpoint writer が存在しない")

    def test_ac1_issue_a_not_blocked_by_issue_b_critical_finding(
        self, tmp_path: Path
    ) -> None:
        """Issue A は Issue B の CRITICAL finding によって block されないこと。

        N=3 並列 writer シナリオ:
        - Issue 101: PASS（CRITICAL finding なし）
        - Issue 102: CRITICAL finding あり（block されるべき）
        - Issue 103: PASS（CRITICAL finding なし）

        Issue 101 と 103 の merge-gate は 102 の CRITICAL finding で block されてはならない。
        """
        raise NotImplementedError(
            "AC #1 未実装: per-issue checkpoint isolation がないため "
            "Issue 101/103 が Issue 102 の CRITICAL finding で誤って block される"
        )

    def test_ac1_three_concurrent_writers_no_cross_contamination(
        self, tmp_path: Path
    ) -> None:
        """N=3 並列 writer が同時にチェックポイントを書き込んでも cross-contamination が発生しないこと。

        各 worker は異なる issue 番号で per-issue checkpoint を書き込む。
        merge-gate は自分の issue の checkpoint のみを読む。
        """
        raise NotImplementedError(
            "AC #1 未実装: concurrent writer isolation テストは "
            "per-issue checkpoint (AC2) の実装が前提"
        )

    def test_ac1_worker_reads_only_own_issue_checkpoint(
        self, tmp_path: Path
    ) -> None:
        """merge-gate は自分の issue 番号に対応した checkpoint のみを読むこと。

        issue_number=200 の merge-gate は checkpoints/phase-review-200.json を読み、
        checkpoints/phase-review-201.json や checkpoints/phase-review.json を
        読まないことを確認する。
        """
        raise NotImplementedError(
            "AC #1 未実装: _check_phase_review_guard が issue_number 引数を受け付けず "
            "per-issue checkpoint ファイルを解決できない"
        )

    def test_ac1_check_phase_review_guard_accepts_issue_number(
        self, tmp_path: Path
    ) -> None:
        """_check_phase_review_guard が issue_number 引数を受け付けること。

        現在の実装は issue_number を受け付けないため、このテストは fail する。
        """
        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "checkpoints").mkdir()

        # per-issue checkpoint を書き込む（issue_number=300）
        per_issue_ckpt = autopilot_dir / "checkpoints" / "phase-review-300.json"
        per_issue_ckpt.write_text(
            json.dumps(
                {
                    "step": "phase-review",
                    "status": "PASS",
                    "findings": [],
                    "issue_number": "300",
                    "timestamp": "2026-05-05T00:00:00Z",
                },
                ensure_ascii=False,
                indent=2,
            )
        )

        # AC2 実装後: issue_number="300" が渡され、per-issue checkpoint を読む
        # 現在 (RED): _check_phase_review_guard に issue_number 引数がないため fail する
        import inspect
        sig = inspect.signature(_check_phase_review_guard)
        assert "issue_number" in sig.parameters, (
            "AC #1/#2 未実装: _check_phase_review_guard に issue_number 引数が存在しない。"
            "per-issue checkpoint を解決できない。"
        )

    def test_ac1_parallel_merge_gates_return_correct_results(
        self, tmp_path: Path
    ) -> None:
        """3 つの parallel merge-gate が同時実行され、各々が正しい判定を返すこと。

        - issue 400: PASS checkpoint → merge-gate は通過
        - issue 401: CRITICAL checkpoint → merge-gate は REJECT
        - issue 402: PASS checkpoint → merge-gate は通過
        """
        raise NotImplementedError(
            "AC #1 未実装: parallel merge-gate の per-issue isolation が未実装。"
            "全 issue が phase-review.json を共有しており、"
            "issue 401 の CRITICAL finding が 400/402 を誤って block する。"
        )
