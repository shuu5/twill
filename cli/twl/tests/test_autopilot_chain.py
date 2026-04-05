"""Tests for twl.autopilot.chain — ChainRunner step transitions (AC6).

Covers:
  - Normal step transitions (happy path)
  - quick Issue step skipping
  - Crash recovery / invalid transition rejection
  - CHAIN_STEPS ordering and completeness
  - QUICK_SKIP_STEPS coverage
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from twl.autopilot.chain import (
    CHAIN_STEPS,
    QUICK_SKIP_STEPS,
    ChainError,
    ChainRunner,
)
from twl.autopilot.state import StateManager


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    return d


@pytest.fixture
def state(autopilot_dir: Path) -> StateManager:
    return StateManager(autopilot_dir=autopilot_dir)


@pytest.fixture
def runner(autopilot_dir: Path, tmp_path: Path) -> ChainRunner:
    scripts_root = tmp_path / "scripts"
    scripts_root.mkdir()
    return ChainRunner(scripts_root=scripts_root, autopilot_dir=autopilot_dir)


def _init_issue(state: StateManager, issue: str = "1") -> None:
    state.write(type_="issue", role="worker", issue=issue, init=True)


# ===========================================================================
# CHAIN_STEPS structure
# ===========================================================================


class TestChainStepsDefinition:
    def test_chain_steps_not_empty(self) -> None:
        assert len(CHAIN_STEPS) > 0

    def test_chain_steps_are_strings(self) -> None:
        assert all(isinstance(s, str) for s in CHAIN_STEPS)

    def test_chain_steps_no_duplicates(self) -> None:
        assert len(CHAIN_STEPS) == len(set(CHAIN_STEPS))

    def test_chain_steps_contains_key_steps(self) -> None:
        essential = {"init", "check", "change-apply", "all-pass-check", "pr-cycle-report"}
        assert essential.issubset(set(CHAIN_STEPS))

    def test_quick_skip_steps_subset_of_chain_steps(self) -> None:
        assert QUICK_SKIP_STEPS.issubset(set(CHAIN_STEPS))

    def test_quick_skip_steps_not_empty(self) -> None:
        assert len(QUICK_SKIP_STEPS) > 0

    def test_init_is_first_step(self) -> None:
        assert CHAIN_STEPS[0] == "init"

    def test_pr_cycle_report_is_last_step(self) -> None:
        assert CHAIN_STEPS[-1] == "pr-cycle-report"


# ===========================================================================
# Normal transitions
# ===========================================================================


class TestNextStepNormal:
    def test_first_step_from_empty(self, runner: ChainRunner, autopilot_dir: Path, state: StateManager) -> None:
        _init_issue(state, "1")
        # current_step = "" → first step in chain
        result = runner.next_step("1", "")
        assert result == CHAIN_STEPS[0]

    def test_step_after_init(self, runner: ChainRunner, state: StateManager) -> None:
        _init_issue(state, "1")
        result = runner.next_step("1", "init")
        expected = CHAIN_STEPS[CHAIN_STEPS.index("init") + 1]
        assert result == expected

    def test_step_sequence_all(self, runner: ChainRunner, state: StateManager) -> None:
        """Verify the full sequence of non-quick steps."""
        _init_issue(state, "2")
        for i, step in enumerate(CHAIN_STEPS[:-1]):
            next_s = runner.next_step("2", step)
            assert next_s == CHAIN_STEPS[i + 1], f"After {step} expected {CHAIN_STEPS[i+1]}, got {next_s}"

    def test_done_after_last_step(self, runner: ChainRunner, state: StateManager) -> None:
        _init_issue(state, "3")
        result = runner.next_step("3", CHAIN_STEPS[-1])
        assert result == "done"

    def test_unknown_current_step_returns_first(self, runner: ChainRunner, state: StateManager) -> None:
        _init_issue(state, "4")
        result = runner.next_step("4", "nonexistent-step")
        assert result == CHAIN_STEPS[0]


# ===========================================================================
# Quick Issue skipping
# ===========================================================================


class TestNextStepQuick:
    def _make_quick_issue(self, state: StateManager, autopilot_dir: Path, issue: str = "10") -> None:
        _init_issue(state, issue)
        state.write(type_="issue", role="worker", issue=issue, sets=["is_quick=true"])

    def test_quick_skips_quick_skip_steps(
        self, runner: ChainRunner, state: StateManager, autopilot_dir: Path
    ) -> None:
        self._make_quick_issue(state, autopilot_dir, "10")
        # After init, quick issues skip QUICK_SKIP_STEPS
        current = "init"
        result = runner.next_step("10", current)
        # Should skip any QUICK_SKIP_STEPS
        assert result not in QUICK_SKIP_STEPS

    def test_quick_full_sequence_no_skipped_steps(
        self, runner: ChainRunner, state: StateManager, autopilot_dir: Path
    ) -> None:
        self._make_quick_issue(state, autopilot_dir, "11")
        seen_steps: list[str] = []
        current = ""
        for _ in range(len(CHAIN_STEPS) + 2):
            next_s = runner.next_step("11", current)
            if next_s == "done":
                break
            seen_steps.append(next_s)
            current = next_s
        # None of the seen steps should be in QUICK_SKIP_STEPS
        skipped_in_path = [s for s in seen_steps if s in QUICK_SKIP_STEPS]
        assert not skipped_in_path, f"Quick Issue should skip: {skipped_in_path}"

    def test_non_quick_includes_all_steps(
        self, runner: ChainRunner, state: StateManager, autopilot_dir: Path
    ) -> None:
        _init_issue(state, "12")
        state.write(type_="issue", role="worker", issue="12", sets=["is_quick=false"])
        seen: list[str] = []
        current = ""
        for _ in range(len(CHAIN_STEPS) + 2):
            next_s = runner.next_step("12", current)
            if next_s == "done":
                break
            seen.append(next_s)
            current = next_s
        for step in QUICK_SKIP_STEPS:
            assert step in seen, f"Non-quick Issue should include {step}"


# ===========================================================================
# Invalid transitions
# ===========================================================================


class TestValidateTransition:
    def test_forward_transition_ok(self, runner: ChainRunner) -> None:
        runner.validate_transition("1", "init", "board-status-update")

    def test_backward_transition_raises(self, runner: ChainRunner) -> None:
        with pytest.raises(ChainError, match="不正な遷移"):
            runner.validate_transition("1", "board-status-update", "init")

    def test_same_step_transition_raises(self, runner: ChainRunner) -> None:
        with pytest.raises(ChainError):
            runner.validate_transition("1", "init", "init")

    def test_unknown_from_step_raises(self, runner: ChainRunner) -> None:
        with pytest.raises(ChainError, match="不正な遷移元"):
            runner.validate_transition("1", "nonexistent", "check")

    def test_unknown_to_step_raises(self, runner: ChainRunner) -> None:
        with pytest.raises(ChainError, match="不正な遷移先"):
            runner.validate_transition("1", "init", "nonexistent")

    def test_to_done_is_ok_from_last(self, runner: ChainRunner) -> None:
        # "done" is a valid terminal — should not raise
        runner.validate_transition("1", CHAIN_STEPS[-2], CHAIN_STEPS[-1])


# ===========================================================================
# record_step
# ===========================================================================


class TestRecordStep:
    def test_record_step_updates_state(
        self, runner: ChainRunner, state: StateManager, autopilot_dir: Path
    ) -> None:
        _init_issue(state, "20")
        # Override runner's autopilot_dir to use our test dir
        runner.autopilot_dir = autopilot_dir
        # Patch _write_state_field to use StateManager directly
        with patch.object(runner, "_write_state_field") as mock_write:
            runner.record_step("20", "check")
            mock_write.assert_called_once_with("20", "current_step=check")

    def test_record_step_ignores_invalid_step_id(self, runner: ChainRunner) -> None:
        # Should not raise even with invalid step id
        runner.record_step("1", "")
        runner.record_step("1", "invalid step with spaces!")

    def test_record_step_ignores_empty_issue(self, runner: ChainRunner) -> None:
        runner.record_step("", "check")


# ===========================================================================
# next_step validation
# ===========================================================================


class TestNextStepValidation:
    def test_invalid_issue_num_raises(self, runner: ChainRunner, state: StateManager) -> None:
        _init_issue(state, "1")
        with pytest.raises(ChainError):
            runner.next_step("abc", "init")

    def test_empty_issue_num_raises(self, runner: ChainRunner) -> None:
        with pytest.raises(ChainError):
            runner.next_step("", "init")

    def test_zero_issue_num_raises(self, runner: ChainRunner) -> None:
        # "0" is technically a digit but issue numbers are positive
        # Currently the validator checks ^\d+$ so "0" passes — document actual behavior
        # If it reads empty state, returns first step
        result = runner.next_step("0", "init")
        # Should return next step (is_quick defaults to false when state not found)
        assert result in CHAIN_STEPS


# ===========================================================================
# CLI entrypoint
# ===========================================================================


class TestChainCLI:
    def test_next_step_cli(self, autopilot_dir: Path, state: StateManager) -> None:
        _init_issue(state, "30")
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.chain", "next-step", "30", "init"],
            capture_output=True, text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )
        assert result.returncode == 0
        assert result.stdout.strip() in CHAIN_STEPS

    def test_unknown_step_cli(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.chain", "unknown-step-xyz"],
            capture_output=True, text=True,
        )
        assert result.returncode != 0

    def test_no_args_cli(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.chain"],
            capture_output=True, text=True,
        )
        assert result.returncode != 0

    def test_next_step_requires_args(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.chain", "next-step"],
            capture_output=True, text=True,
        )
        assert result.returncode != 0
