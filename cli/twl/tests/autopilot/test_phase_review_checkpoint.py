"""Tests for phase-review checkpoint existence and skip-label handling.

Covers:
  Requirement: phase-review checkpoint 存在チェック
    - phase-review checkpoint が不在の場合は REJECT
    - scope/direct ラベル付き Issue は phase-review チェックをスキップ
    - quick ラベル付き Issue は phase-review チェックをスキップ
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


# ---------------------------------------------------------------------------
# Requirement: phase-review checkpoint 存在チェック（スキップ条件）
# ---------------------------------------------------------------------------


class TestPhaseReviewCheckpointSkipLabels:
    """
    Scenario: scope/direct ラベル付き Issue は phase-review チェックをスキップ
    WHEN: Issue に scope/direct ラベルが付与されており、
          phase-review.json が不在の状態で merge-gate が実行される
    THEN: merge-gate は phase-review チェックをスキップし、
          他のチェックの結果で判定を続行する

    Scenario: quick ラベル付き Issue は phase-review チェックをスキップ
    WHEN: Issue に quick ラベルが付与されており、
          phase-review.json が不在の状態で merge-gate が実行される
    THEN: merge-gate は phase-review チェックをスキップし、
          他のチェックの結果で判定を続行する
    """

    def test_scope_direct_label_skips_check_when_checkpoint_missing(
        self, autopilot_dir: Path
    ) -> None:
        """scope/direct ラベルがある場合、checkpoint 不在でも例外を送出しない。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        # Should not raise
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=["scope/direct"],
            force=False,
        )

    def test_quick_label_skips_check_when_checkpoint_missing(
        self, autopilot_dir: Path
    ) -> None:
        """quick ラベルがある場合、checkpoint 不在でも例外を送出しない。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        # Should not raise
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=["quick"],
            force=False,
        )

    def test_scope_direct_label_also_skips_critical_findings_check(
        self, autopilot_dir: Path
    ) -> None:
        """scope/direct ラベルがある場合、CRITICAL findings があっても例外を送出しない。"""
        findings = [
            {"severity": "CRITICAL", "confidence": 90, "message": "critical issue"},
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="FAIL"),
        )

        # Should not raise — label-based skip applies to all phase-review checks
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=["scope/direct"],
            force=False,
        )

    def test_quick_label_also_skips_critical_findings_check(
        self, autopilot_dir: Path
    ) -> None:
        """quick ラベルがある場合、CRITICAL findings があっても例外を送出しない。"""
        findings = [
            {"severity": "CRITICAL", "confidence": 95, "message": "critical issue"},
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="FAIL"),
        )

        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=["quick"],
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

    def test_multiple_labels_including_quick_skips_check(
        self, autopilot_dir: Path
    ) -> None:
        """複数ラベル中に quick が含まれる場合もスキップ。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        # Should not raise
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=["bug", "quick", "enhancement"],
            force=False,
        )
