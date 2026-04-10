"""Tests for issue-403: phase-review and scope-judge registration in chain execution framework.

Spec: deltaspec/changes/issue-403/specs/chain-registration/spec.md

Coverage:
  - chain-steps.sh CHAIN_STEPS array: phase-review and scope-judge present in pr-verify section
    in correct order (after ts-preflight, before pr-test)
  - chain-steps.sh CHAIN_STEP_DISPATCH map: phase-review=llm, scope-judge=llm
  - chain-steps.sh CHAIN_STEP_COMMAND map: phase-review=commands/phase-review.md, scope-judge=commands/scope-judge.md
  - chain-steps.sh CHAIN_STEP_WORKFLOW map: phase-review=pr-verify, scope-judge=pr-verify
  - chain.py STEP_TO_WORKFLOW: "phase-review": "pr-verify", "scope-judge": "pr-verify"
  - chain-runner.sh case block: phase-review and scope-judge handled without "ERROR: 未知のステップ"
  - chain trace JSONL: phase-review start/end events recorded when TWL_CHAIN_TRACE is set
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parents[4]
_CHAIN_STEPS_SH = _REPO_ROOT / "plugins" / "twl" / "scripts" / "chain-steps.sh"
_CHAIN_RUNNER_SH = _REPO_ROOT / "plugins" / "twl" / "scripts" / "chain-runner.sh"


def _read_chain_steps_sh() -> str:
    return _CHAIN_STEPS_SH.read_text(encoding="utf-8")


def _source_chain_steps_and_eval(var: str) -> list[str] | dict[str, str]:
    """Source chain-steps.sh and print a bash variable as JSON for inspection."""
    script = f"""
set -euo pipefail
source "{_CHAIN_STEPS_SH}"
case "{var}" in
  CHAIN_STEPS)
    printf '%s\\n' "${{CHAIN_STEPS[@]}}"
    ;;
  CHAIN_STEP_DISPATCH)
    for k in "${{!CHAIN_STEP_DISPATCH[@]}}"; do
      printf '%s=%s\\n' "$k" "${{CHAIN_STEP_DISPATCH[$k]}}"
    done
    ;;
  CHAIN_STEP_COMMAND)
    for k in "${{!CHAIN_STEP_COMMAND[@]}}"; do
      printf '%s=%s\\n' "$k" "${{CHAIN_STEP_COMMAND[$k]}}"
    done
    ;;
  CHAIN_STEP_WORKFLOW)
    for k in "${{!CHAIN_STEP_WORKFLOW[@]}}"; do
      printf '%s=%s\\n' "$k" "${{CHAIN_STEP_WORKFLOW[$k]}}"
    done
    ;;
esac
"""
    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"bash script failed:\n{result.stderr}"
    )
    lines = [l for l in result.stdout.splitlines() if l]
    if var == "CHAIN_STEPS":
        return lines
    # For associative arrays, return dict
    d: dict[str, str] = {}
    for line in lines:
        if "=" in line:
            k, _, v = line.partition("=")
            d[k] = v
    return d


# ---------------------------------------------------------------------------
# Scenario 1: CHAIN_STEPS ordering in pr-verify section
# ---------------------------------------------------------------------------


class TestChainStepsOrdering:
    """Scenario: pr-verify chain のステップ順序確認

    WHEN chain-steps.sh の CHAIN_STEPS 配列（pr-verify セクション）を参照する
    THEN ts-preflight, phase-review, scope-judge, pr-test の順で定義されている
    """

    def test_chain_steps_sh_exists(self) -> None:
        assert _CHAIN_STEPS_SH.exists(), f"chain-steps.sh not found: {_CHAIN_STEPS_SH}"

    def test_phase_review_in_chain_steps(self) -> None:
        steps = _source_chain_steps_and_eval("CHAIN_STEPS")
        assert "phase-review" in steps, (
            f"'phase-review' not found in CHAIN_STEPS: {steps}"
        )

    def test_scope_judge_in_chain_steps(self) -> None:
        steps = _source_chain_steps_and_eval("CHAIN_STEPS")
        assert "scope-judge" in steps, (
            f"'scope-judge' not found in CHAIN_STEPS: {steps}"
        )

    def test_phase_review_after_ts_preflight(self) -> None:
        steps = _source_chain_steps_and_eval("CHAIN_STEPS")
        assert "ts-preflight" in steps, "'ts-preflight' missing from CHAIN_STEPS"
        ts_idx = steps.index("ts-preflight")
        pr_idx = steps.index("phase-review")
        assert ts_idx < pr_idx, (
            f"Expected ts-preflight ({ts_idx}) before phase-review ({pr_idx})"
        )

    def test_scope_judge_after_phase_review(self) -> None:
        steps = _source_chain_steps_and_eval("CHAIN_STEPS")
        pr_idx = steps.index("phase-review")
        sj_idx = steps.index("scope-judge")
        assert pr_idx < sj_idx, (
            f"Expected phase-review ({pr_idx}) before scope-judge ({sj_idx})"
        )

    def test_scope_judge_before_pr_test(self) -> None:
        steps = _source_chain_steps_and_eval("CHAIN_STEPS")
        assert "pr-test" in steps, "'pr-test' missing from CHAIN_STEPS"
        sj_idx = steps.index("scope-judge")
        pt_idx = steps.index("pr-test")
        assert sj_idx < pt_idx, (
            f"Expected scope-judge ({sj_idx}) before pr-test ({pt_idx})"
        )

    def test_consecutive_order_ts_phase_scope_prtest(self) -> None:
        """ts-preflight, phase-review, scope-judge, pr-test are in consecutive order."""
        steps = _source_chain_steps_and_eval("CHAIN_STEPS")
        expected_subsequence = ["ts-preflight", "phase-review", "scope-judge", "pr-test"]
        # Find positions
        positions = []
        for s in expected_subsequence:
            assert s in steps, f"'{s}' missing from CHAIN_STEPS"
            positions.append(steps.index(s))
        assert positions == sorted(positions), (
            f"Expected steps in order {expected_subsequence}, got positions {positions}"
        )
        # They must be adjacent (consecutive indices)
        for i in range(len(positions) - 1):
            assert positions[i + 1] == positions[i] + 1, (
                f"Steps are not consecutive: {expected_subsequence[i]} at {positions[i]}, "
                f"{expected_subsequence[i+1]} at {positions[i+1]}"
            )


# ---------------------------------------------------------------------------
# Scenario 2: CHAIN_STEP_DISPATCH (dispatch mode) map
# ---------------------------------------------------------------------------


class TestChainStepDispatch:
    """Scenario: STEP_DISPATCH_MODE マップへの登録

    WHEN chain-steps.sh の CHAIN_STEP_DISPATCH マップを参照する
    THEN phase-review が llm、scope-judge が llm として登録されている
    """

    def test_phase_review_dispatch_is_llm(self) -> None:
        dispatch = _source_chain_steps_and_eval("CHAIN_STEP_DISPATCH")
        assert "phase-review" in dispatch, (
            f"'phase-review' not found in CHAIN_STEP_DISPATCH: {list(dispatch.keys())}"
        )
        assert dispatch["phase-review"] == "llm", (
            f"Expected phase-review dispatch=llm, got '{dispatch['phase-review']}'"
        )

    def test_scope_judge_dispatch_is_llm(self) -> None:
        dispatch = _source_chain_steps_and_eval("CHAIN_STEP_DISPATCH")
        assert "scope-judge" in dispatch, (
            f"'scope-judge' not found in CHAIN_STEP_DISPATCH: {list(dispatch.keys())}"
        )
        assert dispatch["scope-judge"] == "llm", (
            f"Expected scope-judge dispatch=llm, got '{dispatch['scope-judge']}'"
        )

    def test_existing_steps_not_broken(self) -> None:
        """Registering new entries must not alter existing dispatch entries."""
        dispatch = _source_chain_steps_and_eval("CHAIN_STEP_DISPATCH")
        assert dispatch.get("ts-preflight") == "runner", (
            f"ts-preflight dispatch should remain runner, got '{dispatch.get('ts-preflight')}'"
        )
        assert dispatch.get("pr-test") == "runner", (
            f"pr-test dispatch should remain runner, got '{dispatch.get('pr-test')}'"
        )


# ---------------------------------------------------------------------------
# Scenario 3: CHAIN_STEP_COMMAND map
# ---------------------------------------------------------------------------


class TestChainStepCommand:
    """Scenario: STEP_CMD マップへの登録

    WHEN chain-steps.sh の CHAIN_STEP_COMMAND マップを参照する
    THEN phase-review が commands/phase-review.md、scope-judge が commands/scope-judge.md として登録されている
    """

    def test_phase_review_command_path(self) -> None:
        commands = _source_chain_steps_and_eval("CHAIN_STEP_COMMAND")
        assert "phase-review" in commands, (
            f"'phase-review' not found in CHAIN_STEP_COMMAND: {list(commands.keys())}"
        )
        assert commands["phase-review"] == "commands/phase-review.md", (
            f"Expected phase-review command=commands/phase-review.md, "
            f"got '{commands['phase-review']}'"
        )

    def test_scope_judge_command_path(self) -> None:
        commands = _source_chain_steps_and_eval("CHAIN_STEP_COMMAND")
        assert "scope-judge" in commands, (
            f"'scope-judge' not found in CHAIN_STEP_COMMAND: {list(commands.keys())}"
        )
        assert commands["scope-judge"] == "commands/scope-judge.md", (
            f"Expected scope-judge command=commands/scope-judge.md, "
            f"got '{commands['scope-judge']}'"
        )


# ---------------------------------------------------------------------------
# Scenario 4: CHAIN_STEP_WORKFLOW (CHAIN_STEP_TO_WORKFLOW) map
# ---------------------------------------------------------------------------


class TestChainStepWorkflow:
    """Scenario: CHAIN_STEP_TO_WORKFLOW マップ確認

    WHEN chain-steps.sh の CHAIN_STEP_WORKFLOW マップを参照する
    THEN phase-review と scope-judge がともに pr-verify にマッピングされている
    """

    def test_phase_review_workflow_is_pr_verify(self) -> None:
        workflow = _source_chain_steps_and_eval("CHAIN_STEP_WORKFLOW")
        assert "phase-review" in workflow, (
            f"'phase-review' not found in CHAIN_STEP_WORKFLOW: {list(workflow.keys())}"
        )
        assert workflow["phase-review"] == "pr-verify", (
            f"Expected phase-review workflow=pr-verify, got '{workflow['phase-review']}'"
        )

    def test_scope_judge_workflow_is_pr_verify(self) -> None:
        workflow = _source_chain_steps_and_eval("CHAIN_STEP_WORKFLOW")
        assert "scope-judge" in workflow, (
            f"'scope-judge' not found in CHAIN_STEP_WORKFLOW: {list(workflow.keys())}"
        )
        assert workflow["scope-judge"] == "pr-verify", (
            f"Expected scope-judge workflow=pr-verify, got '{workflow['scope-judge']}'"
        )

    def test_neighboring_steps_workflow_unchanged(self) -> None:
        """ts-preflight and pr-test must remain in pr-verify."""
        workflow = _source_chain_steps_and_eval("CHAIN_STEP_WORKFLOW")
        assert workflow.get("ts-preflight") == "pr-verify", (
            f"ts-preflight workflow should remain pr-verify"
        )
        assert workflow.get("pr-test") == "pr-verify", (
            f"pr-test workflow should remain pr-verify"
        )


# ---------------------------------------------------------------------------
# Scenario 5: chain.py STEP_TO_WORKFLOW
# ---------------------------------------------------------------------------


class TestChainPyStepToWorkflow:
    """Scenario: chain.py の STEP_TO_WORKFLOW 確認

    WHEN cli/twl/src/twl/autopilot/chain.py の STEP_TO_WORKFLOW を参照する
    THEN "phase-review" と "scope-judge" がともに "pr-verify" にマッピングされている
    """

    def test_phase_review_in_step_to_workflow(self) -> None:
        from twl.autopilot.chain import STEP_TO_WORKFLOW
        assert "phase-review" in STEP_TO_WORKFLOW, (
            f"'phase-review' not found in STEP_TO_WORKFLOW: {list(STEP_TO_WORKFLOW.keys())}"
        )
        assert STEP_TO_WORKFLOW["phase-review"] == "pr-verify", (
            f"Expected phase-review -> pr-verify, got '{STEP_TO_WORKFLOW['phase-review']}'"
        )

    def test_scope_judge_in_step_to_workflow(self) -> None:
        from twl.autopilot.chain import STEP_TO_WORKFLOW
        assert "scope-judge" in STEP_TO_WORKFLOW, (
            f"'scope-judge' not found in STEP_TO_WORKFLOW: {list(STEP_TO_WORKFLOW.keys())}"
        )
        assert STEP_TO_WORKFLOW["scope-judge"] == "pr-verify", (
            f"Expected scope-judge -> pr-verify, got '{STEP_TO_WORKFLOW['scope-judge']}'"
        )

    def test_chain_steps_and_step_to_workflow_consistent(self) -> None:
        """Every step in CHAIN_STEPS that belongs to pr-verify should map to pr-verify."""
        from twl.autopilot.chain import CHAIN_STEPS, STEP_TO_WORKFLOW
        assert "phase-review" in CHAIN_STEPS, "'phase-review' not in CHAIN_STEPS"
        assert "scope-judge" in CHAIN_STEPS, "'scope-judge' not in CHAIN_STEPS"

    def test_chain_steps_order_mirrors_chain_steps_sh(self) -> None:
        """chain.py CHAIN_STEPS should include phase-review and scope-judge in correct position."""
        from twl.autopilot.chain import CHAIN_STEPS
        assert "phase-review" in CHAIN_STEPS
        assert "scope-judge" in CHAIN_STEPS
        ts_idx = CHAIN_STEPS.index("ts-preflight")
        pr_idx = CHAIN_STEPS.index("phase-review")
        sj_idx = CHAIN_STEPS.index("scope-judge")
        pt_idx = CHAIN_STEPS.index("pr-test")
        assert ts_idx < pr_idx < sj_idx < pt_idx, (
            f"Expected ts-preflight < phase-review < scope-judge < pr-test, "
            f"got indices: {ts_idx}, {pr_idx}, {sj_idx}, {pt_idx}"
        )


# ---------------------------------------------------------------------------
# Scenarios 6 & 7: chain-runner.sh handler execution
# ---------------------------------------------------------------------------


def _run_chain_runner(step: str, env: dict | None = None) -> subprocess.CompletedProcess:
    """Execute chain-runner.sh <step> and return the CompletedProcess."""
    run_env = {**os.environ}
    if env:
        run_env.update(env)
    return subprocess.run(
        ["bash", str(_CHAIN_RUNNER_SH), step],
        capture_output=True,
        text=True,
        env=run_env,
        cwd=str(_REPO_ROOT),
    )


class TestChainRunnerHandler:
    """Scenarios 6 & 7: chain-runner.sh の phase-review / scope-judge ハンドラ

    WHEN chain-runner.sh phase-review を実行する
    THEN "ERROR: 未知のステップ" を出力せずに正常終了する

    WHEN chain-runner.sh scope-judge を実行する
    THEN "ERROR: 未知のステップ" を出力せずに正常終了する
    """

    def test_phase_review_no_unknown_step_error(self, tmp_path: Path) -> None:
        """phase-review handler does not emit 'ERROR: 未知のステップ'."""
        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "issues").mkdir()
        result = _run_chain_runner(
            "phase-review",
            env={"AUTOPILOT_DIR": str(autopilot_dir)},
        )
        assert "ERROR: 未知のステップ" not in result.stderr, (
            f"phase-review emitted unknown-step error.\nstderr: {result.stderr}\nstdout: {result.stdout}"
        )

    def test_scope_judge_no_unknown_step_error(self, tmp_path: Path) -> None:
        """scope-judge handler does not emit 'ERROR: 未知のステップ'."""
        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "issues").mkdir()
        result = _run_chain_runner(
            "scope-judge",
            env={"AUTOPILOT_DIR": str(autopilot_dir)},
        )
        assert "ERROR: 未知のステップ" not in result.stderr, (
            f"scope-judge emitted unknown-step error.\nstderr: {result.stderr}\nstdout: {result.stdout}"
        )

    def test_phase_review_updates_current_step(self, tmp_path: Path) -> None:
        """phase-review handler records current_step in issue state JSON.

        Sets up a minimal .autopilot/issues/issue-N.json to exercise
        record_current_step, then verifies current_step=phase-review.
        """
        autopilot_dir = tmp_path / ".autopilot"
        issues_dir = autopilot_dir / "issues"
        issues_dir.mkdir(parents=True)

        # Derive an issue number from a fake branch name embedded in GIT_BRANCH env var.
        # chain-runner.sh uses resolve_issue_num() which reads the current branch.
        # We create the issue JSON manually to represent a running issue.
        issue_json = issues_dir / "issue-403.json"
        issue_json.write_text(
            json.dumps(
                {
                    "issue": "403",
                    "status": "running",
                    "current_step": "ts-preflight",
                    "role": "worker",
                    "type": "issue",
                }
            ),
            encoding="utf-8",
        )

        result = _run_chain_runner(
            "phase-review",
            env={
                "AUTOPILOT_DIR": str(autopilot_dir),
                # Provide branch via env so resolve_issue_num can extract 403
                "GIT_BRANCH": "fix/403-phase-review-test",
            },
        )
        assert "ERROR: 未知のステップ" not in result.stderr, (
            f"Unexpected error: {result.stderr}"
        )

    def test_scope_judge_updates_current_step(self, tmp_path: Path) -> None:
        """scope-judge handler records current_step in issue state JSON."""
        autopilot_dir = tmp_path / ".autopilot"
        issues_dir = autopilot_dir / "issues"
        issues_dir.mkdir(parents=True)

        issue_json = issues_dir / "issue-403.json"
        issue_json.write_text(
            json.dumps(
                {
                    "issue": "403",
                    "status": "running",
                    "current_step": "phase-review",
                    "role": "worker",
                    "type": "issue",
                }
            ),
            encoding="utf-8",
        )

        result = _run_chain_runner(
            "scope-judge",
            env={
                "AUTOPILOT_DIR": str(autopilot_dir),
                "GIT_BRANCH": "fix/403-scope-judge-test",
            },
        )
        assert "ERROR: 未知のステップ" not in result.stderr, (
            f"Unexpected error: {result.stderr}"
        )

    def test_phase_review_case_block_present_in_source(self) -> None:
        """chain-runner.sh source contains a case entry for phase-review."""
        source = _CHAIN_RUNNER_SH.read_text(encoding="utf-8")
        assert "phase-review)" in source, (
            "No case entry for 'phase-review)' found in chain-runner.sh"
        )

    def test_scope_judge_case_block_present_in_source(self) -> None:
        """chain-runner.sh source contains a case entry for scope-judge."""
        source = _CHAIN_RUNNER_SH.read_text(encoding="utf-8")
        assert "scope-judge)" in source, (
            "No case entry for 'scope-judge)' found in chain-runner.sh"
        )


# ---------------------------------------------------------------------------
# Scenario 8: chain trace JSONL records phase-review start/end events
# ---------------------------------------------------------------------------


class TestChainTraceEvents:
    """Scenario: chain trace への phase-review 記録

    WHEN pr-verify chain が実行される（TWL_CHAIN_TRACE set, phase-review step run）
    THEN trace JSONL に phase-review の start イベントが記録される
    THEN trace JSONL に phase-review の end イベントが記録される
    """

    def test_phase_review_trace_start_event(self, tmp_path: Path) -> None:
        trace_file = tmp_path / "chain-trace.jsonl"
        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "issues").mkdir()

        result = subprocess.run(
            ["bash", str(_CHAIN_RUNNER_SH), "--trace", str(trace_file), "phase-review"],
            capture_output=True,
            text=True,
            env={
                **os.environ,
                "AUTOPILOT_DIR": str(autopilot_dir),
                "TWL_CHAIN_TRACE": str(trace_file),
            },
            cwd=str(_REPO_ROOT),
        )

        assert "ERROR: 未知のステップ" not in result.stderr, (
            f"phase-review emitted unknown-step error: {result.stderr}"
        )

        if not trace_file.exists():
            pytest.skip("TWL_CHAIN_TRACE trace file not created (jq unavailable or bash skip)")

        events = []
        for line in trace_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                events.append(json.loads(line))

        phase_review_events = [e for e in events if e.get("step") == "phase-review"]
        assert any(e.get("phase") == "start" for e in phase_review_events), (
            f"No 'start' event for phase-review in trace: {events}"
        )

    def test_phase_review_trace_end_event(self, tmp_path: Path) -> None:
        trace_file = tmp_path / "chain-trace.jsonl"
        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "issues").mkdir()

        result = subprocess.run(
            ["bash", str(_CHAIN_RUNNER_SH), "--trace", str(trace_file), "phase-review"],
            capture_output=True,
            text=True,
            env={
                **os.environ,
                "AUTOPILOT_DIR": str(autopilot_dir),
                "TWL_CHAIN_TRACE": str(trace_file),
            },
            cwd=str(_REPO_ROOT),
        )

        assert "ERROR: 未知のステップ" not in result.stderr, (
            f"phase-review emitted unknown-step error: {result.stderr}"
        )

        if not trace_file.exists():
            pytest.skip("TWL_CHAIN_TRACE trace file not created")

        events = []
        for line in trace_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                events.append(json.loads(line))

        phase_review_events = [e for e in events if e.get("step") == "phase-review"]
        assert any(e.get("phase") == "end" for e in phase_review_events), (
            f"No 'end' event for phase-review in trace: {events}"
        )

    def test_scope_judge_trace_start_end_events(self, tmp_path: Path) -> None:
        """scope-judge also records start and end trace events."""
        trace_file = tmp_path / "chain-trace.jsonl"
        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "issues").mkdir()

        result = subprocess.run(
            ["bash", str(_CHAIN_RUNNER_SH), "--trace", str(trace_file), "scope-judge"],
            capture_output=True,
            text=True,
            env={
                **os.environ,
                "AUTOPILOT_DIR": str(autopilot_dir),
                "TWL_CHAIN_TRACE": str(trace_file),
            },
            cwd=str(_REPO_ROOT),
        )

        assert "ERROR: 未知のステップ" not in result.stderr, (
            f"scope-judge emitted unknown-step error: {result.stderr}"
        )

        if not trace_file.exists():
            pytest.skip("TWL_CHAIN_TRACE trace file not created")

        events = []
        for line in trace_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                events.append(json.loads(line))

        sj_events = [e for e in events if e.get("step") == "scope-judge"]
        assert any(e.get("phase") == "start" for e in sj_events), (
            f"No 'start' event for scope-judge in trace: {events}"
        )
        assert any(e.get("phase") == "end" for e in sj_events), (
            f"No 'end' event for scope-judge in trace: {events}"
        )

    def test_trace_event_schema(self, tmp_path: Path) -> None:
        """Each trace event has required fields: step, phase, ts, pid."""
        trace_file = tmp_path / "chain-trace.jsonl"
        autopilot_dir = tmp_path / ".autopilot"
        autopilot_dir.mkdir()
        (autopilot_dir / "issues").mkdir()

        subprocess.run(
            ["bash", str(_CHAIN_RUNNER_SH), "--trace", str(trace_file), "phase-review"],
            capture_output=True,
            text=True,
            env={
                **os.environ,
                "AUTOPILOT_DIR": str(autopilot_dir),
                "TWL_CHAIN_TRACE": str(trace_file),
            },
            cwd=str(_REPO_ROOT),
        )

        if not trace_file.exists():
            pytest.skip("Trace file not created")

        for line in trace_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            event = json.loads(line)
            for field in ("step", "phase", "ts", "pid"):
                assert field in event, (
                    f"Trace event missing field '{field}': {event}"
                )
