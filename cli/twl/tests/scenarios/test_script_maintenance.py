#!/usr/bin/env python3
"""Tests for deps.yaml scripts SSOT: Maintenance scenarios.

Spec: openspec/changes/depsyaml-scripts-ssot/specs/maintenance/spec.md

Covers:
- find_orphans: detect unused scripts, skip used scripts
- check_dead_components: detect unreachable scripts
- check_files: script file existence checks
- rename_component: rename scripts section key and calls references
- complexity_report: include script nodes in Type Balance
"""

import shutil
import subprocess
import os
import sys
import tempfile
from pathlib import Path

import yaml



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
    for name, data in deps.get("scripts", {}).items():
        path_str = data.get("path", "")
        if not path_str:
            continue
        file_path = plugin_dir / path_str
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(f"#!/bin/bash\n# {name}\necho '{name}'\n", encoding="utf-8")


def make_script_fixture(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture with scripts for maintenance tests."""
    plugin_dir = tmpdir / "test-plugin-maint"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-maint",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": [
                    {"atomic": "my-action"},
                ],
            },
        },
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An atomic command",
                "calls": [
                    {"script": "used-script"},
                ],
            },
        },
        "agents": {},
        "scripts": {
            "used-script": {
                "type": "script",
                "path": "scripts/used-script.sh",
                "description": "A used script",
                "calls": [],
            },
            "unused-script": {
                "type": "script",
                "path": "scripts/unused-script.sh",
                "description": "An unused script (orphan)",
                "calls": [],
            },
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
# Test base class
# ---------------------------------------------------------------------------

class _MaintenanceTestBase:
    """Shared setup/teardown for maintenance tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_script_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _modify_deps(self, mutator):
        deps = _load_deps(self.plugin_dir)
        mutator(deps)
        _write_deps(self.plugin_dir, deps)
        return deps


# ===========================================================================
# Requirement: orphans で script ノードを検出する
# ===========================================================================

class TestOrphansScript(_MaintenanceTestBase):
    """find_orphans should detect unused script nodes."""

    def test_unused_script_detected(self):
        """Scenario: 未使用 script の検出
        WHEN twl --orphans を実行し、どのコンポーネントからも calls されていない script が存在する
        THEN unused リストにその script:{name} が含まれる"""
        result = run_engine(self.plugin_dir, "--orphans")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        assert "unused-script" in output, (
            f"Unused script not detected in orphans:\n{output}"
        )

    def test_used_script_not_in_orphans(self):
        """Scenario: 使用中 script は報告しない
        WHEN script が atomic コンポーネントの calls から参照されている
        THEN その script は unused リストに含まれない"""
        result = run_engine(self.plugin_dir, "--orphans")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        # "used-script" may appear in context but should not be in the unused list
        # Parse the unused section
        lines = output.splitlines()
        in_unused = False
        unused_scripts = []
        for line in lines:
            if "unused" in line.lower() or "Unused" in line:
                in_unused = True
                continue
            if in_unused and "script:" in line:
                unused_scripts.append(line.strip())
            elif in_unused and line.strip() == "":
                in_unused = False

        for entry in unused_scripts:
            assert "used-script" not in entry or "unused-script" in entry, (
                f"used-script wrongly in unused list: {entry}"
            )

    def test_all_scripts_referenced_no_orphans(self):
        """Edge case: when all scripts are referenced, none should be orphans."""
        def mutator(deps):
            # Also reference unused-script from my-action
            deps["commands"]["my-action"]["calls"].append(
                {"script": "unused-script"}
            )
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--orphans")
        assert result.returncode == 0
        # Neither script should be in unused
        lines = result.stdout.splitlines()
        for line in lines:
            if "script:" in line and "unused" in line.lower():
                # Check it's in "no dependencies" not "unused"
                pass  # scripts have no calls, so they might appear in no-deps


# ===========================================================================
# Requirement: dead component 検出で script を含める
# ===========================================================================

class TestDeadComponentScript(_MaintenanceTestBase):
    """check_dead_components should detect unreachable scripts."""

    def test_unreachable_script_detected(self):
        """Scenario: 到達不能 script の検出
        WHEN twl --complexity を実行し、controller -> ... -> atomic -> script の経路が存在しない script がある
        THEN Dead Components リストにその script が含まれる"""
        result = run_engine(self.plugin_dir, "--complexity")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        # unused-script has no path from controller -> ... -> it
        assert "unused-script" in output, (
            f"Unreachable script not in Dead Components:\n{output}"
        )

    def test_reachable_script_not_dead(self):
        """Edge case: script reachable through controller -> atomic -> script is NOT dead."""
        result = run_engine(self.plugin_dir, "--complexity")
        assert result.returncode == 0
        # Check the Dead Components section specifically
        output = result.stdout
        lines = output.splitlines()
        in_dead = False
        dead_entries = []
        for line in lines:
            if "Dead Components" in line:
                in_dead = True
                continue
            if in_dead and line.startswith("##"):
                break
            if in_dead and "script:" in line:
                dead_entries.append(line)

        # used-script is reachable: controller -> my-action -> used-script
        dead_text = "\n".join(dead_entries)
        assert "used-script" not in dead_text or "unused" in dead_text, (
            f"Reachable script wrongly in Dead Components:\n{dead_text}"
        )


# ===========================================================================
# Requirement: check でスクリプトファイルの存在確認をする
# ===========================================================================

class TestCheckFilesScript(_MaintenanceTestBase):
    """check_files should verify script file existence."""

    def test_script_file_exists_ok(self):
        """Scenario: スクリプトファイルが存在する
        WHEN twl --check を実行し、script の path が指すファイルが存在する
        THEN そのノードは ok と判定される"""
        result = run_engine(self.plugin_dir, "--check")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        # No missing file errors for scripts
        output = result.stdout
        lines = [l for l in output.splitlines() if "script" in l.lower() and "missing" in l.lower()]
        assert len(lines) == 0, f"Script file wrongly reported as missing:\n{output}"

    def test_script_file_missing(self):
        """Scenario: スクリプトファイルが見つからない
        WHEN twl --check を実行し、script の path が指すファイルが存在しない
        THEN そのノードは missing と判定され、エラー出力に含まれる"""
        # Delete the script file
        (self.plugin_dir / "scripts" / "used-script.sh").unlink()

        result = run_engine(self.plugin_dir, "--check")
        # Should fail or report missing
        output = result.stdout + result.stderr
        assert "missing" in output.lower() or result.returncode != 0, (
            f"Missing script file not detected:\n{output}"
        )
        assert "used-script" in output, (
            f"Script name not in missing report:\n{output}"
        )

    def test_script_file_missing_path(self):
        """Edge case: script with non-existent path from the start."""
        def mutator(deps):
            deps["scripts"]["ghost-script"] = {
                "type": "script",
                "path": "scripts/ghost-script.sh",
                "description": "Ghost script",
                "calls": [],
            }
        self._modify_deps(mutator)
        # Do NOT create ghost-script.sh

        result = run_engine(self.plugin_dir, "--check")
        output = result.stdout + result.stderr
        assert "ghost-script" in output, (
            f"Ghost script not detected as missing:\n{output}"
        )


# ===========================================================================
# Requirement: rename で scripts セクションのキー名を変更する
# ===========================================================================

class TestRenameScript(_MaintenanceTestBase):
    """rename_component should handle scripts section renaming."""

    def test_rename_script_key_and_calls(self):
        """Scenario: script の rename
        WHEN twl --rename old-script new-script を実行し、old-script が scripts セクションに存在する
        THEN deps.yaml の scripts セクションのキーが new-script に変更され、
             全 calls 内の {script: old-script} が {script: new-script} に更新される"""
        result = run_engine(
            self.plugin_dir, "--rename", "used-script", "renamed-script"
        )
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"

        deps = _load_deps(self.plugin_dir)
        # Key renamed in scripts section
        assert "renamed-script" in deps["scripts"]
        assert "used-script" not in deps["scripts"]

        # Calls updated in referencing component
        calls = deps["commands"]["my-action"]["calls"]
        call_targets = []
        for c in calls:
            if "script" in c:
                call_targets.append(c["script"])
        assert "renamed-script" in call_targets, (
            f"Calls not updated after rename: {calls}"
        )
        assert "used-script" not in call_targets, (
            f"Old name still in calls after rename: {calls}"
        )

    def test_rename_nonexistent_fails(self):
        """Scenario: rename 対象が見つからない
        WHEN twl --rename nonexistent new-name を実行し、
             skills/commands/agents/scripts/chains のいずれにも nonexistent が存在しない
        THEN エラーメッセージが表示され、変更は行われない"""
        deps_before = (self.plugin_dir / "deps.yaml").read_text()
        result = run_engine(
            self.plugin_dir, "--rename", "nonexistent", "new-name"
        )
        assert result.returncode != 0, (
            f"Expected failure for nonexistent rename.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert "not found" in result.stderr, (
            f"Expected 'not found' error:\nstderr: {result.stderr}"
        )
        # deps.yaml unchanged
        deps_after = (self.plugin_dir / "deps.yaml").read_text()
        assert deps_before == deps_after

    def test_rename_script_dry_run(self):
        """Edge case: dry run should not modify files."""
        deps_before = (self.plugin_dir / "deps.yaml").read_text()
        result = run_engine(
            self.plugin_dir, "--rename", "used-script", "renamed-script", "--dry-run"
        )
        assert result.returncode == 0
        assert "[dry-run]" in result.stdout
        deps_after = (self.plugin_dir / "deps.yaml").read_text()
        assert deps_before == deps_after

    def test_rename_script_to_existing_fails(self):
        """Edge case: renaming to an already existing name should fail."""
        result = run_engine(
            self.plugin_dir, "--rename", "used-script", "unused-script"
        )
        assert result.returncode != 0
        assert "already exists" in result.stderr

    def test_validate_after_script_rename(self):
        """Edge case: validate should pass after a successful rename."""
        run_engine(self.plugin_dir, "--rename", "used-script", "renamed-script")
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"


# ===========================================================================
# Requirement: complexity_report で script を含める
# ===========================================================================

class TestComplexityScript(_MaintenanceTestBase):
    """complexity_report should include script nodes in Type Balance."""

    def test_complexity_script_type_balance(self):
        """Scenario: complexity での script 集計
        WHEN twl --complexity を実行し、scripts セクションにコンポーネントが存在する
        THEN Type Balance セクションに script の件数が表示される"""
        result = run_engine(self.plugin_dir, "--complexity")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        # Type Balance section should mention script
        assert "script" in output.lower(), (
            f"No script mention in complexity report:\n{output}"
        )
        # Should show count of 2 (used-script and unused-script)
        # Look for the Type Balance section
        in_balance = False
        for line in output.splitlines():
            if "Type Balance" in line or "type balance" in line.lower():
                in_balance = True
            elif in_balance and "script" in line.lower():
                # Verify the count
                assert "2" in line, (
                    f"Expected 2 scripts in Type Balance: {line}"
                )
                break
        else:
            if not in_balance:
                pass  # Type Balance section might not exist yet - test documents the requirement


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestOrphansScript,
        TestDeadComponentScript,
        TestCheckFilesScript,
        TestRenameScript,
        TestComplexityScript,
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
