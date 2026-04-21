"""Tests for chain.py export API and twl chain export CLI (Issue #790)."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

from twl.autopilot.chain import (
    CHAIN_METADATA,
    CHAIN_STEP_COMMAND,
    CHAIN_STEP_DISPATCH,
    CHAIN_STEPS,
    STEP_TO_WORKFLOW,
    WORKFLOW_NEXT_SKILL,
    export_chain_steps_sh,
    export_deps_chains,
)


# ===========================================================================
# export_deps_chains()
# ===========================================================================


class TestExportDepsChains:
    def test_returns_dict(self) -> None:
        result = export_deps_chains()
        assert isinstance(result, dict)

    def test_all_workflows_present(self) -> None:
        result = export_deps_chains()
        workflows = set(STEP_TO_WORKFLOW.values())
        for wf in workflows:
            assert wf in result, f"Workflow '{wf}' missing from export_deps_chains()"

    def test_each_chain_has_required_keys(self) -> None:
        result = export_deps_chains()
        for wf, data in result.items():
            assert "type" in data, f"{wf}: missing 'type'"
            assert "description" in data, f"{wf}: missing 'description'"
            assert "steps" in data, f"{wf}: missing 'steps'"
            assert isinstance(data["steps"], list), f"{wf}: 'steps' must be a list"

    def test_steps_are_subsets_of_chain_steps(self) -> None:
        result = export_deps_chains()
        all_steps = set(CHAIN_STEPS)
        for wf, data in result.items():
            for step in data["steps"]:
                assert step in all_steps, f"{wf}: step '{step}' not in CHAIN_STEPS"

    def test_no_step_duplicated_across_chains(self) -> None:
        result = export_deps_chains()
        seen: list[str] = []
        for data in result.values():
            for step in data["steps"]:
                assert step not in seen, f"Step '{step}' appears in multiple chains"
                seen.append(step)

    def test_all_chain_steps_are_exported(self) -> None:
        result = export_deps_chains()
        exported_steps: set[str] = set()
        for data in result.values():
            exported_steps.update(data["steps"])
        for step in CHAIN_STEPS:
            if STEP_TO_WORKFLOW.get(step):
                assert step in exported_steps, f"Step '{step}' not exported"

    def test_type_values_are_valid(self) -> None:
        result = export_deps_chains()
        valid_types = {"A", "B", "meta"}
        for wf, data in result.items():
            assert data["type"] in valid_types, f"{wf}: invalid type '{data['type']}'"

    def test_setup_chain_contains_init(self) -> None:
        result = export_deps_chains()
        assert "setup" in result
        assert "init" in result["setup"]["steps"]


# ===========================================================================
# export_chain_steps_sh()
# ===========================================================================


class TestExportChainStepsSh:
    def test_returns_string(self) -> None:
        result = export_chain_steps_sh()
        assert isinstance(result, str)

    def test_starts_with_shebang(self) -> None:
        result = export_chain_steps_sh()
        assert result.startswith("#!/usr/bin/env bash")

    def test_contains_chain_steps_array(self) -> None:
        result = export_chain_steps_sh()
        assert "CHAIN_STEPS=(" in result

    def test_all_chain_steps_in_output(self) -> None:
        result = export_chain_steps_sh()
        for step in CHAIN_STEPS:
            assert f"  {step}\n" in result or f"  {step}" in result, \
                f"Step '{step}' not found in chain-steps.sh output"

    def test_contains_quick_skip_steps(self) -> None:
        result = export_chain_steps_sh()
        assert "QUICK_SKIP_STEPS=(" in result

    def test_contains_direct_skip_steps(self) -> None:
        result = export_chain_steps_sh()
        assert "DIRECT_SKIP_STEPS=(" in result

    def test_contains_dispatch_assoc_array(self) -> None:
        result = export_chain_steps_sh()
        assert "CHAIN_STEP_DISPATCH=(" in result

    def test_contains_workflow_assoc_array(self) -> None:
        result = export_chain_steps_sh()
        assert "CHAIN_STEP_WORKFLOW=(" in result

    def test_contains_workflow_next_skill(self) -> None:
        result = export_chain_steps_sh()
        assert "CHAIN_WORKFLOW_NEXT_SKILL=(" in result

    def test_contains_step_command(self) -> None:
        result = export_chain_steps_sh()
        assert "CHAIN_STEP_COMMAND=(" in result

    def test_all_workflow_next_skills_in_output(self) -> None:
        result = export_chain_steps_sh()
        for workflow in WORKFLOW_NEXT_SKILL:
            assert f"[{workflow}]" in result, f"Workflow '{workflow}' missing from output"

    def test_no_auto_generated_notice(self) -> None:
        result = export_chain_steps_sh()
        assert "直接編集しないこと" in result


# ===========================================================================
# CHAIN_STEP_DISPATCH integrity
# ===========================================================================


class TestChainStepDispatch:
    def test_all_chain_steps_have_dispatch(self) -> None:
        for step in CHAIN_STEPS:
            assert step in CHAIN_STEP_DISPATCH, f"Step '{step}' missing from CHAIN_STEP_DISPATCH"

    def test_dispatch_values_are_valid(self) -> None:
        valid = {"runner", "llm", "trigger"}
        for step, mode in CHAIN_STEP_DISPATCH.items():
            assert mode in valid, f"Step '{step}' has invalid dispatch mode '{mode}'"

    def test_llm_steps_have_or_empty_command(self) -> None:
        for step, mode in CHAIN_STEP_DISPATCH.items():
            if mode == "llm":
                assert step in CHAIN_STEP_COMMAND, \
                    f"LLM step '{step}' missing from CHAIN_STEP_COMMAND"

    def test_non_llm_steps_not_in_command(self) -> None:
        for step, mode in CHAIN_STEP_DISPATCH.items():
            if mode != "llm":
                assert step not in CHAIN_STEP_COMMAND, \
                    f"Non-LLM step '{step}' should not be in CHAIN_STEP_COMMAND"


# ===========================================================================
# CHAIN_METADATA integrity
# ===========================================================================


class TestChainMetadata:
    def test_all_workflows_have_metadata(self) -> None:
        workflows = set(STEP_TO_WORKFLOW.values())
        for wf in workflows:
            assert wf in CHAIN_METADATA, f"Workflow '{wf}' missing from CHAIN_METADATA"

    def test_metadata_has_type_and_description(self) -> None:
        for wf, meta in CHAIN_METADATA.items():
            assert "type" in meta, f"{wf}: missing 'type' in CHAIN_METADATA"
            assert "description" in meta, f"{wf}: missing 'description' in CHAIN_METADATA"


# ===========================================================================
# CLI: twl chain export (with feature flag)
# ===========================================================================


class TestChainExportCLI:
    def _run(self, *args: str, env: dict | None = None) -> subprocess.CompletedProcess:
        base_env = {**os.environ, "TWL_CHAIN_SSOT_MODE": "chain.py"}
        if env:
            base_env.update(env)
        return subprocess.run(
            [sys.executable, "-m", "twl", "chain", "export", *args],
            capture_output=True,
            text=True,
            env=base_env,
        )

    def test_yaml_stdout(self, tmp_path: Path) -> None:
        """--yaml prints deps.yaml with chains: section."""
        result = self._run("--yaml", "--plugin-root", str(_make_plugin_root(tmp_path)))
        assert result.returncode == 0
        assert "chains:" in result.stdout

    def test_shell_stdout(self, tmp_path: Path) -> None:
        """--shell prints chain-steps.sh content."""
        result = self._run("--shell", "--plugin-root", str(_make_plugin_root(tmp_path)))
        assert result.returncode == 0
        assert "CHAIN_STEPS=(" in result.stdout

    def test_yaml_write(self, tmp_path: Path) -> None:
        """--yaml --write updates deps.yaml."""
        pr = _make_plugin_root(tmp_path)
        result = self._run("--yaml", "--write", "--plugin-root", str(pr))
        assert result.returncode == 0
        updated = (pr / "deps.yaml").read_text()
        assert "chains:" in updated

    def test_shell_write(self, tmp_path: Path) -> None:
        """--shell --write writes chain-steps.sh."""
        pr = _make_plugin_root(tmp_path)
        result = self._run("--shell", "--write", "--plugin-root", str(pr))
        assert result.returncode == 0
        assert (pr / "scripts" / "chain-steps.sh").exists()

    def test_fallback_mode_returns_error(self, tmp_path: Path) -> None:
        """TWL_CHAIN_SSOT_MODE=deps.yaml → exit 1."""
        pr = _make_plugin_root(tmp_path)
        result = self._run(
            "--yaml", "--plugin-root", str(pr),
            env={"TWL_CHAIN_SSOT_MODE": "deps.yaml"},
        )
        assert result.returncode != 0

    def test_no_flag_errors(self) -> None:
        """Missing --yaml/--shell → exit non-zero."""
        result = self._run()
        assert result.returncode != 0

    def test_mutually_exclusive_flags(self, tmp_path: Path) -> None:
        """--yaml and --shell are mutually exclusive."""
        pr = _make_plugin_root(tmp_path)
        result = self._run("--yaml", "--shell", "--plugin-root", str(pr))
        assert result.returncode != 0


def _make_plugin_root(tmp_path: Path) -> Path:
    """Create a minimal plugin root with deps.yaml for tests."""
    pr = tmp_path / "plugin"
    pr.mkdir()
    (pr / "scripts").mkdir()
    (pr / "deps.yaml").write_text(
        "version: \"3.0\"\nplugin: test\nchains:\n  setup:\n    type: \"A\"\n    steps:\n      - init\n",
        encoding="utf-8",
    )
    return pr
