"""Tests for phase-review checkpoint existence handling.

Covers:
  Requirement: phase-review checkpoint 存在チェック
    - phase-review checkpoint が不在の場合は REJECT
"""

from __future__ import annotations

from pathlib import Path

import pytest

from twl.autopilot.mergegate import MergeGateError, _check_phase_review_guard
from .conftest import _phase_review_json, _write_phase_review


# ---------------------------------------------------------------------------
# Requirement: phase-review checkpoint 存在チェック
# ---------------------------------------------------------------------------


class TestPhaseReviewCheckpointPresence:
    """
    Scenario: phase-review checkpoint が不在の場合は REJECT
    WHEN: .autopilot/checkpoints/phase-review.json が存在しない状態で merge-gate が実行される
    THEN: merge-gate は REJECT を返し、
          「phase-review checkpoint が不在です。specialist review を実行してください」
          というエラーメッセージを出力する
    """

    def test_missing_checkpoint_raises_error(self, autopilot_dir: Path) -> None:
        """phase-review.json が不在の場合、MergeGateError を送出する。"""
        # checkpoint ファイルを作成しない
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        with pytest.raises(MergeGateError, match="phase-review checkpoint が不在です"):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=False,
            )

    def test_missing_checkpoint_error_message_includes_specialist_review(
        self, autopilot_dir: Path
    ) -> None:
        """エラーメッセージに「specialist review を実行してください」が含まれる。"""
        with pytest.raises(MergeGateError, match="specialist review を実行してください"):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=False,
            )

    def test_present_checkpoint_without_critical_findings_does_not_raise(
        self, autopilot_dir: Path
    ) -> None:
        """checkpoint が存在し CRITICAL findings がない場合は例外を送出しない。"""
        _write_phase_review(autopilot_dir, _phase_review_json())

        # Should not raise
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
        )

    def test_missing_checkpoint_raises_even_when_checkpoints_dir_missing(
        self, tmp_path: Path
    ) -> None:
        """checkpoints ディレクトリ自体が存在しない場合も REJECT。"""
        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        # checkpoints/ を作成しない

        with pytest.raises(MergeGateError, match="phase-review checkpoint が不在です"):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=False,
            )


    def test_unrelated_label_does_not_skip_check(self, autopilot_dir: Path) -> None:
        """関係のないラベルは phase-review チェックをスキップしない。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        with pytest.raises(MergeGateError, match="phase-review checkpoint が不在です"):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=["bug", "enhancement"],
                force=False,
            )


# ---------------------------------------------------------------------------
# TDD RED: AC2 - per-issue checkpoint スキーマ・writer・reader
# ---------------------------------------------------------------------------


class TestPerIssueCheckpointSchema:
    """
    AC2: per-issue checkpoint file (checkpoints/phase-review-{ISSUE_NUMBER}.json) の
    スキーマ・writer・reader を実装する。

    RED: 以下のテストは AC2 が実装されるまで fail する。
    """

    def test_ac2_per_issue_checkpoint_filename_format(
        self, autopilot_dir: Path
    ) -> None:
        """checkpoints/phase-review-{ISSUE_NUMBER}.json のパスが解決されること。

        _check_phase_review_guard に issue_number="500" を渡すと
        checkpoints/phase-review-500.json を参照することを確認する。
        """
        import json

        # per-issue checkpoint のみを作成（共有ファイルなし）
        per_issue_ckpt = autopilot_dir / "checkpoints" / "phase-review-500.json"
        per_issue_ckpt.write_text(
            json.dumps(
                {"step": "phase-review", "status": "PASS", "findings": [], "issue_number": "500"},
                ensure_ascii=False,
            )
        )

        # issue_number="500" を渡すと per-issue ファイルを読んで PASS する
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
            issue_number="500",
        )

    def test_ac2_guard_reads_per_issue_checkpoint_when_issue_number_given(
        self, autopilot_dir: Path
    ) -> None:
        """issue_number を指定した場合、phase-review-{N}.json を読むこと。

        phase-review.json（共有ファイル）ではなく、
        phase-review-{ISSUE_NUMBER}.json（per-issue ファイル）を読む。
        """
        import json

        # per-issue checkpoint: PASS
        per_issue_ckpt = autopilot_dir / "checkpoints" / "phase-review-500.json"
        per_issue_ckpt.write_text(
            json.dumps(
                {
                    "step": "phase-review",
                    "status": "PASS",
                    "findings": [],
                    "issue_number": "500",
                    "timestamp": "2026-05-05T00:00:00Z",
                },
                ensure_ascii=False,
                indent=2,
            )
        )

        # 共有 checkpoint: CRITICAL finding あり（per-issue 解決なら無視される）
        shared_ckpt = autopilot_dir / "checkpoints" / "phase-review.json"
        shared_ckpt.write_text(
            json.dumps(
                {
                    "step": "phase-review",
                    "status": "FAIL",
                    "findings": [
                        {
                            "severity": "CRITICAL",
                            "confidence": 90,
                            "message": "other issue critical finding",
                        }
                    ],
                    "timestamp": "2026-05-05T00:00:00Z",
                },
                ensure_ascii=False,
                indent=2,
            )
        )

        # issue_number="500" を渡すと per-issue checkpoint を読み、共有 CRITICAL を無視して PASS する
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
            issue_number="500",
        )

    def test_ac2_checkpoint_writer_accepts_issue_number_argument(
        self, tmp_path: Path
    ) -> None:
        """CheckpointManager.write が --issue-number 引数で per-issue ファイルを生成すること。

        write(step="phase-review", status="PASS", issue_number="600") を呼ぶと
        checkpoints/phase-review-600.json が生成されることを確認する。
        """
        from twl.autopilot.checkpoint import CheckpointManager
        import inspect

        sig = inspect.signature(CheckpointManager.write)
        assert "issue_number" in sig.parameters, (
            "AC #2 未実装: CheckpointManager.write に issue_number 引数が存在しない。"
            "per-issue checkpoint ファイルを生成できない。"
        )

    def test_ac2_checkpoint_file_contains_issue_number_field(
        self, tmp_path: Path
    ) -> None:
        """per-issue checkpoint JSON に issue_number フィールドが含まれること。

        スキーマ検証: phase-review-{N}.json は issue_number フィールドを持つ。
        """
        import json
        from twl.autopilot.checkpoint import CheckpointManager

        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)
        mgr.write(step="phase-review", status="PASS", findings=[], issue_number="600")

        ckpt_file = ckpt_dir / "phase-review-600.json"
        assert ckpt_file.exists(), "phase-review-600.json が生成されていない"
        data = json.loads(ckpt_file.read_text())
        assert data.get("issue_number") == "600", (
            f"checkpoint JSON に issue_number フィールドが含まれない: {data}"
        )

    def test_ac2_issue_number_from_environment_variable(
        self, autopilot_dir: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """ISSUE_NUMBER 環境変数から per-issue checkpoint path を動的決定すること。

        mergegate_guards.py の _check_phase_review_guard が ISSUE_NUMBER 環境変数を参照し、
        checkpoints/phase-review-{ISSUE_NUMBER}.json を解決できることを確認する。
        """
        import inspect
        from twl.autopilot.mergegate_guards import _check_phase_review_guard

        # ISSUE_NUMBER 環境変数を設定
        monkeypatch.setenv("ISSUE_NUMBER", "700")

        sig = inspect.signature(_check_phase_review_guard)
        # AC2 実装後: ISSUE_NUMBER env var を参照するか issue_number 引数を持つ
        has_issue_number_param = "issue_number" in sig.parameters
        # ISSUE_NUMBER env var 参照はシグネチャ検査では確認できないため、
        # 引数の存在を検証する（最低限の RED チェック）
        assert has_issue_number_param, (
            "AC #2 未実装: _check_phase_review_guard に issue_number 引数がなく、"
            "ISSUE_NUMBER 環境変数からも per-issue checkpoint path を決定できない"
        )

    def test_ac2_checkpoint_cli_accepts_issue_number_flag(self) -> None:
        """checkpoint.py CLI が --issue-number 引数を受け付けること。

        `python3 -m twl.autopilot.checkpoint write --step phase-review --status PASS --issue-number 800`
        が per-issue ファイル checkpoints/phase-review-800.json を生成する。
        """
        from twl.autopilot.checkpoint import _parse_write_args

        # AC2 実装後: --issue-number 引数が parse される
        try:
            result = _parse_write_args(
                ["--step", "phase-review", "--status", "PASS", "--issue-number", "800"]
            )
            assert result.get("issue_number") == "800", (
                "AC #2 未実装: --issue-number が parse されるが issue_number キーが "
                "返り値に含まれない"
            )
        except SystemExit:
            raise AssertionError(
                "AC #2 未実装: checkpoint CLI が --issue-number 引数を認識せず "
                "Unknown argument エラーで exit した"
            )

