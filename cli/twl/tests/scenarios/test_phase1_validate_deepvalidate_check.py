#!/usr/bin/env python3
"""Tests for Phase 1: validate/deep-validate/check JSON output.

Spec: deltaspec/changes/validate-audit-complexity-json-format/specs/phase1-validate-deepvalidate-check.md

Covers:
- validate JSON output (violations, clean state, chain_validate integration)
- deep-validate JSON output (warnings, criticals)
- check JSON output (ok files, missing files, chain_validate integration)
"""

import json
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


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def _make_valid_plugin(tmpdir: Path, name: str = "valid") -> Path:
    """Create a valid v3.0 plugin with no violations."""
    plugin_dir = tmpdir / f"test-plugin-{name}"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": f"test-{name}",
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
                "calls": [],
            },
        },
        "agents": {},
        "scripts": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def _make_type_violation_plugin(tmpdir: Path) -> Path:
    """Create a plugin with type rule violations (controller in wrong section)."""
    plugin_dir = tmpdir / "test-plugin-type-violation"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-type-violation",
        "commands": {
            "misplaced-controller": {
                "type": "controller",
                "path": "commands/misplaced-controller.md",
                "description": "Controller in wrong section",
                "calls": [],
            },
        },
        "skills": {},
        "agents": {},
        "scripts": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def _make_bloated_controller_plugin(tmpdir: Path) -> Path:
    """Create a plugin with a controller that has many lines (triggers deep-validate warning)."""
    plugin_dir = tmpdir / "test-plugin-bloated"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-bloated",
        "skills": {
            "bloated-controller": {
                "type": "controller",
                "path": "skills/bloated-controller/SKILL.md",
                "description": "Bloated controller",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
        "scripts": {},
    }
    _write_deps(plugin_dir, deps)

    # Create a bloated controller file (>120 lines body to trigger warning, but <=200 to avoid critical)
    skill_dir = plugin_dir / "skills" / "bloated-controller"
    skill_dir.mkdir(parents=True)
    body_lines = "\n".join([f"Line {i} of bloated controller content." for i in range(150)])
    (skill_dir / "SKILL.md").write_text(
        f"---\nname: bloated-controller\ndescription: Test\n---\n\n{body_lines}\n",
        encoding="utf-8",
    )
    return plugin_dir


def _make_missing_file_plugin(tmpdir: Path) -> Path:
    """Create a plugin where a component's file is missing."""
    plugin_dir = tmpdir / "test-plugin-missing"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-missing",
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
                "calls": [],
            },
        },
        "agents": {},
        "scripts": {},
    }
    _write_deps(plugin_dir, deps)
    # Only create controller file, NOT the command file -> missing
    skill_dir = plugin_dir / "skills" / "my-controller"
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        "---\nname: my-controller\ndescription: Test\n---\n\nContent.\n",
        encoding="utf-8",
    )
    return plugin_dir


def _make_chain_violation_plugin(tmpdir: Path) -> Path:
    """Create a v3.0 plugin with chain validation violations."""
    plugin_dir = tmpdir / "test-plugin-chain-violation"
    plugin_dir.mkdir()

    # v3.0 with chain that references non-existent steps
    deps = {
        "version": "3.0",
        "plugin": "test-chain-violation",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": [
                    {"atomic": "my-action"},
                ],
                "chains": ["my-chain"],
            },
        },
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An action",
                "calls": [],
            },
        },
        "agents": {},
        "scripts": {},
        "chains": {
            "my-chain": {
                "steps": [
                    {"command": "nonexistent-step"},
                ],
            },
        },
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)

    # Create chain file
    chains_dir = plugin_dir / "chains"
    chains_dir.mkdir(parents=True, exist_ok=True)
    (chains_dir / "my-chain.yaml").write_text(
        yaml.dump({"steps": [{"command": "nonexistent-step"}]}, default_flow_style=False),
        encoding="utf-8",
    )
    return plugin_dir


# ---------------------------------------------------------------------------
# Test base class
# ---------------------------------------------------------------------------

class _Phase1TestBase:
    """Shared setup/teardown for phase 1 tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: validate の JSON 出力
# ===========================================================================

class TestValidateJsonOutput(_Phase1TestBase):
    """Scenario tests for validate --format json output."""

    def test_validate_violations_json_output(self):
        """Scenario: validate violations の JSON 出力
        WHEN: 型ルール違反がある状態で --validate --format json を実行する
        THEN: items に severity, component, message, code フィールドを持つ要素が含まれる
        """
        plugin_dir = _make_type_violation_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")
        output = json.loads(result.stdout.strip())

        assert len(output["items"]) > 0, "items should not be empty when violations exist"

        # Check that at least one item has the expected structure
        violation_items = [i for i in output["items"] if i.get("severity") == "critical"]
        assert len(violation_items) > 0, "Should have at least one critical item"

        for item in violation_items:
            assert "severity" in item
            assert "component" in item
            assert "message" in item
            assert "code" in item, "validate items should include 'code' field"

    def test_validate_clean_json_output(self):
        """Scenario: validate 正常時の JSON 出力
        WHEN: 全型ルールが満たされた状態で --validate --format json を実行する
        THEN: items が空配列で、summary.total が 0、exit_code が 0 となる
        """
        plugin_dir = _make_valid_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")
        output = json.loads(result.stdout.strip())

        assert output["items"] == [], f"items should be empty but got {output['items']}"
        assert output["summary"]["total"] == 0
        assert output["exit_code"] == 0

    def test_validate_chain_results_integrated(self):
        """Scenario: chain_validate の結果統合
        WHEN: chain 検証で warning がある状態で --validate --format json を実行する
        THEN: items に chain 由来の warning も含まれる
        """
        plugin_dir = _make_chain_violation_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")
        output = json.loads(result.stdout.strip())

        # Should have items from chain validation
        assert len(output["items"]) > 0, "items should not be empty when chain violations exist"


# ===========================================================================
# Requirement: deep-validate の JSON 出力
# ===========================================================================

class TestDeepValidateJsonOutput(_Phase1TestBase):
    """Scenario tests for deep-validate --format json output."""

    def test_deep_validate_warning_json_output(self):
        """Scenario: deep-validate の JSON 出力
        WHEN: controller bloat 警告がある状態で --deep-validate --format json を実行する
        THEN: items に severity: warning, check フィールドを持つ要素が含まれる
        """
        plugin_dir = _make_bloated_controller_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--deep-validate", "--format", "json")
        output = json.loads(result.stdout.strip())

        warning_items = [i for i in output["items"] if i.get("severity") == "warning"]
        assert len(warning_items) > 0, "Should have at least one warning item for bloated controller"

        for item in warning_items:
            assert "check" in item, "deep-validate items should include 'check' field"
            assert "severity" in item
            assert "component" in item
            assert "message" in item

    def test_deep_validate_criticals_json_output(self):
        """Scenario: deep-validate criticals の JSON 出力
        WHEN: critical な深層違反がある状態で --deep-validate --format json を実行する
        THEN: items に severity: critical の要素が含まれ、exit_code が 1 となる
        """
        # Use type violation plugin which will cause critical violations in deep-validate
        plugin_dir = _make_type_violation_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--deep-validate", "--format", "json")
        output = json.loads(result.stdout.strip())

        critical_items = [i for i in output["items"] if i.get("severity") == "critical"]
        assert len(critical_items) > 0, "Should have at least one critical item"
        assert output["exit_code"] == 1


# ===========================================================================
# Requirement: check の JSON 出力
# ===========================================================================

class TestCheckJsonOutput(_Phase1TestBase):
    """Scenario tests for check --format json output."""

    def test_check_ok_files_json_output(self):
        """Scenario: check の正常系 JSON 出力
        WHEN: 全ファイルが存在する状態で --check --format json を実行する
        THEN: items に severity: ok, path, status: ok の要素が含まれる
        """
        plugin_dir = _make_valid_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--check", "--format", "json")
        output = json.loads(result.stdout.strip())

        ok_items = [i for i in output["items"] if i.get("severity") == "ok"]
        assert len(ok_items) > 0, "Should have ok items when all files exist"

        for item in ok_items:
            assert "path" in item, "check items should include 'path' field"
            assert "status" in item, "check items should include 'status' field"
            assert item["status"] == "ok"
            assert "component" in item
            assert "message" in item

    def test_check_missing_files_json_output(self):
        """Scenario: check の missing ファイル JSON 出力
        WHEN: ファイルが欠損している状態で --check --format json を実行する
        THEN: items に severity: critical, status: missing の要素が含まれ、exit_code が 1 となる
        """
        plugin_dir = _make_missing_file_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--check", "--format", "json")
        output = json.loads(result.stdout.strip())

        missing_items = [i for i in output["items"] if i.get("status") == "missing"]
        assert len(missing_items) > 0, "Should have missing items when files are absent"

        for item in missing_items:
            assert item["severity"] == "critical"
            assert "path" in item
            assert "component" in item
            assert "message" in item

        assert output["exit_code"] == 1

    def test_check_chain_validate_integration(self):
        """Scenario: check で chain_validate の結果統合
        WHEN: v3.0 deps.yaml で chain 違反がある状態で --check --format json を実行する
        THEN: items にファイル存在チェック結果と chain 検証結果の両方が含まれる
        """
        plugin_dir = _make_chain_violation_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--check", "--format", "json")
        output = json.loads(result.stdout.strip())

        # Should have both file check results and chain validation results
        assert len(output["items"]) > 0, "items should not be empty"

        # Check that file existence items are present (at least the valid files)
        has_file_items = any(
            "status" in i and i["status"] in ("ok", "missing") for i in output["items"]
        )
        assert has_file_items, "Should have file existence check items"
