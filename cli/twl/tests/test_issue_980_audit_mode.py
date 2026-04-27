"""Tests for Issue #980: SPECIALIST_AUDIT_MODE=warn → fail 昇格判断.

TDD RED phase — all tests fail until implementation is complete.

AC-1: ADR-025 Known Gap 3 に定量的 KPI を記録
AC-2: .supervisor/wave-D-summary.md に派生 Issue E-3 条件を記録
AC-3: plugins/twl/refs/rollback-specialist-audit-flip.md を新規作成
AC-4: audit-false-positive 観察 channel を確立
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parents[3]
ADR_025_PATH = REPO_ROOT / "plugins/twl/architecture/decisions/ADR-025-co-autopilot-phase-review-guarantee.md"
WAVE_D_SUMMARY_PATH = REPO_ROOT / ".supervisor/wave-D-summary.md"
ROLLBACK_DOC_PATH = REPO_ROOT / "plugins/twl/refs/rollback-specialist-audit-flip.md"
SPECIALIST_AUDIT_SH = REPO_ROOT / "plugins/twl/scripts/specialist-audit.sh"
AUTO_MERGE_SH = REPO_ROOT / "plugins/twl/scripts/auto-merge.sh"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def adr_025_text() -> str:
    assert ADR_025_PATH.exists(), f"ADR-025 ファイルが存在しない: {ADR_025_PATH}"
    return ADR_025_PATH.read_text()


@pytest.fixture(scope="module")
def rollback_doc_text() -> str:
    assert ROLLBACK_DOC_PATH.exists(), f"rollback 文書が存在しない: {ROLLBACK_DOC_PATH}"
    return ROLLBACK_DOC_PATH.read_text()


@pytest.fixture(scope="module")
def wave_d_summary_text() -> str:
    assert WAVE_D_SUMMARY_PATH.exists(), f"wave-D-summary.md が存在しない: {WAVE_D_SUMMARY_PATH}"
    return WAVE_D_SUMMARY_PATH.read_text()


# ---------------------------------------------------------------------------
# AC-1: ADR-025 Known Gap 3 に定量的 KPI を記録
# ---------------------------------------------------------------------------

class TestAc1AdrKpiQuantification:
    """AC-1: Known Gap 3 の昇格条件を定量化し ADR に記録する。"""

    def test_ac1a_known_gap3_contains_quantitative_condition(self, adr_025_text: str):
        # AC-1(a): 機械検証可能な定量条件（post-fix merge PR 件数 + false-positive 件数）
        # RED: 現在の Known Gap 3 は "2 週間" のみで定量件数条件がない
        gap3_match = re.search(
            r"Known Gap 3.*?(?=Known Gap \d|##|\Z)", adr_025_text, re.DOTALL
        )
        assert gap3_match, "Known Gap 3 が ADR-025 に見当たらない"
        gap3_text = gap3_match.group(0)
        has_pr_count_condition = bool(
            re.search(r"post.fix.merge.PR.*?件|PR.*?\d+.*?件", gap3_text)
        )
        has_false_positive_count = bool(
            re.search(r"false.positive.*?0\s*件|偽陽性.*?0\s*件", gap3_text)
        )
        assert has_pr_count_condition, (
            "Known Gap 3 に post-fix merge PR 件数の定量条件がない"
        )
        assert has_false_positive_count, (
            "Known Gap 3 に false-positive 0 件の定量条件がない"
        )

    def test_ac1b_known_gap3_contains_grep_pattern(self, adr_025_text: str):
        # AC-1(b): KPI 計測 input 経路 (grep パターン) が ADR-025 に明記されている
        # RED: 現在の ADR-025 に grep パターン記述なし
        assert 'grep' in adr_025_text, (
            'ADR-025 に grep パターンの記述がない (KPI 計測 input 経路の明示が必要)'
        )
        assert '"status":"FAIL"' in adr_025_text or '"status":"WARN"' in adr_025_text, (
            'ADR-025 に audit ログ grep パターン ("status":"FAIL"/"WARN") の記述がない'
        )

    def test_ac1b_wave_c_excluded_from_measurement(self, adr_025_text: str):
        # AC-1(b): Wave C は wave-collect 経由ログ不在のため計測対象外と明記
        # RED: 現在の ADR-025 に Wave C 除外の記述なし
        assert "Wave C" in adr_025_text, (
            "ADR-025 に Wave C の計測対象除外の記述がない"
        )

    def test_ac1c_kpi_option_recorded_with_rationale(self, adr_025_text: str):
        # AC-1(c): 選定 KPI 案 (A/B/C) と選定理由が ADR-025 に記録されている
        # RED: 現在の ADR-025 に KPI 案 A/B/C の記録なし
        has_option = bool(
            re.search(r"案\s*[ABC]|KPI\s*案|option\s*[ABC]", adr_025_text, re.IGNORECASE)
        )
        assert has_option, "ADR-025 に KPI 案 A/B/C の選定記録がない"

    def test_ac1d_worker_architecture_shall_documented(self, adr_025_text: str):
        # AC-1(d): ADR 補追領域 PR で worker-architecture が SHALL 要件と明記
        # RED: 現在の ADR-025 に worker-architecture SHALL の明示なし
        assert "worker-architecture" in adr_025_text, (
            "ADR-025 に worker-architecture への言及がない"
        )
        gap3_or_gap1_match = re.search(
            r"(SHALL|MUST).*worker.architecture|worker.architecture.*(SHALL|MUST)",
            adr_025_text,
        )
        assert gap3_or_gap1_match, (
            "ADR-025 に worker-architecture SHALL/MUST 要件の記述がない"
        )


# ---------------------------------------------------------------------------
# AC-2: .supervisor/wave-D-summary.md に派生 Issue E-3 条件を記録
# ---------------------------------------------------------------------------

class TestAc2WaveDSummary:
    """AC-2: .supervisor/wave-D-summary.md を新規作成し E-3 条件を記録する。"""

    def test_ac2_wave_d_summary_exists(self):
        # AC-2: .supervisor/wave-D-summary.md が存在する
        # RED: ファイルが存在しない
        assert WAVE_D_SUMMARY_PATH.exists(), (
            f".supervisor/wave-D-summary.md が存在しない: {WAVE_D_SUMMARY_PATH}"
        )

    def test_ac2_contains_e3_derivation_condition(self, wave_d_summary_text: str):
        # AC-2: E-3 相当条項として派生 Issue 起票条件が記載されている
        # RED: ファイルが存在しないため fail
        has_e3 = bool(re.search(r"E.?3|修正\s*E|派生.*Issue|derivation.*issue", wave_d_summary_text, re.IGNORECASE))
        assert has_e3, "wave-D-summary.md に E-3 派生 Issue 起票条件の記録がない"

    def test_ac2_contains_implementation_ready_timing(self, wave_d_summary_text: str):
        # AC-2: 実装 ready timing (最短 2026-05-09) が記載されている
        # RED: ファイルが存在しないため fail
        assert "2026-05-09" in wave_d_summary_text or "KPI 達成" in wave_d_summary_text, (
            "wave-D-summary.md に実装 ready timing (2026-05-09 / KPI 達成) の記載がない"
        )

    def test_ac2_contains_phase1_priority_rule(self, wave_d_summary_text: str):
        # AC-2: Phase 1 開始が close 前に来た場合の優先ルールが記載
        # RED: ファイルが存在しないため fail
        has_phase1_rule = bool(re.search(r"Phase\s*1.*priority|Phase\s*1.*先に|Phase\s*1.*close", wave_d_summary_text))
        assert has_phase1_rule, "wave-D-summary.md に Phase 1 priority rule の記載がない"


# ---------------------------------------------------------------------------
# AC-3: plugins/twl/refs/rollback-specialist-audit-flip.md を新規作成
# ---------------------------------------------------------------------------

class TestAc3RollbackDoc:
    """AC-3: rollback 文書を新規作成し SSoT・手順・ポリシーを記載する。"""

    def test_ac3_rollback_doc_exists(self):
        # AC-3: plugins/twl/refs/rollback-specialist-audit-flip.md が存在する
        # RED: ファイルが存在しない
        assert ROLLBACK_DOC_PATH.exists(), (
            f"rollback 文書が存在しない: {ROLLBACK_DOC_PATH}"
        )

    def test_ac3_level1_ssot_mentioned(self, rollback_doc_text: str):
        # AC-3: Level 1 SSoT (specialist-audit.sh:44) が明示されている
        # RED: ファイルが存在しないため fail
        assert "specialist-audit.sh" in rollback_doc_text, (
            "rollback 文書に specialist-audit.sh への言及がない"
        )
        assert ":44" in rollback_doc_text or "line 44" in rollback_doc_text.lower(), (
            "rollback 文書に specialist-audit.sh:44 (Level 1 SSoT) の明示がない"
        )

    def test_ac3_rollback_procedure_documented(self, rollback_doc_text: str):
        # AC-3: git revert → gh pr create の rollback 手順が記載
        # RED: ファイルが存在しないため fail
        assert "git revert" in rollback_doc_text, (
            "rollback 文書に git revert 手順がない"
        )
        assert "gh pr create" in rollback_doc_text, (
            "rollback 文書に gh pr create 手順がない"
        )

    def test_ac3_audit_log_investigation_documented(self, rollback_doc_text: str):
        # AC-3: .audit/ ログ調査手順が記載
        # RED: ファイルが存在しないため fail
        assert ".audit/" in rollback_doc_text, (
            "rollback 文書に .audit/ ログ調査手順がない"
        )
        assert '"status":"FAIL"' in rollback_doc_text, (
            'rollback 文書に grep "status":"FAIL" ログ抽出手順がない'
        )

    def test_ac3_level23_followup_policy_documented(self, rollback_doc_text: str):
        # AC-3: Level 2/3 追随不要ポリシーが明記
        # RED: ファイルが存在しないため fail
        has_level23 = bool(
            re.search(r"Level\s*[23]|auto.merge\.sh.*Level|Level.*auto.merge", rollback_doc_text)
        )
        assert has_level23, (
            "rollback 文書に Level 2/3 追随ポリシーの記述がない"
        )


# ---------------------------------------------------------------------------
# AC-4: 観察 channel 確立
# ---------------------------------------------------------------------------

class TestAc4ObservationChannel:
    """AC-4: audit-false-positive 観察 channel を確立する。"""

    def test_ac4a_label_creation_idempotent_check(self):
        # AC-4(a): audit-false-positive ラベル作成ロジックが実装済み
        # RED: specialist-audit.sh / auto-merge.sh にラベル作成コードがない
        audit_sh_text = SPECIALIST_AUDIT_SH.read_text()
        auto_merge_text = AUTO_MERGE_SH.read_text()
        has_label_logic = (
            "audit-false-positive" in audit_sh_text
            or "audit-false-positive" in auto_merge_text
        )
        assert has_label_logic, (
            "audit-false-positive ラベル作成ロジックが "
            "specialist-audit.sh または auto-merge.sh に存在しない"
        )

    def test_ac4b_auto_comment_mechanism_exists(self):
        # AC-4(b): audit FAIL → 自動 Issue comment 機構が実装済み
        # RED: 現在 auto-merge.sh / specialist-audit.sh に自動コメント機能なし
        audit_sh_text = SPECIALIST_AUDIT_SH.read_text()
        auto_merge_text = AUTO_MERGE_SH.read_text()
        has_auto_comment = bool(
            re.search(r"gh\s+issue\s+comment|issue.*comment.*audit", audit_sh_text)
            or re.search(r"gh\s+issue\s+comment|issue.*comment.*audit", auto_merge_text)
        )
        assert has_auto_comment, (
            "audit FAIL → 自動 Issue comment 機構が "
            "specialist-audit.sh または auto-merge.sh に存在しない"
        )

    def test_ac4c_weekly_review_rule_documented(self):
        # AC-4(c): 週次 audit log review の運用ルールが文書化済み
        # RED: su-observer 関連文書に週次レビュールールの記述なし
        su_observer_refs = REPO_ROOT / "plugins/twl/skills/su-observer/refs"
        wave_mgmt = su_observer_refs / "su-observer-wave-management.md"
        assert wave_mgmt.exists(), f"wave-management.md が存在しない: {wave_mgmt}"
        wave_mgmt_text = wave_mgmt.read_text()
        has_audit_review_rule = bool(
            re.search(r"週次|weekly|audit.*log.*review|specialist.audit.*review", wave_mgmt_text, re.IGNORECASE)
        )
        assert has_audit_review_rule, (
            "su-observer-wave-management.md に週次 audit log review の運用ルールがない"
        )
