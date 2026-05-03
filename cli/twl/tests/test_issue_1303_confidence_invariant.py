"""TDD RED phase tests for Issue #1303.

tech-debt: checkpoint.py の confidence フィルタ不在と
ac-verify 書き込み経路の依存を明示化

AC-1: 対象 file/symbol の修正実施（body 詳細参照）
  - checkpoint.py write() docstring に「confidence フィルタは書き込み側の責務」の記述がない
  - fix-phase.md 発動条件セクションに confidence への言及がない
  - ac-verify の書き込み経路（ac-impl-coverage-check.sh, ac-verify.md LLM パス）の
    confidence 設定一覧がドキュメント化されていない

AC-2: 修正後 twl validate で WARNING 解消確認（プロセスチェック）

AC-3: 関連 ADR/SKILL/refs に整合する更新
  - checkpoint.py docstring の変更が ref-specialist-output-schema.md など関連 refs と
    整合していること
  - ac-verify.md の CRITICAL Finding テンプレートの confidence 値が設計意図と一致していること

AC-4: regression test — confidence フィルタ不在の設計意図の persistence 確認
  - ac-verify 経由で書き込まれる CRITICAL Finding は必ず confidence >= 80 であること
  - confidence < 80 の CRITICAL Finding は critical_count に加算されるが
    merge-gate でブロックされないこと（設計意図の明示）

AC-1, AC-3, AC-4 は実装後 GREEN。AC-2 は自動化不可のプロセスチェックのため skip。
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

# リポジトリルートの特定
REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent

# 対象ファイルのパス
CHECKPOINT_PY = REPO_ROOT / "cli" / "twl" / "src" / "twl" / "autopilot" / "checkpoint.py"
FIX_PHASE_MD = REPO_ROOT / "plugins" / "twl" / "commands" / "fix-phase.md"
AC_IMPL_COVERAGE_CHECK_SH = REPO_ROOT / "plugins" / "twl" / "scripts" / "ac-impl-coverage-check.sh"
AC_VERIFY_MD = REPO_ROOT / "plugins" / "twl" / "commands" / "ac-verify.md"
REF_SPECIALIST_OUTPUT_SCHEMA_MD = REPO_ROOT / "plugins" / "twl" / "refs" / "ref-specialist-output-schema.md"


# ---------------------------------------------------------------------------
# AC-1: checkpoint.py の write() docstring に confidence への言及
# ---------------------------------------------------------------------------


class TestAC1CheckpointDocstring:
    """AC-1: checkpoint.py write() docstring に confidence フィルタ設計の記述を追加する。

    現在は「Write checkpoint JSON and return a confirmation message.」のみ。
    「CRITICAL severity のみカウントし confidence フィルタは書き込み側の責務」
    という設計意図が docstring に記述されていないため、RED 状態。
    """

    def test_ac1_write_docstring_mentions_confidence_responsibility(self):
        """AC-1: write() docstring に confidence フィルタは書き込み側の責務であることが記述されている。

        RED: 現在の docstring は 'Write checkpoint JSON and return a confirmation message.'
             のみで confidence への言及がない。
        """
        text = CHECKPOINT_PY.read_text(encoding="utf-8")

        # write() メソッドの docstring を抽出
        # def write( ... 直後の """ ... """ を探す
        write_method_match = re.search(
            r'def write\s*\([^)]*\)[^:]*:\s*"""(.*?)"""',
            text,
            re.DOTALL,
        )
        assert write_method_match is not None, "write() メソッドが見つからない"
        docstring = write_method_match.group(1)

        # confidence フィルタは書き込み側の責務であることへの言及
        confidence_mentioned = (
            "confidence" in docstring.lower()
            or "書き込み側" in docstring
            or "writer responsibility" in docstring.lower()
            or "writing side" in docstring.lower()
        )
        assert confidence_mentioned, (
            "AC-1 FAIL: write() docstring に confidence フィルタの設計意図が記述されていない。"
            f"現在の docstring: {docstring.strip()!r}"
        )

    def test_ac1_write_docstring_mentions_critical_only(self):
        """AC-1: write() docstring に critical_count は CRITICAL severity のみカウントすることが記述されている。

        RED: 現在の docstring は設計意図（CRITICAL severity のみカウント）を説明していない。
        """
        text = CHECKPOINT_PY.read_text(encoding="utf-8")

        write_method_match = re.search(
            r'def write\s*\([^)]*\)[^:]*:\s*"""(.*?)"""',
            text,
            re.DOTALL,
        )
        assert write_method_match is not None, "write() メソッドが見つからない"
        docstring = write_method_match.group(1)

        # CRITICAL severity のみカウントする設計意図への言及
        critical_only_mentioned = (
            "CRITICAL" in docstring
            and ("only" in docstring.lower() or "のみ" in docstring or "severity" in docstring.lower())
        )
        assert critical_only_mentioned, (
            "AC-1 FAIL: write() docstring に critical_count は CRITICAL severity のみカウントする設計意図が記述されていない。"
            f"現在の docstring: {docstring.strip()!r}"
        )


# ---------------------------------------------------------------------------
# AC-1: fix-phase.md の発動条件に confidence への言及
# ---------------------------------------------------------------------------


class TestAC1FixPhaseDocumentation:
    """AC-1: fix-phase.md の発動条件セクションに confidence の説明を追加する。

    現在は:
      IF phase_review_critical + ac_verify_critical == 0
      THEN SKIP（修正不要）
    の条件に confidence への言及がない。
    """

    def test_ac1_fix_phase_activation_condition_mentions_confidence(self):
        """AC-1: fix-phase.md の発動条件セクションに confidence への言及がある。

        RED: 現在の fix-phase.md 発動条件セクションには confidence の記述がない。
        """
        text = FIX_PHASE_MD.read_text(encoding="utf-8")
        assert "confidence" in text.lower(), (
            "AC-1 FAIL: fix-phase.md に confidence への言及がない。"
            "発動条件セクションに CRITICAL severity のみを対象とし "
            "confidence フィルタは書き込み側の責務である旨を記述すること。"
        )

    def test_ac1_fix_phase_explains_writer_side_responsibility(self):
        """AC-1: fix-phase.md に書き込み側の責務（confidence 保証）が説明されている。

        RED: 現在は書き込み側の confidence 保証への言及がない。
        """
        text = FIX_PHASE_MD.read_text(encoding="utf-8")

        # 書き込み側の責務または confidence >= 80 の言及
        writer_responsibility_mentioned = (
            "書き込み側" in text
            or "writer" in text.lower()
            or "confidence >= 80" in text
            or "confidence >=80" in text
        )
        assert writer_responsibility_mentioned, (
            "AC-1 FAIL: fix-phase.md に書き込み側の confidence 保証責務の記述がない。"
        )


# ---------------------------------------------------------------------------
# AC-1: ac-verify 書き込み経路の confidence 設定一覧化
# ---------------------------------------------------------------------------


class TestAC1WritePathDocumentation:
    """AC-1: ac-verify 書き込み経路の confidence 設定を一覧化したドキュメントが存在する。

    現在は以下の経路が存在するが、一覧化されていない:
    - ac-impl-coverage-check.sh: CRITICAL=confidence:90, WARNING=confidence:80
    - ac-verify.md LLM delegate パス: CRITICAL=confidence:80, WARNING=confidence:75

    書き込み経路一覧は checkpoint.py docstring または fix-phase.md に記載すること。
    """

    def test_ac1_write_path_inventory_exists_in_checkpoint_or_fix_phase(self):
        """AC-1: ac-verify 書き込み経路の confidence 設定一覧が checkpoint.py または fix-phase.md に存在する。

        RED: 現在どちらのファイルにも書き込み経路一覧のドキュメントがない。
        """
        checkpoint_text = CHECKPOINT_PY.read_text(encoding="utf-8")
        fix_phase_text = FIX_PHASE_MD.read_text(encoding="utf-8")

        # 書き込み経路一覧への言及（ac-impl-coverage-check.sh への言及）
        coverage_check_mentioned = (
            "ac-impl-coverage-check" in checkpoint_text
            or "ac-impl-coverage-check" in fix_phase_text
        )
        assert coverage_check_mentioned, (
            "AC-1 FAIL: ac-verify 書き込み経路一覧（ac-impl-coverage-check.sh 等）が "
            "checkpoint.py または fix-phase.md に記載されていない。"
        )

    def test_ac1_llm_delegate_path_mentioned_in_documentation(self):
        """AC-1: LLM delegate パスの confidence 設定が documentation に記載されている。

        RED: 現在 LLM delegate パスの confidence 設定への言及がない。
        """
        checkpoint_text = CHECKPOINT_PY.read_text(encoding="utf-8")
        fix_phase_text = FIX_PHASE_MD.read_text(encoding="utf-8")
        ac_verify_text = AC_VERIFY_MD.read_text(encoding="utf-8")

        # LLM delegate パスの言及（ac-verify.md の LLM パスの confidence 設定について）
        # ac-verify.md の CRITICAL Finding が confidence=80 である旨の説明
        llm_path_confidence_documented = (
            "LLM delegate" in checkpoint_text
            or "LLM delegate" in fix_phase_text
            or (
                "confidence" in ac_verify_text
                and "CRITICAL" in ac_verify_text
                and (
                    "書き込み側" in ac_verify_text
                    or "責務" in ac_verify_text
                    or "invariant" in ac_verify_text.lower()
                    or "guarantee" in ac_verify_text.lower()
                )
            )
        )
        assert llm_path_confidence_documented, (
            "AC-1 FAIL: LLM delegate パスの confidence 設定が documentation に記載されていない。"
        )


# ---------------------------------------------------------------------------
# AC-2: twl validate プロセスチェック（NotImplementedError）
# ---------------------------------------------------------------------------


class TestAC2TwlValidate:
    """AC-2: 修正後 twl validate で WARNING 解消確認（プロセスチェック）。

    自動テスト不可のプロセスチェック。手動実行: `twl validate` または `twl check`
    で WARNING なしで通過することを確認すること。
    """

    @pytest.mark.skip(reason="AC-2: twl validate は手動プロセスチェックのため自動化不可")
    def test_ac2_twl_validate_process_check(self):
        """AC-2: 修正後に twl validate または該当 specialist で WARNING 解消確認。"""
        pass


# ---------------------------------------------------------------------------
# AC-3: 関連 ADR/SKILL/refs の整合性
# ---------------------------------------------------------------------------


class TestAC3RelatedDocsAlignment:
    """AC-3: 関連 ADR/SKILL/refs に整合する更新。

    ref-specialist-output-schema.md のブロック判定:
    'severity == "CRITICAL" AND confidence >= 80' が merge-gate の条件。
    この条件と checkpoint.py critical_count (confidence フィルタなし) の
    設計意図の整合性が refs に明記されていること。
    """

    def test_ac3_ref_specialist_output_schema_documents_confidence_invariant(self):
        """AC-3: ref-specialist-output-schema.md に confidence >= 80 が書き込み側の責務であることが記述されている。

        RED: 現在は merge-gate フィルタ閾値として 'confidence >= 80' の記述はあるが、
             それが書き込み側で保証されるべき invariant であることが明記されていない。
        """
        text = REF_SPECIALIST_OUTPUT_SCHEMA_MD.read_text(encoding="utf-8")

        # 書き込み側の confidence 保証 invariant への言及
        invariant_documented = (
            "書き込み側" in text
            or "writer" in text.lower()
            or "invariant" in text.lower()
            or "guarantee" in text.lower()
            or "ac-impl-coverage-check" in text
        )
        assert invariant_documented, (
            "AC-3 FAIL: ref-specialist-output-schema.md に confidence >= 80 が "
            "書き込み側の invariant であることが明記されていない。"
            "merge-gate フィルタ閾値の説明に書き込み側の責務を追記すること。"
        )

    def test_ac3_ac_verify_md_critical_confidence_is_explicitly_constrained(self):
        """AC-3: ac-verify.md の CRITICAL Finding テンプレートに confidence 制約が明記されている。

        RED: 現在の ac-verify.md CRITICAL Finding テンプレートは confidence=80 を使用しているが、
             「CRITICAL は confidence >= 80 でなければならない」という制約が明記されていない。
        """
        text = AC_VERIFY_MD.read_text(encoding="utf-8")

        # CRITICAL Finding テンプレートで confidence 制約が説明されているか
        # 「CRITICAL の場合は confidence >= 80 でなければならない」という記述
        critical_confidence_constraint = (
            "confidence" in text
            and "CRITICAL" in text
            and (
                ">= 80" in text
                or ">=80" in text
                or "minimum.*80" in text.lower()
                or "80 以上" in text
                or "80以上" in text
                or "書き込み側" in text
            )
        )
        assert critical_confidence_constraint, (
            "AC-3 FAIL: ac-verify.md の CRITICAL Finding テンプレートに "
            "confidence >= 80 制約が明記されていない。"
        )


# ---------------------------------------------------------------------------
# AC-4: regression test — confidence >= 80 の invariant 検証
# ---------------------------------------------------------------------------


class TestAC4ConfidenceInvariant:
    """AC-4: regression test — ac-verify 経由の CRITICAL Finding は confidence >= 80 であること。

    設計意図の persistence を確認する regression test。

    ac-impl-coverage-check.sh が出力する CRITICAL Finding は confidence=90 固定。
    ac-verify.md の LLM delegate パスが出力する CRITICAL Finding は confidence=80。
    いずれも confidence >= 80 を満たす。

    この invariant が future regression で破れないことを静的に検証する。
    """

    def test_ac4_ac_impl_coverage_check_critical_confidence_is_90(self):
        """AC-4: ac-impl-coverage-check.sh の CRITICAL Finding は confidence=90 固定である。

        RED: 現在この値が正しいことは既知だが、
             これが「設計意図」として doc に記録されていないため、
             静的検証対象として機能していない。
             実装後は doc に confidence=90 の根拠記述が必要。
        """
        text = AC_IMPL_COVERAGE_CHECK_SH.read_text(encoding="utf-8")

        # CRITICAL confidence 値を抽出
        # "severity": "CRITICAL" に隣接する confidence 値を探す
        critical_block_match = re.search(
            r'"severity":\s*"CRITICAL".*?"confidence":\s*(\d+)',
            text,
            re.DOTALL,
        )
        assert critical_block_match is not None, (
            "ac-impl-coverage-check.sh の CRITICAL Finding に confidence フィールドが見つからない"
        )
        critical_confidence = int(critical_block_match.group(1))
        assert critical_confidence >= 80, (
            f"AC-4 FAIL: ac-impl-coverage-check.sh の CRITICAL confidence が {critical_confidence} < 80。"
            "fix-phase が正しく発動するためには confidence >= 80 が必要。"
        )

        # さらに、この invariant が doc コメントとして記録されていること
        # "# confidence=90 は merge-gate ブロック条件 (>= 80) を満たすための設計" などのコメント
        invariant_documented_in_script = (
            "confidence" in text
            and (
                "merge-gate" in text
                or "invariant" in text.lower()
                or "ブロック" in text
                or "block" in text.lower()
                or ">= 80" in text
            )
        )
        assert invariant_documented_in_script, (
            "AC-4 FAIL: ac-impl-coverage-check.sh に confidence=90 の根拠コメントがない。"
            "merge-gate ブロック条件との関係を doc コメントとして記録すること。"
        )

    def test_ac4_ac_verify_md_llm_critical_confidence_is_at_least_80(self):
        """AC-4: ac-verify.md の LLM delegate CRITICAL Finding テンプレートは confidence >= 80 である。

        RED: 現在 confidence=80 の値は存在するが、
             これが「merge-gate ブロック条件を満たすための invariant」として
             明示されていないため regression 検証が不十分。
             実装後は ac-verify.md に invariant の説明が必要。
        """
        text = AC_VERIFY_MD.read_text(encoding="utf-8")

        # CRITICAL Finding テンプレートの confidence 値を確認
        # Step 2: Findings 構築 の CRITICAL Finding サンプル JSON を探す
        critical_confidence_match = re.search(
            r'"severity":\s*"CRITICAL".*?"confidence":\s*(\d+)',
            text,
            re.DOTALL,
        )
        assert critical_confidence_match is not None, (
            "AC-4 FAIL: ac-verify.md の CRITICAL Finding テンプレートに confidence フィールドが見つからない"
        )
        critical_confidence = int(critical_confidence_match.group(1))
        assert critical_confidence >= 80, (
            f"AC-4 FAIL: ac-verify.md の CRITICAL confidence が {critical_confidence} < 80。"
            "fix-phase が正しく発動するためには confidence >= 80 が必要。"
        )

        # この invariant が明示されていること
        invariant_explicitly_stated = (
            "confidence" in text
            and (
                "merge-gate" in text
                or ">= 80" in text
                or ">=80" in text
                or "invariant" in text.lower()
                or "書き込み側" in text
                or "責務" in text
            )
        )
        assert invariant_explicitly_stated, (
            "AC-4 FAIL: ac-verify.md の CRITICAL Finding テンプレートに "
            "confidence >= 80 が merge-gate ブロック条件を満たす invariant であることが明示されていない。"
        )

    def test_ac4_checkpoint_write_does_not_filter_by_confidence(self):
        """AC-4: checkpoint.py write() の critical_count は confidence フィルタを持たない（設計意図）。

        このテストは「confidence フィルタを意図的に持たない」設計が
        docstring に明記されることで GREEN になる。

        RED: 現在 docstring に confidence フィルタ不在の設計意図が記述されていないため FAIL。
        """
        from twl.autopilot.checkpoint import CheckpointManager
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            mgr = CheckpointManager(checkpoint_dir=Path(tmpdir) / "checkpoints")

            # confidence=50 の CRITICAL Finding を書き込む
            # 現在の実装: critical_count に加算される (confidence フィルタなし)
            findings_with_low_confidence = [
                {
                    "severity": "CRITICAL",
                    "confidence": 50,  # merge-gate のブロック閾値 80 未満
                    "message": "test finding with low confidence",
                    "category": "bug",
                    "file": "test.py",
                    "line": 1,
                }
            ]
            mgr.write(
                step="test-step",
                status="FAIL",
                findings=findings_with_low_confidence,
            )

            # critical_count を読み返す
            critical_count = mgr.read(step="test-step", field="critical_count")
            assert critical_count == "1", (
                f"AC-4 FAIL: checkpoint.py write() は confidence フィルタを持たないため "
                f"confidence=50 の CRITICAL も critical_count に加算されるべきだが、実際: {critical_count}"
            )

        # 設計意図が docstring に明記されているかを確認
        checkpoint_text = CHECKPOINT_PY.read_text(encoding="utf-8")
        write_method_match = re.search(
            r'def write\s*\([^)]*\)[^:]*:\s*"""(.*?)"""',
            checkpoint_text,
            re.DOTALL,
        )
        assert write_method_match is not None, "write() メソッドが見つからない"
        docstring = write_method_match.group(1)

        # docstring に confidence フィルタ不在の設計意図が明記されていること
        design_intent_documented = (
            "confidence" in docstring.lower()
            or "書き込み側" in docstring
            or "writer" in docstring.lower()
        )
        assert design_intent_documented, (
            "AC-4 FAIL: checkpoint.py write() docstring に "
            "confidence フィルタを意図的に持たないという設計意図が記述されていない。"
            f"現在の docstring: {docstring.strip()!r}"
        )
