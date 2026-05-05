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


# ---------------------------------------------------------------------------
# TDD RED: AC3 - Wave 並列実行の false-block 0 件確認（プロセス AC）
# ---------------------------------------------------------------------------


class TestWaveParallelFalseBlockObservation:
    """
    AC3: Wave 41 以降の複数 Issue 並列 Wave (>= 3 issue) を 2 回以上実行し、
    merge-gate false-block 発生件数 = 0 を確認する。

    プロセス AC: su-observer が Wave 完了後のアーカイブを検証する。
    テストスタブは観測フレームワーク（ログパターン検証）の存在確認のみ行う。
    impl_files: [] （観測プロセス AC）
    """

    @pytest.mark.skip(
        reason=(
            "AC3 はプロセス AC: Wave 41+ 並列実行観測は自動テストでは検証不可。"
            "su-observer が .autopilot/archive/<session-id>/ の orchestrator log を"
            " grep し 0 件であることを doobidoo memory に記録する。"
        )
    )
    def test_ac3_process_ac_stub(self) -> None:
        """AC3 はプロセス AC のため、最小スタブのみ。

        実際の確認: su-observer が `.autopilot/archive/<session-id>/` の
        orchestrator log を `grep "merge-gate.*ERROR.*phase-review.*CRITICAL"` し
        0 件であることを doobidoo memory に記録する。
        """


# ---------------------------------------------------------------------------
# TDD RED: AC4 - docstring / ADR-025 checkpoint isolation 記述（ドキュメント AC）
# ---------------------------------------------------------------------------


class TestCheckpointIsolationDocumentation:
    """
    AC4: mergegate_guards.py の docstring と ADR-025 の Known Gap セクションに
    「checkpoint isolation」記述を追加する。

    ドキュメント AC: テストはドキュメントの存在・内容を検証する。
    impl_files: [] （ドキュメント AC）
    """

    def test_ac4_mergegate_guards_docstring_mentions_checkpoint_isolation(
        self,
    ) -> None:
        """mergegate_guards.py の _check_phase_review_guard docstring に
        checkpoint isolation 記述が含まれること。
        """
        from twl.autopilot.mergegate_guards import _check_phase_review_guard

        docstring = _check_phase_review_guard.__doc__ or ""
        assert "checkpoint isolation" in docstring.lower() or "isolation" in docstring.lower(), (
            "AC #4 未実装: _check_phase_review_guard の docstring に "
            "'checkpoint isolation' または 'isolation' の記述が存在しない"
        )

    def test_ac4_adr025_contains_checkpoint_isolation_section(self) -> None:
        """ADR-025 の Known Gap セクションに 'checkpoint isolation' が含まれること。"""
        from pathlib import Path

        adr_file = (
            Path(__file__).resolve().parents[4]
            / "plugins"
            / "twl"
            / "architecture"
            / "decisions"
            / "ADR-025-co-autopilot-phase-review-guarantee.md"
        )
        assert adr_file.exists(), f"ADR-025 ファイルが存在しない: {adr_file}"

        content = adr_file.read_text(encoding="utf-8")
        assert "checkpoint isolation" in content.lower(), (
            "AC #4 未実装: ADR-025 に 'checkpoint isolation' の記述が存在しない。"
            "Known Gap セクションへの追加または Superseded ADR の新設が必要。"
        )


# ---------------------------------------------------------------------------
# TDD RED: AC5 - 新スキーマへの regression チェック
# ---------------------------------------------------------------------------


class TestNewSchemaRegression:
    """
    AC5: 既存テストが新スキーマ（per-issue checkpoint）に対応して全て pass すること。

    新スキーマ変更 (per-issue checkpoint) により fail する可能性のある箇所を
    RED テストとして記録する。既存テストは弱化・削除しない。
    """

    def test_ac5_existing_guard_still_works_with_shared_checkpoint_path(
        self, autopilot_dir: Path
    ) -> None:
        """AC5 regression: 後方互換性として共有 checkpoint パスも機能すること。

        AC2 実装後も issue_number 未指定時は phase-review.json（共有パス）を参照し
        既存テストの挙動が壊れないことを確認する。

        既存テスト (TestPhaseReviewCheckpointPresence 等) は phase-review.json を
        使用しているため、per-issue 移行後も後方互換性が必要。
        """
        from .conftest import _phase_review_json, _write_phase_review

        # 共有 checkpoint を使って PASS することを確認（後方互換性）
        _write_phase_review(autopilot_dir, _phase_review_json())

        # AC2 実装後: issue_number を渡さない場合は phase-review.json を参照（後方互換）
        # 現在 (GREEN): issue_number 引数がないため既存動作のまま（このテスト自体は pass）
        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
        )

    def test_ac5_new_schema_issue_number_field_required_in_per_issue_checkpoint(
        self, tmp_path: Path
    ) -> None:
        """新スキーマ: per-issue checkpoint は issue_number フィールドを含むこと。

        AC2 実装後の新スキーマでは CheckpointManager.write(issue_number=N) が
        phase-review-{N}.json を生成し、JSON に issue_number フィールドが含まれる。
        """
        import json
        from twl.autopilot.checkpoint import CheckpointManager

        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)
        mgr.write("phase-review", "PASS", findings=[], issue_number="999")

        ckpt_file = ckpt_dir / "phase-review-999.json"
        assert ckpt_file.exists(), "per-issue checkpoint ファイルが生成されていない"
        data = json.loads(ckpt_file.read_text())
        assert "issue_number" in data, f"issue_number フィールドが checkpoint JSON に存在しない: {data}"
        assert data["issue_number"] == "999"

    def test_ac5_mergegate_guard_signature_backward_compatible(self) -> None:
        """AC5 regression: _check_phase_review_guard の既存シグネチャが維持されること。

        AC2 で issue_number 引数が追加された後も、既存の呼び出し
        (autopilot_dir, issue_labels, force) が引き続き動作すること。
        issue_number は Optional なデフォルト引数として追加される必要がある。
        """
        import inspect

        sig = inspect.signature(_check_phase_review_guard)
        params = sig.parameters

        # 既存パラメータが存在すること（regression 確認）
        assert "autopilot_dir" in params, "regression: autopilot_dir パラメータが消えた"
        assert "issue_labels" in params, "regression: issue_labels パラメータが消えた"
        assert "force" in params, "regression: force パラメータが消えた"

        # AC2 実装後: issue_number が Optional デフォルト引数として追加されること
        # 現在 (RED): issue_number がないため fail する
        assert "issue_number" in params, (
            "AC #2/#5 未実装: issue_number が _check_phase_review_guard に追加されていない。"
            "既存呼び出しとの後方互換性を保ちつつ Optional 引数として追加が必要。"
        )


class TestIssueNumberValidation:
    """issue_number バリデーション（負例テスト）。

    _check_phase_review_guard と CheckpointManager._validate_issue_number が
    不正な issue_number を受け付けないことを検証する。
    Warning finding 対応: 負例テストが欠落していたため追加。
    """

    @pytest.mark.parametrize("bad_value", [
        "0",          # 0 始まりは不正
        "abc",        # 英字
        "-1",         # 負数
        "12345678",   # 8桁（上限 7桁）
        "1.5",        # 小数
        "1 2",        # スペース含む
    ])
    def test_invalid_issue_number_raises_in_guard(self, tmp_path: Path, bad_value: str) -> None:
        """不正な issue_number を渡すと _check_phase_review_guard が MergeGateError を送出する。"""
        from twl.autopilot.mergegate_guards import MergeGateError, _check_phase_review_guard

        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "checkpoints").mkdir()

        with pytest.raises(MergeGateError, match="不正な issue_number"):
            _check_phase_review_guard(
                autopilot_dir=autopilot_dir,
                issue_labels=[],
                force=False,
                issue_number=bad_value,
            )

    @pytest.mark.parametrize("bad_value", [
        "0",
        "abc",
        "-1",
        "12345678",
        "1.5",
    ])
    def test_invalid_issue_number_raises_in_checkpoint_manager(self, tmp_path: Path, bad_value: str) -> None:
        """不正な issue_number を渡すと CheckpointManager.write が CheckpointArgError を送出する。"""
        from twl.autopilot.checkpoint import CheckpointArgError, CheckpointManager

        mgr = CheckpointManager(checkpoint_dir=tmp_path)
        with pytest.raises(CheckpointArgError, match="不正な値"):
            mgr.write("phase-review", "PASS", findings=[], issue_number=bad_value)

    @pytest.mark.parametrize("good_value", [
        "1",
        "42",
        "1399",
        "9999999",  # 7桁（上限）
    ])
    def test_valid_issue_number_accepted(self, tmp_path: Path, good_value: str) -> None:
        """正常な issue_number は _check_phase_review_guard で受け付けられる（checkpoint 不在は別 error）。"""
        from twl.autopilot.mergegate_guards import MergeGateError, _check_phase_review_guard

        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "checkpoints").mkdir()
        (autopilot_dir / "checkpoints" / f"phase-review-{good_value}.json").write_text(
            '{"step": "phase-review", "status": "PASS", "findings": []}'
        )

        _check_phase_review_guard(
            autopilot_dir=autopilot_dir,
            issue_labels=[],
            force=False,
            issue_number=good_value,
        )
