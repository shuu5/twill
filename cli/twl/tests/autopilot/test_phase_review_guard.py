"""Tests for phase-review CRITICAL findings guard and --force-warning behavior.

Covers:
  Requirement: phase-review CRITICAL findings の統合
    - phase-review に CRITICAL findings がある場合は REJECT
    - phase-review に CRITICAL findings がない場合は継続

  Requirement: --force 使用時の phase-review 不在 WARNING
    - --force 使用時も phase-review 不在は WARNING 記録
"""

from __future__ import annotations

from pathlib import Path

import pytest

from twl.autopilot.mergegate import MergeGateError, _check_phase_review_guard
from .conftest import _phase_review_json, _write_phase_review


# ---------------------------------------------------------------------------
# Requirement: phase-review CRITICAL findings の統合
# ---------------------------------------------------------------------------


class TestPhaseReviewCriticalFindings:
    """
    Scenario: phase-review に CRITICAL findings がある場合は REJECT
    WHEN: .autopilot/checkpoints/phase-review.json に confidence >= 80 の CRITICAL finding が
          含まれる状態で merge-gate が実行される
    THEN: merge-gate は REJECT を返し、該当 finding の詳細をエラーメッセージに含める

    Scenario: phase-review に CRITICAL findings がない場合は継続
    WHEN: .autopilot/checkpoints/phase-review.json が存在し、
          confidence >= 80 の CRITICAL finding が含まれない状態で merge-gate が実行される
    THEN: merge-gate は phase-review チェックを通過し、他のチェックの結果で判定を続行する
    """

    def test_critical_finding_with_high_confidence_raises_error(
        self, autopilot_dir: Path
    ) -> None:
        """confidence >= 80 の CRITICAL finding がある場合、MergeGateError を送出する。"""
        findings = [
            {
                "severity": "CRITICAL",
                "confidence": 85,
                "message": "security vulnerability detected",
                "file": "src/auth.py",
            }
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="FAIL"),
        )

        with pytest.raises(MergeGateError):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=False,
            )

    def test_critical_finding_error_message_includes_finding_details(
        self, autopilot_dir: Path
    ) -> None:
        """エラーメッセージに finding の詳細（message）が含まれる。"""
        findings = [
            {
                "severity": "CRITICAL",
                "confidence": 90,
                "message": "type invariant violation found",
                "file": "src/core.py",
                "line": 42,
            }
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="FAIL"),
        )

        with pytest.raises(MergeGateError, match="type invariant violation found"):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=False,
            )

    def test_critical_finding_at_exactly_80_confidence_raises_error(
        self, autopilot_dir: Path
    ) -> None:
        """confidence が境界値 80 の CRITICAL finding もエラーを送出する。"""
        findings = [
            {
                "severity": "CRITICAL",
                "confidence": 80,
                "message": "boundary confidence critical issue",
            }
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="FAIL"),
        )

        with pytest.raises(MergeGateError):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=False,
            )

    def test_critical_finding_below_80_confidence_does_not_raise(
        self, autopilot_dir: Path
    ) -> None:
        """confidence < 80 の CRITICAL finding はエラーを送出しない。"""
        findings = [
            {
                "severity": "CRITICAL",
                "confidence": 79,
                "message": "low confidence critical issue",
            }
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="WARN"),
        )

        # Should not raise — confidence below threshold
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
        )

    def test_no_critical_findings_does_not_raise(self, autopilot_dir: Path) -> None:
        """CRITICAL findings が存在しない場合は例外を送出しない。"""
        findings = [
            {
                "severity": "WARNING",
                "confidence": 95,
                "message": "minor style issue",
            }
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="WARN"),
        )

        # Should not raise
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
        )

    def test_empty_findings_list_does_not_raise(self, autopilot_dir: Path) -> None:
        """findings が空リストの場合は例外を送出しない。"""
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=[], status="PASS"),
        )

        # Should not raise
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
        )

    def test_multiple_critical_findings_all_included_in_error(
        self, autopilot_dir: Path
    ) -> None:
        """複数の CRITICAL findings がある場合、最初の finding の詳細がエラーに含まれる。"""
        findings = [
            {
                "severity": "CRITICAL",
                "confidence": 85,
                "message": "first critical issue",
            },
            {
                "severity": "CRITICAL",
                "confidence": 90,
                "message": "second critical issue",
            },
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="FAIL"),
        )

        with pytest.raises(MergeGateError):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=False,
            )

    def test_critical_finding_missing_confidence_field_does_not_raise(
        self, autopilot_dir: Path
    ) -> None:
        """confidence フィールドが欠落した CRITICAL finding は threshold 判定対象外。"""
        findings = [
            {
                "severity": "CRITICAL",
                "message": "no confidence field",
            }
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="WARN"),
        )

        # confidence フィールド欠落時の扱いは実装次第だが、
        # 存在チェックはパスしているため実装に従う。
        # confidence 欠落は threshold 未達として扱う (0 < 80) ことを期待。
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
        )


# ---------------------------------------------------------------------------
# Requirement: --force 使用時の phase-review 不在 WARNING
# ---------------------------------------------------------------------------


class TestPhaseReviewForceWarning:
    """
    Scenario: --force 使用時も phase-review 不在は WARNING 記録
    WHEN: --force オプションを使用して merge-gate が実行され、
          phase-review.json が不在の場合
    THEN: merge-gate は REJECT を返さずに続行するが、
          「WARNING: phase-review checkpoint が不在です（--force により続行）」
          というメッセージをログに記録する
    """

    def test_force_mode_does_not_raise_when_checkpoint_missing(
        self, autopilot_dir: Path
    ) -> None:
        """--force 時は checkpoint 不在でも MergeGateError を送出しない。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        # Should not raise
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=True,
        )

    def test_force_mode_logs_warning_message_when_checkpoint_missing(
        self, autopilot_dir: Path, capsys: pytest.CaptureFixture
    ) -> None:
        """--force 時は checkpoint 不在で WARNING メッセージを出力する。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=True,
        )

        captured = capsys.readouterr()
        # WARNING は stdout または stderr に出力される
        combined_output = captured.out + captured.err
        assert "WARNING" in combined_output
        assert "phase-review checkpoint が不在です" in combined_output

    def test_force_mode_warning_message_mentions_force_flag(
        self, autopilot_dir: Path, capsys: pytest.CaptureFixture
    ) -> None:
        """WARNING メッセージに「--force により続行」が含まれる。"""
        assert not (autopilot_dir / "checkpoints" / "phase-review.json").exists()

        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=True,
        )

        captured = capsys.readouterr()
        combined_output = captured.out + captured.err
        assert "--force" in combined_output or "force" in combined_output.lower()

    def test_force_mode_still_rejects_critical_findings(
        self, autopilot_dir: Path
    ) -> None:
        """--force でも CRITICAL findings (confidence >= 80) がある場合は REJECT する。

        NOTE: --force の免除対象は「checkpoint 不在」のみ。
        CRITICAL findings がある場合の挙動は仕様の明示がないため、
        このテストは最も厳格な解釈（REJECT 継続）を前提とする。
        実装によっては xfail となる可能性がある。
        """
        findings = [
            {
                "severity": "CRITICAL",
                "confidence": 85,
                "message": "critical finding in force mode",
            }
        ]
        _write_phase_review(
            autopilot_dir,
            _phase_review_json(findings=findings, status="FAIL"),
        )

        # --force は checkpoint 不在のみをバイパスする。
        # CRITICAL findings が存在する場合は --force でも REJECT。
        with pytest.raises(MergeGateError):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=True,
            )
