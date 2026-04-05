#!/usr/bin/env python3
"""Tests for twl rename command."""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent / "src" / "twl" / "engine.py"
TWL_CLI = Path(__file__).parent.parent / "twl"


def make_fixture(tmpdir: Path) -> Path:
    """Create a minimal plugin fixture for testing."""
    plugin_dir = tmpdir / "test-plugin"
    plugin_dir.mkdir()

    # deps.yaml
    deps = {
        "version": "2.0",
        "plugin": "test",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": [
                    {"command": "my-action"},
                    {"reference": "my-ref"},
                ],
            },
            "my-ref": {
                "type": "reference",
                "path": "skills/my-ref/SKILL.md",
                "description": "A reference skill",
                "calls": [],
            },
        },
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An atomic command",
                "calls": [],
            },
        },
        "agents": {},
    }
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )

    # skill files
    skill_dir = plugin_dir / "skills" / "my-controller"
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        "---\nname: my-controller\ndescription: Main controller\n---\n\n"
        "Use /test:my-action to do things.\n"
        "Reference: /test:my-ref\n",
        encoding="utf-8",
    )

    ref_dir = plugin_dir / "skills" / "my-ref"
    ref_dir.mkdir(parents=True)
    (ref_dir / "SKILL.md").write_text(
        "---\nname: my-ref\ndescription: A reference\n---\n\n"
        "This is a reference.\n",
        encoding="utf-8",
    )

    # command file
    cmd_dir = plugin_dir / "commands"
    cmd_dir.mkdir(parents=True)
    (cmd_dir / "my-action.md").write_text(
        "---\nname: my-action\ndescription: Action\n---\n\n"
        "Calls /test:my-ref for details.\n",
        encoding="utf-8",
    )

    return plugin_dir


def make_v3_fixture(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture with chains/step_in/chain fields."""
    plugin_dir = tmpdir / "test-plugin-v3"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "testv3",
        "chains": {
            "setup-chain": {
                "steps": ["step-a", "step-b", "step-c"],
            },
        },
        "skills": {
            "step-a": {
                "type": "workflow",
                "path": "skills/step-a/SKILL.md",
                "description": "Step A",
                "chain": "setup-chain",
                "calls": [{"command": "step-b"}],
            },
        },
        "commands": {
            "step-b": {
                "type": "atomic",
                "path": "commands/step-b.md",
                "description": "Step B",
                "chain": "setup-chain",
                "step_in": {"parent": "step-a"},
                "calls": [{"command": "step-c"}],
            },
            "step-c": {
                "type": "atomic",
                "path": "commands/step-c.md",
                "description": "Step C",
                "chain": "setup-chain",
                "step_in": {"parent": "step-b"},
                "calls": [],
            },
        },
        "agents": {},
    }
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )

    # Minimal .md files
    (plugin_dir / "skills" / "step-a").mkdir(parents=True)
    (plugin_dir / "skills" / "step-a" / "SKILL.md").write_text(
        "---\nname: step-a\n---\n\nUse /testv3:step-b next.\n", encoding="utf-8"
    )
    (plugin_dir / "commands").mkdir(parents=True)
    (plugin_dir / "commands" / "step-b.md").write_text(
        "---\nname: step-b\n---\n\nUse /testv3:step-c next.\n", encoding="utf-8"
    )
    (plugin_dir / "commands" / "step-c.md").write_text(
        "---\nname: step-c\n---\n\nFinal step.\n", encoding="utf-8"
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


class TestRenameBasic:
    """Basic rename tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_dry_run_shows_changes(self):
        result = run_engine(self.plugin_dir, "--rename", "my-action", "new-action", "--dry-run")
        assert result.returncode == 0
        assert "[dry-run]" in result.stdout
        assert "my-action" in result.stdout
        assert "new-action" in result.stdout

    def test_dry_run_no_file_changes(self):
        deps_before = (self.plugin_dir / "deps.yaml").read_text()
        run_engine(self.plugin_dir, "--rename", "my-action", "new-action", "--dry-run")
        deps_after = (self.plugin_dir / "deps.yaml").read_text()
        assert deps_before == deps_after

    def test_rename_updates_deps_key(self):
        run_engine(self.plugin_dir, "--rename", "my-action", "new-action")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert "new-action" in deps["commands"]
        assert "my-action" not in deps["commands"]

    def test_rename_updates_calls(self):
        run_engine(self.plugin_dir, "--rename", "my-action", "new-action")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        calls = deps["skills"]["my-controller"]["calls"]
        call_targets = [list(c.values())[0] for c in calls]
        assert "new-action" in call_targets
        assert "my-action" not in call_targets

    def test_rename_updates_frontmatter(self):
        run_engine(self.plugin_dir, "--rename", "my-action", "new-action")
        content = (self.plugin_dir / "commands" / "my-action.md").read_text()
        assert "name: new-action" in content

    def test_rename_updates_body_refs(self):
        run_engine(self.plugin_dir, "--rename", "my-action", "new-action")
        # Check controller body
        content = (self.plugin_dir / "skills" / "my-controller" / "SKILL.md").read_text()
        assert "/test:new-action" in content
        assert "/test:my-action" not in content

    def test_rename_nonexistent_fails(self):
        result = run_engine(self.plugin_dir, "--rename", "nonexistent", "new-name")
        assert result.returncode != 0
        assert "not found" in result.stderr

    def test_rename_to_existing_fails(self):
        result = run_engine(self.plugin_dir, "--rename", "my-action", "my-ref")
        assert result.returncode != 0
        assert "already exists" in result.stderr

    def test_validate_after_rename(self):
        run_engine(self.plugin_dir, "--rename", "my-action", "new-action")
        result = run_engine(self.plugin_dir, "--validate")
        assert "Violations: 0" in result.stdout or "All type constraints satisfied" in result.stdout


class TestRenameCoPrefixController:
    """Tests for renaming controller-* to co-* prefix."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = self._make_controller_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _make_controller_fixture(self, tmpdir: Path) -> Path:
        plugin_dir = tmpdir / "test-plugin"
        plugin_dir.mkdir()

        deps = {
            "version": "2.0",
            "plugin": "dev",
            "skills": {
                "controller-issue": {
                    "type": "controller",
                    "path": "skills/controller-issue/SKILL.md",
                    "description": "Issue management controller",
                    "calls": [
                        {"workflow": "workflow-setup"},
                    ],
                },
                "workflow-setup": {
                    "type": "workflow",
                    "path": "skills/workflow-setup/SKILL.md",
                    "description": "Setup workflow",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        (plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )

        skill_dir = plugin_dir / "skills" / "controller-issue"
        skill_dir.mkdir(parents=True)
        (skill_dir / "SKILL.md").write_text(
            "---\nname: controller-issue\ndescription: Issue management\n---\n\n"
            "Use /dev:workflow-setup to start.\n",
            encoding="utf-8",
        )

        wf_dir = plugin_dir / "skills" / "workflow-setup"
        wf_dir.mkdir(parents=True)
        (wf_dir / "SKILL.md").write_text(
            "---\nname: workflow-setup\ndescription: Setup\n---\n\n"
            "Called from /dev:controller-issue.\n",
            encoding="utf-8",
        )

        return plugin_dir

    def test_rename_controller_to_co_updates_deps_key(self):
        run_engine(self.plugin_dir, "--rename", "controller-issue", "co-issue")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert "co-issue" in deps["skills"]
        assert "controller-issue" not in deps["skills"]

    def test_rename_controller_to_co_preserves_type(self):
        run_engine(self.plugin_dir, "--rename", "controller-issue", "co-issue")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert deps["skills"]["co-issue"]["type"] == "controller"

    def test_rename_controller_to_co_updates_frontmatter(self):
        run_engine(self.plugin_dir, "--rename", "controller-issue", "co-issue")
        # ファイルは新しいパスに移動済み
        content = (self.plugin_dir / "skills" / "co-issue" / "SKILL.md").read_text()
        assert "name: co-issue" in content

    def test_rename_controller_to_co_updates_body_refs(self):
        run_engine(self.plugin_dir, "--rename", "controller-issue", "co-issue")
        content = (self.plugin_dir / "skills" / "workflow-setup" / "SKILL.md").read_text()
        assert "/dev:co-issue" in content
        assert "/dev:controller-issue" not in content

    def test_rename_controller_to_co_updates_path_and_directory(self):
        """Rename updates path field and moves directory."""
        run_engine(self.plugin_dir, "--rename", "controller-issue", "co-issue")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        # path フィールドが更新される
        assert deps["skills"]["co-issue"]["path"] == "skills/co-issue/SKILL.md"
        # ディレクトリが移動される
        assert (self.plugin_dir / "skills" / "co-issue" / "SKILL.md").exists()
        assert not (self.plugin_dir / "skills" / "controller-issue").exists()

    def test_validate_after_controller_to_co_rename(self):
        run_engine(self.plugin_dir, "--rename", "controller-issue", "co-issue")
        result = run_engine(self.plugin_dir, "--validate")
        assert "Violations: 0" in result.stdout or "All type constraints satisfied" in result.stdout


class TestRenameV3:
    """v3.0 chain-related rename tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_v3_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_rename_updates_chains_steps(self):
        run_engine(self.plugin_dir, "--rename", "step-b", "phase-b")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        steps = deps["chains"]["setup-chain"]["steps"]
        assert "phase-b" in steps
        assert "step-b" not in steps

    def test_rename_updates_step_in_parent(self):
        run_engine(self.plugin_dir, "--rename", "step-b", "phase-b")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert deps["commands"]["step-c"]["step_in"]["parent"] == "phase-b"

    def test_rename_chain_updates_chain_field(self):
        """Renaming a chain name updates all components' chain field."""
        run_engine(self.plugin_dir, "--rename", "setup-chain", "init-chain")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert "init-chain" in deps["chains"]
        assert "setup-chain" not in deps["chains"]
        assert deps["skills"]["step-a"]["chain"] == "init-chain"
        assert deps["commands"]["step-b"]["chain"] == "init-chain"
        assert deps["commands"]["step-c"]["chain"] == "init-chain"

    def test_rename_updates_body_and_step_in(self):
        run_engine(self.plugin_dir, "--rename", "step-a", "init-step")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        # step_in.parent updated
        assert deps["commands"]["step-b"]["step_in"]["parent"] == "init-step"
        # body ref updated
        # (step-a doesn't reference itself in body, so just check key renamed)
        assert "init-step" in deps["skills"]
        assert "step-a" not in deps["skills"]


def make_path_entry_points_fixture(tmpdir: Path) -> Path:
    """Create a plugin fixture with entry_points for path/entry_points/directory rename testing."""
    plugin_dir = tmpdir / "test-plugin-path"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "dev",
        "entry_points": [
            "skills/controller-project/SKILL.md",
            "skills/workflow-setup/SKILL.md",
        ],
        "skills": {
            "controller-project": {
                "type": "controller",
                "path": "skills/controller-project/SKILL.md",
                "description": "Project controller",
                "calls": [],
            },
            "workflow-setup": {
                "type": "workflow",
                "path": "skills/workflow-setup/SKILL.md",
                "description": "Setup workflow",
                "calls": [],
            },
        },
        "commands": {
            "flat-cmd": {
                "type": "atomic",
                "path": "commands/flat-cmd.md",
                "description": "A flat command",
                "calls": [],
            },
        },
        "agents": {},
    }
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )

    (plugin_dir / "skills" / "controller-project").mkdir(parents=True)
    (plugin_dir / "skills" / "controller-project" / "SKILL.md").write_text(
        "---\nname: controller-project\n---\n\nProject controller.\n",
        encoding="utf-8",
    )
    (plugin_dir / "skills" / "workflow-setup").mkdir(parents=True)
    (plugin_dir / "skills" / "workflow-setup" / "SKILL.md").write_text(
        "---\nname: workflow-setup\n---\n\nSetup workflow.\n",
        encoding="utf-8",
    )
    (plugin_dir / "commands").mkdir(parents=True)
    (plugin_dir / "commands" / "flat-cmd.md").write_text(
        "---\nname: flat-cmd\n---\n\nA flat command.\n",
        encoding="utf-8",
    )

    return plugin_dir


class TestRenamePathUpdate:
    """Tests for path field update during rename."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_path_entry_points_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_path_updated_on_rename(self):
        """Path field is updated when component name is a path component."""
        run_engine(self.plugin_dir, "--rename", "controller-project", "co-project")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert deps["skills"]["co-project"]["path"] == "skills/co-project/SKILL.md"

    def test_path_not_updated_for_flat_file(self):
        """Flat file path (commands/flat-cmd.md) is not updated since filename != component name."""
        run_engine(self.plugin_dir, "--rename", "flat-cmd", "new-cmd")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        # flat-cmd.md のファイル名は path コンポーネントではないので更新されない
        assert deps["commands"]["new-cmd"]["path"] == "commands/flat-cmd.md"

    def test_partial_match_does_not_affect_bystander(self):
        """Renaming co-auto does not affect co-autopilot's path."""
        # Create a fixture with similar names
        plugin_dir = self.tmpdir / "partial-plugin"
        plugin_dir.mkdir()
        deps = {
            "version": "2.0",
            "plugin": "dev",
            "skills": {
                "co-auto": {
                    "type": "atomic",
                    "path": "skills/co-auto/SKILL.md",
                    "description": "Auto",
                    "calls": [],
                },
                "co-autopilot": {
                    "type": "controller",
                    "path": "skills/co-autopilot/SKILL.md",
                    "description": "Autopilot",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        (plugin_dir / "deps.yaml").write_text(
            yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding="utf-8",
        )
        (plugin_dir / "skills" / "co-auto").mkdir(parents=True)
        (plugin_dir / "skills" / "co-auto" / "SKILL.md").write_text(
            "---\nname: co-auto\n---\n\nAuto.\n", encoding="utf-8"
        )
        (plugin_dir / "skills" / "co-autopilot").mkdir(parents=True)
        (plugin_dir / "skills" / "co-autopilot" / "SKILL.md").write_text(
            "---\nname: co-autopilot\n---\n\nAutopilot.\n", encoding="utf-8"
        )

        run_engine(plugin_dir, "--rename", "co-auto", "co-automatic")
        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        # co-autopilot の path は変更されない
        assert deps["skills"]["co-autopilot"]["path"] == "skills/co-autopilot/SKILL.md"
        # co-automatic の path は更新される
        assert deps["skills"]["co-automatic"]["path"] == "skills/co-automatic/SKILL.md"

    def test_dry_run_shows_path_change(self):
        result = run_engine(
            self.plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        assert result.returncode == 0
        assert "path:" in result.stdout
        assert "skills/controller-project/SKILL.md" in result.stdout
        assert "skills/co-project/SKILL.md" in result.stdout


class TestRenameEntryPoints:
    """Tests for entry_points list update during rename."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_path_entry_points_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_entry_points_updated_on_rename(self):
        run_engine(self.plugin_dir, "--rename", "controller-project", "co-project")
        deps = yaml.safe_load((self.plugin_dir / "deps.yaml").read_text())
        assert "skills/co-project/SKILL.md" in deps["entry_points"]
        assert "skills/controller-project/SKILL.md" not in deps["entry_points"]
        # Other entry_points unchanged
        assert "skills/workflow-setup/SKILL.md" in deps["entry_points"]

    def test_no_error_when_entry_points_undefined(self):
        """Renaming succeeds when deps.yaml has no entry_points key."""
        result = run_engine(
            make_fixture(self.tmpdir), "--rename", "my-action", "new-action"
        )
        assert result.returncode == 0

    def test_dry_run_shows_entry_points_change(self):
        result = run_engine(
            self.plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        assert result.returncode == 0
        assert "entry_points:" in result.stdout


class TestRenameDirectory:
    """Tests for directory rename during component rename."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_path_entry_points_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_directory_renamed(self):
        run_engine(self.plugin_dir, "--rename", "controller-project", "co-project")
        assert (self.plugin_dir / "skills" / "co-project" / "SKILL.md").exists()
        assert not (self.plugin_dir / "skills" / "controller-project").exists()

    def test_directory_content_preserved(self):
        """File content is preserved after directory rename."""
        run_engine(self.plugin_dir, "--rename", "controller-project", "co-project")
        content = (self.plugin_dir / "skills" / "co-project" / "SKILL.md").read_text()
        assert "name: co-project" in content  # frontmatter updated
        assert "Project controller." in content  # body preserved

    def test_destination_exists_error(self):
        """Error when destination directory already exists."""
        # Create destination directory beforehand
        (self.plugin_dir / "skills" / "co-project").mkdir(parents=True)
        result = run_engine(self.plugin_dir, "--rename", "controller-project", "co-project")
        assert result.returncode != 0
        assert "already exists" in result.stderr

    def test_flat_file_no_directory_rename(self):
        """Flat file commands are not affected by directory rename."""
        run_engine(self.plugin_dir, "--rename", "flat-cmd", "new-cmd")
        # File stays at original location (no directory to rename)
        assert (self.plugin_dir / "commands" / "flat-cmd.md").exists()

    def test_dry_run_shows_directory_change(self):
        result = run_engine(
            self.plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        assert result.returncode == 0
        assert "directory:" in result.stdout
        # Directory not actually moved
        assert (self.plugin_dir / "skills" / "controller-project" / "SKILL.md").exists()

    def test_validate_after_directory_rename(self):
        run_engine(self.plugin_dir, "--rename", "controller-project", "co-project")
        result = run_engine(self.plugin_dir, "--validate")
        assert "Violations: 0" in result.stdout or "All type constraints satisfied" in result.stdout


if __name__ == "__main__":
    # Simple runner if pytest not available
    import traceback

    classes = [
        TestRenameBasic, TestRenameCoPrefixController, TestRenameV3,
        TestRenamePathUpdate, TestRenameEntryPoints, TestRenameDirectory,
    ]
    passed = 0
    failed = 0
    errors = []

    for cls in classes:
        for method_name in dir(cls):
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
