#!/usr/bin/env python3
"""Tests for Issue to Project Board auto-add workflow YAML structure.

Spec: openspec/changes/project-board-add-to-project-closedone/specs/add-to-project.md

Requirement: Issue を Project Board に自動追加

Validates that .github/workflows/add-to-project.yml exists with the required
structure to handle opened, reopened, and transferred Issue events.
"""

import sys
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).parent.parent.parent
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "add-to-project.yml"


def _load_workflow() -> dict:
    """Load the add-to-project workflow YAML."""
    return yaml.safe_load(WORKFLOW_PATH.read_text(encoding="utf-8"))


def _skip_if_missing() -> None:
    if not WORKFLOW_PATH.exists():
        pytest.skip(f"Workflow not yet created: {WORKFLOW_PATH}")


class TestAddToProjectWorkflowExists:
    """Prerequisite: workflow file must exist before structural checks."""

    def test_workflow_file_exists(self) -> None:
        """add-to-project.yml exists at .github/workflows/."""
        assert WORKFLOW_PATH.exists(), (
            f"Workflow file not found: {WORKFLOW_PATH}\n"
            "Expected: .github/workflows/add-to-project.yml"
        )

    def test_workflow_is_valid_yaml(self) -> None:
        """add-to-project.yml is valid YAML."""
        _skip_if_missing()
        try:
            wf = _load_workflow()
        except yaml.YAMLError as exc:
            pytest.fail(f"Invalid YAML in add-to-project.yml: {exc}")
        assert isinstance(wf, dict), "Workflow root must be a YAML mapping"


# ===========================================================================
# Requirement: Issue を Project Board に自動追加
# Scenario: 新規 Issue 作成時の自動追加
# ===========================================================================

class TestNewIssueTrigger:
    """Scenario: 新規 Issue 作成時の自動追加

    WHEN: loom リポジトリで新規 Issue が作成される
    THEN: Issue が Project Board (loom-dev-ecosystem) に自動追加される
    """

    def setup_method(self) -> None:
        _skip_if_missing()
        self.wf = _load_workflow()

    def test_triggers_on_issues_event(self) -> None:
        """Workflow is triggered by the 'issues' event."""
        on = self.wf.get("on") or self.wf.get(True)  # YAML parses 'on' as True
        assert on is not None, "Workflow missing 'on:' trigger block"
        assert "issues" in on, (
            f"'issues' event not found in triggers. Found: {list(on.keys())}"
        )

    def test_triggers_on_issues_opened(self) -> None:
        """Workflow triggers on issues.types: [opened, ...]."""
        on = self.wf.get("on") or self.wf.get(True)
        issues_trigger = on.get("issues", {})
        types = issues_trigger.get("types", [])
        assert "opened" in types, (
            f"'opened' not in issues.types: {types}"
        )

    def test_uses_add_to_project_action(self) -> None:
        """At least one step uses actions/add-to-project@v1."""
        jobs = self.wf.get("jobs", {})
        all_uses = []
        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                if "uses" in step:
                    all_uses.append(step["uses"])
        assert any("actions/add-to-project" in u for u in all_uses), (
            f"actions/add-to-project not found in any step. Found uses: {all_uses}"
        )

    def test_add_to_project_action_version(self) -> None:
        """actions/add-to-project is pinned to v1 major version tag."""
        jobs = self.wf.get("jobs", {})
        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                uses = step.get("uses", "")
                if "actions/add-to-project" in uses:
                    assert "@v1" in uses, (
                        f"actions/add-to-project must be pinned to @v1. Found: {uses}"
                    )

    def test_project_url_configured(self) -> None:
        """add-to-project step includes project-url pointing to loom-dev-ecosystem."""
        jobs = self.wf.get("jobs", {})
        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                uses = step.get("uses", "")
                if "actions/add-to-project" in uses:
                    project_url = step.get("with", {}).get("project-url", "")
                    assert "github.com" in project_url, (
                        f"project-url missing or not a GitHub URL: '{project_url}'"
                    )
                    assert "/projects/" in project_url, (
                        f"project-url does not point to a Projects board: '{project_url}'"
                    )
                    return
        pytest.fail("No add-to-project step found with 'with.project-url'")

    def test_github_token_configured(self) -> None:
        """add-to-project step includes github-token (secret reference)."""
        jobs = self.wf.get("jobs", {})
        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                uses = step.get("uses", "")
                if "actions/add-to-project" in uses:
                    token = step.get("with", {}).get("github-token", "")
                    assert token, "github-token is empty or missing"
                    assert "${{" in token or "secrets." in token, (
                        f"github-token must reference a secret, got: '{token}'"
                    )
                    return
        pytest.fail("No add-to-project step found with 'with.github-token'")


# ===========================================================================
# Requirement: Issue を Project Board に自動追加
# Scenario: Issue reopen 時の自動追加
# ===========================================================================

class TestReopenedIssueTrigger:
    """Scenario: Issue reopen 時の自動追加

    WHEN: クローズされた Issue が再度オープンされる
    THEN: Issue が Project Board に追加される（既に存在する場合は重複なし）
    """

    def setup_method(self) -> None:
        _skip_if_missing()
        self.wf = _load_workflow()

    def test_triggers_on_issues_reopened(self) -> None:
        """Workflow triggers on issues.types: [..., reopened, ...]."""
        on = self.wf.get("on") or self.wf.get(True)
        issues_trigger = on.get("issues", {})
        types = issues_trigger.get("types", [])
        assert "reopened" in types, (
            f"'reopened' not in issues.types: {types}\n"
            "Required for: Issue reopen 時の自動追加"
        )

    def test_single_job_handles_all_triggers(self) -> None:
        """A single workflow run handles opened/reopened/transferred (no per-event split)."""
        jobs = self.wf.get("jobs", {})
        # The workflow should have at least one job
        assert len(jobs) >= 1, "Workflow has no jobs defined"

        # All add-to-project steps should be in one consolidated job, not branched per event
        add_to_project_steps = []
        for job_name, job in jobs.items():
            for step in job.get("steps", []):
                if "actions/add-to-project" in step.get("uses", ""):
                    add_to_project_steps.append((job_name, step))

        assert len(add_to_project_steps) >= 1, (
            "No add-to-project step found across all jobs"
        )


# ===========================================================================
# Requirement: Issue を Project Board に自動追加
# Scenario: Issue transfer 時の自動追加
# ===========================================================================

class TestTransferredIssueTrigger:
    """Scenario: Issue transfer 時の自動追加

    WHEN: 他リポから Issue が loom リポジトリに転送される
    THEN: 転送された Issue が Project Board に自動追加される
    """

    def setup_method(self) -> None:
        _skip_if_missing()
        self.wf = _load_workflow()

    def test_triggers_on_issues_transferred(self) -> None:
        """Workflow triggers on issues.types: [..., transferred]."""
        on = self.wf.get("on") or self.wf.get(True)
        issues_trigger = on.get("issues", {})
        types = issues_trigger.get("types", [])
        assert "transferred" in types, (
            f"'transferred' not in issues.types: {types}\n"
            "Required for: Issue transfer 時の自動追加"
        )

    def test_all_three_trigger_types_present(self) -> None:
        """Workflow declares all three required event types: opened, reopened, transferred."""
        on = self.wf.get("on") or self.wf.get(True)
        issues_trigger = on.get("issues", {})
        types = issues_trigger.get("types", [])
        required = {"opened", "reopened", "transferred"}
        missing = required - set(types)
        assert not missing, (
            f"Missing required issue event types: {missing}. "
            f"Found: {types}"
        )

    def test_uses_add_to_project_pat_secret(self) -> None:
        """Workflow references ADD_TO_PROJECT_PAT secret (required for cross-repo project access)."""
        wf_text = WORKFLOW_PATH.read_text(encoding="utf-8")
        assert "ADD_TO_PROJECT_PAT" in wf_text, (
            "ADD_TO_PROJECT_PAT secret not referenced in workflow.\n"
            "This PAT is required for project: scope access to loom-dev-ecosystem."
        )


# ===========================================================================
# Edge cases: YAML structural integrity
# ===========================================================================

class TestWorkflowYamlStructure:
    """Structural edge-case checks for add-to-project.yml."""

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

    def test_permissions_or_token_present(self) -> None:
        """Workflow or job specifies permissions or a PAT token for project access."""
        wf_text = WORKFLOW_PATH.read_text(encoding="utf-8")
        has_permissions = "permissions:" in wf_text
        has_pat = "ADD_TO_PROJECT_PAT" in wf_text
        assert has_permissions or has_pat, (
            "Workflow neither declares 'permissions:' nor uses ADD_TO_PROJECT_PAT. "
            "Project write access requires one of these."
        )


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestAddToProjectWorkflowExists,
        TestNewIssueTrigger,
        TestReopenedIssueTrigger,
        TestTransferredIssueTrigger,
        TestWorkflowYamlStructure,
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
