#!/usr/bin/env python3
"""Tests for chain_validate: bidirectional consistency, type guards, step ordering, prompt consistency.

These tests are written BEFORE the implementation (TDD).
The chain_validate function will be called as part of --validate (v3.0 only).

Spec: openspec/changes/chain-validate/specs/chain-validate/spec.md
"""

import shutil
import subprocess
import os
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent / "twl-engine.py"


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def make_chain_fixture(tmpdir: Path) -> Path:
    """Create a valid v3.0 plugin fixture with complete chain/step configuration.

    The fixture has:
      - chain "workflow-setup" (type A) with steps: [my-workflow, ac-extract, ac-verify]
      - chain "review-flow" (no type) with steps: [my-review-wf]
      - my-controller (controller) -> calls my-workflow with step "1"
      - my-workflow (workflow, chain=workflow-setup) -> calls ac-extract step "2", ac-verify step "3"
      - ac-extract (atomic, chain=workflow-setup, step_in={parent: my-workflow})
      - ac-verify (atomic, chain=workflow-setup, step_in={parent: my-workflow})
      - my-review-wf (workflow, chain=review-flow)
    """
    plugin_dir = tmpdir / "test-plugin-chain"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-chain",
        "chains": {
            "workflow-setup": {
                "description": "Setup workflow chain",
                "type": "A",
                "steps": ["my-workflow", "ac-extract", "ac-verify"],
            },
            "review-flow": {
                "description": "Review flow chain",
                "steps": ["my-review-wf"],
            },
        },
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": [
                    {"workflow": "my-workflow", "step": "1"},
                ],
            },
            "my-workflow": {
                "type": "workflow",
                "path": "skills/my-workflow/SKILL.md",
                "description": "A workflow",
                "chain": "workflow-setup",
                "step_in": {"parent": "my-controller"},
                "calls": [
                    {"atomic": "ac-extract", "step": "2"},
                    {"atomic": "ac-verify", "step": "3"},
                ],
            },
            "my-review-wf": {
                "type": "workflow",
                "path": "skills/my-review-wf/SKILL.md",
                "description": "A review workflow",
                "chain": "review-flow",
                "calls": [],
            },
        },
        "commands": {
            "ac-extract": {
                "type": "atomic",
                "path": "commands/ac-extract.md",
                "description": "Extract action",
                "chain": "workflow-setup",
                "step_in": {"parent": "my-workflow"},
                "calls": [],
            },
            "ac-verify": {
                "type": "atomic",
                "path": "commands/ac-verify.md",
                "description": "Verify action",
                "chain": "workflow-setup",
                "step_in": {"parent": "my-workflow"},
                "calls": [],
            },
        },
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _load_deps(plugin_dir: Path) -> dict:
    return yaml.safe_load((plugin_dir / "deps.yaml").read_text())


def _create_component_files(plugin_dir: Path, deps: dict) -> None:
    """Create minimal markdown files for every component in deps."""
    for section in ("skills", "commands", "agents"):
        for name, data in deps.get(section, {}).items():
            path_str = data.get("path", "")
            if not path_str:
                continue
            file_path = plugin_dir / path_str
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(
                f"---\nname: {name}\ndescription: Test\n---\n\nContent for {name}.\n",
                encoding="utf-8",
            )


def _write_body(plugin_dir: Path, path_str: str, body: str) -> None:
    """Overwrite a component file's body (keeping frontmatter pattern)."""
    file_path = plugin_dir / path_str
    name = file_path.stem
    file_path.write_text(
        f"---\nname: {name}\ndescription: Test\n---\n\n{body}\n",
        encoding="utf-8",
    )


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Test base class with setup/teardown
# ---------------------------------------------------------------------------

class _ChainTestBase:
    """Shared setup/teardown for chain validation tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_chain_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _modify_deps(self, mutator):
        """Load deps, apply mutator function, write back."""
        deps = _load_deps(self.plugin_dir)
        mutator(deps)
        _write_deps(self.plugin_dir, deps)
        return deps


# ===========================================================================
# Requirement: chain bidirectional consistency (chain-bidir)
# ===========================================================================

class TestChainBidirectional(_ChainTestBase):
    """chains.steps <-> component.chain mutual consistency."""

    # --- Happy path ---

    def test_valid_bidirectional_no_error(self):
        """WHEN chains.steps and component.chain are mutually consistent
        THEN no chain-bidir error is emitted and validate passes."""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        assert "[chain-bidir]" not in result.stdout

    # --- Error: listed in steps but missing chain field ---

    def test_in_steps_but_no_chain_field(self):
        """WHEN chains.workflow-setup.steps contains ac-extract
        but ac-extract has no chain field
        THEN CRITICAL [chain-bidir] ac-extract: listed in chains/workflow-setup/steps but has no chain field."""
        def mutator(deps):
            del deps["commands"]["ac-extract"]["chain"]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "[chain-bidir]" in result.stdout
        assert "ac-extract" in result.stdout
        assert "listed in chains/workflow-setup/steps but has no chain field" in result.stdout

    # --- Error: has chain field but not in steps ---

    def test_has_chain_but_not_in_steps(self):
        """WHEN ac-verify has chain='workflow-setup'
        but chains.workflow-setup.steps does not contain ac-verify
        THEN CRITICAL [chain-bidir] ac-verify: chain='workflow-setup' but not listed in chains/workflow-setup/steps."""
        def mutator(deps):
            deps["chains"]["workflow-setup"]["steps"].remove("ac-verify")
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "[chain-bidir]" in result.stdout
        assert "ac-verify" in result.stdout
        assert "not listed in chains/workflow-setup/steps" in result.stdout

    # --- Edge: multiple components violating at once ---

    def test_multiple_bidir_violations(self):
        """WHEN multiple components have mismatched chain/steps
        THEN all violations are reported."""
        def mutator(deps):
            # Remove both from chain field
            del deps["commands"]["ac-extract"]["chain"]
            del deps["commands"]["ac-verify"]["chain"]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert result.stdout.count("[chain-bidir]") >= 2


# ===========================================================================
# Requirement: step bidirectional consistency (step-bidir)
# ===========================================================================

class TestStepBidirectional(_ChainTestBase):
    """parent.calls[].step <-> child.step_in mutual consistency."""

    # --- Happy path ---

    def test_valid_step_bidirectional_no_error(self):
        """WHEN parent calls with step and child has matching step_in
        THEN no step-bidir error is emitted."""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        assert "[step-bidir]" not in result.stdout

    # --- Error: calls has step but child has no step_in ---

    def test_calls_step_but_child_no_step_in(self):
        """WHEN my-workflow calls ac-extract with step='2'
        but ac-extract has no step_in
        THEN CRITICAL [step-bidir] ac-extract: called with step='2' from my-workflow but has no step_in."""
        def mutator(deps):
            del deps["commands"]["ac-extract"]["step_in"]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "[step-bidir]" in result.stdout
        assert "ac-extract" in result.stdout
        assert "has no step_in" in result.stdout

    # --- Error: child has step_in but parent has no step call ---

    def test_child_step_in_but_parent_no_step(self):
        """WHEN ac-verify has step_in={parent: my-workflow}
        but my-workflow has no step call to ac-verify
        THEN CRITICAL [step-bidir] ac-verify: step_in.parent='my-workflow' but my-workflow has no step call to ac-verify."""
        def mutator(deps):
            # Remove the step call for ac-verify from my-workflow
            deps["skills"]["my-workflow"]["calls"] = [
                c for c in deps["skills"]["my-workflow"]["calls"]
                if c.get("atomic") != "ac-verify"
            ]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "[step-bidir]" in result.stdout
        assert "ac-verify" in result.stdout
        assert "has no step call to ac-verify" in result.stdout

    # --- Edge: step_in with decimal step value ---

    def test_step_in_decimal_step_value(self):
        """WHEN parent calls child with step='1.5' and child has step_in pointing back
        THEN no error (step value itself is not checked for match, only existence)."""
        def mutator(deps):
            deps["skills"]["my-workflow"]["calls"][0] = {
                "atomic": "ac-extract", "step": "1.5"
            }
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[step-bidir]" not in result.stdout

    # --- Edge: call without step field should not trigger step-bidir ---

    def test_call_without_step_no_step_bidir_error(self):
        """WHEN a call entry has no step field
        THEN step-bidir check is not triggered for that call."""
        def mutator(deps):
            # Add a call without step
            deps["skills"]["my-workflow"]["calls"].append(
                {"atomic": "ac-extract"}  # duplicate target but no step
            )
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        # Should not produce step-bidir error for the stepless call
        # (may have other issues, but step-bidir should not fire for no-step calls)
        out = result.stdout
        # Count step-bidir mentions - there should be none caused by the stepless call
        # Note: the original step="2" call still exists and is valid
        assert "[step-bidir]" not in out or "has no step_in" not in out


# ===========================================================================
# Requirement: chain type guard (chain-type)
# ===========================================================================

class TestChainTypeGuard(_ChainTestBase):
    """Chain A allows workflow|atomic only, Chain B allows atomic|composite only."""

    # --- Error: specialist in Chain A ---

    def test_specialist_in_chain_a(self):
        """WHEN chains.workflow-setup type=A has a specialist component in steps
        THEN WARNING [chain-type] chains/workflow-setup: specialist 'my-worker' not allowed in Chain A."""
        def mutator(deps):
            # Ensure chain type is A
            deps["chains"]["workflow-setup"]["type"] = "A"
            # Add a specialist agent
            deps["agents"]["my-worker"] = {
                "type": "specialist",
                "path": "agents/my-worker.md",
                "description": "A worker",
                "chain": "workflow-setup",
                "calls": [],
            }
            deps["chains"]["workflow-setup"]["steps"].append("my-worker")
        self._modify_deps(mutator)

        # Create the file for the new component
        worker_path = self.plugin_dir / "agents"
        worker_path.mkdir(parents=True, exist_ok=True)
        (worker_path / "my-worker.md").write_text(
            "---\nname: my-worker\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert "[chain-type]" in result.stdout
        assert "specialist" in result.stdout
        assert "my-worker" in result.stdout
        assert "not allowed in Chain A" in result.stdout

    # --- Error: workflow in Chain B ---

    def test_workflow_in_chain_b(self):
        """WHEN chains.review-flow type=B has a workflow component in steps
        THEN WARNING [chain-type] chains/review-flow: workflow 'my-review-wf' not allowed in Chain B."""
        def mutator(deps):
            deps["chains"]["review-flow"]["type"] = "B"
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[chain-type]" in result.stdout
        assert "workflow" in result.stdout
        assert "my-review-wf" in result.stdout
        assert "not allowed in Chain B" in result.stdout

    # --- Happy path: Chain A with only workflow/atomic ---

    def test_chain_a_valid_types(self):
        """WHEN Chain A only contains workflow and atomic types
        THEN no chain-type warning is emitted."""
        result = run_engine(self.plugin_dir, "--validate")
        assert "[chain-type]" not in result.stdout

    # --- Edge: chain without type field ---

    def test_chain_without_type_skips_check(self):
        """WHEN chain definition has no type field
        THEN type constraint check is skipped (no error/warning)."""
        def mutator(deps):
            # review-flow has no type field already, add a specialist to it
            deps["agents"]["my-worker"] = {
                "type": "specialist",
                "path": "agents/my-worker.md",
                "description": "A worker",
                "chain": "review-flow",
                "calls": [],
            }
            deps["chains"]["review-flow"]["steps"].append("my-worker")
        self._modify_deps(mutator)

        worker_path = self.plugin_dir / "agents"
        worker_path.mkdir(parents=True, exist_ok=True)
        (worker_path / "my-worker.md").write_text(
            "---\nname: my-worker\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert "[chain-type]" not in result.stdout

    # --- Edge: composite in Chain A ---

    def test_composite_in_chain_a(self):
        """WHEN Chain A (type=A) has a composite component
        THEN WARNING [chain-type] because composite is not in {workflow, atomic}."""
        def mutator(deps):
            deps["chains"]["workflow-setup"]["type"] = "A"
            deps["commands"]["my-composite"] = {
                "type": "composite",
                "path": "commands/my-composite.md",
                "description": "A composite",
                "chain": "workflow-setup",
                "calls": [],
            }
            deps["chains"]["workflow-setup"]["steps"].append("my-composite")
        self._modify_deps(mutator)

        (self.plugin_dir / "commands" / "my-composite.md").write_text(
            "---\nname: my-composite\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert "[chain-type]" in result.stdout
        assert "composite" in result.stdout
        assert "not allowed in Chain A" in result.stdout

    # --- Edge: Chain B with only atomic/composite ---

    def test_chain_b_valid_types(self):
        """WHEN Chain B only contains atomic and composite types
        THEN no chain-type warning is emitted."""
        def mutator(deps):
            deps["chains"]["review-flow"]["type"] = "B"
            # Replace the workflow with atomics
            deps["chains"]["review-flow"]["steps"] = ["review-ac"]
            del deps["skills"]["my-review-wf"]["chain"]
            deps["commands"]["review-ac"] = {
                "type": "atomic",
                "path": "commands/review-ac.md",
                "description": "Review atomic",
                "chain": "review-flow",
                "calls": [],
            }
        self._modify_deps(mutator)

        (self.plugin_dir / "commands" / "review-ac.md").write_text(
            "---\nname: review-ac\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert "[chain-type]" not in result.stdout


# ===========================================================================
# Requirement: step ordering (step-order)
# ===========================================================================

class TestStepOrdering(_ChainTestBase):
    """step values in calls must be ascending."""

    # --- Happy path: ascending order ---

    def test_ascending_step_order_no_error(self):
        """WHEN calls have steps [1, 2, 3] in ascending order
        THEN no step-order warning is emitted."""
        # Default fixture has steps "2", "3" which is ascending
        result = run_engine(self.plugin_dir, "--validate")
        assert "[step-order]" not in result.stdout

    # --- Error: descending step values ---

    def test_descending_step_order(self):
        """WHEN calls have steps ['3', '1.5', '5'] (not ascending at '1.5')
        THEN WARNING [step-order] my-workflow: step '1.5' appears after '3' (not ascending)."""
        def mutator(deps):
            deps["skills"]["my-workflow"]["calls"] = [
                {"atomic": "ac-extract", "step": "3"},
                {"atomic": "ac-verify", "step": "1.5"},
            ]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[step-order]" in result.stdout
        assert "1.5" in result.stdout
        assert "after" in result.stdout
        assert "3" in result.stdout

    # --- Edge: equal step values ---

    def test_equal_step_values(self):
        """WHEN two calls have the same step value '2'
        THEN WARNING for duplicate step."""
        def mutator(deps):
            deps["skills"]["my-workflow"]["calls"] = [
                {"atomic": "ac-extract", "step": "2"},
                {"atomic": "ac-verify", "step": "2"},
            ]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[step-order]" in result.stdout
        assert "duplicate" in result.stdout

    # --- Edge: only one step ---

    def test_single_step_no_error(self):
        """WHEN calls have only one entry with step
        THEN no step-order issue."""
        def mutator(deps):
            deps["skills"]["my-workflow"]["calls"] = [
                {"atomic": "ac-extract", "step": "1"},
            ]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[step-order]" not in result.stdout

    # --- Edge: mixed calls with and without step ---

    def test_mixed_step_and_no_step(self):
        """WHEN some calls have step and others do not
        THEN ordering only considers calls with step field."""
        def mutator(deps):
            deps["skills"]["my-workflow"]["calls"] = [
                {"atomic": "ac-extract", "step": "3"},
                {"atomic": "ac-verify"},         # no step
                {"atomic": "ac-extract", "step": "1"},  # out of order
            ]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[step-order]" in result.stdout

    # --- Edge: decimal step ordering ---

    def test_decimal_step_ordering_valid(self):
        """WHEN calls have steps ['1', '1.5', '3'] in ascending order
        THEN no step-order warning."""
        def mutator(deps):
            deps["skills"]["my-workflow"]["calls"] = [
                {"atomic": "ac-extract", "step": "1"},
                {"atomic": "ac-verify", "step": "1.5"},
            ]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[step-order]" not in result.stdout

    # --- Edge: step ordering across multiple components ---

    def test_step_order_per_component(self):
        """WHEN component A has ascending steps and component B has descending steps
        THEN only B gets step-order warning."""
        def mutator(deps):
            # my-workflow: ascending (ok)
            deps["skills"]["my-workflow"]["calls"] = [
                {"atomic": "ac-extract", "step": "1"},
                {"atomic": "ac-verify", "step": "2"},
            ]
            # my-controller: descending (error)
            deps["skills"]["my-controller"]["calls"] = [
                {"workflow": "my-workflow", "step": "5"},
                {"workflow": "my-review-wf", "step": "2"},
            ]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[step-order]" in result.stdout
        assert "my-controller" in result.stdout


# ===========================================================================
# Requirement: prompt body consistency (prompt-chain)
# ===========================================================================

class TestPromptConsistency(_ChainTestBase):
    """body text mentions 'Step N from ...' must match deps.yaml step_in."""

    # --- Error: body mentions step but no step_in ---

    def test_body_mentions_step_but_no_step_in(self):
        """WHEN body says 'workflow-setup Step 3.5 から呼び出される'
        but deps.yaml has no matching step_in
        THEN WARNING [prompt-chain] ac-extract: body mentions 'workflow-setup Step 3.5' but no matching step_in."""
        # Remove step_in from ac-extract, then add body reference
        def mutator(deps):
            del deps["commands"]["ac-extract"]["step_in"]
        self._modify_deps(mutator)

        _write_body(
            self.plugin_dir,
            "commands/ac-extract.md",
            "This component is called as: workflow-setup Step 3.5 から呼び出される\n",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert "[prompt-chain]" in result.stdout
        assert "ac-extract" in result.stdout
        assert "workflow-setup Step 3.5" in result.stdout
        assert "no matching step_in" in result.stdout

    # --- Happy path: body and deps.yaml match ---

    def test_body_matches_step_in(self):
        """WHEN body says 'my-workflow Step 2 から呼び出される'
        and deps.yaml has step_in={parent: my-workflow}
        THEN no prompt-chain warning."""
        _write_body(
            self.plugin_dir,
            "commands/ac-extract.md",
            "This component is: my-workflow Step 2 から呼び出される\nSome other content.\n",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert "[prompt-chain]" not in result.stdout

    # --- Edge: body with no step mention ---

    def test_body_without_step_mention_no_error(self):
        """WHEN body does not mention any step pattern
        THEN no prompt-chain check is triggered."""
        _write_body(
            self.plugin_dir,
            "commands/ac-extract.md",
            "This is a normal command that does extraction.\n",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert "[prompt-chain]" not in result.stdout

    # --- Edge: body mentions step_in parent correctly but different step number ---

    def test_body_mentions_correct_parent_different_step(self):
        """WHEN body says 'my-workflow Step 99 から呼び出される'
        and deps.yaml has step_in={parent: my-workflow}
        THEN this should still pass (step_in check is parent-level, not step-number-level)
        OR produce a warning depending on implementation strictness."""
        _write_body(
            self.plugin_dir,
            "commands/ac-extract.md",
            "This component is: my-workflow Step 99 から呼び出される\n",
        )

        result = run_engine(self.plugin_dir, "--validate")
        # The parent matches, so at minimum no CRITICAL error
        # Implementation may or may not warn about step number mismatch
        assert "[prompt-chain]" not in result.stdout or "CRITICAL" not in result.stdout

    # --- Edge: multiple step mentions in body ---

    def test_body_multiple_step_mentions(self):
        """WHEN body mentions two different parent Step patterns
        and only one has matching step_in
        THEN warning for the unmatched one."""
        _write_body(
            self.plugin_dir,
            "commands/ac-extract.md",
            "my-workflow Step 2 から呼び出される\n"
            "nonexistent-wf Step 5 から呼び出される\n",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert "[prompt-chain]" in result.stdout
        assert "nonexistent-wf Step 5" in result.stdout


# ===========================================================================
# Requirement: twl check integration
# ===========================================================================

class TestTwlCheckIntegration(_ChainTestBase):
    """v3.0 triggers chain_validate, v2.0 skips it."""

    # --- v3.0 with valid chains ---

    def test_v3_check_includes_chain_validation(self):
        """WHEN twl check runs on v3.0 deps.yaml with valid chains
        THEN file check AND chain validation both pass."""
        result = run_engine(self.plugin_dir, "--check")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        assert "All files exist" in result.stdout

    # --- v3.0 with chain violation should fail check ---

    def test_v3_check_fails_on_chain_critical(self):
        """WHEN twl check runs on v3.0 with chain-bidir CRITICAL
        THEN non-zero exit code."""
        def mutator(deps):
            del deps["commands"]["ac-extract"]["chain"]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--check")
        assert result.returncode != 0
        assert "[chain-bidir]" in result.stdout

    # --- v2.0 skips chain validation ---

    def test_v2_check_skips_chain_validation(self):
        """WHEN twl check runs on v2.0 deps.yaml
        THEN chain validation is not executed, only file checks."""
        def mutator(deps):
            deps["version"] = "2.0"
            # Remove v3.0 fields
            deps.pop("chains", None)
            for section in ("skills", "commands", "agents"):
                for data in deps.get(section, {}).values():
                    data.pop("chain", None)
                    data.pop("step_in", None)
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--check")
        assert result.returncode == 0
        assert "[chain-bidir]" not in result.stdout
        assert "[step-bidir]" not in result.stdout
        assert "[chain-type]" not in result.stdout
        assert "[step-order]" not in result.stdout
        assert "[prompt-chain]" not in result.stdout

    # --- v3.0 validate includes chain checks ---

    def test_v3_validate_includes_chain_checks(self):
        """WHEN --validate runs on v3.0 with chain violations
        THEN chain errors appear in validate output."""
        def mutator(deps):
            del deps["commands"]["ac-verify"]["step_in"]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "[step-bidir]" in result.stdout

    # --- v2.0 validate skips chain checks ---

    def test_v2_validate_skips_chain_checks(self):
        """WHEN --validate runs on v2.0 deps.yaml
        THEN no chain-related errors (chain_validate not called)."""
        def mutator(deps):
            deps["version"] = "2.0"
            deps.pop("chains", None)
            for section in ("skills", "commands", "agents"):
                for data in deps.get(section, {}).values():
                    data.pop("chain", None)
                    data.pop("step_in", None)
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0
        assert "[chain-bidir]" not in result.stdout
        assert "[step-bidir]" not in result.stdout


# ===========================================================================
# Additional edge case tests
# ===========================================================================

class TestChainValidateEdgeCases(_ChainTestBase):
    """Edge cases spanning multiple requirements."""

    def test_empty_chains_section(self):
        """WHEN chains section exists but is empty
        THEN no crash, components with chain field produce chain-ref errors (handled by v3_schema)."""
        def mutator(deps):
            deps["chains"] = {}
            # Components still reference the old chain - handled by v3-chain-ref
            # Remove chain fields to avoid v3-chain-ref errors
            for section in ("skills", "commands", "agents"):
                for data in deps.get(section, {}).values():
                    data.pop("chain", None)
                    data.pop("step_in", None)
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        # Should not crash
        assert result.returncode == 0 or "[chain-bidir]" not in result.stdout

    def test_chain_with_no_steps_list(self):
        """WHEN a chain exists but has no steps key
        THEN handled gracefully (empty steps treated as [])."""
        def mutator(deps):
            deps["chains"]["empty-chain"] = {"description": "Empty chain"}
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        # Should not crash; no chain-bidir for empty-chain since no steps
        assert "empty-chain" not in result.stdout or result.returncode == 0

    def test_all_validations_pass_on_clean_fixture(self):
        """The default fixture should pass all validations without any errors."""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        assert "[chain-bidir]" not in result.stdout
        assert "[step-bidir]" not in result.stdout
        assert "[chain-type]" not in result.stdout
        assert "[step-order]" not in result.stdout
        assert "[prompt-chain]" not in result.stdout


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestChainBidirectional,
        TestStepBidirectional,
        TestChainTypeGuard,
        TestStepOrdering,
        TestPromptConsistency,
        TestTwlCheckIntegration,
        TestChainValidateEdgeCases,
    ]
    passed = 0
    failed = 0
    errors = []

    for cls in classes:
        for method_name in sorted(dir(cls)):
            if not method_name.startswith("test_"):
                continue
            instance = cls()
            instance.setup_method()
            try:
                getattr(instance, method_name)()
                passed += 1
                print(f"  PASS: {cls.__name__}.{method_name}")
            except Exception as e:
                failed += 1
                errors.append((f"{cls.__name__}.{method_name}", e))
                print(f"  FAIL: {cls.__name__}.{method_name}: {e}")
                traceback.print_exc()
            finally:
                instance.teardown_method()

    print(f"\n{'=' * 40}")
    print(f"Results: {passed} passed, {failed} failed")
    if errors:
        print("\nFailures:")
        for name, err in errors:
            print(f"  {name}: {err}")
        sys.exit(1)
    else:
        print("All tests passed!")
