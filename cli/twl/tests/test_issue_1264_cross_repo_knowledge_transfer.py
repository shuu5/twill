"""Tests for Issue #1264: cross-repo knowledge transfer via architecture/protocols.

TDD RED phase test stubs.
All tests FAIL before implementation (intentional RED).

AC list:
  AC1: architecture/protocols/<name>.md の spec 構造が ref-architecture-spec.md に定義されている
       (Participants / Pinned Reference / Interface Contract / Drift Detection / Migration Path の 5 セクション)
  AC2: protocols/*.md の Pinned Reference セクションで 40-char commit SHA が必須化されている
       (worker-arch-doc-reviewer で ^[a-f0-9]{40}$ regex 検証)
  AC3: tag/branch 参照が明示的に拒否される (drift リスクの明文化)
  AC4: protocols/*.md の sha pin を検出する worker 観点が confidence >= 80 で動作 (false positive 抑制)
  AC5: architect-completeness-check が protocols/ を optional 認識 —
       protocols/ なしの状態で architect-completeness-check を実行し WARNING が出ないことを確認
       (ref-architecture-spec.md の RECOMMENDED Severity 追加後に検証)
  AC6: 新規 ADR-033 で ADR-007-cross-repo-project-management.md との直交関係が明記されている
  AC7: ADR-033 に contracts/ と protocols/ の棲み分け基準が明記されている
  AC8: drift detection の運用例 (cron / GitHub Actions / 手動レビュー) が ADR-033 に記載されている
  AC9: protocols/*.md の例 (実例 1 件以上) が examples/ ディレクトリにある
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

WORKTREE_ROOT = Path(__file__).resolve().parents[3]

REF_ARCH_SPEC = WORKTREE_ROOT / "plugins/twl/refs/ref-architecture-spec.md"
WORKER_ARCH_DOC_REVIEWER = WORKTREE_ROOT / "plugins/twl/agents/worker-arch-doc-reviewer.md"
ARCHITECT_COMPLETENESS_CHECK = WORKTREE_ROOT / "plugins/twl/commands/architect-completeness-check.md"
ADR_033_GLOB_PATTERN = "plugins/twl/architecture/decisions/ADR-033-*.md"
ADR_007_PATH = WORKTREE_ROOT / "plugins/twl/architecture/decisions/ADR-007-cross-repo-project-management.md"

# Candidate paths for protocols examples
EXAMPLES_PROTOCOLS_DIR = WORKTREE_ROOT / "architecture" / "examples"
PLUGINS_EXAMPLES_DIR = WORKTREE_ROOT / "plugins/twl/architecture/examples"


def _find_adr_033() -> Path | None:
    """ADR-033 ファイルを検索する。"""
    candidates = list((WORKTREE_ROOT / "plugins/twl/architecture/decisions").glob("ADR-033-*.md"))
    if candidates:
        return candidates[0]
    return None


# ---------------------------------------------------------------------------
# AC1: ref-architecture-spec.md に protocols/<name>.md の 5 セクション構造が定義されている
# ---------------------------------------------------------------------------


class TestAC1ProtocolsSpecStructure:
    """AC1: ref-architecture-spec.md が protocols/ ディレクトリと 5 セクション構造を定義していること."""

    def test_ac1_protocols_section_in_ref_arch_spec(self):
        # AC: ref-architecture-spec.md の ## ディレクトリ構造 (または類似セクション) に
        #     protocols/ の記述が存在すること
        # RED: 現在の ref-architecture-spec.md には protocols/ セクションが存在しないため FAIL する
        assert REF_ARCH_SPEC.exists(), f"ref-architecture-spec.md が存在しない: {REF_ARCH_SPEC}"
        text = REF_ARCH_SPEC.read_text(encoding="utf-8")
        assert "protocols/" in text, (
            "AC1 未実装: ref-architecture-spec.md に 'protocols/' の記述が存在しない"
        )

    def test_ac1_five_required_sections_defined(self):
        # AC: protocols/<name>.md の必須セクションとして
        #     Participants / Pinned Reference / Interface Contract / Drift Detection / Migration Path
        #     の 5 セクションが ref-architecture-spec.md に定義されていること
        # RED: 現在の ref-architecture-spec.md にはこれらのセクション定義が存在しないため FAIL する
        assert REF_ARCH_SPEC.exists(), f"ref-architecture-spec.md が存在しない: {REF_ARCH_SPEC}"
        text = REF_ARCH_SPEC.read_text(encoding="utf-8")
        required_sections = [
            "Participants",
            "Pinned Reference",
            "Interface Contract",
            "Drift Detection",
            "Migration Path",
        ]
        missing = [s for s in required_sections if s not in text]
        assert not missing, (
            f"AC1 未実装: ref-architecture-spec.md に以下のセクション定義が存在しない: {missing}"
        )


# ---------------------------------------------------------------------------
# AC2: worker-arch-doc-reviewer が Pinned Reference の 40-char SHA を正規表現検証する
# ---------------------------------------------------------------------------


class TestAC2PinnedReferenceSHAValidation:
    """AC2: worker-arch-doc-reviewer に ^[a-f0-9]{40}$ の SHA 検証が定義されていること."""

    def test_ac2_sha_regex_in_worker_reviewer(self):
        # AC: worker-arch-doc-reviewer.md のレビュー観点に
        #     ^[a-f0-9]{40}$ の regex による Pinned Reference SHA 検証が存在すること
        # RED: 現在の worker-arch-doc-reviewer.md には SHA 検証観点が存在しないため FAIL する
        assert WORKER_ARCH_DOC_REVIEWER.exists(), (
            f"worker-arch-doc-reviewer.md が存在しない: {WORKER_ARCH_DOC_REVIEWER}"
        )
        text = WORKER_ARCH_DOC_REVIEWER.read_text(encoding="utf-8")
        # 40-char hex SHA の正規表現パターンが含まれていること
        assert re.search(r"\^?\[a-f0-9\]\{40\}", text) or "[a-f0-9]{40}" in text, (
            "AC2 未実装: worker-arch-doc-reviewer.md に '^[a-f0-9]{40}$' の SHA 検証観点が存在しない"
        )

    def test_ac2_pinned_reference_check_mentioned(self):
        # AC: worker-arch-doc-reviewer.md に Pinned Reference セクションのチェックが言及されていること
        # RED: 現在の worker-arch-doc-reviewer.md には Pinned Reference チェックが存在しないため FAIL する
        assert WORKER_ARCH_DOC_REVIEWER.exists(), (
            f"worker-arch-doc-reviewer.md が存在しない: {WORKER_ARCH_DOC_REVIEWER}"
        )
        text = WORKER_ARCH_DOC_REVIEWER.read_text(encoding="utf-8")
        assert "Pinned Reference" in text, (
            "AC2 未実装: worker-arch-doc-reviewer.md に 'Pinned Reference' の記述が存在しない"
        )


# ---------------------------------------------------------------------------
# AC3: tag/branch 参照が明示的に拒否される (drift リスクの明文化)
# ---------------------------------------------------------------------------


class TestAC3TagBranchRejection:
    """AC3: ref-architecture-spec.md または worker-arch-doc-reviewer.md で
    tag/branch 参照拒否が明文化されていること."""

    def test_ac3_tag_branch_rejection_in_spec(self):
        # AC: protocols/<name>.md の Pinned Reference において tag または branch 参照が
        #     明示的に拒否される旨が ref-architecture-spec.md に記載されていること
        # RED: 現在の ref-architecture-spec.md には tag/branch 拒否の記述が存在しないため FAIL する
        assert REF_ARCH_SPEC.exists(), f"ref-architecture-spec.md が存在しない: {REF_ARCH_SPEC}"
        text = REF_ARCH_SPEC.read_text(encoding="utf-8")
        # tag または branch の参照を「明示的に拒否・禁止」する記述が含まれていること
        # drift だけでは AC3 の意図（拒否の明文化）を保証しないため除外する
        has_tag_rejection = re.search(r"tag|branch", text, re.IGNORECASE) and (
            "拒否" in text or "reject" in text.lower() or "禁止" in text or "不可" in text
        )
        assert has_tag_rejection, (
            "AC3 未実装: ref-architecture-spec.md に tag/branch 参照拒否 (drift リスク明文化) の記述が存在しない"
        )

    def test_ac3_tag_branch_rejection_in_worker_reviewer(self):
        # AC: worker-arch-doc-reviewer.md のレビュー観点に tag/branch 参照検出が含まれていること
        # RED: 現在の worker-arch-doc-reviewer.md には tag/branch 検出観点が存在しないため FAIL する
        assert WORKER_ARCH_DOC_REVIEWER.exists(), (
            f"worker-arch-doc-reviewer.md が存在しない: {WORKER_ARCH_DOC_REVIEWER}"
        )
        text = WORKER_ARCH_DOC_REVIEWER.read_text(encoding="utf-8")
        has_tag_or_branch = re.search(r"\btag\b|\bbranch\b", text, re.IGNORECASE)
        assert has_tag_or_branch, (
            "AC3 未実装: worker-arch-doc-reviewer.md に tag/branch 参照検出の観点が存在しない"
        )


# ---------------------------------------------------------------------------
# AC4: sha pin 検出観点が confidence >= 80 で動作する
# ---------------------------------------------------------------------------


class TestAC4SHAPinConfidence:
    """AC4: worker-arch-doc-reviewer.md の SHA pin 検出観点に confidence >= 80 の記述が存在すること."""

    def test_ac4_confidence_threshold_defined(self):
        # AC: worker-arch-doc-reviewer.md に SHA pin 検出の confidence 閾値 (>= 80) が
        #     明示されているか、既存の confidence 閾値ルール下で protocols/*.md の SHA 検証が動作すること
        # RED: 現在の worker-arch-doc-reviewer.md には protocols セクションの SHA pin 観点が
        #      存在しないため FAIL する
        assert WORKER_ARCH_DOC_REVIEWER.exists(), (
            f"worker-arch-doc-reviewer.md が存在しない: {WORKER_ARCH_DOC_REVIEWER}"
        )
        text = WORKER_ARCH_DOC_REVIEWER.read_text(encoding="utf-8")
        # protocols/*.md を明示的に対象にした ### セクション見出しが存在すること
        has_protocols_section = bool(re.search(r"###.*protocols", text, re.IGNORECASE))
        assert has_protocols_section, (
            "AC4 未実装: worker-arch-doc-reviewer.md に protocols/*.md の SHA pin 検出観点セクションが存在しない"
        )

    def test_ac4_sha_pin_review_category_exists(self):
        # AC: worker-arch-doc-reviewer.md に protocols/*.md に関するレビュー観点テーブルが存在すること
        # RED: 現在の worker-arch-doc-reviewer.md には protocols セクションが存在しないため FAIL する
        assert WORKER_ARCH_DOC_REVIEWER.exists(), (
            f"worker-arch-doc-reviewer.md が存在しない: {WORKER_ARCH_DOC_REVIEWER}"
        )
        text = WORKER_ARCH_DOC_REVIEWER.read_text(encoding="utf-8")
        # protocols/*.md を対象にしたレビューテーブルがあること
        has_protocols_table = re.search(r"protocols/\*\.md|protocols/\.", text)
        assert has_protocols_table, (
            "AC4 未実装: worker-arch-doc-reviewer.md に 'protocols/*.md' 対象のレビューテーブルが存在しない"
        )


# ---------------------------------------------------------------------------
# AC5: architect-completeness-check が protocols/ を optional (RECOMMENDED) として認識する
# ---------------------------------------------------------------------------


class TestAC5ProtocolsOptionalInCompleteness:
    """AC5: ref-architecture-spec.md に protocols/ が RECOMMENDED Severity で登録されており、
    architect-completeness-check が WARNING を出さないこと."""

    def test_ac5_protocols_entry_in_required_files_table(self):
        # AC: ref-architecture-spec.md の ## 必須ファイル テーブルに protocols/ の行が
        #     Severity=RECOMMENDED で存在すること
        # RED: 現在の ref-architecture-spec.md の必須ファイルテーブルに protocols/ が存在しないため FAIL する
        assert REF_ARCH_SPEC.exists(), f"ref-architecture-spec.md が存在しない: {REF_ARCH_SPEC}"
        text = REF_ARCH_SPEC.read_text(encoding="utf-8")
        # 必須ファイルテーブル内に protocols/ が RECOMMENDED で登録されていること
        has_protocols_recommended = (
            "protocols/" in text
            and "RECOMMENDED" in text
        )
        assert has_protocols_recommended, (
            "AC5 未実装: ref-architecture-spec.md の必須ファイルテーブルに "
            "'protocols/' (Severity=RECOMMENDED) が存在しない"
        )

    def test_ac5_protocols_no_warning_in_completeness_check_doc(self):
        # AC: architect-completeness-check.md が protocols/ の不在を WARNING として扱わないこと
        #     (RECOMMENDED = INFO レベルであることが architect-completeness-check.md に反映されていること)
        # RED: 現在の architect-completeness-check.md には protocols/ の言及が存在しないため FAIL する
        assert ARCHITECT_COMPLETENESS_CHECK.exists(), (
            f"architect-completeness-check.md が存在しない: {ARCHITECT_COMPLETENESS_CHECK}"
        )
        text = ARCHITECT_COMPLETENESS_CHECK.read_text(encoding="utf-8")
        # protocols/ への言及が存在すること (RECOMMENDED/INFO レベルの記述)
        assert "protocols/" in text or "protocols" in text.lower(), (
            "AC5 未実装: architect-completeness-check.md に protocols/ の扱い (RECOMMENDED/optional) が記述されていない"
        )


# ---------------------------------------------------------------------------
# AC6: ADR-033 が ADR-007-cross-repo-project-management.md との直交関係を明記している
# ---------------------------------------------------------------------------


class TestAC6ADR033CrossRepoOrthogonality:
    """AC6: ADR-033 ファイルが存在し、ADR-007 との直交関係が明記されていること."""

    def test_ac6_adr033_file_exists(self):
        # AC: plugins/twl/architecture/decisions/ADR-033-*.md が存在すること
        # RED: ADR-033 ファイルがまだ存在しないため FAIL する
        adr033 = _find_adr_033()
        assert adr033 is not None, (
            "AC6 未実装: plugins/twl/architecture/decisions/ADR-033-*.md が存在しない"
        )

    def test_ac6_adr033_mentions_adr007_orthogonality(self):
        # AC: ADR-033 に ADR-007-cross-repo-project-management.md との直交関係が明記されていること
        # RED: ADR-033 ファイルがまだ存在しないため FAIL する
        adr033 = _find_adr_033()
        if adr033 is None:
            pytest.fail("AC6 未実装: ADR-033 ファイルが存在しないため直交関係を検証できない")
        text = adr033.read_text(encoding="utf-8")
        has_adr007_ref = "ADR-007" in text or "cross-repo-project-management" in text
        assert has_adr007_ref, (
            "AC6 未実装: ADR-033 に ADR-007 (cross-repo-project-management) への参照が存在しない"
        )
        # 直交関係の明記
        has_orthogonality = (
            "直交" in text
            or "orthogonal" in text.lower()
            or "独立" in text
            or "棲み分け" in text
        )
        assert has_orthogonality, (
            "AC6 未実装: ADR-033 に ADR-007 との直交関係 (直交/orthogonal/独立) の記述が存在しない"
        )


# ---------------------------------------------------------------------------
# AC7: ADR-033 に contracts/ と protocols/ の棲み分け基準が明記されている
# ---------------------------------------------------------------------------


class TestAC7ADR033ContractsProtocolsDistinction:
    """AC7: ADR-033 に contracts/ と protocols/ の棲み分け基準が記載されていること."""

    def test_ac7_adr033_contracts_vs_protocols_criterion(self):
        # AC: ADR-033 に contracts/ と protocols/ の棲み分け基準が明記されていること
        # RED: ADR-033 ファイルがまだ存在しないため FAIL する
        adr033 = _find_adr_033()
        if adr033 is None:
            pytest.fail("AC7 未実装: ADR-033 ファイルが存在しないため棲み分け基準を検証できない")
        text = adr033.read_text(encoding="utf-8")
        has_contracts = "contracts/" in text or "contracts" in text.lower()
        has_protocols = "protocols/" in text or "protocols" in text.lower()
        assert has_contracts and has_protocols, (
            f"AC7 未実装: ADR-033 に contracts/ と protocols/ 両方の記述が必要 "
            f"(contracts={'あり' if has_contracts else 'なし'}, "
            f"protocols={'あり' if has_protocols else 'なし'})"
        )
        # 棲み分け基準の記述
        has_distinction = (
            "棲み分け" in text
            or "distinction" in text.lower()
            or "使い分け" in text
            or "違い" in text
            or "差異" in text
        )
        assert has_distinction, (
            "AC7 未実装: ADR-033 に contracts/ と protocols/ の棲み分け基準 "
            "(棲み分け/distinction/使い分け) の記述が存在しない"
        )


# ---------------------------------------------------------------------------
# AC8: drift detection の運用例 が ADR-033 に記載されている
# ---------------------------------------------------------------------------


class TestAC8ADR033DriftDetectionExamples:
    """AC8: ADR-033 に drift detection 運用例 (cron / GitHub Actions / 手動レビュー) が記載されていること."""

    def test_ac8_adr033_drift_detection_examples(self):
        # AC: ADR-033 に drift detection の運用例として
        #     cron / GitHub Actions / 手動レビュー のうち最低 1 つが記載されていること
        # RED: ADR-033 ファイルがまだ存在しないため FAIL する
        adr033 = _find_adr_033()
        if adr033 is None:
            pytest.fail("AC8 未実装: ADR-033 ファイルが存在しないため drift detection 運用例を検証できない")
        text = adr033.read_text(encoding="utf-8")
        has_drift_detection = "drift" in text.lower() or "Drift" in text
        assert has_drift_detection, (
            "AC8 未実装: ADR-033 に 'Drift Detection' の記述が存在しない"
        )
        # cron / GitHub Actions / 手動レビュー のいずれかが存在すること
        has_operation_example = (
            "cron" in text.lower()
            or "GitHub Actions" in text
            or "github actions" in text.lower()
            or "手動" in text
            or "manual" in text.lower()
        )
        assert has_operation_example, (
            "AC8 未実装: ADR-033 に drift detection の運用例 "
            "(cron / GitHub Actions / 手動レビュー) が記載されていない"
        )

    def test_ac8_adr033_all_three_operation_examples(self):
        # AC: ADR-033 に cron / GitHub Actions / 手動レビュー の 3 つすべてが記載されていること
        # RED: ADR-033 ファイルがまだ存在しないため FAIL する
        adr033 = _find_adr_033()
        if adr033 is None:
            pytest.fail("AC8 未実装: ADR-033 ファイルが存在しないため drift detection 運用例を検証できない")
        text = adr033.read_text(encoding="utf-8")
        missing = []
        if "cron" not in text.lower():
            missing.append("cron")
        if "GitHub Actions" not in text and "github actions" not in text.lower():
            missing.append("GitHub Actions")
        if "手動" not in text and "manual" not in text.lower():
            missing.append("手動レビュー")
        assert not missing, (
            f"AC8 未実装: ADR-033 に以下の運用例が記載されていない: {missing}"
        )


# ---------------------------------------------------------------------------
# AC9: protocols/*.md の例 (実例 1 件以上) が examples/ ディレクトリにある
# ---------------------------------------------------------------------------


class TestAC9ProtocolsExamplesDirectory:
    """AC9: examples/ ディレクトリに protocols/*.md の実例が 1 件以上存在すること."""

    def test_ac9_examples_directory_exists(self):
        # AC: architecture/examples/ または plugins/twl/architecture/examples/ に
        #     examples ディレクトリが存在すること
        # RED: examples/ ディレクトリがまだ存在しないため FAIL する
        examples_dir_exists = EXAMPLES_PROTOCOLS_DIR.exists() or PLUGINS_EXAMPLES_DIR.exists()
        assert examples_dir_exists, (
            f"AC9 未実装: examples/ ディレクトリが存在しない "
            f"(確認パス: {EXAMPLES_PROTOCOLS_DIR}, {PLUGINS_EXAMPLES_DIR})"
        )

    def test_ac9_protocols_example_file_exists(self):
        # AC: examples/ 配下に protocols/ 関連の .md ファイルが 1 件以上存在すること
        # RED: examples/ ディレクトリ自体がまだ存在しないため FAIL する
        candidate_dirs = [EXAMPLES_PROTOCOLS_DIR, PLUGINS_EXAMPLES_DIR]
        example_files: list[Path] = []
        for d in candidate_dirs:
            if d.exists():
                # **/*.md は再帰的なため *.md を内包する。set() で重複を除去する
                example_files.extend(set(d.glob("**/*.md")))
        assert len(example_files) >= 1, (
            "AC9 未実装: examples/ ディレクトリに protocols/*.md の実例 .md ファイルが存在しない "
            f"(確認ディレクトリ: {[str(d) for d in candidate_dirs]})"
        )
