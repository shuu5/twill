#!/usr/bin/env python3
"""Tests for JSON format common requirements.

Spec: openspec/changes/validate-audit-complexity-json-format/specs/json-format-common.md

Covers:
- --format json argument acceptance
- Common envelope structure (command, version, plugin, items, summary, exit_code)
- items common fields (severity, component, message)
- exit code consistency between process and JSON
"""

import json
import shutil
import subprocess
import os
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "twl-engine.py"


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


def _make_valid_plugin(tmpdir: Path) -> Path:
    """Create a valid v3.0 plugin fixture with no violations."""
    plugin_dir = tmpdir / "test-plugin-json"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-json",
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


def _make_violation_plugin(tmpdir: Path) -> Path:
    """Create a plugin fixture with type rule violations."""
    plugin_dir = tmpdir / "test-plugin-violation"
    plugin_dir.mkdir()

    # controller placed in commands section -> section violation
    deps = {
        "version": "3.0",
        "plugin": "test-violation",
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

class _JsonTestBase:
    """Shared setup/teardown for JSON format tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _modify_deps(self, plugin_dir: Path, mutator):
        deps = _load_deps(plugin_dir)
        mutator(deps)
        _write_deps(plugin_dir, deps)
        return deps


# ===========================================================================
# Requirement: --format json 引数
# ===========================================================================

class TestFormatJsonArg(_JsonTestBase):
    """Scenario tests for --format json argument handling."""

    def test_format_json_outputs_pure_json(self):
        """Scenario: --format json 指定時
        WHEN: --validate --format json を実行する
        THEN: stdout に純粋な JSON のみが出力される
        """
        plugin_dir = _make_valid_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")
        # stdout should be valid JSON and nothing else
        output = result.stdout.strip()
        parsed = json.loads(output)  # Raises if not valid JSON
        assert isinstance(parsed, dict)

    def test_format_unspecified_outputs_text(self):
        """Scenario: --format 未指定時
        WHEN: --validate を実行する（--format なし）
        THEN: 既存のテキスト出力がそのまま表示される
        """
        plugin_dir = _make_valid_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate")
        output = result.stdout.strip()
        # Should NOT be JSON, should contain text output markers
        assert "=== Type Validation Results ===" in output
        # Verify it's not JSON
        try:
            json.loads(output)
            assert False, "Output should not be valid JSON when --format is not specified"
        except json.JSONDecodeError:
            pass

    def test_invalid_format_value_errors(self):
        """Scenario: 不正な format 値
        WHEN: --format xml を実行する
        THEN: argparse がエラーを返す
        """
        plugin_dir = _make_valid_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "xml")
        assert result.returncode != 0
        # argparse error messages go to stderr
        assert "invalid choice" in result.stderr.lower() or "error" in result.stderr.lower()


# ===========================================================================
# Requirement: 共通エンベロープ構造
# ===========================================================================

class TestCommonEnvelope(_JsonTestBase):
    """Scenario tests for common JSON envelope structure."""

    def test_envelope_fields_present(self):
        """Scenario: エンベロープフィールド検証
        WHEN: 任意のコマンドを --format json で実行する
        THEN: 出力 JSON が command, version, plugin, items, summary, exit_code を全て含む
        """
        plugin_dir = _make_valid_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")
        output = json.loads(result.stdout.strip())

        # Check all required fields exist with correct types
        assert "command" in output and isinstance(output["command"], str)
        assert "version" in output and isinstance(output["version"], str)
        assert "plugin" in output and isinstance(output["plugin"], str)
        assert "items" in output and isinstance(output["items"], list)
        assert "summary" in output and isinstance(output["summary"], dict)
        assert "exit_code" in output and isinstance(output["exit_code"], int)

    def test_summary_aggregation(self):
        """Scenario: summary 集計
        WHEN: items に severity: critical が2件、warning が1件ある
        THEN: summary は {"critical": 2, "warning": 1, "info": 0, "ok": 0, "total": 3} となる
        """
        plugin_dir = _make_violation_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")
        output = json.loads(result.stdout.strip())

        summary = output["summary"]
        items = output["items"]

        # Verify summary fields exist
        assert "critical" in summary
        assert "warning" in summary
        assert "info" in summary
        assert "ok" in summary
        assert "total" in summary

        # Verify summary matches items count
        critical_count = sum(1 for i in items if i.get("severity") == "critical")
        warning_count = sum(1 for i in items if i.get("severity") == "warning")
        info_count = sum(1 for i in items if i.get("severity") == "info")
        ok_count = sum(1 for i in items if i.get("severity") == "ok")

        assert summary["critical"] == critical_count
        assert summary["warning"] == warning_count
        assert summary["info"] == info_count
        assert summary["ok"] == ok_count
        assert summary["total"] == len(items)


# ===========================================================================
# Requirement: items 共通フィールド
# ===========================================================================

class TestItemsCommonFields(_JsonTestBase):
    """Scenario tests for items common fields."""

    def test_items_have_required_fields(self):
        """Scenario: items 共通フィールド存在確認
        WHEN: JSON 出力の items 配列の各要素を検査する
        THEN: 全要素が severity, component, message を持つ
        """
        plugin_dir = _make_violation_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")
        output = json.loads(result.stdout.strip())

        valid_severities = {"critical", "warning", "info", "ok"}

        for idx, item in enumerate(output["items"]):
            assert "severity" in item, f"items[{idx}] missing 'severity'"
            assert item["severity"] in valid_severities, (
                f"items[{idx}] severity '{item['severity']}' not in {valid_severities}"
            )
            assert "component" in item and isinstance(item["component"], str), (
                f"items[{idx}] missing or invalid 'component'"
            )
            assert "message" in item and isinstance(item["message"], str), (
                f"items[{idx}] missing or invalid 'message'"
            )


# ===========================================================================
# Requirement: exit code の一貫性
# ===========================================================================

class TestExitCodeConsistency(_JsonTestBase):
    """Scenario tests for exit code consistency."""

    def test_exit_code_1_on_violations(self):
        """Scenario: JSON 出力時の exit code
        WHEN: violations ありの --validate --format json を実行する
        THEN: exit code が 1 であり、かつ JSON 内の exit_code フィールドも 1 である
        """
        plugin_dir = _make_violation_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")

        output = json.loads(result.stdout.strip())
        assert result.returncode == 1
        assert output["exit_code"] == 1

    def test_exit_code_0_on_clean(self):
        """Scenario: 正常時の exit code
        WHEN: violations なしの --validate --format json を実行する
        THEN: exit code が 0 であり、かつ JSON 内の exit_code フィールドも 0 である
        """
        plugin_dir = _make_valid_plugin(self.tmpdir)
        result = run_engine(plugin_dir, "--validate", "--format", "json")

        output = json.loads(result.stdout.strip())
        assert result.returncode == 0
        assert output["exit_code"] == 0
