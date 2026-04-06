#!/usr/bin/env python3
"""Tests for output_schema field validation in deep_validate().

Spec: deltaspec/changes/tech-debt-deepvalidate-outputschema/specs/output-schema-validation.md

Requirement: output_schema 空文字列の検出

Coverage: edge-cases
- Scenario: 空文字列の output_schema
- Scenario: 有効な custom 値
- Scenario: 未宣言（None）
- Scenario: その他の無効な値
"""

import shutil
import subprocess
import os
import sys
import tempfile
from pathlib import Path
from typing import Dict, Optional

import yaml



# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _create_specialist_body(plugin_dir: Path, agent_name: str, body: str) -> None:
    """Create a specialist agent .md file with the given body text."""
    agent_dir = plugin_dir / "agents" / agent_name
    agent_dir.mkdir(parents=True, exist_ok=True)
    (agent_dir / "AGENT.md").write_text(
        f"---\nname: {agent_name}\ndescription: Test specialist\n---\n\n{body}\n",
        encoding="utf-8",
    )


def make_specialist_fixture(
    tmpdir: Path,
    *,
    body: str = (
        "## Purpose\nAnalyze code.\n\n"
        "## Output\nReturn PASS or FAIL.\n\n"
        "## Constraint\nMUST NOT skip.\n\n"
        "findings: list\nseverity: high/low\nconfidence: 0.0-1.0\n"
    ),
    output_schema: Optional[str] = None,
    set_output_schema: bool = False,
    agent_name: str = "my-specialist",
) -> Path:
    """Create a plugin fixture with a single specialist agent.

    Args:
        body: The body text of the specialist's AGENT.md
        output_schema: Value to set for output_schema field (only used if set_output_schema=True)
        set_output_schema: Whether to include output_schema in deps.yaml at all
        agent_name: Name of the specialist agent
    """
    plugin_dir = tmpdir / "test-plugin-schema"
    plugin_dir.mkdir(exist_ok=True)

    agent_spec: Dict = {
        "type": "specialist",
        "path": f"agents/{agent_name}/AGENT.md",
        "description": "Test specialist agent",
        "calls": [],
    }
    if set_output_schema:
        agent_spec["output_schema"] = output_schema

    deps = {
        "version": "3.0",
        "plugin": "test-schema",
        "skills": {
            "main-controller": {
                "type": "controller",
                "path": "skills/main-controller/SKILL.md",
                "description": "Main controller",
                "calls": [{"specialist": agent_name}],
            },
        },
        "commands": {},
        "agents": {
            agent_name: agent_spec,
        },
    }
    _write_deps(plugin_dir, deps)

    # Create controller file
    ctrl_dir = plugin_dir / "skills" / "main-controller"
    ctrl_dir.mkdir(parents=True, exist_ok=True)
    (ctrl_dir / "SKILL.md").write_text(
        "---\nname: main-controller\ndescription: Controller\n---\n\n## Step 0\nRoute.\n",
        encoding="utf-8",
    )

    # Create specialist body
    _create_specialist_body(plugin_dir, agent_name, body)

    return plugin_dir


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py with the given arguments."""
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Test base class with setup/teardown
# ---------------------------------------------------------------------------

class _OutputSchemaTestBase:
    """Shared setup/teardown for output_schema validation tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: output_schema 空文字列の検出
# ===========================================================================

class TestOutputSchemaValidation(_OutputSchemaTestBase):
    """deep_validate() section E validates the output_schema field value."""

    # --- Scenario: 空文字列の output_schema ---

    def test_empty_string_output_schema_reports_empty_warning(self):
        """Scenario: 空文字列の output_schema
        WHEN specialist コンポーネントが output_schema: "" を宣言している
        THEN [specialist-output-schema] {cname}: empty output_schema value (expected 'custom' or omit) 警告が出力される
        """
        body = (
            "## Purpose\nAnalyze code.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "findings: list\nseverity: high/low\nconfidence: 0.0-1.0\n"
        )
        plugin_dir = make_specialist_fixture(
            self.tmpdir, body=body, output_schema="", set_output_schema=True
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected [specialist-output-schema] warning but got:\n{result.stdout}"
        )
        assert "my-specialist" in result.stdout, (
            f"Expected component name in warning but got:\n{result.stdout}"
        )
        assert "empty output_schema value" in result.stdout, (
            f"Expected 'empty output_schema value' message but got:\n{result.stdout}"
        )

    # --- Scenario: 有効な custom 値 ---

    def test_custom_output_schema_no_warning(self):
        """Scenario: 有効な custom 値
        WHEN specialist コンポーネントが output_schema: custom を宣言している
        THEN output_schema 関連の警告は出力されない
        """
        # Body intentionally missing keywords — custom skips validation entirely
        body = "## Purpose\nCustom output format.\n\nNo standard schema keywords.\n"
        plugin_dir = make_specialist_fixture(
            self.tmpdir, body=body, output_schema="custom", set_output_schema=True
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected no output_schema warning for 'custom' but got:\n{result.stdout}"
        )

    # --- Scenario: 未宣言（None） ---

    def test_undeclared_output_schema_runs_keyword_validation(self):
        """Scenario: 未宣言（None）
        WHEN specialist コンポーネントが output_schema を宣言していない
        THEN output_schema の invalid value 警告は出力されず、スキーマキーワード検証が実行される
        """
        # Body with all required keywords — keyword validation should pass
        body = (
            "## Purpose\nAnalyze code quality.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "## Constraint\nMUST NOT skip.\n\n"
            "Report findings with severity and confidence.\n"
        )
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        # No invalid value warning
        assert "invalid output_schema value" not in result.stdout, (
            f"Expected no 'invalid output_schema value' warning but got:\n{result.stdout}"
        )
        assert "empty output_schema value" not in result.stdout, (
            f"Expected no 'empty output_schema value' warning but got:\n{result.stdout}"
        )
        # Keyword validation ran and passed — no schema warning at all
        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected keyword validation to pass but got:\n{result.stdout}"
        )

    def test_undeclared_output_schema_keyword_validation_detects_missing(self):
        """Scenario: 未宣言（None） — keyword validation fires when keywords are absent
        WHEN specialist コンポーネントが output_schema を宣言しておらず、キーワードが不足している
        THEN missing keywords の警告が出力される（keyword validation が実行された証拠）
        """
        body = "## Purpose\nDo something.\n\nNo schema keywords at all.\n"
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        # Keyword validation must have run and found missing keywords
        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected keyword validation warning but got:\n{result.stdout}"
        )
        assert "missing output schema keywords" in result.stdout, (
            f"Expected 'missing output schema keywords' message but got:\n{result.stdout}"
        )
        # But NOT an invalid value warning
        assert "invalid output_schema value" not in result.stdout, (
            f"Expected no 'invalid output_schema value' warning but got:\n{result.stdout}"
        )

    # --- Scenario: その他の無効な値 ---

    def test_invalid_nonempty_output_schema_reports_invalid_warning(self):
        """Scenario: その他の無効な値
        WHEN specialist コンポーネントが output_schema: "invalid" など custom 以外の非空値を宣言している
        THEN [specialist-output-schema] {cname}: invalid output_schema value '{value}' (expected 'custom' or omit) 警告が出力される
        """
        body = (
            "## Purpose\nAnalyze.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "findings, severity, confidence.\n"
        )
        plugin_dir = make_specialist_fixture(
            self.tmpdir, body=body, output_schema="invalid", set_output_schema=True
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected [specialist-output-schema] warning but got:\n{result.stdout}"
        )
        assert "my-specialist" in result.stdout, (
            f"Expected component name in warning but got:\n{result.stdout}"
        )
        assert "invalid output_schema value" in result.stdout, (
            f"Expected 'invalid output_schema value' message but got:\n{result.stdout}"
        )
        assert "invalid" in result.stdout, (
            f"Expected the bad value to appear in warning but got:\n{result.stdout}"
        )

    def test_invalid_nonempty_output_schema_skips_keyword_validation(self):
        """Scenario: その他の無効な値 — keyword validation is skipped after invalid value warning
        WHEN specialist が invalid な output_schema 値を持ちかつキーワードが不足している
        THEN invalid value 警告のみ出力され、missing keywords 警告は出力されない
        """
        # Body missing all keywords
        body = "## Purpose\nDo something.\n\nNo keywords at all.\n"
        plugin_dir = make_specialist_fixture(
            self.tmpdir, body=body, output_schema="bad-value", set_output_schema=True
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "invalid output_schema value" in result.stdout, (
            f"Expected invalid value warning but got:\n{result.stdout}"
        )
        # Keyword validation should be skipped (continue after invalid value warning)
        assert "missing output schema keywords" not in result.stdout, (
            f"Expected keyword validation to be skipped but got:\n{result.stdout}"
        )

    def test_various_invalid_values_all_report_warning(self):
        """Scenario: その他の無効な値 — multiple invalid value strings are all rejected
        WHEN specialist が 'json', 'schema', 'true' などの custom 以外の非空値を宣言している
        THEN それぞれについて invalid output_schema value 警告が出力される
        """
        body = (
            "## Purpose\nAnalyze.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "findings, severity, confidence.\n"
        )
        for bad_value in ("json", "schema", "true", "Custom", "CUSTOM"):
            with tempfile.TemporaryDirectory() as tmpdir:
                plugin_dir = make_specialist_fixture(
                    Path(tmpdir), body=body, output_schema=bad_value, set_output_schema=True
                )
                result = run_engine(plugin_dir, "--deep-validate")

                assert "[specialist-output-schema]" in result.stdout, (
                    f"Expected warning for output_schema='{bad_value}' but got:\n{result.stdout}"
                )
                assert "invalid output_schema value" in result.stdout, (
                    f"Expected 'invalid output_schema value' for '{bad_value}' but got:\n{result.stdout}"
                )


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestOutputSchemaValidation,
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
