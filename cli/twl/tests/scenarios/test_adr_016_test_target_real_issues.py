#!/usr/bin/env python3
"""Tests for ADR-016: test-target --real-issues mode design decisions.

Spec: deltaspec/changes/issue-444/specs/adr-016/spec.md

Verifies that ADR-016 exists at plugins/twl/architecture/decisions/
ADR-016-test-target-real-issues.md and contains all required sections and
content as mandated by the issue-444 spec.
"""

import re
from pathlib import Path

import pytest

# The ADR lives in plugins/twl, not cli/twl
REPO_ROOT = Path(__file__).parent.parent.parent.parent.parent
ADR_PATH = (
    REPO_ROOT
    / "plugins"
    / "twl"
    / "architecture"
    / "decisions"
    / "ADR-016-test-target-real-issues.md"
)


def _read_adr() -> str:
    """Read ADR-016 content, skipping if not yet created."""
    if not ADR_PATH.exists():
        pytest.skip(f"ADR-016 does not exist yet at {ADR_PATH}")
    return ADR_PATH.read_text(encoding="utf-8")


def _extract_headings(content: str) -> list[str]:
    """Extract all heading texts from Markdown content."""
    return [
        m.group(1).strip()
        for m in re.finditer(r"^#{1,6}\s+(.+)$", content, re.MULTILINE)
    ]


class TestAdr016FileCreation:
    """Scenario: ADR-016 ファイル作成

    WHEN: issue #444 の受け入れ基準を満たす変更が加えられる
    THEN: plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md
          が存在し、タイトル・Status・Context・3選択肢比較表・Decision・Consequences
          を含む
    """

    def test_adr_016_file_exists(self) -> None:
        """ADR-016-test-target-real-issues.md exists at the expected path."""
        assert ADR_PATH.exists(), (
            f"ADR-016 not found at {ADR_PATH}. "
            "The file must be created as part of issue-444."
        )

    def test_adr_016_has_title(self) -> None:
        """ADR-016 has a title heading."""
        content = _read_adr()
        headings = _extract_headings(content)
        assert headings, "ADR-016 has no headings at all"
        # First heading should be the title (level 1 or level 2)
        assert re.search(
            r"^#{1,2}\s+",
            content,
            re.MULTILINE,
        ), "ADR-016 must have a top-level title heading"

    def test_adr_016_has_required_sections(self) -> None:
        """ADR-016 contains Status, Context, Decision, Consequences sections."""
        content = _read_adr()
        headings_lower = [h.lower() for h in _extract_headings(content)]

        required = ["status", "context", "decision", "consequences"]
        missing = [
            s for s in required
            if not any(s in h for h in headings_lower)
        ]
        assert not missing, (
            f"ADR-016 is missing required sections: {missing}. "
            f"Found headings: {_extract_headings(content)}"
        )

    def test_adr_016_has_comparison_table(self) -> None:
        """ADR-016 contains a 3-strategy comparison table (Markdown table syntax)."""
        content = _read_adr()
        # Markdown tables use | as column separator
        table_rows = [
            line for line in content.splitlines()
            if line.strip().startswith("|") and "|" in line[1:]
        ]
        assert len(table_rows) >= 4, (
            "ADR-016 must contain a comparison table with at least 3 data rows "
            f"(header + separator + 3 strategies). Found {len(table_rows)} table rows."
        )


class TestAdr016ComparisonTableContent:
    """Scenario: 比較表の内容検証

    WHEN: ADR-016 を読む
    THEN: 3 戦略それぞれの隔離性・GitHub API 依存・クリーンアップ複雑度の評価と
          選定根拠が明記されている
    """

    def test_table_contains_three_strategies(self) -> None:
        """ADR-016 comparison table covers all 3 candidate strategies."""
        content = _read_adr()
        # Strategy 1: 専用リポ / dedicated repo
        has_dedicated = bool(
            re.search(r"専用リポ|dedicated.?repo|separate.?repo", content, re.IGNORECASE)
        )
        # Strategy 2: 実リポ test ラベル / real repo test label
        has_real_label = bool(
            re.search(
                r"実リポ|real.?repo|test\s*ラベル|test.?label",
                content,
                re.IGNORECASE,
            )
        )
        # Strategy 3: mock GitHub API
        has_mock = bool(
            re.search(r"mock.{0,20}(github|api)|github.{0,20}mock", content, re.IGNORECASE)
        )
        missing_strategies = []
        if not has_dedicated:
            missing_strategies.append("専用リポ (dedicated repo)")
        if not has_real_label:
            missing_strategies.append("実リポ test ラベル (real repo with test label)")
        if not has_mock:
            missing_strategies.append("mock GitHub API")
        assert not missing_strategies, (
            f"ADR-016 comparison table is missing strategies: {missing_strategies}"
        )

    def test_table_contains_isolation_axis(self) -> None:
        """ADR-016 comparison table includes 隔離性 (isolation) axis."""
        content = _read_adr()
        assert re.search(
            r"隔離性|isolation|isolat",
            content,
            re.IGNORECASE,
        ), "ADR-016 comparison table must include 隔離性 (isolation) as a comparison axis"

    def test_table_contains_github_api_dependency_axis(self) -> None:
        """ADR-016 comparison table includes GitHub API 依存度 axis."""
        content = _read_adr()
        assert re.search(
            r"GitHub\s*API\s*依存|api.{0,15}depend|depend.{0,15}api",
            content,
            re.IGNORECASE,
        ), (
            "ADR-016 comparison table must include GitHub API 依存 "
            "(GitHub API dependency) as a comparison axis"
        )

    def test_table_contains_cleanup_complexity_axis(self) -> None:
        """ADR-016 comparison table includes クリーンアップ複雑度 axis."""
        content = _read_adr()
        assert re.search(
            r"クリーンアップ.{0,10}複雑|cleanup.{0,15}complex|clean.{0,15}complex",
            content,
            re.IGNORECASE,
        ), (
            "ADR-016 comparison table must include クリーンアップ複雑度 "
            "(cleanup complexity) as a comparison axis"
        )

    def test_table_contains_selection_rationale(self) -> None:
        """ADR-016 includes the rationale for the chosen strategy."""
        content = _read_adr()
        has_rationale = bool(
            re.search(
                r"選定根拠|選択根拠|選んだ理由|rationale|reason|because|のため|から",
                content,
                re.IGNORECASE,
            )
        )
        assert has_rationale, (
            "ADR-016 must include selection rationale (選定根拠) for the chosen strategy"
        )


class TestAdr016IntegrationFlowDocumented:
    """Scenario: 統合フロー記載

    WHEN: ADR-016 を読む
    THEN: --real-issues 時のフロー（リポ作成→Issue起票→autopilot→observe→cleanup）
          が記載されている
    """

    def test_real_issues_flag_documented(self) -> None:
        """ADR-016 documents the --real-issues flag / mode."""
        content = _read_adr()
        assert re.search(
            r"--real-issues|real.issues\s*mode|real.issues\s*モード",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document the --real-issues flag"

    def test_flow_repo_creation_step_documented(self) -> None:
        """ADR-016 documents the repo creation step in the integration flow."""
        content = _read_adr()
        assert re.search(
            r"リポ作成|repo.{0,10}creat|creat.{0,10}repo|repository.{0,10}creat",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document the repository creation step in the flow"

    def test_flow_issue_creation_step_documented(self) -> None:
        """ADR-016 documents the Issue creation step in the integration flow."""
        content = _read_adr()
        assert re.search(
            r"Issue\s*起票|issue.{0,10}creat|creat.{0,10}issue|起票",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document the Issue creation step in the flow"

    def test_flow_autopilot_step_documented(self) -> None:
        """ADR-016 documents the autopilot step in the integration flow."""
        content = _read_adr()
        assert re.search(
            r"autopilot",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document the autopilot step in the integration flow"

    def test_flow_observe_step_documented(self) -> None:
        """ADR-016 documents the observe/observer step in the integration flow."""
        content = _read_adr()
        assert re.search(
            r"observe|observer|観察",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document the observe step in the integration flow"

    def test_flow_cleanup_step_documented(self) -> None:
        """ADR-016 documents the cleanup step in the integration flow."""
        content = _read_adr()
        assert re.search(
            r"cleanup|クリーンアップ|clean.?up",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document the cleanup step in the integration flow"

    def test_co_self_improve_integration_documented(self) -> None:
        """ADR-016 documents co-self-improve integration."""
        content = _read_adr()
        assert re.search(
            r"co-self-improve|co_self_improve",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document the co-self-improve integration"


class TestAdr016CleanupDesignDocumented:
    """Scenario: クリーンアップ設計の記載

    WHEN: ADR-016 を読む
    THEN: PR クローズ・Issue クローズ・branch 削除の後処理フローが記載されている
    """

    def test_pr_close_documented(self) -> None:
        """ADR-016 documents PR close in the cleanup flow."""
        content = _read_adr()
        assert re.search(
            r"PR.{0,15}(クローズ|close|clos)|close.{0,15}PR|(pull.?request).{0,15}close",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document PR close in the cleanup flow"

    def test_issue_close_documented(self) -> None:
        """ADR-016 documents Issue close in the cleanup flow."""
        content = _read_adr()
        assert re.search(
            r"Issue.{0,15}(クローズ|close|clos)|close.{0,15}issue",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document Issue close in the cleanup flow"

    def test_branch_delete_documented(self) -> None:
        """ADR-016 documents branch deletion in the cleanup flow."""
        content = _read_adr()
        assert re.search(
            r"branch.{0,15}(削除|delet|remov)|bランチ.{0,15}削除",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document branch deletion in the cleanup flow"

    def test_cleanup_runs_regardless_of_test_outcome(self) -> None:
        """ADR-016 states cleanup runs regardless of test success or failure."""
        content = _read_adr()
        has_unconditional = bool(
            re.search(
                r"成功.{0,30}失敗|失敗.{0,30}成功"
                r"|regardless|問わず|にかかわらず"
                r"|always|必ず|常に",
                content,
                re.IGNORECASE,
            )
        )
        assert has_unconditional, (
            "ADR-016 must state that cleanup is performed regardless of "
            "test success or failure (成功・失敗問わず)"
        )


class TestAdr016ResponsibilityDecisionDocumented:
    """Scenario: 責務決定の記載

    WHEN: ADR-016 を読む
    THEN: test-project-init --mode real-issues 拡張として決定されたことと、
          その根拠が記載されている
    """

    def test_test_project_init_decision_documented(self) -> None:
        """ADR-016 documents test-project-init as the chosen responsibility holder."""
        content = _read_adr()
        assert re.search(
            r"test-project-init|test_project_init",
            content,
            re.IGNORECASE,
        ), "ADR-016 must document test-project-init as the decision"

    def test_real_issues_mode_flag_documented(self) -> None:
        """ADR-016 documents --mode real-issues extension of test-project-init."""
        content = _read_adr()
        assert re.search(
            r"--mode\s+real-issues|mode.{0,10}real.issues",
            content,
            re.IGNORECASE,
        ), (
            "ADR-016 must document --mode real-issues as the chosen extension "
            "of test-project-init"
        )

    def test_rationale_for_responsibility_decision(self) -> None:
        """ADR-016 explains why test-project-init was chosen over a new command."""
        content = _read_adr()
        # Should mention the alternative (new command) and reason for rejection/selection
        has_rationale = bool(
            re.search(
                r"新規コマンド|new.?command|既存.{0,20}拡張|extend.{0,20}exist"
                r"|根拠|rationale|reason|because|のため",
                content,
                re.IGNORECASE,
            )
        )
        assert has_rationale, (
            "ADR-016 must explain the rationale for choosing test-project-init "
            "extension over creating a new command"
        )
