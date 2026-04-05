#!/usr/bin/env python3
"""Tests for deep_validate model checks on specialist components.

Spec: openspec/changes/model-specialist-validate/specs/deep-validate-model.md

Covers:
- ALLOWED_MODELS constant definition
- model-required WARNING for specialist without model
- No warning/info for specialist with valid model
- INFO for unknown model values (typo detection)
- WARNING for opus on specialist
- specialist-only scope (controller etc. not checked)
"""

import shutil
import subprocess
import os
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "twl-engine.py"
TWL_SRC = str(Path(__file__).resolve().parent.parent.parent / "src")


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

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


def make_specialist_fixture(tmpdir: Path, *, model: str | None = "sonnet") -> Path:
    """Create a v3.0 plugin fixture with a specialist agent.

    Args:
        model: The model value for the specialist. None means no model field.
    """
    plugin_dir = tmpdir / "test-plugin-model"
    plugin_dir.mkdir()

    specialist_data: dict = {
        "type": "specialist",
        "path": "agents/my-specialist.md",
        "description": "A specialist agent",
        "calls": [],
    }
    if model is not None:
        specialist_data["model"] = model

    deps = {
        "version": "3.0",
        "plugin": "test-model",
        "chains": {},
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": [
                    {"specialist": "my-specialist"},
                ],
            },
        },
        "commands": {},
        "agents": {
            "my-specialist": specialist_data,
        },
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


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

class _ModelTestBase:
    """Shared setup/teardown for model validation tests."""

    model_value: str | None = "sonnet"  # default: valid model

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_specialist_fixture(self.tmpdir, model=self.model_value)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _modify_deps(self, mutator):
        """Load deps, apply mutator function, write back."""
        deps = _load_deps(self.plugin_dir)
        mutator(deps)
        _write_deps(self.plugin_dir, deps)
        return deps


# ===========================================================================
# Requirement: ALLOWED_MODELS constant definition
# ===========================================================================

class TestAllowedModelsConstant:
    """ALLOWED_MODELS = {"haiku", "sonnet", "opus"} must exist at module level."""

    def test_allowed_models_is_set_with_expected_values(self):
        """Scenario: constant is accessible
        WHEN twl package is imported
        THEN ALLOWED_MODELS is a set containing {"haiku", "sonnet", "opus"}."""
        # We test by running a subprocess that imports and checks
        check_script = (
            f"import sys; sys.path.insert(0, {repr(TWL_SRC)}); "
            "from twl.core.types import ALLOWED_MODELS; "
            "am = ALLOWED_MODELS; "
            "assert am is not None, 'ALLOWED_MODELS not found'; "
            "assert isinstance(am, (set, frozenset)), f'expected set, got {type(am)}'; "
            "assert am == {'haiku', 'sonnet', 'opus'}, f'unexpected value: {am}'; "
            "print('OK')"
        )
        result = subprocess.run(
            [sys.executable, "-c", check_script],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, (
            f"ALLOWED_MODELS check failed.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert "OK" in result.stdout


# ===========================================================================
# Requirement: specialist model required WARNING
# ===========================================================================

class TestModelRequiredWarning(_ModelTestBase):
    """deep_validate reports WARNING when specialist has no model field."""

    model_value = None  # no model field

    def test_model_missing_specialist_warns(self):
        """Scenario: model undeclared specialist
        WHEN specialist type component has no model field
        THEN adds '[model-required] {name}: specialist で model 未宣言' to WARNING."""
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[model-required]" in result.stdout
        assert "my-specialist" in result.stdout
        assert "model 未宣言" in result.stdout


# ===========================================================================
# Requirement: specialist with valid model OK
# ===========================================================================

class TestModelDeclaredOk(_ModelTestBase):
    """deep_validate does not warn when specialist has valid model."""

    model_value = "sonnet"

    def test_model_declared_valid_no_warning(self):
        """Scenario: model declared specialist
        WHEN specialist type component has model field with ALLOWED_MODELS value
        THEN no WARNING or INFO is reported."""
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[model-required]" not in result.stdout

    def test_model_haiku_no_warning(self):
        """Edge case: haiku is a valid model and should produce no warnings."""
        def mutator(deps):
            deps["agents"]["my-specialist"]["model"] = "haiku"
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[model-required]" not in result.stdout


# ===========================================================================
# Requirement: unknown model value INFO
# ===========================================================================

class TestUnknownModelInfo(_ModelTestBase):
    """deep_validate reports INFO for model values not in ALLOWED_MODELS."""

    model_value = "sonne"  # typo

    def test_unknown_model_value_info(self):
        """Scenario: unknown model value
        WHEN specialist model is 'sonne' (not in ALLOWED_MODELS)
        THEN adds '[model-required] {name}: model '{value}' は許可リストにありません' to INFO."""
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[model-required]" in result.stdout
        assert "my-specialist" in result.stdout
        assert "許可リストにありません" in result.stdout
        assert "sonne" in result.stdout

    def test_unknown_model_empty_string_info(self):
        """Edge case: empty string model value should be treated as unknown."""
        def mutator(deps):
            deps["agents"]["my-specialist"]["model"] = ""
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--deep-validate")
        # Empty string is not in ALLOWED_MODELS, so should produce info or warning
        assert "[model-required]" in result.stdout


# ===========================================================================
# Requirement: opus WARNING
# ===========================================================================

class TestOpusWarning(_ModelTestBase):
    """deep_validate reports WARNING when specialist uses opus."""

    model_value = "opus"

    def test_opus_specialist_warns(self):
        """Scenario: specialist with opus
        WHEN specialist model is 'opus'
        THEN adds '[model-required] {name}: specialist に opus は推奨されません' to WARNING."""
        result = run_engine(self.plugin_dir, "--deep-validate")
        assert "[model-required]" in result.stdout
        assert "my-specialist" in result.stdout
        assert "opus は推奨されません" in result.stdout


# ===========================================================================
# Requirement: specialist-only scope
# ===========================================================================

class TestNonSpecialistSkipped(_ModelTestBase):
    """deep_validate model check only targets specialist type."""

    model_value = "sonnet"  # won't matter for the controller

    def test_controller_without_model_no_warning(self):
        """Scenario: controller without model
        WHEN controller type component has no model field
        THEN no model-required WARNING/INFO is reported."""
        # Default fixture has controller without model field
        result = run_engine(self.plugin_dir, "--deep-validate")
        # Ensure no model-required error mentioning the controller
        lines = [
            line for line in result.stdout.splitlines()
            if "[model-required]" in line and "my-controller" in line
        ]
        assert len(lines) == 0, f"Unexpected model-required for controller: {lines}"

    def test_workflow_without_model_no_warning(self):
        """Edge case: workflow type should not trigger model-required check."""
        def mutator(deps):
            deps["skills"]["my-workflow"] = {
                "type": "workflow",
                "path": "skills/my-workflow/SKILL.md",
                "description": "A workflow",
                "calls": [],
            }
        self._modify_deps(mutator)

        # Create file for workflow
        wf_path = self.plugin_dir / "skills" / "my-workflow"
        wf_path.mkdir(parents=True, exist_ok=True)
        (wf_path / "SKILL.md").write_text(
            "---\nname: my-workflow\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--deep-validate")
        lines = [
            line for line in result.stdout.splitlines()
            if "[model-required]" in line and "my-workflow" in line
        ]
        assert len(lines) == 0, f"Unexpected model-required for workflow: {lines}"

    def test_atomic_without_model_no_warning(self):
        """Edge case: atomic type should not trigger model-required check."""
        def mutator(deps):
            deps["commands"]["my-atomic"] = {
                "type": "atomic",
                "path": "commands/my-atomic.md",
                "description": "An atomic command",
                "calls": [],
            }
        self._modify_deps(mutator)

        (self.plugin_dir / "commands").mkdir(parents=True, exist_ok=True)
        (self.plugin_dir / "commands" / "my-atomic.md").write_text(
            "---\nname: my-atomic\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--deep-validate")
        lines = [
            line for line in result.stdout.splitlines()
            if "[model-required]" in line and "my-atomic" in line
        ]
        assert len(lines) == 0, f"Unexpected model-required for atomic: {lines}"

    def test_composite_without_model_no_warning(self):
        """Edge case: composite type should not trigger model-required check."""
        def mutator(deps):
            deps["commands"]["my-composite"] = {
                "type": "composite",
                "path": "commands/my-composite.md",
                "description": "A composite command",
                "calls": [],
            }
        self._modify_deps(mutator)

        (self.plugin_dir / "commands").mkdir(parents=True, exist_ok=True)
        (self.plugin_dir / "commands" / "my-composite.md").write_text(
            "---\nname: my-composite\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--deep-validate")
        lines = [
            line for line in result.stdout.splitlines()
            if "[model-required]" in line and "my-composite" in line
        ]
        assert len(lines) == 0, f"Unexpected model-required for composite: {lines}"


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestAllowedModelsConstant,
        TestModelRequiredWarning,
        TestModelDeclaredOk,
        TestUnknownModelInfo,
        TestOpusWarning,
        TestNonSpecialistSkipped,
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
            except Exception as e:
                failed += 1
                errors.append((f"{cls.__name__}.{method_name}", e))
                print(f"  FAIL: {cls.__name__}.{method_name}: {e}")
                traceback.print_exc()
            finally:
                if hasattr(instance, "teardown_method"):
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
