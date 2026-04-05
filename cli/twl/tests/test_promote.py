#!/usr/bin/env python3
"""Tests for twl promote command."""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent / "twl-engine.py"


def make_fixture(tmpdir: Path) -> Path:
    """Create a minimal plugin fixture for testing promote."""
    plugin_dir = tmpdir / "test-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "test",
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
            "my-workflow": {
                "type": "workflow",
                "path": "skills/my-workflow/SKILL.md",
                "description": "A workflow",
                "can_spawn": ["atomic", "composite", "specialist"],
                "spawnable_by": ["controller", "user"],
                "calls": [
                    {"command": "my-action"},
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
            "my-composite": {
                "type": "composite",
                "path": "commands/my-composite.md",
                "description": "A composite command",
                "can_spawn": ["specialist"],
                "spawnable_by": ["workflow", "controller"],
                "calls": [
                    {"agent": "my-worker"},
                ],
            },
        },
        "agents": {
            "my-worker": {
                "type": "specialist",
                "path": "agents/my-worker.md",
                "description": "A specialist agent",
                "spawnable_by": ["composite", "controller", "workflow"],
                "calls": [],
            },
        },
    }
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )

    # skill files
    for name in ("my-controller", "my-workflow", "my-ref"):
        d = plugin_dir / "skills" / name
        d.mkdir(parents=True)
        (d / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: Test\n---\n\nContent for {name}.\n",
            encoding="utf-8",
        )

    # command files
    (plugin_dir / "commands").mkdir(parents=True)
    for name in ("my-action", "my-composite"):
        (plugin_dir / "commands" / f"{name}.md").write_text(
            f"---\nname: {name}\ndescription: Test\n---\n\nContent for {name}.\n",
            encoding="utf-8",
        )

    # agent files
    (plugin_dir / "agents").mkdir(parents=True)
    (plugin_dir / "agents" / "my-worker.md").write_text(
        "---\nname: my-worker\ndescription: Test\n---\n\nContent for my-worker.\n",
        encoding="utf-8",
    )

    return plugin_dir


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


class TestPromoteBasic:
    """Basic promote tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_dry_run_shows_changes(self):
        result = run_engine(self.plugin_dir, "--promote", "my-action", "controller", "--dry-run")
        assert result.returncode == 0
        assert "[dry-run]" in result.stdout
        assert "controller" in result.stdout

    def test_dry_run_no_file_changes(self):
        deps_before = (self.plugin_dir / "deps.yaml").read_text()
        run_engine(self.plugin_dir, "--promote", "my-action", "controller", "--dry-run")
        deps_after = (self.plugin_dir / "deps.yaml").read_text()
        assert deps_before == deps_after
        # File should still be in commands/
        assert (self.plugin_dir / "commands" / "my-action.md").exists()

    def test_promote_atomic_to_controller(self):
        """Promote atomic (commands) → controller (skills): section move + file move."""
        result = run_engine(self.plugin_dir, "--promote", "my-action", "controller")
        assert result.returncode == 0

        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        # Moved to skills section
        assert "my-action" in deps["skills"]
        assert "my-action" not in deps["commands"]
        # Type updated
        assert deps["skills"]["my-action"]["type"] == "controller"
        # Path updated
        assert deps["skills"]["my-action"]["path"] == "skills/my-action/SKILL.md"
        # File moved
        assert (self.plugin_dir / "skills" / "my-action" / "SKILL.md").exists()
        assert not (self.plugin_dir / "commands" / "my-action.md").exists()

    def test_demote_controller_to_atomic(self):
        """Demote controller (skills) → atomic (commands): reverse section move."""
        result = run_engine(self.plugin_dir, "--promote", "my-controller", "atomic")
        assert result.returncode == 0

        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert "my-controller" in deps["commands"]
        assert "my-controller" not in deps["skills"]
        assert deps["commands"]["my-controller"]["type"] == "atomic"
        assert deps["commands"]["my-controller"]["path"] == "commands/my-controller.md"
        # File moved
        assert (self.plugin_dir / "commands" / "my-controller.md").exists()
        assert not (self.plugin_dir / "skills" / "my-controller" / "SKILL.md").exists()

    def test_same_section_type_change(self):
        """Change workflow → controller within skills section (no file move)."""
        result = run_engine(self.plugin_dir, "--promote", "my-workflow", "controller")
        assert result.returncode == 0

        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert "my-workflow" in deps["skills"]
        assert deps["skills"]["my-workflow"]["type"] == "controller"
        # Path unchanged (same section)
        assert deps["skills"]["my-workflow"]["path"] == "skills/my-workflow/SKILL.md"
        # File not moved
        assert (self.plugin_dir / "skills" / "my-workflow" / "SKILL.md").exists()

    def test_promote_updates_can_spawn(self):
        """Promoting should update can_spawn to new type defaults."""
        run_engine(self.plugin_dir, "--promote", "my-action", "controller")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        can_spawn = deps["skills"]["my-action"].get("can_spawn", [])
        assert "workflow" in can_spawn
        assert "specialist" in can_spawn

    def test_promote_updates_spawnable_by(self):
        """Promoting should update spawnable_by to new type defaults."""
        run_engine(self.plugin_dir, "--promote", "my-action", "controller")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        spawnable_by = deps["skills"]["my-action"].get("spawnable_by", [])
        assert "user" in spawnable_by

    def test_promote_to_specialist(self):
        """Promote atomic → specialist: commands → agents."""
        result = run_engine(self.plugin_dir, "--promote", "my-action", "specialist")
        assert result.returncode == 0

        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert "my-action" in deps["agents"]
        assert "my-action" not in deps["commands"]
        assert deps["agents"]["my-action"]["type"] == "specialist"
        assert deps["agents"]["my-action"]["path"] == "agents/my-action.md"
        assert (self.plugin_dir / "agents" / "my-action.md").exists()

    def test_promote_specialist_to_workflow(self):
        """Promote specialist → workflow: agents → skills."""
        result = run_engine(self.plugin_dir, "--promote", "my-worker", "workflow")
        assert result.returncode == 0

        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert "my-worker" in deps["skills"]
        assert "my-worker" not in deps["agents"]
        assert deps["skills"]["my-worker"]["type"] == "workflow"
        assert deps["skills"]["my-worker"]["path"] == "skills/my-worker/SKILL.md"
        assert (self.plugin_dir / "skills" / "my-worker" / "SKILL.md").exists()
        assert not (self.plugin_dir / "agents" / "my-worker.md").exists()

    def test_same_type_noop(self):
        """Promoting to the same type should report no change."""
        result = run_engine(self.plugin_dir, "--promote", "my-action", "atomic")
        assert result.returncode != 0
        assert "already type" in result.stdout

    def test_invalid_type_fails(self):
        """Unknown type should fail."""
        result = run_engine(self.plugin_dir, "--promote", "my-action", "nonexistent")
        assert result.returncode != 0
        assert "unknown type" in result.stderr

    def test_nonexistent_component_fails(self):
        """Non-existent component should fail."""
        result = run_engine(self.plugin_dir, "--promote", "ghost", "controller")
        assert result.returncode != 0
        assert "not found" in result.stderr

    def test_validate_after_promote(self):
        """twl validate should pass after promote."""
        run_engine(self.plugin_dir, "--promote", "my-workflow", "controller")
        result = run_engine(self.plugin_dir, "--validate")
        # Should not have violations from the type change itself
        assert result.returncode == 0

    def test_empty_dir_cleaned_up(self):
        """After moving from skills/{name}/SKILL.md, the empty dir should be removed."""
        run_engine(self.plugin_dir, "--promote", "my-ref", "atomic")
        assert not (self.plugin_dir / "skills" / "my-ref").exists()

    def test_preserves_other_fields(self):
        """Promote should preserve description, calls, and other fields."""
        run_engine(self.plugin_dir, "--promote", "my-action", "controller")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert deps["skills"]["my-action"]["description"] == "An atomic command"
        assert deps["skills"]["my-action"]["calls"] == []


if __name__ == "__main__":
    # Simple runner if pytest not available
    import traceback

    classes = [TestPromoteBasic]
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
