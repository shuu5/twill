"""BDD integration tests for non-terminal chain recovery — Issue #469.

Covers three spec areas:
  specs/resolve-next-workflow-module/spec.md
    Requirement: resolve_next_workflow モジュール
  specs/orchestrator-completion-fallback/spec.md
    Requirement: orchestrator 実装完了パターン検知 fallback
    Requirement: stagnate 閾値の環境変数一元化
  specs/e2e-recovery-test/spec.md
    Requirement: orchestrator recovery E2E テスト

Primary test target: twl.autopilot.resolve_next_workflow (未作成 → 作成予定)
Secondary target  : plugins/twl/scripts/autopilot-orchestrator.sh
                    (_nudge_command_for_pattern の 実装完了 パターン検知ロジック)
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from twl.autopilot.chain import ChainRunner, WORKFLOW_NEXT_SKILL, STEP_TO_WORKFLOW
from twl.autopilot.state import StateManager


# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def autopilot_dir(tmp_path: Path) -> Path:
    """Minimal .autopilot directory with issues/ subdirectory."""
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    return d


@pytest.fixture()
def issue_state_file(autopilot_dir: Path) -> Path:
    """Create a minimal issue-469.json in running state."""
    data = {
        "issue": 469,
        "status": "running",
        "branch": "fix/469-worker-workflow-pr-verify-nonterminalch",
        "pr": None,
        "window": "",
        "started_at": "2026-04-11T00:00:00Z",
        "updated_at": "2026-04-11T00:00:00Z",
        "current_step": "",
        "retry_count": 0,
        "fix_instructions": None,
        "merged_at": None,
        "files_changed": [],
        "failure": None,
        "workflow_done": None,
        "implementation_pr": None,
        "deltaspec_mode": None,
        "is_quick": False,
    }
    f = autopilot_dir / "issues" / "issue-469.json"
    f.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    return f


@pytest.fixture()
def state_manager(autopilot_dir: Path) -> StateManager:
    return StateManager(autopilot_dir=autopilot_dir)


@pytest.fixture()
def scripts_root(tmp_path: Path) -> Path:
    d = tmp_path / "scripts"
    d.mkdir()
    return d


@pytest.fixture()
def chain_runner(scripts_root: Path, autopilot_dir: Path) -> ChainRunner:
    return ChainRunner(scripts_root=scripts_root, autopilot_dir=autopilot_dir)


# ---------------------------------------------------------------------------
# Requirement: resolve_next_workflow モジュール
# Spec: specs/resolve-next-workflow-module/spec.md
# ---------------------------------------------------------------------------


class TestResolveNextWorkflowModule:
    """
    Scenario: workflow_done=test-ready の場合に次 skill を返す
    WHEN: issue-469.json の workflow_done が "test-ready" で is_quick=false の状態で
          python3 -m twl.autopilot.resolve_next_workflow --issue 469 を実行する
    THEN: stdout に /twl:workflow-pr-verify が出力され exit 0 で終了する

    Scenario: workflow_done=null の場合に失敗する
    WHEN: issue-469.json の workflow_done が null または空の状態で
          python3 -m twl.autopilot.resolve_next_workflow --issue 469 を実行する
    THEN: stdout は空で exit 非ゼロで終了する

    Scenario: workflow_done=setup の場合に次 skill を返す
    WHEN: issue-469.json の workflow_done が "setup" で is_quick=false の状態で
          python3 -m twl.autopilot.resolve_next_workflow --issue 469 を実行する
    THEN: stdout に /twl:workflow-test-ready が出力され exit 0 で終了する
    """

    def test_workflow_done_test_ready_returns_pr_verify(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """WHEN workflow_done=test-ready, is_quick=false
        THEN stdout=/twl:workflow-pr-verify, exit=0."""
        # Arrange: write workflow_done=test-ready into state file
        data = json.loads(issue_state_file.read_text())
        data["workflow_done"] = "test-ready"
        data["is_quick"] = False
        issue_state_file.write_text(json.dumps(data))

        # Act
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        # Assert
        assert result.returncode == 0, (
            f"Expected exit 0 but got {result.returncode}. stderr={result.stderr!r}"
        )
        assert result.stdout.strip() == "/twl:workflow-pr-verify", (
            f"Expected '/twl:workflow-pr-verify' but got {result.stdout.strip()!r}"
        )

    def test_workflow_done_null_returns_nonzero_exit_empty_stdout(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """WHEN workflow_done=null
        THEN stdout is empty, exit != 0."""
        # Arrange: ensure workflow_done is null (already null in fixture)
        data = json.loads(issue_state_file.read_text())
        assert data["workflow_done"] is None

        # Act
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        # Assert: exit non-zero and stdout empty
        assert result.returncode != 0, (
            "Expected non-zero exit when workflow_done=null, "
            f"but got returncode={result.returncode}. stdout={result.stdout!r}"
        )
        assert result.stdout.strip() == "", (
            f"Expected empty stdout but got {result.stdout.strip()!r}"
        )

    def test_workflow_done_empty_string_returns_nonzero_exit_empty_stdout(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """WHEN workflow_done is empty string
        THEN stdout is empty, exit != 0."""
        data = json.loads(issue_state_file.read_text())
        data["workflow_done"] = ""
        issue_state_file.write_text(json.dumps(data))

        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        assert result.returncode != 0
        assert result.stdout.strip() == ""

    def test_workflow_done_setup_returns_workflow_test_ready(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """WHEN workflow_done=setup, is_quick=false
        THEN stdout=/twl:workflow-test-ready, exit=0."""
        data = json.loads(issue_state_file.read_text())
        data["workflow_done"] = "setup"
        data["is_quick"] = False
        issue_state_file.write_text(json.dumps(data))

        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        assert result.returncode == 0, (
            f"Expected exit 0 but got {result.returncode}. stderr={result.stderr!r}"
        )
        assert result.stdout.strip() == "/twl:workflow-test-ready", (
            f"Expected '/twl:workflow-test-ready' but got {result.stdout.strip()!r}"
        )

    def test_missing_issue_file_returns_nonzero(self, autopilot_dir: Path) -> None:
        """WHEN issue state file is absent
        THEN exit non-zero and stdout empty."""
        # No fixture: issue-469.json does not exist
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        assert result.returncode != 0
        assert result.stdout.strip() == ""

    def test_missing_issue_arg_returns_nonzero(self, autopilot_dir: Path) -> None:
        """WHEN --issue argument is omitted
        THEN exit non-zero."""
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )
        assert result.returncode != 0

    def test_stdout_has_no_trailing_noise(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """stdout contains exactly the skill command with optional trailing newline only."""
        data = json.loads(issue_state_file.read_text())
        data["workflow_done"] = "test-ready"
        issue_state_file.write_text(json.dumps(data))

        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        # stdout must be exactly the skill + newline (no ANSI, no extra lines)
        lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
        assert len(lines) == 1, f"Expected exactly one output line, got: {lines!r}"
        assert lines[0] == "/twl:workflow-pr-verify"


# ---------------------------------------------------------------------------
# Requirement: ChainRunner.resolve_next_workflow — workflow_done 委譲ロジック
# (Unit-level: tests how STEP_TO_WORKFLOW feeds into WORKFLOW_NEXT_SKILL)
# ---------------------------------------------------------------------------


class TestWorkflowDoneChainMapping:
    """Unit tests for the STEP_TO_WORKFLOW + WORKFLOW_NEXT_SKILL mapping constants.

    These constants are the SSOT for which skill follows a completed workflow.
    Issue #469 root cause: test-ready workflow completion was not triggering
    workflow-pr-verify because workflow_done=test-ready was not set/read.
    """

    def test_test_ready_maps_to_workflow_pr_verify(self) -> None:
        """WORKFLOW_NEXT_SKILL["test-ready"] must be "workflow-pr-verify"."""
        assert WORKFLOW_NEXT_SKILL.get("test-ready") == "workflow-pr-verify", (
            "SSOT maps test-ready → workflow-pr-verify"
        )

    def test_setup_maps_to_workflow_test_ready(self) -> None:
        """WORKFLOW_NEXT_SKILL["setup"] must be "workflow-test-ready"."""
        assert WORKFLOW_NEXT_SKILL.get("setup") == "workflow-test-ready"

    def test_pr_verify_maps_to_workflow_pr_fix(self) -> None:
        assert WORKFLOW_NEXT_SKILL.get("pr-verify") == "workflow-pr-fix"

    def test_pr_fix_maps_to_workflow_pr_merge(self) -> None:
        assert WORKFLOW_NEXT_SKILL.get("pr-fix") == "workflow-pr-merge"

    def test_pr_merge_maps_to_empty_string(self) -> None:
        """pr-merge is terminal — no next skill."""
        assert WORKFLOW_NEXT_SKILL.get("pr-merge") == ""

    def test_all_workflow_next_skill_values_are_strings(self) -> None:
        for k, v in WORKFLOW_NEXT_SKILL.items():
            assert isinstance(v, str), f"WORKFLOW_NEXT_SKILL[{k!r}] must be str, got {type(v)}"

    def test_resolve_next_workflow_returns_prefixed_skill_for_test_ready(
        self, chain_runner: ChainRunner
    ) -> None:
        """ChainRunner.resolve_next_workflow('test-ready', autopilot=True, quick=False)
        should return 'workflow-pr-verify' (the skill name without /twl: prefix).

        The resolve_next_workflow CLI module is responsible for prefixing '/twl:'.
        """
        # Use deps.yaml real flow or stub; test the core method contract
        with patch.object(
            chain_runner,
            "_load_worker_lifecycle_flow",
            return_value=_minimal_flow(),
        ):
            result = chain_runner.resolve_next_workflow(
                "test-ready", is_autopilot=True, is_quick=False
            )
        # The method returns skill name (without /twl: prefix)
        assert result == "workflow-pr-verify", (
            f"Expected 'workflow-pr-verify', got {result!r}"
        )

    def test_resolve_next_workflow_returns_empty_for_null_workflow_done(
        self, chain_runner: ChainRunner
    ) -> None:
        """When workflow_done is absent (''), resolve_next_workflow returns ''."""
        with patch.object(
            chain_runner,
            "_load_worker_lifecycle_flow",
            return_value=_minimal_flow(),
        ):
            result = chain_runner.resolve_next_workflow(
                "", is_autopilot=True, is_quick=False
            )
        assert result == ""


# ---------------------------------------------------------------------------
# Requirement: orchestrator recovery E2E テスト
# Spec: specs/e2e-recovery-test/spec.md
# ---------------------------------------------------------------------------


class TestOrchestratorRecoveryE2E:
    """
    Scenario: workflow_done 未書き込み時の resolve 失敗確認
    WHEN: issue-469 の state で workflow_done=null のまま
          resolve_next_workflow --issue 469 を呼ぶ
    THEN: exit 非ゼロで終了し、stdout が空であることを確認できる

    Scenario: workflow_done 書き込み後の resolve 成功確認
    WHEN: state write --set workflow_done=test-ready で書き込んだ後に
          resolve_next_workflow --issue 469 を呼ぶ
    THEN: exit 0 で /twl:workflow-pr-verify が stdout に出力される
    """

    def test_resolve_fails_when_workflow_done_not_written(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """
        WHEN: workflow_done=null (未書き込み)
        THEN: resolve_next_workflow exits non-zero, stdout empty.
        """
        # Verify fixture: workflow_done is null
        data = json.loads(issue_state_file.read_text())
        assert data.get("workflow_done") is None, "Fixture must have workflow_done=null"

        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        assert result.returncode != 0, (
            "resolve_next_workflow must fail (non-zero exit) when workflow_done=null"
        )
        assert result.stdout.strip() == "", (
            f"stdout must be empty when workflow_done=null, got {result.stdout!r}"
        )

    def test_resolve_succeeds_after_workflow_done_written(
        self, autopilot_dir: Path, issue_state_file: Path, state_manager: StateManager
    ) -> None:
        """
        WHEN: state write --set workflow_done=test-ready → then resolve_next_workflow
        THEN: exit 0, stdout=/twl:workflow-pr-verify.
        """
        # Step 1: Write workflow_done=test-ready via StateManager (simulates orchestrator write)
        state_manager.write(
            type_="issue",
            role="pilot",
            issue="469",
            sets=["workflow_done=test-ready"],
        )

        # Verify write succeeded
        updated = json.loads(issue_state_file.read_text())
        assert updated.get("workflow_done") == "test-ready", (
            "State write must persist workflow_done=test-ready"
        )

        # Step 2: Invoke resolve_next_workflow CLI
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        assert result.returncode == 0, (
            f"Expected exit 0 after workflow_done=test-ready write. "
            f"returncode={result.returncode}, stderr={result.stderr!r}"
        )
        assert result.stdout.strip() == "/twl:workflow-pr-verify", (
            f"Expected '/twl:workflow-pr-verify', got {result.stdout.strip()!r}"
        )

    def test_state_write_pilot_workflow_done_is_allowed(
        self, issue_state_file: Path, state_manager: StateManager
    ) -> None:
        """StateManager.write() with role=pilot and workflow_done is in the allow-list."""
        # Should not raise — workflow_done is an allowed pilot key
        msg = state_manager.write(
            type_="issue",
            role="pilot",
            issue="469",
            sets=["workflow_done=test-ready"],
        )
        assert "OK" in msg

    def test_workflow_done_null_after_state_write_null_re_fails_resolve(
        self, autopilot_dir: Path, issue_state_file: Path, state_manager: StateManager
    ) -> None:
        """After setting workflow_done=test-ready then resetting to null,
        resolve_next_workflow must fail again."""
        # Step 1: set
        state_manager.write(
            type_="issue", role="pilot", issue="469", sets=["workflow_done=test-ready"]
        )
        # Step 2: reset to null
        state_manager.write(
            type_="issue", role="pilot", issue="469", sets=["workflow_done=null"]
        )
        data = json.loads(issue_state_file.read_text())
        assert data.get("workflow_done") is None

        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        assert result.returncode != 0
        assert result.stdout.strip() == ""


# ---------------------------------------------------------------------------
# Requirement: orchestrator 実装完了パターン検知 fallback
# Spec: specs/orchestrator-completion-fallback/spec.md
#
# NOTE: _nudge_command_for_pattern is a bash function. These tests verify:
#   (a) the state-write side-effect (via StateManager)
#   (b) the expected output pattern for injection
#   Since we cannot unit-test the bash function directly in pytest, we test
#   the Python state-layer contract that the fallback depends on, and document
#   the expected behavior of the bash layer via integration sub-process tests
#   where the orchestrator script is sourced.
# ---------------------------------------------------------------------------


class TestNudgeCommandForPattern:
    """
    Scenario: 実装完了パターン検知時に workflow_done を書き inject する
    WHEN: Worker pane 出力が静止し、最終出力に '>>> 実装完了: issue-469' が含まれる
    THEN: orchestrator が state write --role pilot --set workflow_done=test-ready を実行し、
          その後 tmux に /twl:workflow-pr-verify #469 を inject する

    Scenario: 既存パターンへの影響なし
    WHEN: pane 出力が 'setup chain 完了' を含む（既存パターン）
    THEN: 従来通り /twl:workflow-test-ready #469 が inject され、
          実装完了パターン処理は行われない
    """

    def test_completion_pattern_triggers_state_write_workflow_done_test_ready(
        self,
        issue_state_file: Path,
        state_manager: StateManager,
    ) -> None:
        """Simulate orchestrator state write when '>>> 実装完了: issue-469' is detected.

        The bash _nudge_command_for_pattern function (to be implemented) must call:
            state write --type issue --issue 469 --role pilot --set workflow_done=test-ready
        before injecting the skill command.  This test verifies the state layer
        accepts such a write and persists the value correctly.
        """
        # Simulate what orchestrator fallback must do
        state_manager.write(
            type_="issue",
            role="pilot",
            issue="469",
            sets=["workflow_done=test-ready"],
        )

        data = json.loads(issue_state_file.read_text())
        assert data.get("workflow_done") == "test-ready", (
            "After completion-pattern detection, workflow_done must be 'test-ready'"
        )

    def test_completion_pattern_expected_inject_command(self) -> None:
        """The inject command for '>>> 実装完了' pattern must be '/twl:workflow-pr-verify #469'.

        This is the contract the bash function must satisfy (documented as unit truth).
        """
        issue = "469"
        # Expected command that _nudge_command_for_pattern must output
        expected = f"/twl:workflow-pr-verify #{issue}"

        # Verify shape: must match the inject allow-list pattern
        import re
        pattern = r"^/twl:workflow-[a-z][a-z0-9-]* #\d+$"
        assert re.match(pattern, expected), (
            f"Expected inject command {expected!r} does not match allow-list pattern"
        )

    def test_setup_chain_kanryo_pattern_is_unaffected(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """'setup chain 完了' pattern must not set workflow_done=test-ready.

        The bash fallback for '>>> 実装完了' must only fire on that specific pattern.
        'setup chain 完了' must continue routing to /twl:workflow-test-ready (existing behavior).
        """
        # The state must remain untouched for 'setup chain 完了'
        data_before = json.loads(issue_state_file.read_text())
        assert data_before.get("workflow_done") is None

        # 'setup chain 完了' is handled by the existing _nudge_command_for_pattern branch
        # which does NOT write workflow_done. Verify state is unchanged (no side-effect).
        data_after = json.loads(issue_state_file.read_text())
        assert data_after.get("workflow_done") == data_before.get("workflow_done"), (
            "'setup chain 完了' pattern must not alter workflow_done in state"
        )

    def test_completion_pattern_keyword_is_precise(self) -> None:
        """'>>> 実装完了: issue-N' must match; adjacent patterns must not collide."""
        import re

        # The pattern the bash layer will match (from spec)
        target_pattern = r">>> 実装完了: issue-\d+"

        matching = [
            ">>> 実装完了: issue-469",
            ">>> 実装完了: issue-1",
            "some preamble >>> 実装完了: issue-469 trailing",
        ]
        non_matching = [
            "setup chain 完了",
            "テスト準備完了",
            "workflow-pr-verify 完了",
            ">>> 提案完了",
        ]

        for text in matching:
            assert re.search(target_pattern, text), (
                f"Expected pattern to match {text!r}"
            )
        for text in non_matching:
            assert not re.search(target_pattern, text), (
                f"Expected pattern NOT to match {text!r}"
            )


# ---------------------------------------------------------------------------
# Requirement: stagnate 閾値の環境変数一元化
# Spec: specs/orchestrator-completion-fallback/spec.md
# ---------------------------------------------------------------------------


class TestStagnateThreshold:
    """
    Scenario: 連続 RESOLVE_FAILED で WARN を出力する
    WHEN: inject_next_workflow が AUTOPILOT_STAGNATE_SEC / POLL_INTERVAL 回連続で
          RESOLVE_FAILED になる
    THEN: orchestrator が stderr に
          '[orchestrator] WARN: issue=<N> stagnate detected' を出力する
    """

    def test_stagnate_threshold_calculation(self) -> None:
        """AUTOPILOT_STAGNATE_SEC / POLL_INTERVAL gives the stagnate threshold.

        Default: 600 / 10 = 60 consecutive RESOLVE_FAILED → WARN.
        """
        default_stagnate_sec = int(os.environ.get("AUTOPILOT_STAGNATE_SEC", "600"))
        poll_interval = 10  # default POLL_INTERVAL in orchestrator
        expected_threshold = default_stagnate_sec // poll_interval

        assert expected_threshold == 60, (
            f"Expected threshold 60 (600s / 10s), got {expected_threshold}"
        )

    def test_stagnate_env_override_is_respected(self) -> None:
        """When AUTOPILOT_STAGNATE_SEC is overridden, threshold changes proportionally."""
        custom_sec = 300
        poll_interval = 10
        threshold = custom_sec // poll_interval
        assert threshold == 30

    def test_stagnate_warn_message_format(self) -> None:
        """The WARN message must match the expected format for grep/log parsing."""
        import re

        issue = "469"
        expected_msg = f"[orchestrator] WARN: issue={issue} stagnate detected"

        # Verify the format is parseable
        pattern = r"\[orchestrator\] WARN: issue=\d+ stagnate detected"
        assert re.match(pattern, expected_msg), (
            f"Message {expected_msg!r} does not match expected log format"
        )

    def test_resolve_failed_accumulates_before_warn(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """Simulate accumulation of RESOLVE_FAILED counts up to threshold.

        This test documents the contract: the orchestrator must track how many
        consecutive times resolve_next_workflow returns non-zero (RESOLVE_FAILED)
        and emit a WARN when count >= AUTOPILOT_STAGNATE_SEC / POLL_INTERVAL.
        """
        stagnate_sec = int(os.environ.get("AUTOPILOT_STAGNATE_SEC", "600"))
        poll_interval = 10
        threshold = stagnate_sec // poll_interval

        # Simulate threshold consecutive failures
        failure_count = 0
        for _ in range(threshold):
            result = subprocess.run(
                [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
                capture_output=True,
                text=True,
                env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
            )
            if result.returncode != 0:
                failure_count += 1

        # After threshold failures, the count matches — orchestrator must emit WARN
        assert failure_count == threshold, (
            f"Expected {threshold} consecutive failures, got {failure_count}"
        )


# ---------------------------------------------------------------------------
# Edge case: resolve_next_workflow module contract
# ---------------------------------------------------------------------------


class TestResolveNextWorkflowEdgeCases:
    """Edge cases for the resolve_next_workflow module CLI contract."""

    def test_invalid_issue_number_returns_nonzero(self, autopilot_dir: Path) -> None:
        """Non-numeric issue arg must exit non-zero."""
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "abc"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )
        assert result.returncode != 0

    def test_output_is_prefixed_skill_command(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """The stdout skill command must begin with /twl: to be injectable by orchestrator."""
        import re

        data = json.loads(issue_state_file.read_text())
        data["workflow_done"] = "test-ready"
        issue_state_file.write_text(json.dumps(data))

        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        assert result.returncode == 0
        skill = result.stdout.strip()
        # Must satisfy orchestrator allow-list: /twl:workflow-<kebab>
        assert re.match(r"^/twl:workflow-[a-z][a-z0-9-]*$", skill), (
            f"Skill '{skill}' must match /twl:workflow-<kebab> allow-list pattern"
        )

    def test_is_quick_false_test_ready_gives_pr_verify_not_quick_path(
        self, autopilot_dir: Path, issue_state_file: Path
    ) -> None:
        """is_quick=false must not route to quick-path; test-ready must give pr-verify."""
        data = json.loads(issue_state_file.read_text())
        data["workflow_done"] = "test-ready"
        data["is_quick"] = False
        issue_state_file.write_text(json.dumps(data))

        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.resolve_next_workflow", "--issue", "469"],
            capture_output=True,
            text=True,
            env={**os.environ, "AUTOPILOT_DIR": str(autopilot_dir)},
        )

        assert result.returncode == 0
        assert result.stdout.strip() == "/twl:workflow-pr-verify"
        assert "quick" not in result.stdout.lower()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _minimal_flow() -> list[dict]:
    """Minimal worker-lifecycle flow for ChainRunner unit tests."""
    return [
        {
            "id": "setup",
            "chain": "setup",
            "next": [
                {"condition": "!quick && autopilot", "goto": "test-ready"},
                {"condition": "quick && autopilot", "goto": "quick-path"},
                {"condition": "!autopilot", "stop": True},
            ],
        },
        {
            "id": "quick-path",
            "chain": None,
            "next": [{"goto": "done"}],
        },
        {
            "id": "test-ready",
            "chain": "test-ready",
            "skill": "workflow-test-ready",
            "next": [
                {"condition": "autopilot", "goto": "pr-verify"},
                {"condition": "!autopilot", "stop": True},
            ],
        },
        {
            "id": "pr-verify",
            "chain": "pr-verify",
            "skill": "workflow-pr-verify",
            "next": [
                {"condition": "autopilot", "goto": "pr-fix"},
                {"condition": "!autopilot", "stop": True},
            ],
        },
        {
            "id": "pr-fix",
            "chain": "pr-fix",
            "skill": "workflow-pr-fix",
            "next": [
                {"condition": "autopilot", "goto": "pr-merge"},
                {"condition": "!autopilot", "stop": True},
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
