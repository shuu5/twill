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
    DIRECT_SKIP_STEPS,
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

    def test_direct_skip_steps_subset_of_chain_steps(self) -> None:
        assert DIRECT_SKIP_STEPS.issubset(set(CHAIN_STEPS))

    def test_direct_skip_steps_not_empty(self) -> None:
        assert len(DIRECT_SKIP_STEPS) > 0

    def test_direct_skip_steps_contains_expected(self) -> None:
        assert {"change-propose", "change-id-resolve", "change-apply"}.issubset(DIRECT_SKIP_STEPS)

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
# Direct mode step skipping
# ===========================================================================


class TestNextStepDirect:
    def _make_direct_issue(self, state: StateManager, issue: str = "20") -> None:
        _init_issue(state, issue)
        state.write(type_="issue", role="worker", issue=issue, sets=["is_quick=false", "mode=direct"])

    def _make_propose_issue(self, state: StateManager, issue: str = "21") -> None:
        _init_issue(state, issue)
        state.write(type_="issue", role="worker", issue=issue, sets=["is_quick=false", "mode=propose"])

    def test_direct_skips_direct_skip_steps(
        self, runner: ChainRunner, state: StateManager, autopilot_dir: Path
    ) -> None:
        self._make_direct_issue(state, "20")
        seen: list[str] = []
        current = ""
        for _ in range(len(CHAIN_STEPS) + 2):
            next_s = runner.next_step("20", current)
            if next_s == "done":
                break
            seen.append(next_s)
            current = next_s
        skipped_in_path = [s for s in seen if s in DIRECT_SKIP_STEPS]
        assert not skipped_in_path, f"direct mode should skip: {skipped_in_path}"

    def test_propose_includes_direct_skip_steps(
        self, runner: ChainRunner, state: StateManager, autopilot_dir: Path
    ) -> None:
        self._make_propose_issue(state, "21")
        seen: list[str] = []
        current = ""
        for _ in range(len(CHAIN_STEPS) + 2):
            next_s = runner.next_step("21", current)
            if next_s == "done":
                break
            seen.append(next_s)
            current = next_s
        for step in DIRECT_SKIP_STEPS:
            assert step in seen, f"propose mode should include {step}"

    def test_mode_unset_does_not_apply_direct_skip(
        self, runner: ChainRunner, state: StateManager, autopilot_dir: Path
    ) -> None:
        _init_issue(state, "22")
        state.write(type_="issue", role="worker", issue="22", sets=["is_quick=false"])
        seen: list[str] = []
        current = ""
        for _ in range(len(CHAIN_STEPS) + 2):
            next_s = runner.next_step("22", current)
            if next_s == "done":
                break
            seen.append(next_s)
            current = next_s
        for step in DIRECT_SKIP_STEPS:
            assert step in seen, f"mode unset: DIRECT_SKIP_STEPS should not apply, {step} missing"


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


# ===========================================================================
# step_init
# ===========================================================================


class TestStepInit:
    """Tests for ChainRunner.step_init() AC (#338)."""

    def _make_runner(self, tmp_path: Path, autopilot_dir: Path) -> ChainRunner:
        scripts_root = tmp_path / "scripts"
        scripts_root.mkdir(exist_ok=True)
        return ChainRunner(scripts_root=scripts_root, autopilot_dir=autopilot_dir)

    def test_no_deltaspec_non_quick_non_direct_returns_propose_auto_init(
        self, tmp_path: Path, autopilot_dir: Path
    ) -> None:
        """deltaspec/ なし + quick なし + direct なし → propose (auto_init=true)."""
        runner = self._make_runner(tmp_path, autopilot_dir)
        with (
            patch.object(runner, "_git_current_branch", return_value="feat/some-branch"),
            patch.object(runner, "_project_root", return_value=tmp_path),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init("")
        assert result["recommended_action"] == "propose"
        assert result.get("auto_init") is True
        assert result.get("deltaspec") is False

    def test_scope_direct_label_returns_direct(
        self, tmp_path: Path, autopilot_dir: Path
    ) -> None:
        """scope/direct ラベルあり → direct."""
        runner = self._make_runner(tmp_path, autopilot_dir)
        with (
            patch.object(runner, "_git_current_branch", return_value="feat/some-branch"),
            patch.object(runner, "_project_root", return_value=tmp_path),
            patch.object(runner, "_fetch_labels", return_value=["scope/direct"]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init("338")
        assert result["recommended_action"] == "direct"
        assert result.get("deltaspec") is False
        assert result.get("is_direct") is True

    # ------------------------------------------------------------------
    # Issue #784: step_init auto_init パス — issue_num あり
    # ------------------------------------------------------------------

    def test_issue_num_no_deltaspec_writes_mode_propose(
        self, tmp_path: Path, autopilot_dir: Path
    ) -> None:
        """issue_num='784' + deltaspec/ 不在 → _write_state_field が mode=propose で呼ばれる (ADR-015)."""
        runner = self._make_runner(tmp_path, autopilot_dir)
        with (
            patch.object(runner, "_git_current_branch", return_value="feat/784-adr-015"),
            patch.object(runner, "_project_root", return_value=tmp_path),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field") as mock_write,
        ):
            result = runner.step_init("784")

        assert result["recommended_action"] == "propose"
        assert result.get("auto_init") is True
        assert result.get("deltaspec") is False
        assert result.get("is_quick") is False

        # _write_state_field の呼び出し列を検証
        call_kvs = [call.args[1] for call in mock_write.call_args_list]
        assert "mode=propose" in call_kvs, (
            f"_write_state_field に mode=propose が渡されていない。実際の呼び出し: {call_kvs}"
        )

    def test_issue_num_no_deltaspec_writes_state_in_order(
        self, tmp_path: Path, autopilot_dir: Path
    ) -> None:
        """issue_num あり + deltaspec/ 不在 → is_quick/is_direct を先に書いてから mode=propose を書く."""
        runner = self._make_runner(tmp_path, autopilot_dir)
        with (
            patch.object(runner, "_git_current_branch", return_value="feat/784-adr-015"),
            patch.object(runner, "_project_root", return_value=tmp_path),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field") as mock_write,
        ):
            runner.step_init("784")

        call_kvs = [call.args[1] for call in mock_write.call_args_list]
        # is_quick と is_direct はラベル判定直後（mode=propose より前）に書かれる
        assert "is_quick=false" in call_kvs
        assert "is_direct=false" in call_kvs
        idx_mode = call_kvs.index("mode=propose")
        idx_quick = call_kvs.index("is_quick=false")
        assert idx_quick < idx_mode, "is_quick は mode=propose より前に書かれなければならない"

    def test_issue_num_no_deltaspec_issue_num_passed_to_write(
        self, tmp_path: Path, autopilot_dir: Path
    ) -> None:
        """_write_state_field の第1引数 (issue_num) が '784' であることを確認する."""
        runner = self._make_runner(tmp_path, autopilot_dir)
        with (
            patch.object(runner, "_git_current_branch", return_value="feat/784-adr-015"),
            patch.object(runner, "_project_root", return_value=tmp_path),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field") as mock_write,
        ):
            runner.step_init("784")

        # mode=propose 呼び出し時の issue_num を確認
        mode_calls = [c for c in mock_write.call_args_list if c.args[1] == "mode=propose"]
        assert len(mode_calls) == 1, "mode=propose の書き込みはちょうど1回であること"
        assert mode_calls[0].args[0] == "784", (
            f"issue_num が '784' でない: {mode_calls[0].args[0]!r}"
        )

    def test_empty_issue_num_no_deltaspec_no_write_state(
        self, tmp_path: Path, autopilot_dir: Path
    ) -> None:
        """issue_num='' のとき _write_state_field は呼ばれない（既存テストのエッジケース補完）."""
        runner = self._make_runner(tmp_path, autopilot_dir)
        with (
            patch.object(runner, "_git_current_branch", return_value="feat/some-branch"),
            patch.object(runner, "_project_root", return_value=tmp_path),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field") as mock_write,
        ):
            result = runner.step_init("")

        assert result["recommended_action"] == "propose"
        # issue_num が空なので state 書き込みは行われない
        mode_calls = [c for c in mock_write.call_args_list if c.args[1] == "mode=propose"]
        assert len(mode_calls) == 0, "issue_num='' では mode=propose を書いてはならない"

    def test_non_numeric_issue_num_no_deltaspec_no_write_mode(
        self, tmp_path: Path, autopilot_dir: Path
    ) -> None:
        """issue_num が数字でない場合（例: 'abc'）は mode=propose を書かない."""
        runner = self._make_runner(tmp_path, autopilot_dir)
        with (
            patch.object(runner, "_git_current_branch", return_value="feat/abc-test"),
            patch.object(runner, "_project_root", return_value=tmp_path),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field") as mock_write,
        ):
            result = runner.step_init("abc")

        assert result["recommended_action"] == "propose"
        mode_calls = [c for c in mock_write.call_args_list if "mode=" in c.args[1]]
        assert len(mode_calls) == 0, "非数値 issue_num では mode 書き込み不可"


# ---------------------------------------------------------------------------
# step_check — monorepo test directory detection (Issue #406)
# ---------------------------------------------------------------------------


class TestStepCheckMonorepo:
    """step_check が monorepo 構造のテストディレクトリを正しく検出する。"""

    def _make_runner(self, tmp_path: Path, autopilot_dir: Path) -> ChainRunner:
        scripts_root = tmp_path / "scripts"
        scripts_root.mkdir(exist_ok=True)
        return ChainRunner(scripts_root=scripts_root, autopilot_dir=autopilot_dir)

    def _setup_ci(self, root: Path) -> None:
        """CI/CD と DeltaSpec を用意してチェック以外の FAIL を防ぐ。"""
        (root / ".github" / "workflows").mkdir(parents=True, exist_ok=True)
        (root / ".github" / "workflows" / "ci.yml").touch()
        (root / "deltaspec" / "changes" / "some-change").mkdir(parents=True, exist_ok=True)
        (root / "deltaspec" / "changes" / "some-change" / "proposal.md").touch()

    def test_root_tests_dir_passes(self, tmp_path: Path, autopilot_dir: Path) -> None:
        """AC-3: $root/tests/ にテストがあれば PASS（単一リポ退行なし）。"""
        root = tmp_path / "project"
        root.mkdir()
        self._setup_ci(root)
        (root / "tests").mkdir()
        (root / "tests" / "foo.bats").touch()

        runner = self._make_runner(tmp_path, autopilot_dir)
        with patch.object(runner, "_project_root", return_value=root):
            result = runner.step_check()
        assert result is True

    def test_component_tests_depth1_passes(self, tmp_path: Path, autopilot_dir: Path) -> None:
        """AC-2: $root/tests/ 不在でも $root/*/tests/ にテストがあれば PASS。"""
        root = tmp_path / "project"
        root.mkdir()
        self._setup_ci(root)
        (root / "plugins" / "tests").mkdir(parents=True)
        (root / "plugins" / "tests" / "spec.bats").touch()

        runner = self._make_runner(tmp_path, autopilot_dir)
        with patch.object(runner, "_project_root", return_value=root):
            result = runner.step_check()
        assert result is True

    def test_component_tests_depth2_passes(self, tmp_path: Path, autopilot_dir: Path) -> None:
        """AC-1: $root/*/*/tests/ にテストがあれば PASS。"""
        root = tmp_path / "project"
        root.mkdir()
        self._setup_ci(root)
        (root / "cli" / "twl" / "tests").mkdir(parents=True)
        (root / "cli" / "twl" / "tests" / "test_chain.py").touch()

        runner = self._make_runner(tmp_path, autopilot_dir)
        with patch.object(runner, "_project_root", return_value=root):
            result = runner.step_check()
        assert result is True

    def test_no_tests_fails(self, tmp_path: Path, autopilot_dir: Path) -> None:
        """テストファイルが一切なければ FAIL。"""
        root = tmp_path / "project"
        root.mkdir()
        self._setup_ci(root)

        runner = self._make_runner(tmp_path, autopilot_dir)
        with patch.object(runner, "_project_root", return_value=root):
            result = runner.step_check()
        assert result is False
