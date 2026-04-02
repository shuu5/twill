#!/usr/bin/env python3
"""Tests for specialist output schema keyword validation in deep-validate and audit.

Spec: openspec/changes/specialist-deep-validate/specs/deep-validate-output-schema.md

Coverage: edge-cases
- 9 spec scenarios (ADDED + MODIFIED requirements)
- 4 edge-case scenarios (no specialist, empty body, both PASS/FAIL, empty output_schema)
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, Optional

import yaml

LOOM_ENGINE = Path(__file__).parent.parent / "loom-engine.py"


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
    body: str = "## Purpose\nAnalyze code.\n\n## Output\nReturn PASS or FAIL.\n\n## Constraint\nMUST NOT skip.\n\nfindings: list\nseverity: high/low\nconfidence: 0.0-1.0\n",
    output_schema: Optional[str] = None,
    agent_name: str = "my-specialist",
) -> Path:
    """Create a plugin fixture with a single specialist agent.

    Args:
        body: The body text of the specialist's AGENT.md
        output_schema: If provided, set output_schema field in deps.yaml for the agent
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
    if output_schema is not None:
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
    """Run loom-engine.py with the given arguments."""
    return subprocess.run(
        [sys.executable, str(LOOM_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Test base class with setup/teardown
# ---------------------------------------------------------------------------

class _SchemaTestBase:
    """Shared setup/teardown for output schema validation tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: specialist 出力スキーマキーワード検証
# ===========================================================================

class TestSpecialistOutputSchemaKeywords(_SchemaTestBase):
    """deep-validate checks that specialist body contains output schema keywords."""

    # --- Scenario: 全キーワードが存在する specialist → WARNING なし ---

    def test_all_keywords_present_no_warning(self):
        """WHEN specialist の body に PASS, findings, severity, confidence が含まれる
        THEN deep-validate は WARNING を報告しない"""
        body = (
            "## Purpose\nAnalyze code quality.\n\n"
            "## Output\nReturn PASS or FAIL with details.\n\n"
            "## Constraint\nMUST NOT skip analysis.\n\n"
            "Report findings with severity and confidence scores.\n"
        )
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected no schema warning but got:\n{result.stdout}"
        )

    # --- Scenario: キーワードが不足している specialist → WARNING 報告 ---

    def test_missing_keyword_reports_warning(self):
        """WHEN specialist の body に findings が含まれるが severity が含まれない
        THEN deep-validate は [specialist-output-schema] WARNING を報告する"""
        body = (
            "## Purpose\nAnalyze code.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "Report findings with confidence scores.\n"
        )
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected schema warning but got:\n{result.stdout}"
        )
        assert "my-specialist" in result.stdout
        assert "severity" in result.stdout

    # --- Scenario: PASS/FAIL のいずれか一方のみ存在 → 合格 ---

    def test_only_fail_present_passes_result_values(self):
        """WHEN specialist の body に FAIL は含まれるが PASS は含まれない
        THEN result_values カテゴリは合格とし WARNING を報告しない"""
        body = (
            "## Purpose\nValidate compliance.\n\n"
            "## Output\nReturn FAIL if non-compliant.\n\n"
            "Report findings with severity and confidence.\n"
        )
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        # result_values should pass (FAIL alone is sufficient)
        # No warning about missing result_values keywords
        assert "[specialist-output-schema]" not in result.stdout or "result_values" not in result.stdout, (
            f"Expected result_values to pass with only FAIL, but got:\n{result.stdout}"
        )


# ===========================================================================
# Requirement: output_schema custom によるスキップ
# ===========================================================================

class TestOutputSchemaCustomSkip(_SchemaTestBase):
    """output_schema: custom skips keyword validation."""

    # --- Scenario: output_schema: custom → スキップ ---

    def test_output_schema_custom_skips_validation(self):
        """WHEN specialist の deps.yaml 定義に output_schema: custom が設定されている
        THEN deep-validate はその specialist の出力スキーマ検証をスキップする"""
        # Body intentionally missing all keywords
        body = "## Purpose\nDo custom stuff.\n\nNo standard keywords here.\n"
        plugin_dir = make_specialist_fixture(
            self.tmpdir, body=body, output_schema="custom"
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected skip for custom schema but got:\n{result.stdout}"
        )

    # --- Scenario: output_schema: invalid → WARNING ---

    def test_output_schema_invalid_reports_warning(self):
        """WHEN specialist の deps.yaml 定義に output_schema: invalid が設定されている
        THEN deep-validate は [specialist-output-schema] WARNING を報告する"""
        body = (
            "## Purpose\nAnalyze.\n\n"
            "## Output\nReturn PASS.\n\n"
            "findings, severity, confidence all present.\n"
        )
        plugin_dir = make_specialist_fixture(
            self.tmpdir, body=body, output_schema="invalid"
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected warning for invalid output_schema but got:\n{result.stdout}"
        )

    # --- Scenario: output_schema 未設定 → 通常検証 ---

    def test_output_schema_not_set_runs_normal_validation(self):
        """WHEN specialist の deps.yaml 定義に output_schema フィールドがない
        THEN deep-validate は通常通りキーワード検証を実行する"""
        # Body with all keywords → should pass normally
        body = (
            "## Purpose\nAnalyze.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "Report findings with severity and confidence.\n"
        )
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected normal validation pass but got:\n{result.stdout}"
        )

    def test_output_schema_not_set_detects_missing_keywords(self):
        """WHEN output_schema is not set and keywords are missing
        THEN deep-validate detects and reports missing keywords"""
        body = "## Purpose\nDo something.\n\nNo schema keywords.\n"
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected warning for missing keywords but got:\n{result.stdout}"
        )


# ===========================================================================
# Requirement: audit Section 5 スキーマ準拠列の追加
# ===========================================================================

class TestAuditSection5Schema(_SchemaTestBase):
    """audit Section 5 shows Schema column for specialists."""

    # --- Scenario: Schema 列が Yes ---

    def test_schema_column_yes(self):
        """WHEN specialist の body に全出力スキーマキーワードが含まれる
        THEN audit Section 5 の Schema 列に Yes と表示される"""
        body = (
            "## Purpose\nAnalyze.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "## Constraint\nMUST NOT skip.\n\n"
            "Report findings with severity and confidence.\n"
        )
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--audit")

        # Find the Section 5 table row for my-specialist
        lines = result.stdout.splitlines()
        section5_row = None
        in_section5 = False
        for line in lines:
            if "## 5. Self-Contained" in line:
                in_section5 = True
                continue
            if in_section5 and "my-specialist" in line:
                section5_row = line
                break
            if in_section5 and line.startswith("## ") and "Self-Contained" not in line:
                break

        assert section5_row is not None, (
            f"Could not find my-specialist row in Section 5:\n{result.stdout}"
        )
        # Parse the Schema column from the table row
        columns = [c.strip() for c in section5_row.split("|")]
        # Expect Schema column to contain "Yes"
        assert "Yes" in section5_row, (
            f"Expected Schema=Yes in row: {section5_row}"
        )

    # --- Scenario: Schema 列が Skip（custom） ---

    def test_schema_column_skip_custom(self):
        """WHEN specialist の deps.yaml に output_schema: custom が設定されている
        THEN audit Section 5 の Schema 列に Skip と表示される"""
        body = "## Purpose\nCustom output.\n\n## Output\nCustom.\n\nNo standard keywords.\n"
        plugin_dir = make_specialist_fixture(
            self.tmpdir, body=body, output_schema="custom"
        )
        result = run_engine(plugin_dir, "--audit")

        lines = result.stdout.splitlines()
        section5_row = None
        in_section5 = False
        for line in lines:
            if "## 5. Self-Contained" in line:
                in_section5 = True
                continue
            if in_section5 and "my-specialist" in line:
                section5_row = line
                break
            if in_section5 and line.startswith("## ") and "Self-Contained" not in line:
                break

        assert section5_row is not None, (
            f"Could not find my-specialist row in Section 5:\n{result.stdout}"
        )
        assert "Skip" in section5_row, (
            f"Expected Schema=Skip in row: {section5_row}"
        )

    # --- Scenario: Schema 不足が severity に影響（WARNING） ---

    def test_schema_no_affects_severity_warning(self):
        """WHEN specialist の Purpose と Output は OK だが Schema が No
        THEN Section 5 の severity は WARNING となる"""
        # Body has Purpose and Output headers but missing schema keywords
        body = (
            "## Purpose\nAnalyze code.\n\n"
            "## Output\nReturn results.\n\n"
            "## Constraint\nMUST NOT skip.\n\n"
            "No schema keywords here at all.\n"
        )
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--audit")

        lines = result.stdout.splitlines()
        section5_row = None
        in_section5 = False
        for line in lines:
            if "## 5. Self-Contained" in line:
                in_section5 = True
                continue
            if in_section5 and "my-specialist" in line:
                section5_row = line
                break
            if in_section5 and line.startswith("## ") and "Self-Contained" not in line:
                break

        assert section5_row is not None, (
            f"Could not find my-specialist row in Section 5:\n{result.stdout}"
        )
        assert "WARNING" in section5_row, (
            f"Expected WARNING severity in row: {section5_row}"
        )


# ===========================================================================
# Edge cases
# ===========================================================================

class TestOutputSchemaEdgeCases(_SchemaTestBase):
    """Edge cases for specialist output schema validation."""

    # --- Edge: plugin with no specialist → skip ---

    def test_no_specialist_plugin_skips_schema_check(self):
        """WHEN plugin has no specialist agents
        THEN deep-validate does not produce any specialist-output-schema warnings"""
        plugin_dir = self.tmpdir / "test-plugin-no-specialist"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "test-no-specialist",
            "skills": {
                "main-controller": {
                    "type": "controller",
                    "path": "skills/main-controller/SKILL.md",
                    "description": "Main controller",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        ctrl_dir = plugin_dir / "skills" / "main-controller"
        ctrl_dir.mkdir(parents=True, exist_ok=True)
        (ctrl_dir / "SKILL.md").write_text(
            "---\nname: main-controller\ndescription: Ctrl\n---\n\n## Step 0\nRoute.\n",
            encoding="utf-8",
        )

        result = run_engine(plugin_dir, "--deep-validate")
        assert "[specialist-output-schema]" not in result.stdout

    # --- Edge: specialist with empty body ---

    def test_specialist_empty_body_reports_warning(self):
        """WHEN specialist body is empty (only frontmatter)
        THEN deep-validate reports [specialist-output-schema] warning for all missing keywords"""
        body = ""
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected warning for empty body but got:\n{result.stdout}"
        )

    # --- Edge: both PASS and FAIL present ---

    def test_both_pass_and_fail_present(self):
        """WHEN specialist body contains both PASS and FAIL
        THEN result_values passes (both present is also valid)"""
        body = (
            "## Purpose\nEvaluate.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "Report findings with severity and confidence.\n"
        )
        plugin_dir = make_specialist_fixture(self.tmpdir, body=body)
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected no warning with both PASS/FAIL but got:\n{result.stdout}"
        )

    # --- Edge: output_schema is empty string ---

    def test_output_schema_empty_string(self):
        """WHEN output_schema field is empty string
        THEN treated as invalid value, empty output_schema warning is reported"""
        body = (
            "## Purpose\nAnalyze.\n\n"
            "## Output\nReturn PASS.\n\n"
            "findings, severity, confidence.\n"
        )
        plugin_dir = make_specialist_fixture(
            self.tmpdir, body=body, output_schema=""
        )
        result = run_engine(plugin_dir, "--deep-validate")

        # Empty string is an invalid value, should produce a specific warning
        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected empty output_schema warning but got:\n{result.stdout}"
        )
        assert "empty output_schema value" in result.stdout, (
            f"Expected 'empty output_schema value' message but got:\n{result.stdout}"
        )


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestSpecialistOutputSchemaKeywords,
        TestOutputSchemaCustomSkip,
        TestAuditSection5Schema,
        TestOutputSchemaEdgeCases,
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
