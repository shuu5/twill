"""Tests for Issue #442: test-scenario-catalog.md に regression-003〜006 追加.

Spec: deltaspec/changes/issue-442/specs/test-scenario-catalog/spec.md

Coverage:
  Requirement: regression-003 full-chain シナリオ
    - Scenario: regression-003 フォーマット準拠
        WHEN: test-scenario-catalog.md を参照する
        THEN: regression-003 エントリが存在し、level=regression、issues_count=1、
              complexity=medium、expected_duration_min/max・expected_conflicts・
              expected_pr_count が記載されている
    - Scenario: regression-003 issue_template
        WHEN: regression-003 の issue_templates を展開する
        THEN: DeltaSpec を要求する Issue body が含まれており、
              setup → test-ready → pr-verify → pr-merge の全遷移を誘発できる

  Requirement: regression-004 Bug #436 再現シナリオ
    - Scenario: regression-004 フォーマット準拠
        WHEN: test-scenario-catalog.md を参照する
        THEN: regression-004 エントリが存在し、level=regression、issues_count=1、
              expected_duration_min/max・expected_conflicts・expected_pr_count が記載されている
    - Scenario: regression-004 Bug 再現条件
        WHEN: regression-004 の issue_templates を展開する
        THEN: Issue body に DeltaSpec（twl spec new）を使う指示が含まれており、
              orchestrator の issue: フィールド grep が 0 件ヒットして archive 失敗を誘発できる
              条件が記述されている

  Requirement: regression-005 Bug #438 再現シナリオ
    - Scenario: regression-005 フォーマット準拠
        WHEN: test-scenario-catalog.md を参照する
        THEN: regression-005 エントリが存在し、level=regression、issues_count=1、
              expected_duration_min/max・expected_conflicts・expected_pr_count が記載されている
    - Scenario: regression-005 Bug 再現条件
        WHEN: regression-005 の issue_templates を展開する
        THEN: Issue body に長時間実行（120 秒超）を要する処理を含む指示が記述されており、
              Orchestrator polling loop の timeout を誘発できる条件が明示されている

  Requirement: regression-006 Bug #439 再現シナリオ
    - Scenario: regression-006 フォーマット準拠
        WHEN: test-scenario-catalog.md を参照する
        THEN: regression-006 エントリが存在し、level=regression、issues_count=1、
              expected_duration_min/max・expected_conflicts・expected_pr_count が記載されている
    - Scenario: regression-006 Bug 再現条件
        WHEN: regression-006 の issue_templates を展開する
        THEN: Issue body に pr-verify の review フェーズをスキップさせる条件が含まれており、
              phase-review.json が生成されないまま merge-gate に到達できる状況が記述されている

  Edge cases (--coverage=edge-cases):
    - YAML コードブロックが正しく抽出できること（フォーマット不正検出）
    - 必須フィールドが欠落した場合にテストが明示的に失敗すること
    - issue_templates が空でないこと
    - issue_templates の各テンプレートに title / body / labels / complexity が存在すること
    - body が空文字でないこと
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import pytest
import yaml

# ---------------------------------------------------------------------------
# Catalog file location
# ---------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent.parent.parent
_CATALOG_PATH = _REPO_ROOT / "plugins" / "twl" / "refs" / "test-scenario-catalog.md"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _parse_catalog(catalog_path: Path) -> dict[str, Any]:
    """Read test-scenario-catalog.md and return a dict of scenario_id -> parsed YAML."""
    text = catalog_path.read_text(encoding="utf-8")

    # Extract all fenced yaml code blocks
    code_blocks = re.findall(r"```yaml\n(.*?)```", text, re.DOTALL)

    scenarios: dict[str, Any] = {}
    for block in code_blocks:
        # Skip blocks that are schema examples (contain placeholder like "<scenario-id>")
        if "<scenario-id>" in block:
            continue
        # Skip comment-only blocks
        stripped = block.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            parsed = yaml.safe_load(block)
        except yaml.YAMLError:
            continue
        if isinstance(parsed, dict):
            scenarios.update(parsed)

    return scenarios


_CATALOG: dict[str, Any] | None = None


def _get_catalog() -> dict[str, Any]:
    global _CATALOG
    if _CATALOG is None:
        _CATALOG = _parse_catalog(_CATALOG_PATH)
    return _CATALOG


def _get_scenario(scenario_id: str) -> dict[str, Any]:
    catalog = _get_catalog()
    assert scenario_id in catalog, (
        f"Scenario '{scenario_id}' not found in {_CATALOG_PATH}. "
        f"Available scenarios: {sorted(catalog.keys())}"
    )
    return catalog[scenario_id]


# ---------------------------------------------------------------------------
# catalog file existence guard
# ---------------------------------------------------------------------------


def test_catalog_file_exists() -> None:
    """Catalog file must exist at plugins/twl/refs/test-scenario-catalog.md."""
    assert _CATALOG_PATH.exists(), (
        f"test-scenario-catalog.md not found at {_CATALOG_PATH}"
    )


# ===========================================================================
# Requirement: regression-003 issue_template（full-chain 固有）
# ===========================================================================


class TestRegression003IssueTemplate:
    """Scenario: regression-003 issue_template
    WHEN regression-003 の issue_templates を展開する
    THEN DeltaSpec を要求する Issue body が含まれており
         setup → test-ready → pr-verify → pr-merge の全遷移を誘発できる
    """

    def test_regression_003_body_mentions_deltaspec(self) -> None:
        """THEN issue body contains reference to DeltaSpec / twl spec new."""
        sc = _get_scenario("regression-003")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies).lower()
        assert any(kw in combined for kw in ("deltaspec", "twl spec", "spec new", "spec-driven")), (
            "regression-003 issue body must reference DeltaSpec (e.g. 'twl spec new' or 'DeltaSpec')"
        )

    def test_regression_003_body_enables_full_chain_transitions(self) -> None:
        """THEN issue body contains enough content to drive setup→test-ready→pr-verify→pr-merge."""
        sc = _get_scenario("regression-003")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies)
        assert len(combined) >= 100, (
            f"regression-003 issue body is too short ({len(combined)} chars) to drive "
            "setup→test-ready→pr-verify→pr-merge full chain"
        )

    def test_regression_003_complexity_is_medium(self) -> None:
        """THEN issue_template complexity == 'medium' (regression-003 is medium complexity)."""
        sc = _get_scenario("regression-003")
        templates = sc.get("issue_templates", [])
        assert len(templates) > 0, "regression-003 must have at least one issue_template"
        complexities = [t.get("complexity") for t in templates]
        assert "medium" in complexities, (
            f"regression-003 must have at least one issue_template with complexity=medium, "
            f"got: {complexities}"
        )


# ===========================================================================
# Requirement: regression-004 Bug #436 再現条件（固有）
# ===========================================================================


class TestRegression004BugReproCondition:
    """Scenario: regression-004 Bug 再現条件
    WHEN regression-004 の issue_templates を展開する
    THEN Issue body に DeltaSpec（twl spec new）を使う指示が含まれており
         orchestrator の issue: フィールド grep が 0 件ヒットして archive 失敗を誘発できる
         条件が記述されている
    """

    def test_regression_004_body_references_twl_spec_new(self) -> None:
        """THEN issue body explicitly instructs use of 'twl spec new'."""
        sc = _get_scenario("regression-004")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies)
        assert any(
            kw in combined for kw in ("twl spec new", "twl spec", "deltaspec", "DeltaSpec")
        ), (
            "regression-004 issue body must instruct the agent to run 'twl spec new' "
            "(Bug #436 reproduction condition)"
        )

    def test_regression_004_body_describes_archive_failure_condition(self) -> None:
        """THEN issue body is substantive enough to describe archive failure condition."""
        sc = _get_scenario("regression-004")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies).lower()
        assert len(combined) >= 80, (
            f"regression-004 body too short ({len(combined)} chars) to describe "
            "Bug #436 archive-failure condition"
        )


# ===========================================================================
# Requirement: regression-005 Bug #438 再現条件（固有）
# ===========================================================================


class TestRegression005BugReproCondition:
    """Scenario: regression-005 Bug 再現条件
    WHEN regression-005 の issue_templates を展開する
    THEN Issue body に長時間実行（120 秒超）を要する処理を含む指示が記述されており
         Orchestrator polling loop の timeout を誘発できる条件が明示されている
    """

    def test_regression_005_body_describes_long_running_task(self) -> None:
        """THEN issue body describes a task requiring more than 120 seconds to reproduce Bug #438."""
        sc = _get_scenario("regression-005")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies).lower()
        timeout_keywords = (
            "120", "sleep", "wait", "timeout", "long", "秒", "時間", "遅延", "polling"
        )
        assert any(kw in combined for kw in timeout_keywords), (
            "regression-005 issue body must describe a long-running task (>120s) "
            "to reproduce Bug #438 Orchestrator polling timeout. "
            f"Checked keywords: {timeout_keywords}"
        )

    def test_regression_005_body_timeout_condition_explicit(self) -> None:
        """THEN body is substantive enough to contain explicit timeout condition."""
        sc = _get_scenario("regression-005")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies)
        assert len(combined) >= 80, (
            f"regression-005 body too short ({len(combined)} chars) to describe "
            "Bug #438 polling timeout reproduction condition"
        )


# ===========================================================================
# Requirement: regression-006 Bug #439 再現条件（固有）
# ===========================================================================


class TestRegression006BugReproCondition:
    """Scenario: regression-006 Bug 再現条件
    WHEN regression-006 の issue_templates を展開する
    THEN Issue body に pr-verify の review フェーズをスキップさせる条件が含まれており
         phase-review.json が生成されないまま merge-gate に到達できる状況が記述されている
    """

    def test_regression_006_body_describes_review_skip_condition(self) -> None:
        """THEN issue body describes condition that causes review phase to be skipped (Bug #439)."""
        sc = _get_scenario("regression-006")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies).lower()
        review_keywords = (
            "review", "pr-verify", "phase-review", "merge-gate", "mergegate",
            "レビュー", "skip", "スキップ"
        )
        assert any(kw in combined for kw in review_keywords), (
            "regression-006 issue body must describe a condition that causes the review "
            "phase to be skipped (Bug #439). "
            f"Checked keywords: {review_keywords}"
        )

    def test_regression_006_body_references_phase_review_json(self) -> None:
        """THEN body explicitly references phase-review.json or merge-gate condition."""
        sc = _get_scenario("regression-006")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies)
        assert any(
            kw in combined
            for kw in ("phase-review", "phase_review", "merge-gate", "merge_gate", "pr-verify")
        ), (
            "regression-006 issue body must reference 'phase-review.json' or 'merge-gate' "
            "to describe the Bug #439 reproduction condition"
        )

    def test_regression_006_body_is_substantive(self) -> None:
        """THEN body is long enough to contain the reproduction description."""
        sc = _get_scenario("regression-006")
        bodies = [t.get("body", "") for t in sc.get("issue_templates", [])]
        combined = "\n".join(bodies)
        assert len(combined) >= 80, (
            f"regression-006 body too short ({len(combined)} chars) to describe "
            "Bug #439 phase-review.json absence condition"
        )


# ===========================================================================
# Edge cases: フォーマット準拠・フィールド欠落検出（全新規シナリオ共通）
# ===========================================================================


class TestCatalogEdgeCases:
    """Edge cases: catalog format validation and field completeness for regression-003〜006."""

    _REGRESSION_IDS = ["regression-003", "regression-004", "regression-005", "regression-006"]

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_entry_exists(self, scenario_id: str) -> None:
        """THEN each new regression scenario key is present in the catalog."""
        catalog = _get_catalog()
        assert scenario_id in catalog, (
            f"Scenario '{scenario_id}' must be defined in test-scenario-catalog.md"
        )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_has_description(self, scenario_id: str) -> None:
        """THEN each new regression scenario has a non-empty description field."""
        sc = _get_scenario(scenario_id)
        desc = sc.get("description")
        assert desc and isinstance(desc, str) and len(desc.strip()) > 0, (
            f"{scenario_id} must have a non-empty 'description' field"
        )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_level_is_regression(self, scenario_id: str) -> None:
        """THEN level == 'regression' for all new scenarios."""
        sc = _get_scenario(scenario_id)
        assert sc.get("level") == "regression", (
            f"{scenario_id} level must be 'regression', got: {sc.get('level')!r}"
        )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_issues_count_is_1(self, scenario_id: str) -> None:
        """THEN issues_count == 1 for all new Bug-repro scenarios."""
        sc = _get_scenario(scenario_id)
        val = sc.get("issues_count")
        assert isinstance(val, int) and val == 1, (
            f"{scenario_id} issues_count must be 1, got: {val!r}"
        )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_duration_range_valid(self, scenario_id: str) -> None:
        """THEN expected_duration_max >= expected_duration_min > 0."""
        sc = _get_scenario(scenario_id)
        min_val = sc.get("expected_duration_min")
        max_val = sc.get("expected_duration_max")
        assert isinstance(min_val, int) and min_val > 0, (
            f"{scenario_id} expected_duration_min must be a positive int"
        )
        assert isinstance(max_val, int) and max_val >= min_val, (
            f"{scenario_id} expected_duration_max ({max_val}) must be >= "
            f"expected_duration_min ({min_val})"
        )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_has_expected_conflicts(self, scenario_id: str) -> None:
        """THEN expected_conflicts is present and is a non-negative integer."""
        sc = _get_scenario(scenario_id)
        val = sc.get("expected_conflicts")
        assert val is not None, f"{scenario_id} must have expected_conflicts"
        assert isinstance(val, int) and val >= 0, (
            f"{scenario_id} expected_conflicts must be a non-negative int, got: {val!r}"
        )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_has_expected_pr_count(self, scenario_id: str) -> None:
        """THEN expected_pr_count is present and is a positive integer."""
        sc = _get_scenario(scenario_id)
        val = sc.get("expected_pr_count")
        assert val is not None, f"{scenario_id} must have expected_pr_count"
        assert isinstance(val, int) and val > 0, (
            f"{scenario_id} expected_pr_count must be a positive int, got: {val!r}"
        )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_issue_templates_not_empty(self, scenario_id: str) -> None:
        """THEN issue_templates is a non-empty list."""
        sc = _get_scenario(scenario_id)
        templates = sc.get("issue_templates")
        assert isinstance(templates, list) and len(templates) > 0, (
            f"{scenario_id} issue_templates must be a non-empty list"
        )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_each_template_has_title_body_labels(self, scenario_id: str) -> None:
        """THEN each issue_template entry has non-empty title, body, and labels."""
        sc = _get_scenario(scenario_id)
        for i, t in enumerate(sc.get("issue_templates", [])):
            assert isinstance(t, dict), (
                f"{scenario_id} issue_templates[{i}] must be a dict"
            )
            assert t.get("title") and isinstance(t["title"], str), (
                f"{scenario_id} issue_templates[{i}].title must be a non-empty string"
            )
            assert t.get("body") and isinstance(t["body"], str), (
                f"{scenario_id} issue_templates[{i}].body must be a non-empty string"
            )
            labels = t.get("labels")
            assert isinstance(labels, list) and len(labels) > 0, (
                f"{scenario_id} issue_templates[{i}].labels must be a non-empty list"
            )

    @pytest.mark.parametrize("scenario_id", _REGRESSION_IDS)
    def test_scenario_each_template_complexity_valid(self, scenario_id: str) -> None:
        """THEN each issue_template complexity is one of trivial | medium | complex."""
        sc = _get_scenario(scenario_id)
        valid_complexities = {"trivial", "medium", "complex"}
        for i, t in enumerate(sc.get("issue_templates", [])):
            complexity = t.get("complexity")
            assert complexity in valid_complexities, (
                f"{scenario_id} issue_templates[{i}].complexity must be one of "
                f"{valid_complexities}, got: {complexity!r}"
            )

    def test_no_duplicate_scenario_ids_in_catalog(self) -> None:
        """Edge case: YAML parsing must not silently merge duplicate keys.

        yaml.safe_load deduplicates keys — we check the raw text has no duplicate top-level IDs.
        """
        text = _CATALOG_PATH.read_text(encoding="utf-8")
        code_blocks = re.findall(r"```yaml\n(.*?)```", text, re.DOTALL)
        seen: list[str] = []
        for block in code_blocks:
            if "<scenario-id>" in block or not block.strip():
                continue
            for line in block.splitlines():
                m = re.match(r"^([a-z][\w-]+):\s*$", line)
                if m:
                    seen.append(m.group(1))
        duplicates = {sid for sid in seen if seen.count(sid) > 1}
        assert not duplicates, (
            f"Duplicate scenario IDs found in catalog: {duplicates}"
        )

    def test_catalog_yaml_blocks_parseable(self) -> None:
        """Edge case: all non-schema yaml blocks in catalog must parse without YAML errors."""
        text = _CATALOG_PATH.read_text(encoding="utf-8")
        code_blocks = re.findall(r"```yaml\n(.*?)```", text, re.DOTALL)
        errors: list[str] = []
        for i, block in enumerate(code_blocks):
            if "<scenario-id>" in block or not block.strip():
                continue
            try:
                yaml.safe_load(block)
            except yaml.YAMLError as e:
                errors.append(f"Block {i}: {e}")
        assert not errors, (
            f"YAML parse errors found in test-scenario-catalog.md:\n" +
            "\n".join(errors)
        )
