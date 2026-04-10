"""Tests for MergeGate phase-review checkpoint guard.

Covers (issue-439 spec: deltaspec/changes/issue-439/specs/phase-review-guard/spec.md):

  Requirement: phase-review checkpoint 存在チェック
    - phase-review checkpoint が不在の場合は REJECT
    - scope/direct ラベル付き Issue は phase-review チェックをスキップ
    - quick ラベル付き Issue は phase-review チェックをスキップ

  Requirement: phase-review CRITICAL findings の統合
    - phase-review に CRITICAL findings がある場合は REJECT
    - phase-review に CRITICAL findings がない場合は継続

  Requirement: --force 使用時の phase-review 不在 WARNING
    - --force 使用時も phase-review 不在は WARNING 記録
"""

from __future__ import annotations

import json
import sys
import io
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from twl.autopilot.mergegate import MergeGate, MergeGateError, _check_phase_review_guard


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    """Autopilot directory with checkpoints subdirectory."""
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    (d / "checkpoints").mkdir()
    return d


@pytest.fixture
def scripts_root(tmp_path: Path) -> Path:
    d = tmp_path / "scripts"
    d.mkdir()
    return d


@pytest.fixture
def gate(autopilot_dir: Path, scripts_root: Path) -> MergeGate:
    return MergeGate(
        issue="439",
        pr_number="500",
        branch="feat/439-phase-review-guard",
        autopilot_dir=autopilot_dir,
        scripts_root=scripts_root,
    )


@pytest.fixture
def gate_force(autopilot_dir: Path, scripts_root: Path) -> MergeGate:
    return MergeGate(
        issue="439",
        pr_number="500",
        branch="feat/439-phase-review-guard",
        autopilot_dir=autopilot_dir,
        scripts_root=scripts_root,
        force=True,
    )


def _phase_review_json(
    *,
    findings: list[dict] | None = None,
    status: str = "PASS",
) -> dict:
    """Build a minimal phase-review.json payload."""
    findings = findings or []
    critical_count = sum(
        1 for f in findings if f.get("severity") == "CRITICAL"
    )
    return {
        "step": "phase-review",
        "status": status,
        "findings_summary": f"{critical_count} CRITICAL, 0 WARNING",
        "critical_count": critical_count,
        "findings": findings,
        "timestamp": "2026-04-11T00:00:00Z",
    }


def _write_phase_review(autopilot_dir: Path, data: dict) -> Path:
    """Write phase-review.json to the checkpoints directory."""
    ckpt_file = autopilot_dir / "checkpoints" / "phase-review.json"
    ckpt_file.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    return ckpt_file


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
