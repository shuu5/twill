#!/usr/bin/env python3
"""Tests for Issue close → Project Board Status Done workflow YAML structure.

Spec: openspec/changes/project-board-add-to-project-closedone/specs/project-status-done.md

Requirements:
- Issue クローズ時に Status を Done に更新
- GraphQL による Item 検索と条件付き更新

Validates that .github/workflows/project-status-done.yml exists with the
required structure: issues.closed trigger, GraphQL item search, conditional
Status update, and graceful no-op when item is not found.
"""

import re
import sys
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).parent.parent.parent.parent.parent
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "project-status-done.yml"

# Hardcoded IDs from design.md / Issue #56 body
EXPECTED_PROJECT_ID = "PVT_kwHOCNFEd84BS03g"
EXPECTED_STATUS_FIELD_ID = "PVTSSF_lAHOCNFEd84BS03gzhAPzog"
EXPECTED_DONE_OPTION_ID = "98236657"


def _load_workflow() -> dict:
    """Load the project-status-done workflow YAML."""
    return yaml.safe_load(WORKFLOW_PATH.read_text(encoding="utf-8"))


def _skip_if_missing() -> None:
    if not WORKFLOW_PATH.exists():
        pytest.skip(f"Workflow not yet created: {WORKFLOW_PATH}")


class TestProjectStatusDoneWorkflowExists:
    """Prerequisite: workflow file must exist before structural checks."""

    def test_workflow_file_exists(self) -> None:
        """project-status-done.yml exists at .github/workflows/."""
        assert WORKFLOW_PATH.exists(), (
            f"Workflow file not found: {WORKFLOW_PATH}\n"
            "Expected: .github/workflows/project-status-done.yml"
        )

    def test_workflow_is_valid_yaml(self) -> None:
        """project-status-done.yml is valid YAML."""
        _skip_if_missing()
        try:
            wf = _load_workflow()
        except yaml.YAMLError as exc:
            pytest.fail(f"Invalid YAML in project-status-done.yml: {exc}")
        assert isinstance(wf, dict), "Workflow root must be a YAML mapping"


# ===========================================================================
# Requirement: Issue クローズ時に Status を Done に更新
# Scenario: Board 登録済み Issue のクローズ
# ===========================================================================

class TestBoardRegisteredIssueClose:
    """Scenario: Board 登録済み Issue のクローズ

    WHEN: Project Board に登録済みの Issue がクローズされる
    THEN: その Issue の Project Board Status が Done に更新される
    """

    def setup_method(self) -> None:
        _skip_if_missing()
        self.wf = _load_workflow()
        self.wf_text = WORKFLOW_PATH.read_text(encoding="utf-8")

    def test_triggers_on_issues_closed(self) -> None:
        """Workflow is triggered by issues.types: [closed]."""
        on = self.wf.get("on") or self.wf.get(True)
        assert on is not None, "Workflow missing 'on:' trigger block"
        assert "issues" in on, (
            f"'issues' event not found in triggers. Found: {list(on.keys())}"
        )
        issues_trigger = on.get("issues", {})
        types = issues_trigger.get("types", [])
        assert "closed" in types, (
            f"'closed' not in issues.types: {types}"
        )

    def test_uses_gh_api_graphql(self) -> None:
        """Workflow uses 'gh api graphql' for Project Item operations."""
        assert "gh api graphql" in self.wf_text, (
            "Workflow does not contain 'gh api graphql'.\n"
            "Required for Project Item search and Status update."
        )

    def test_references_updateprojectv2itemfieldvalue_mutation(self) -> None:
        """Workflow contains updateProjectV2ItemFieldValue GraphQL mutation."""
        assert "updateProjectV2ItemFieldValue" in self.wf_text, (
            "updateProjectV2ItemFieldValue mutation not found in workflow.\n"
            "Required to update Status field to Done."
        )

    def test_hardcoded_project_id_matches_spec(self) -> None:
        """Workflow uses the correct Project ID from Issue #56."""
        assert EXPECTED_PROJECT_ID in self.wf_text, (
            f"Project ID '{EXPECTED_PROJECT_ID}' not found in workflow.\n"
            "Must match the ID from Issue #56 / design.md."
        )

    def test_hardcoded_status_field_id_matches_spec(self) -> None:
        """Workflow uses the correct Status field ID from Issue #56."""
        assert EXPECTED_STATUS_FIELD_ID in self.wf_text, (
            f"Status field ID '{EXPECTED_STATUS_FIELD_ID}' not found in workflow.\n"
            "Must match the ID from Issue #56 / design.md."
        )

    def test_hardcoded_done_option_id_matches_spec(self) -> None:
        """Workflow uses the correct Done option ID from Issue #56."""
        assert EXPECTED_DONE_OPTION_ID in self.wf_text, (
            f"Done option ID '{EXPECTED_DONE_OPTION_ID}' not found in workflow.\n"
            "Must match the ID from Issue #56 / design.md."
        )


# ===========================================================================
# Requirement: Issue クローズ時に Status を Done に更新
# Scenario: Board 未登録 Issue のクローズ
# ===========================================================================

class TestBoardUnregisteredIssueClose:
    """Scenario: Board 未登録 Issue のクローズ

    WHEN: Project Board に未登録の Issue がクローズされる
    THEN: workflow run は success (green) で完了し、エラーは発生しない
    """

    def setup_method(self) -> None:
        _skip_if_missing()
        self.wf = _load_workflow()
        self.wf_text = WORKFLOW_PATH.read_text(encoding="utf-8")

    def test_no_unconditional_mutation_step(self) -> None:
        """Status update step is guarded by a condition (not run unconditionally)."""
        jobs = self.wf.get("jobs", {})
        update_steps = []
        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                run_script = step.get("run", "")
                if "updateProjectV2ItemFieldValue" in run_script:
                    update_steps.append(step)

        # Every mutation step must have an 'if:' condition or be inside a
        # conditional block (checked via 'if' key or by using continue-on-error)
        for step in update_steps:
            has_if = "if" in step
            has_continue_on_error = step.get("continue-on-error", False)
            assert has_if or has_continue_on_error, (
                f"Step '{step.get('name', '<unnamed>')}' runs updateProjectV2ItemFieldValue "
                "unconditionally.\n"
                "Board-unregistered Issues would cause workflow failure.\n"
                "Add 'if:' condition or 'continue-on-error: true'."
            )

    def test_search_step_precedes_mutation_step(self) -> None:
        """A GraphQL search/query step exists before the mutation step."""
        jobs = self.wf.get("jobs", {})
        for job_name, job in jobs.items():
            steps = job.get("steps", [])
            search_idx = None
            mutation_idx = None
            for i, step in enumerate(steps):
                run = step.get("run", "")
                if "gh api graphql" in run and "updateProjectV2ItemFieldValue" not in run:
                    search_idx = i
                if "updateProjectV2ItemFieldValue" in run:
                    mutation_idx = i

            if mutation_idx is not None:
                assert search_idx is not None, (
                    f"Job '{job_name}': mutation step found but no preceding search step.\n"
                    "Item must be searched before attempting Status update."
                )
                assert search_idx < mutation_idx, (
                    f"Job '{job_name}': search step (index {search_idx}) must come "
                    f"before mutation step (index {mutation_idx})."
                )

    def test_workflow_does_not_use_exit_1_unconditionally(self) -> None:
        """Workflow does not have unconditional 'exit 1' that would fail on missing item."""
        jobs = self.wf.get("jobs", {})
        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                run = step.get("run", "")
                # Allow 'exit 1' only inside conditional blocks (i.e., if/then in shell)
                # A bare 'exit 1' not inside an 'if' shell construct is problematic
                bare_exit1 = re.search(r"^exit 1\s*$", run, re.MULTILINE)
                if bare_exit1:
                    step_if = step.get("if", "")
                    assert step_if, (
                        f"Step '{step.get('name', '<unnamed>')}' in job '{job_name}' "
                        "has unconditional 'exit 1' without an 'if:' guard.\n"
                        "This would fail when Board-unregistered Issue is closed."
                    )


# ===========================================================================
# Requirement: GraphQL による Item 検索と条件付き更新
# Scenario: Item 検索成功時の Status 更新
# ===========================================================================

class TestItemSearchSuccess:
    """Scenario: Item 検索成功時の Status 更新

    WHEN: GraphQL クエリで Issue に対応する Project Item が見つかる
    THEN: updateProjectV2ItemFieldValue mutation で Status field を Done option に更新する
    """

    def setup_method(self) -> None:
        _skip_if_missing()
        self.wf = _load_workflow()
        self.wf_text = WORKFLOW_PATH.read_text(encoding="utf-8")

    def test_mutation_targets_status_field(self) -> None:
        """Workflow mutation references fieldId (Status field ID)."""
        assert "fieldId" in self.wf_text or "field_id" in self.wf_text, (
            "No 'fieldId' reference found in workflow.\n"
            "updateProjectV2ItemFieldValue requires fieldId parameter."
        )

    def test_mutation_targets_done_option_value(self) -> None:
        """Workflow mutation sets value to Done option ID."""
        # The mutation must reference the Done option ID as the value
        assert EXPECTED_DONE_OPTION_ID in self.wf_text, (
            f"Done option ID '{EXPECTED_DONE_OPTION_ID}' missing from workflow.\n"
            "updateProjectV2ItemFieldValue must set singleSelectValue to this ID."
        )

    def test_graphql_references_issue_node_id(self) -> None:
        """Workflow uses issue node ID (github.event.issue.node_id) for GraphQL query."""
        uses_node_id = (
            "node_id" in self.wf_text
            or "github.event.issue.node_id" in self.wf_text
        )
        assert uses_node_id, (
            "Workflow does not reference issue node_id.\n"
            "GraphQL Project Item search requires the Issue's node_id."
        )

    def test_gh_token_for_graphql_available(self) -> None:
        """Workflow makes GH_TOKEN or PAT available for gh api graphql calls."""
        has_gh_token = "GH_TOKEN" in self.wf_text
        has_github_token = "GITHUB_TOKEN" in self.wf_text
        has_pat = "ADD_TO_PROJECT_PAT" in self.wf_text
        assert has_gh_token or has_github_token or has_pat, (
            "Workflow does not set GH_TOKEN, GITHUB_TOKEN, or ADD_TO_PROJECT_PAT.\n"
            "gh api graphql requires an authenticated token with project: scope."
        )


# ===========================================================================
# Requirement: GraphQL による Item 検索と条件付き更新
# Scenario: Item 検索結果が空の場合
# ===========================================================================

class TestItemSearchEmpty:
    """Scenario: Item 検索結果が空の場合

    WHEN: GraphQL クエリで Issue に対応する Project Item が見つからない
    THEN: 更新ステップをスキップし、workflow は正常終了する
    """

    def setup_method(self) -> None:
        _skip_if_missing()
        self.wf = _load_workflow()
        self.wf_text = WORKFLOW_PATH.read_text(encoding="utf-8")

    def test_empty_result_guard_exists(self) -> None:
        """Workflow has a guard to skip update when search returns empty result.

        Acceptable patterns:
        - Shell conditional: if [ -z "$ITEM_ID" ]; then exit 0; fi
        - Shell conditional: if [ -n "$ITEM_ID" ]; then <mutation>; fi
        - Step 'if:' expression checking output of search step
        - continue-on-error on mutation step
        """
        jobs = self.wf.get("jobs", {})
        found_guard = False

        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                run = step.get("run", "")
                step_if = step.get("if", "")
                continue_on_error = step.get("continue-on-error", False)

                # Pattern 1: shell-level null check on item variable
                if re.search(r'if\s+\[.*-[zn].*\$\w*(ITEM|item|NODE|node)\w*', run):
                    found_guard = True
                # Pattern 2: step-level 'if:' referencing previous step output
                if step_if and ("steps." in str(step_if) or "item" in str(step_if).lower()):
                    found_guard = True
                # Pattern 3: continue-on-error on mutation step
                if continue_on_error and "updateProjectV2ItemFieldValue" in run:
                    found_guard = True

        assert found_guard, (
            "No guard found for empty GraphQL search result.\n"
            "Workflow must skip Status update when Project Item is not found.\n"
            "Expected: shell 'if [ -z \"$ITEM_ID\" ]' or step 'if:' condition "
            "or 'continue-on-error: true' on mutation step."
        )

    def test_mutation_step_not_reached_when_no_item(self) -> None:
        """Mutation step is in a conditional block or guarded by an output check."""
        jobs = self.wf.get("jobs", {})
        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                run = step.get("run", "")
                if "updateProjectV2ItemFieldValue" in run:
                    step_if = step.get("if", "")
                    continue_on_error = step.get("continue-on-error", False)

                    # Check shell-level guard inside the run script
                    has_shell_guard = bool(
                        re.search(r'if\s+\[', run)
                        or re.search(r'\$\w*(ITEM|item)\w*.*\|\|.*exit\s+0', run)
                    )
                    has_step_guard = bool(step_if)

                    assert has_shell_guard or has_step_guard or continue_on_error, (
                        f"Mutation step '{step.get('name', '<unnamed>')}' in job "
                        f"'{job_name}' has no guard against empty item lookup.\n"
                        "Add 'if:' condition, shell guard, or 'continue-on-error: true'."
                    )


# ===========================================================================
# Edge cases: YAML structural integrity
# ===========================================================================

class TestProjectStatusDoneYamlStructure:
    """Structural edge-case checks for project-status-done.yml."""

    def setup_method(self) -> None:
        _skip_if_missing()
        self.wf = _load_workflow()

    def test_has_name_field(self) -> None:
        """Workflow has a human-readable 'name:' field."""
        assert "name" in self.wf, "Workflow missing 'name:' field"
        assert self.wf["name"], "Workflow 'name:' is empty"

    def test_has_jobs_section(self) -> None:
        """Workflow has a 'jobs:' section."""
        assert "jobs" in self.wf, "Workflow missing 'jobs:' section"
        assert self.wf["jobs"], "Workflow 'jobs:' section is empty"

    def test_jobs_have_runs_on(self) -> None:
        """Every job specifies 'runs-on:'."""
        jobs = self.wf.get("jobs", {})
        for job_name, job in jobs.items():
            assert "runs-on" in job, (
                f"Job '{job_name}' missing 'runs-on:'"
            )

    def test_only_closed_in_issues_types(self) -> None:
        """Workflow triggers only on issues.closed (not opened/reopened/transferred)."""
        on = self.wf.get("on") or self.wf.get(True)
        issues_trigger = on.get("issues", {}) if on else {}
        types = issues_trigger.get("types", [])
        assert "closed" in types, f"'closed' not in issues.types: {types}"
        # Should not trigger on opened/reopened (that is add-to-project's job)
        unexpected = [t for t in types if t in ("opened", "reopened", "transferred")]
        assert not unexpected, (
            f"project-status-done.yml should only trigger on 'closed', "
            f"not on: {unexpected}"
        )

    def test_no_add_to_project_action(self) -> None:
        """project-status-done.yml does not use actions/add-to-project (wrong workflow)."""
        wf_text = WORKFLOW_PATH.read_text(encoding="utf-8")
        assert "actions/add-to-project" not in wf_text, (
            "project-status-done.yml should not use actions/add-to-project.\n"
            "That action belongs in add-to-project.yml."
        )


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestProjectStatusDoneWorkflowExists,
        TestBoardRegisteredIssueClose,
        TestBoardUnregisteredIssueClose,
        TestItemSearchSuccess,
        TestItemSearchEmpty,
        TestProjectStatusDoneYamlStructure,
    ]
    passed = 0
    failed = 0
    errors = []

    for cls in classes:
        for method_name in sorted(dir(cls)):
            if not method_name.startswith("test_"):
                continue
            instance = cls()
            if hasattr(instance, "setup_method"):
                instance.setup_method()
            try:
                getattr(instance, method_name)()
                passed += 1
                print(f"  PASS: {cls.__name__}.{method_name}")
            except pytest.skip.Exception as e:
                print(f"  SKIP: {cls.__name__}.{method_name}: {e}")
            except Exception as e:
                failed += 1
                errors.append((f"{cls.__name__}.{method_name}", e))
                print(f"  FAIL: {cls.__name__}.{method_name}: {e}")
                traceback.print_exc()

    print(f"\n{'=' * 40}")
    print(f"Results: {passed} passed, {failed} failed")
    if errors:
        print("\nFailures:")
        for name, err in errors:
            print(f"  {name}: {err}")
        sys.exit(1)
    else:
        print("All tests passed!")
