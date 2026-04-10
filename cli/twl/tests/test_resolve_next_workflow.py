"""Tests for ChainRunner.resolve_next_workflow() — AC for Issue #337.

All autopilot-related tests assume autopilot=True unless stated otherwise.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

from twl.autopilot.chain import ChainRunner


# ---------------------------------------------------------------------------
# Minimal flow fixture matching plugins/twl/deps.yaml worker-lifecycle
# ---------------------------------------------------------------------------

WORKER_LIFECYCLE_FLOW: list[dict] = [
    {
        "id": "setup",
        "chain": "setup",
        "next": [
            {"condition": "quick && autopilot", "goto": "quick-path"},
            {"condition": "!quick && autopilot", "goto": "test-ready"},
            {"condition": "!autopilot", "stop": True,
             "message": "setup chain 完了。次: /twl:workflow-test-ready"},
        ],
    },
    {
        "id": "quick-path",
        "chain": None,
        "description": "quick Issue の短縮パス",
        "inline_steps": ["直接実装 → commit → push", "PR 作成", "ac-verify", "merge-gate"],
        "next": [{"goto": "done"}],
    },
    {
        "id": "test-ready",
        "chain": "test-ready",
        "skill": "workflow-test-ready",
        "next": [
            {"condition": "autopilot", "goto": "pr-verify"},
            {"condition": "!autopilot", "stop": True,
             "message": "完了。次: /twl:workflow-pr-verify"},
        ],
    },
    {
        "id": "pr-verify",
        "chain": "pr-verify",
        "skill": "workflow-pr-verify",
        "next": [
            {"condition": "autopilot", "goto": "pr-fix"},
            {"condition": "!autopilot", "stop": True,
             "message": "workflow-pr-verify 完了。"},
        ],
    },
    {
        "id": "pr-fix",
        "chain": "pr-fix",
        "skill": "workflow-pr-fix",
        "next": [
            {"condition": "autopilot", "goto": "pr-merge"},
            {"condition": "!autopilot", "stop": True,
             "message": "workflow-pr-fix 完了。"},
        ],
    },
    {
        "id": "pr-merge",
        "chain": "pr-merge",
        "skill": "workflow-pr-merge",
        "terminal": True,
    },
    {
        "id": "done",
        "terminal": True,
    },
]


@pytest.fixture
def runner(tmp_path: Path) -> ChainRunner:
    scripts_root = tmp_path / "scripts"
    scripts_root.mkdir()
    autopilot_dir = tmp_path / ".autopilot"
    autopilot_dir.mkdir()
    r = ChainRunner(scripts_root=scripts_root, autopilot_dir=autopilot_dir)
    return r


@pytest.fixture
def patched_runner(runner: ChainRunner):
    """Runner with _load_worker_lifecycle_flow patched to use test fixture."""
    with patch.object(runner, "_load_worker_lifecycle_flow", return_value=WORKER_LIFECYCLE_FLOW):
        yield runner


# ===========================================================================
# AC: setup → "workflow-test-ready" (autopilot=True, quick=False)
# ===========================================================================

class TestSetupTransitions:
    def test_setup_autopilot_true_quick_false(self, patched_runner: ChainRunner) -> None:
        result = patched_runner.resolve_next_workflow("setup", is_autopilot=True, is_quick=False)
        assert result == "workflow-test-ready"

    def test_setup_autopilot_true_quick_true(self, patched_runner: ChainRunner) -> None:
        # AC: setup + quick=true + autopilot=true → "quick-path"
        result = patched_runner.resolve_next_workflow("setup", is_autopilot=True, is_quick=True)
        assert result == "quick-path"

    def test_setup_autopilot_false(self, patched_runner: ChainRunner) -> None:
        # AC: setup + autopilot=false → "" (stop 条件)
        result = patched_runner.resolve_next_workflow("setup", is_autopilot=False, is_quick=False)
        assert result == ""


# ===========================================================================
# AC: pr-verify → "workflow-pr-fix"
# ===========================================================================

class TestPrVerifyTransition:
    def test_pr_verify_autopilot_true(self, patched_runner: ChainRunner) -> None:
        result = patched_runner.resolve_next_workflow("pr-verify", is_autopilot=True, is_quick=False)
        assert result == "workflow-pr-fix"

    def test_pr_verify_autopilot_false(self, patched_runner: ChainRunner) -> None:
        result = patched_runner.resolve_next_workflow("pr-verify", is_autopilot=False, is_quick=False)
        assert result == ""


# ===========================================================================
# AC: pr-fix → "workflow-pr-merge"
# ===========================================================================

class TestPrFixTransition:
    def test_pr_fix_autopilot_true(self, patched_runner: ChainRunner) -> None:
        result = patched_runner.resolve_next_workflow("pr-fix", is_autopilot=True, is_quick=False)
        assert result == "workflow-pr-merge"

    def test_pr_fix_autopilot_false(self, patched_runner: ChainRunner) -> None:
        result = patched_runner.resolve_next_workflow("pr-fix", is_autopilot=False, is_quick=False)
        assert result == ""


# ===========================================================================
# AC: pr-merge → "" (terminal node)
# ===========================================================================

class TestPrMergeTransition:
    def test_pr_merge_returns_empty(self, patched_runner: ChainRunner) -> None:
        result = patched_runner.resolve_next_workflow("pr-merge", is_autopilot=True, is_quick=False)
        assert result == ""

    def test_pr_merge_any_flags_returns_empty(self, patched_runner: ChainRunner) -> None:
        for autopilot in (True, False):
            for quick in (True, False):
                result = patched_runner.resolve_next_workflow("pr-merge", autopilot, quick)
                assert result == "", f"pr-merge should return '' (autopilot={autopilot}, quick={quick})"


# ===========================================================================
# Edge cases
# ===========================================================================

class TestEdgeCases:
    def test_unknown_workflow_returns_empty(self, patched_runner: ChainRunner) -> None:
        result = patched_runner.resolve_next_workflow("nonexistent", is_autopilot=True, is_quick=False)
        assert result == ""

    def test_done_node_returns_empty(self, patched_runner: ChainRunner) -> None:
        result = patched_runner.resolve_next_workflow("done", is_autopilot=True, is_quick=False)
        assert result == ""

    def test_return_type_is_str(self, patched_runner: ChainRunner) -> None:
        for workflow in ("setup", "pr-verify", "pr-fix", "pr-merge", "done", "nonexistent"):
            result = patched_runner.resolve_next_workflow(workflow, is_autopilot=True, is_quick=False)
            assert isinstance(result, str), f"Expected str for {workflow}, got {type(result)}"


# ===========================================================================
# _eval_workflow_condition unit tests
# ===========================================================================

class TestEvalWorkflowCondition:
    def test_empty_condition_always_true(self, runner: ChainRunner) -> None:
        assert runner._eval_workflow_condition("", True, True) is True
        assert runner._eval_workflow_condition("", False, False) is True

    def test_autopilot_true(self, runner: ChainRunner) -> None:
        assert runner._eval_workflow_condition("autopilot", True, False) is True
        assert runner._eval_workflow_condition("autopilot", False, False) is False

    def test_not_autopilot(self, runner: ChainRunner) -> None:
        assert runner._eval_workflow_condition("!autopilot", False, False) is True
        assert runner._eval_workflow_condition("!autopilot", True, False) is False

    def test_quick_flag(self, runner: ChainRunner) -> None:
        assert runner._eval_workflow_condition("quick", True, True) is True
        assert runner._eval_workflow_condition("quick", True, False) is False

    def test_not_quick(self, runner: ChainRunner) -> None:
        assert runner._eval_workflow_condition("!quick", True, False) is True
        assert runner._eval_workflow_condition("!quick", True, True) is False

    def test_compound_quick_and_autopilot(self, runner: ChainRunner) -> None:
        assert runner._eval_workflow_condition("quick && autopilot", True, True) is True
        assert runner._eval_workflow_condition("quick && autopilot", True, False) is False
        assert runner._eval_workflow_condition("quick && autopilot", False, True) is False

    def test_compound_not_quick_and_autopilot(self, runner: ChainRunner) -> None:
        assert runner._eval_workflow_condition("!quick && autopilot", True, False) is True
        assert runner._eval_workflow_condition("!quick && autopilot", True, True) is False
        assert runner._eval_workflow_condition("!quick && autopilot", False, False) is False

    def test_unknown_token_returns_false(self, runner: ChainRunner) -> None:
        assert runner._eval_workflow_condition("unknown", True, True) is False


# ===========================================================================
# CLI: python3 -m twl.autopilot.chain resolve-next-workflow <workflow-id>
# ===========================================================================

class TestResolveNextWorkflowCLI:
    def test_missing_workflow_id_returns_error(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.chain", "resolve-next-workflow"],
            capture_output=True, text=True,
        )
        assert result.returncode != 0

    def test_no_args_returns_error(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.chain"],
            capture_output=True, text=True,
        )
        assert result.returncode != 0

    def test_unknown_workflow_outputs_empty_string(self) -> None:
        """Unknown workflow ID exits 0 and prints empty string to stdout."""
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.chain", "resolve-next-workflow", "nonexistent-workflow"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0
        assert result.stdout.strip() == ""
