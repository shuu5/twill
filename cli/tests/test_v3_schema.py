#!/usr/bin/env python3
"""Tests for deps.yaml v3.0 schema: calls type-name keys, chains, step, step_in, chain fields."""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent / "twl-engine.py"


def make_v3_fixture(tmpdir: Path) -> Path:
    """Create a valid v3.0 plugin fixture."""
    plugin_dir = tmpdir / "test-plugin-v3"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "testv3",
        "chains": {
            "setup-chain": {
                "description": "Setup workflow chain",
                "steps": ["my-workflow", "my-action", "my-sub"],
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
            "my-ref": {
                "type": "reference",
                "path": "skills/my-ref/SKILL.md",
                "description": "A reference",
                "spawnable_by": ["all"],
                "calls": [],
            },
            "my-workflow": {
                "type": "workflow",
                "path": "skills/my-workflow/SKILL.md",
                "description": "A workflow",
                "chain": "setup-chain",
                "step_in": {"parent": "my-controller"},
                "calls": [
                    {"atomic": "my-action", "step": "2"},
                    {"atomic": "my-sub", "step": "3"},
                    {"composite": "my-composite"},
                ],
            },
        },
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An atomic command",
                "chain": "setup-chain",
                "step_in": {"parent": "my-workflow"},
                "calls": [
                    {"reference": "my-ref"},
                ],
            },
            "my-sub": {
                "type": "atomic",
                "path": "commands/my-sub.md",
                "description": "A sub command",
                "chain": "setup-chain",
                "step_in": {"parent": "my-workflow"},
                "calls": [],
            },
            "my-composite": {
                "type": "composite",
                "path": "commands/my-composite.md",
                "description": "A composite command",
                "calls": [
                    {"specialist": "my-worker"},
                ],
            },
        },
        "agents": {
            "my-worker": {
                "type": "specialist",
                "path": "agents/my-worker.md",
                "description": "A specialist agent",
                "calls": [],
            },
        },
    }
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )

    # Create minimal files
    for name in ("my-controller", "my-workflow", "my-ref"):
        d = plugin_dir / "skills" / name
        d.mkdir(parents=True)
        (d / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: Test\n---\n\nContent for {name}.\n",
            encoding="utf-8",
        )

    (plugin_dir / "commands").mkdir(parents=True)
    for name in ("my-action", "my-sub", "my-composite"):
        (plugin_dir / "commands" / f"{name}.md").write_text(
            f"---\nname: {name}\ndescription: Test\n---\n\nContent for {name}.\n",
            encoding="utf-8",
        )

    (plugin_dir / "agents").mkdir(parents=True)
    (plugin_dir / "agents" / "my-worker.md").write_text(
        "---\nname: my-worker\ndescription: Test\n---\n\nContent for my-worker.\n",
        encoding="utf-8",
    )

    return plugin_dir


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, str(TWL_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


class TestV3ValidFixture:
    """Valid v3.0 fixture should pass all checks."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_v3_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_validate_passes(self):
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        assert "All type constraints satisfied" in result.stdout

    def test_check_passes(self):
        result = run_engine(self.plugin_dir, "--check")
        assert result.returncode == 0
        assert "All files exist" in result.stdout

    def test_tree_output(self):
        result = run_engine(self.plugin_dir, "--tree")
        assert result.returncode == 0


class TestV3CallsKeyValidation:
    """v3.0 should reject section-name keys in calls."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_v3_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_v3_rejects_command_key(self):
        """v3.0 should reject 'command:' key, require 'atomic:' or 'composite:'."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        # Change a valid call to use section-name key
        deps["skills"]["my-workflow"]["calls"] = [
            {"command": "my-action"},  # should fail in v3.0
        ]
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-calls-key" in result.stdout

    def test_v3_rejects_skill_key(self):
        """v3.0 should reject 'skill:' key."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["skills"]["my-controller"]["calls"] = [
            {"skill": "my-workflow"},  # should fail in v3.0
        ]
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-calls-key" in result.stdout

    def test_v3_rejects_agent_key(self):
        """v3.0 should reject 'agent:' key."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["commands"]["my-composite"]["calls"] = [
            {"agent": "my-worker"},  # should fail in v3.0
        ]
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-calls-key" in result.stdout

    def test_v2_allows_section_keys(self):
        """v2.0 should still allow section-name keys."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["version"] = "2.0"
        # Use section-name keys for v2.0
        deps["skills"]["my-controller"]["calls"] = [
            {"skill": "my-workflow"},
        ]
        deps["skills"]["my-workflow"]["calls"] = [
            {"command": "my-action"},
        ]
        deps["commands"]["my-action"]["calls"] = [
            {"reference": "my-ref"},
        ]
        # Remove v3.0 fields
        for section in ("skills", "commands", "agents"):
            for data in deps.get(section, {}).values():
                data.pop("chain", None)
                data.pop("step_in", None)
        deps.pop("chains", None)
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0


class TestV3StepField:
    """Tests for step field in calls entries."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_v3_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_step_string_valid(self):
        """step as string should pass."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["skills"]["my-controller"]["calls"] = [
            {"workflow": "my-workflow", "step": "1.5"},
        ]
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0

    def test_step_non_string_fails(self):
        """step as non-string should fail in v3.0."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["skills"]["my-controller"]["calls"] = [
            {"workflow": "my-workflow", "step": 1},  # int, not str
        ]
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-step-type" in result.stdout


class TestV3StepIn:
    """Tests for step_in field on components."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_v3_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_step_in_valid(self):
        """Valid step_in should pass."""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0

    def test_step_in_missing_parent_fails(self):
        """step_in without parent key should fail."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["commands"]["my-action"]["step_in"] = {"step": "2"}  # missing parent
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-step_in-parent" in result.stdout

    def test_step_in_nonexistent_parent_fails(self):
        """step_in.parent referencing non-existent component should fail."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["commands"]["my-action"]["step_in"] = {"parent": "ghost-component"}
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-step_in-ref" in result.stdout


class TestV3Chain:
    """Tests for chain field and chains section."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_v3_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_chain_valid(self):
        """Valid chain references should pass."""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0

    def test_chain_nonexistent_fails(self):
        """chain referencing non-existent chain name should fail."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["skills"]["my-workflow"]["chain"] = "nonexistent-chain"
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-chain-ref" in result.stdout

    def test_chains_steps_nonexistent_component_fails(self):
        """chains.steps referencing non-existent component should fail."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        deps["chains"]["setup-chain"]["steps"].append("ghost-step")
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-chains-ref" in result.stdout


class TestV2BackwardCompat:
    """v2.0 deps.yaml should continue to work with section-name keys."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = self._make_v2_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _make_v2_fixture(self, tmpdir: Path) -> Path:
        plugin_dir = tmpdir / "test-plugin-v2"
        plugin_dir.mkdir()

        deps = {
            "version": "2.0",
            "plugin": "testv2",
            "skills": {
                "my-controller": {
                    "type": "controller",
                    "path": "skills/my-controller/SKILL.md",
                    "description": "Main controller",
                    "can_spawn": ["workflow", "atomic", "composite", "specialist", "reference"],
                    "spawnable_by": ["user"],
                    "calls": [
                        {"command": "my-action"},
                        {"reference": "my-ref"},
                    ],
                },
                "my-ref": {
                    "type": "reference",
                    "path": "skills/my-ref/SKILL.md",
                    "description": "A reference skill",
                    "spawnable_by": ["all"],
                    "calls": [],
                },
            },
            "commands": {
                "my-action": {
                    "type": "atomic",
                    "path": "commands/my-action.md",
                    "description": "An atomic command",
                    "can_spawn": ["reference"],
                    "spawnable_by": ["workflow", "controller"],
                    "calls": [],
                },
            },
            "agents": {},
        }
        (plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )

        for name in ("my-controller", "my-ref"):
            d = plugin_dir / "skills" / name
            d.mkdir(parents=True)
            (d / "SKILL.md").write_text(
                f"---\nname: {name}\ndescription: Test\n---\n\nContent.\n",
                encoding="utf-8",
            )

        (plugin_dir / "commands").mkdir(parents=True)
        (plugin_dir / "commands" / "my-action.md").write_text(
            "---\nname: my-action\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        return plugin_dir

    def test_v2_validate_passes(self):
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"

    def test_v2_check_passes(self):
        result = run_engine(self.plugin_dir, "--check")
        assert result.returncode == 0

    def test_v2_no_version_treated_as_v2(self):
        """deps.yaml without version field should be treated as v2.0."""
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        del deps["version"]
        (self.plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0


if __name__ == "__main__":
    import traceback

    classes = [
        TestV3ValidFixture,
        TestV3CallsKeyValidation,
        TestV3StepField,
        TestV3StepIn,
        TestV3Chain,
        TestV2BackwardCompat,
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
