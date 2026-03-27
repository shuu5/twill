#!/usr/bin/env python3
"""Tests for Phase 2: audit/complexity data collection separation and JSON output.

Spec: openspec/changes/validate-audit-complexity-json-format/specs/phase2-audit-complexity.md

Covers:
- audit_collect() data collection separation and return value
- audit_report() backward compatibility
- audit --format json output
- complexity_collect() data collection separation and return value
- complexity_report() backward compatibility
- complexity --format json output
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from importlib import util as importlib_util

import yaml

LOOM_ENGINE = Path(__file__).parent.parent.parent / "loom-engine.py"


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


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


def _load_engine_module():
    """Import loom-engine.py as a module for direct function testing."""
    spec = importlib_util.spec_from_file_location("loom_engine", str(LOOM_ENGINE))
    mod = importlib_util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run loom-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, str(LOOM_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def _make_audit_plugin(tmpdir: Path) -> Path:
    """Create a plugin with a large controller to trigger audit warnings."""
    plugin_dir = tmpdir / "test-plugin-audit"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-audit",
        "skills": {
            "big-controller": {
                "type": "controller",
                "path": "skills/big-controller/SKILL.md",
                "description": "A large controller",
                "calls": [
                    {"atomic": "my-action"},
                ],
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
    }
    _write_deps(plugin_dir, deps)

    # Create a bloated controller (>120 body lines = warning, >200 = critical)
    skill_dir = plugin_dir / "skills" / "big-controller"
    skill_dir.mkdir(parents=True)
    body_lines = "\n".join([f"Step {i}: do something important." for i in range(186)])
    (skill_dir / "SKILL.md").write_text(
        f"---\nname: big-controller\ndescription: A large controller\n---\n\n{body_lines}\n",
        encoding="utf-8",
    )

    # Create action file
    cmd_dir = plugin_dir / "commands"
    cmd_dir.mkdir(parents=True, exist_ok=True)
    (cmd_dir / "my-action.md").write_text(
        "---\nname: my-action\ndescription: An action\n---\n\nDo the thing.\n",
        encoding="utf-8",
    )
    return plugin_dir


def _make_complexity_plugin(tmpdir: Path) -> Path:
    """Create a plugin with high fan-out to trigger complexity warnings."""
    plugin_dir = tmpdir / "test-plugin-complexity"
    plugin_dir.mkdir()

    # Create controller with many calls (fan-out > 8)
    calls = [{"atomic": f"action-{i}"} for i in range(10)]
    commands = {}
    for i in range(10):
        commands[f"action-{i}"] = {
            "type": "atomic",
            "path": f"commands/action-{i}.md",
            "description": f"Action {i}",
            "calls": [],
        }

    deps = {
        "version": "3.0",
        "plugin": "test-complexity",
        "skills": {
            "high-fanout-ctrl": {
                "type": "controller",
                "path": "skills/high-fanout-ctrl/SKILL.md",
                "description": "High fan-out controller",
                "calls": calls,
            },
        },
        "commands": commands,
        "agents": {},
        "scripts": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Test base class
# ---------------------------------------------------------------------------

class _Phase2TestBase:
    """Shared setup/teardown for phase 2 tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: audit のデータ収集関数分離
# ===========================================================================

class TestAuditCollect(_Phase2TestBase):
    """Scenario tests for audit_collect() data collection separation."""

    def test_audit_collect_returns_items_list(self):
        """Scenario: audit_collect の戻り値
        WHEN: audit_collect() を呼び出す
        THEN: items リストが返され、各要素が severity, component, message, section, value, threshold を持つ
        """
        plugin_dir = _make_audit_plugin(self.tmpdir)

        # Import and call audit_collect directly
        engine = _load_engine_module()
        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        items = engine.audit_collect(deps, plugin_dir)

        assert isinstance(items, list), "audit_collect should return a list"

        # Check that items have the required fields
        for idx, item in enumerate(items):
            assert "severity" in item, f"items[{idx}] missing 'severity'"
            assert "component" in item, f"items[{idx}] missing 'component'"
            assert "message" in item, f"items[{idx}] missing 'message'"
            assert "section" in item, f"items[{idx}] missing 'section'"
            assert "value" in item, f"items[{idx}] missing 'value'"
            assert "threshold" in item, f"items[{idx}] missing 'threshold'"

    def test_audit_report_backward_compatible(self):
        """Scenario: audit_report の後方互換
        WHEN: 既存の --audit を --format なしで実行する
        THEN: 出力が変更前と完全に同一である（テキスト形式）
        """
        plugin_dir = _make_audit_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--audit")

        # Should produce text output, not JSON
        output = result.stdout
        assert "=== Loom Compliance Audit ===" in output
        # The text output should contain table-like formatting
        assert "##" in output or "|" in output

        # Should NOT be valid JSON
        try:
            json.loads(output.strip())
            assert False, "Text output should not be valid JSON"
        except json.JSONDecodeError:
            pass


# ===========================================================================
# Requirement: audit の JSON 出力
# ===========================================================================

class TestAuditJsonOutput(_Phase2TestBase):
    """Scenario tests for audit --format json output."""

    def test_audit_json_output_with_warning(self):
        """Scenario: audit の JSON 出力
        WHEN: controller サイズ警告がある状態で --audit --format json を実行する
        THEN: items に severity: warning, section: controller_size, value, threshold を持つ要素が含まれる
        """
        plugin_dir = _make_audit_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--audit", "--format", "json")
        output = json.loads(result.stdout.strip())

        # Verify envelope structure
        assert "command" in output
        assert "items" in output
        assert "summary" in output

        # Find controller_size items
        controller_items = [
            i for i in output["items"]
            if i.get("section") == "controller_size"
        ]
        assert len(controller_items) > 0, "Should have controller_size audit items"

        for item in controller_items:
            assert "severity" in item
            assert "component" in item
            assert "message" in item
            assert "section" in item
            assert "value" in item
            assert "threshold" in item


# ===========================================================================
# Requirement: complexity のデータ収集関数分離
# ===========================================================================

class TestComplexityCollect(_Phase2TestBase):
    """Scenario tests for complexity_collect() data collection separation."""

    def test_complexity_collect_returns_items_list(self):
        """Scenario: complexity_collect の戻り値
        WHEN: complexity_collect() を呼び出す
        THEN: items リストが返され、各要素が severity, component, message, metric を持つ
        """
        plugin_dir = _make_complexity_plugin(self.tmpdir)

        engine = _load_engine_module()
        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        graph = engine.build_graph(deps, plugin_dir)
        items = engine.complexity_collect(graph, deps, plugin_dir)

        assert isinstance(items, list), "complexity_collect should return a list"

        for idx, item in enumerate(items):
            assert "severity" in item, f"items[{idx}] missing 'severity'"
            assert "component" in item, f"items[{idx}] missing 'component'"
            assert "message" in item, f"items[{idx}] missing 'message'"
            assert "metric" in item, f"items[{idx}] missing 'metric'"

    def test_complexity_report_backward_compatible(self):
        """Scenario: complexity_report の後方互換
        WHEN: 既存の --complexity を --format なしで実行する
        THEN: 出力が変更前と完全に同一である（テキスト形式）
        """
        plugin_dir = _make_complexity_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--complexity")

        output = result.stdout
        assert "=== Complexity Report ===" in output

        # Should NOT be valid JSON
        try:
            json.loads(output.strip())
            assert False, "Text output should not be valid JSON"
        except json.JSONDecodeError:
            pass


# ===========================================================================
# Requirement: complexity の JSON 出力
# ===========================================================================

class TestComplexityJsonOutput(_Phase2TestBase):
    """Scenario tests for complexity --format json output."""

    def test_complexity_json_output_with_fan_out_warning(self):
        """Scenario: complexity の JSON 出力
        WHEN: fan-out 閾値超過がある状態で --complexity --format json を実行する
        THEN: items に severity: warning, metric: fan_out, value, threshold を持つ要素が含まれる
        """
        plugin_dir = _make_complexity_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--complexity", "--format", "json")
        output = json.loads(result.stdout.strip())

        # Verify envelope structure
        assert "command" in output
        assert "items" in output
        assert "summary" in output

        # Find fan_out metric items
        fan_out_items = [
            i for i in output["items"]
            if i.get("metric") == "fan_out"
        ]
        assert len(fan_out_items) > 0, "Should have fan_out metric items"

        for item in fan_out_items:
            assert "severity" in item
            assert "component" in item
            assert "message" in item
            assert "metric" in item
