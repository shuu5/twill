"""TDD RED: Concurrent Writer isolation tests for phase-review merge-gate.

AC1: 並列 Worker 環境で merge-gate が他 Worker の finding を読まないことを pytest シナリオで検証する。
N=3 並列 writer 後に各 issue の merge-gate が他 issue の CRITICAL finding で block されないことを assertion する。

RED: これらのテストは per-issue checkpoint isolation (AC2) が実装されるまで fail する。
"""

from __future__ import annotations

import json
import threading  # noqa: F401  # used in GREEN phase (concurrent writer tests)
from pathlib import Path

import pytest

from twl.autopilot.mergegate import MergeGate, MergeGateError  # noqa: F401  # used in GREEN phase
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

    def _setup_per_issue_ckpt(self, autopilot_dir: Path, issue_num: str, findings: list, status: str = "FAIL") -> None:
        ckpt = autopilot_dir / "checkpoints" / f"phase-review-{issue_num}.json"
        ckpt.write_text(json.dumps(
            {"step": "phase-review", "status": status, "findings": findings, "issue_number": issue_num},
            ensure_ascii=False,
        ))

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
        from twl.autopilot.mergegate import MergeGateError

        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "checkpoints").mkdir()

        self._setup_per_issue_ckpt(autopilot_dir, "101", [], "PASS")
        self._setup_per_issue_ckpt(autopilot_dir, "102", [
            {"severity": "CRITICAL", "confidence": 90, "message": "issue 102 critical finding"}
        ], "FAIL")
        self._setup_per_issue_ckpt(autopilot_dir, "103", [], "PASS")

        # Issue 101: PASS → block されない
        _check_phase_review_guard(autopilot_dir=autopilot_dir, issue_labels=[], force=False, issue_number="101")

        # Issue 102: CRITICAL → block される
        with pytest.raises(MergeGateError, match="CRITICAL"):
            _check_phase_review_guard(autopilot_dir=autopilot_dir, issue_labels=[], force=False, issue_number="102")

        # Issue 103: PASS → block されない
        _check_phase_review_guard(autopilot_dir=autopilot_dir, issue_labels=[], force=False, issue_number="103")

    def test_ac1_three_concurrent_writers_no_cross_contamination(
        self, tmp_path: Path
    ) -> None:
        """N=3 並列 writer が同時にチェックポイントを書き込んでも cross-contamination が発生しないこと。

        各 worker は異なる issue 番号で per-issue checkpoint を書き込む。
        merge-gate は自分の issue の checkpoint のみを読む。
        """
        from twl.autopilot.checkpoint import CheckpointManager
        from twl.autopilot.mergegate import MergeGateError

        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        ckpt_dir = autopilot_dir / "checkpoints"
        ckpt_dir.mkdir()
        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)

        # 3 Workers が concurrent に per-issue checkpoint を書き込む
        mgr.write("phase-review", "PASS", findings=[], issue_number="201")
        mgr.write("phase-review", "FAIL", findings=[
            {"severity": "CRITICAL", "confidence": 90, "message": "worker 202 CRITICAL"}
        ], issue_number="202")
        mgr.write("phase-review", "PASS", findings=[], issue_number="203")

        # 各 merge-gate は自分の checkpoint のみを参照
        _check_phase_review_guard(autopilot_dir=autopilot_dir, issue_labels=[], force=False, issue_number="201")
        with pytest.raises(MergeGateError):
            _check_phase_review_guard(autopilot_dir=autopilot_dir, issue_labels=[], force=False, issue_number="202")
        _check_phase_review_guard(autopilot_dir=autopilot_dir, issue_labels=[], force=False, issue_number="203")

    def test_ac1_worker_reads_only_own_issue_checkpoint(
        self, tmp_path: Path
    ) -> None:
        """merge-gate は自分の issue 番号に対応した checkpoint のみを読むこと。

        issue_number=200 の merge-gate は checkpoints/phase-review-200.json を読み、
        checkpoints/phase-review-201.json や checkpoints/phase-review.json を
        読まないことを確認する。
        """
        from twl.autopilot.mergegate import MergeGateError

        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "checkpoints").mkdir()

        # 200: PASS、201: CRITICAL、shared: CRITICAL
        self._setup_per_issue_ckpt(autopilot_dir, "200", [], "PASS")
        self._setup_per_issue_ckpt(autopilot_dir, "201", [
            {"severity": "CRITICAL", "confidence": 90, "message": "issue 201 CRITICAL"}
        ], "FAIL")
        shared = autopilot_dir / "checkpoints" / "phase-review.json"
        shared.write_text(json.dumps(
            {"step": "phase-review", "status": "FAIL", "findings": [
                {"severity": "CRITICAL", "confidence": 90, "message": "shared CRITICAL"}
            ]}
        ))

        # issue_number=200 は phase-review-200.json を読み、201 や shared の CRITICAL を無視する
        _check_phase_review_guard(autopilot_dir=autopilot_dir, issue_labels=[], force=False, issue_number="200")

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
        import concurrent.futures
        from twl.autopilot.mergegate import MergeGateError

        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "checkpoints").mkdir()

        self._setup_per_issue_ckpt(autopilot_dir, "400", [], "PASS")
        self._setup_per_issue_ckpt(autopilot_dir, "401", [
            {"severity": "CRITICAL", "confidence": 90, "message": "issue 401 CRITICAL finding"}
        ], "FAIL")
        self._setup_per_issue_ckpt(autopilot_dir, "402", [], "PASS")

        results: dict[str, str] = {}

        def run_gate(issue_num: str) -> str:
            try:
                _check_phase_review_guard(
                    autopilot_dir=autopilot_dir, issue_labels=[], force=False, issue_number=issue_num
                )
                return "PASS"
            except MergeGateError:
                return "REJECT"

        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futs = {executor.submit(run_gate, n): n for n in ("400", "401", "402")}
            for fut in concurrent.futures.as_completed(futs):
                results[futs[fut]] = fut.result()

        assert results["400"] == "PASS", f"issue 400 should PASS, got {results['400']}"
        assert results["401"] == "REJECT", f"issue 401 should REJECT, got {results['401']}"
        assert results["402"] == "PASS", f"issue 402 should PASS, got {results['402']}"
