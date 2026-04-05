#!/usr/bin/env python3
"""Tests for audit_report Section 6: Model Declaration.

Spec: openspec/changes/model-specialist-validate/specs/audit-model-section.md

Covers:
- model declared specialist shows OK row
- model undeclared specialist shows WARNING row
- unknown model value shows INFO row
- opus model shows WARNING row
- Section 6 header format
"""

import shutil
import subprocess
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


def make_audit_fixture(tmpdir: Path, specialists: dict | None = None) -> Path:
    """Create a v3.0 plugin fixture for audit report testing.

    Args:
        specialists: dict of specialist_name -> model_value (None = no model field).
    """
    plugin_dir = tmpdir / "test-plugin-audit"
    plugin_dir.mkdir()

    if specialists is None:
        specialists = {"my-specialist": "sonnet"}

    agents = {}
    calls = []
    for name, model in specialists.items():
        agent_data: dict = {
            "type": "specialist",
            "path": f"agents/{name}.md",
            "description": f"Specialist {name}",
            "calls": [],
        }
        if model is not None:
            agent_data["model"] = model
        agents[name] = agent_data
        calls.append({"specialist": name})

    deps = {
        "version": "3.0",
        "plugin": "test-audit",
        "chains": {},
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": calls,
            },
        },
        "commands": {},
        "agents": agents,
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, str(TWL_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Test base class with setup/teardown
# ---------------------------------------------------------------------------

class _AuditTestBase:
    """Shared setup/teardown for audit model section tests."""

    specialists: dict = {"my-specialist": "sonnet"}  # default

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_audit_fixture(self.tmpdir, specialists=self.specialists)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _modify_deps(self, mutator):
        """Load deps, apply mutator function, write back."""
        deps = _load_deps(self.plugin_dir)
        mutator(deps)
        _write_deps(self.plugin_dir, deps)
        return deps

    def _run_audit(self) -> str:
        """Run --audit and return stdout."""
        result = run_engine(self.plugin_dir, "--audit")
        return result.stdout

    def _get_section6_lines(self) -> list[str]:
        """Extract only Section 6 lines from audit output."""
        output = self._run_audit()
        lines = output.splitlines()
        in_section6 = False
        section6_lines = []
        for line in lines:
            if "## 6. Model Declaration" in line:
                in_section6 = True
                section6_lines.append(line)
                continue
            if in_section6:
                if line.startswith("## ") and "6." not in line:
                    break
                section6_lines.append(line)
        return section6_lines


# ===========================================================================
# Requirement: audit Model Declaration section - model declared OK
# ===========================================================================

class TestAuditModelDeclaredOk(_AuditTestBase):
    """Model Declaration table shows OK for specialist with valid model."""

    specialists = {"my-specialist": "sonnet"}

    def test_model_declared_ok_row(self):
        """Scenario: model declared specialist
        WHEN specialist has model: sonnet
        THEN table outputs '| my-specialist | specialist | sonnet | OK |'."""
        output = self._run_audit()
        assert "6. Model Declaration" in output
        # Check table row (flexible whitespace matching)
        assert "my-specialist" in output
        assert "sonnet" in output
        # Verify the OK severity for this row
        lines = output.splitlines()
        for line in lines:
            if "my-specialist" in line and "sonnet" in line:
                assert "OK" in line, f"Expected OK severity in line: {line}"
                break
        else:
            assert False, "Could not find my-specialist row with sonnet in audit output"


# ===========================================================================
# Requirement: audit Model Declaration section - model undeclared WARNING
# ===========================================================================

class TestAuditModelUndeclaredWarning(_AuditTestBase):
    """Model Declaration table shows WARNING for specialist without model."""

    specialists = {"no-model-agent": None}

    def test_model_undeclared_warning_row(self):
        """Scenario: model undeclared specialist
        WHEN specialist has no model field
        THEN table outputs '| {name} | specialist | (none) | WARNING |' and increments warnings."""
        lines = self._get_section6_lines()
        assert any("6. Model Declaration" in l for l in lines)
        for line in lines:
            if "no-model-agent" in line and "specialist" in line:
                assert "(none)" in line, f"Expected '(none)' in line: {line}"
                assert "WARNING" in line, f"Expected WARNING severity in line: {line}"
                break
        else:
            assert False, f"Could not find no-model-agent row in Section 6: {lines}"


# ===========================================================================
# Requirement: audit Model Declaration section - unknown model INFO
# ===========================================================================

class TestAuditUnknownModelInfo(_AuditTestBase):
    """Model Declaration table shows INFO for specialist with unknown model."""

    specialists = {"typo-agent": "sonne"}

    def test_unknown_model_info_row(self):
        """Scenario: unknown model value specialist
        WHEN specialist has model value not in ALLOWED_MODELS
        THEN table outputs '| {name} | specialist | {value} | INFO |'."""
        output = self._run_audit()
        assert "6. Model Declaration" in output
        lines = output.splitlines()
        for line in lines:
            if "typo-agent" in line and "sonne" in line:
                assert "INFO" in line, f"Expected INFO severity in line: {line}"
                break
        else:
            assert False, "Could not find typo-agent row with sonne in audit output"


# ===========================================================================
# Requirement: audit Model Declaration section - opus WARNING
# ===========================================================================

class TestAuditOpusWarning(_AuditTestBase):
    """Model Declaration table shows WARNING for specialist with opus."""

    specialists = {"opus-agent": "opus"}

    def test_opus_warning_row(self):
        """Scenario: specialist with opus
        WHEN specialist has model: opus
        THEN table outputs '| {name} | specialist | opus | WARNING |' and increments warnings."""
        lines = self._get_section6_lines()
        assert any("6. Model Declaration" in l for l in lines)
        for line in lines:
            if "opus-agent" in line and "opus" in line:
                assert "WARNING" in line, f"Expected WARNING severity in line: {line}"
                break
        else:
            assert False, f"Could not find opus-agent row in Section 6: {lines}"


# ===========================================================================
# Requirement: audit Model Declaration table format
# ===========================================================================

class TestAuditTableFormat(_AuditTestBase):
    """Section 6 has correct header format."""

    specialists = {"my-specialist": "sonnet"}

    def test_section_6_header(self):
        """Scenario: table header
        WHEN audit is executed
        THEN Section 6 starts with '## 6. Model Declaration' and has
             '| Name | Type | Model | Severity |' header."""
        output = self._run_audit()

        # Check section header
        assert "## 6. Model Declaration" in output

        # Check table header
        lines = output.splitlines()
        found_header = False
        for line in lines:
            if "Name" in line and "Type" in line and "Model" in line and "Severity" in line:
                # Verify it's a table header with pipes
                assert line.strip().startswith("|"), f"Expected table format: {line}"
                assert line.strip().endswith("|"), f"Expected table format: {line}"
                found_header = True
                break
        assert found_header, (
            "Could not find '| Name | Type | Model | Severity |' header in audit output.\n"
            f"Output:\n{output}"
        )

    def test_section_6_separator_line(self):
        """Edge case: table should have a separator line after header."""
        output = self._run_audit()
        lines = output.splitlines()
        for i, line in enumerate(lines):
            if "Name" in line and "Type" in line and "Model" in line and "Severity" in line:
                # Next line should be a separator (dashes)
                if i + 1 < len(lines):
                    sep_line = lines[i + 1]
                    assert "---" in sep_line, (
                        f"Expected separator line after header, got: {sep_line}"
                    )
                break


# ===========================================================================
# Mixed scenarios (edge cases)
# ===========================================================================

class TestAuditMixedSpecialists(_AuditTestBase):
    """Audit with multiple specialists in different model states."""

    specialists = {
        "good-agent": "sonnet",
        "no-model-agent": None,
        "typo-agent": "sonne",
        "opus-agent": "opus",
    }

    def test_all_specialists_appear_in_table(self):
        """Edge case: all specialists should appear in Section 6 table."""
        output = self._run_audit()
        assert "6. Model Declaration" in output
        for name in ("good-agent", "no-model-agent", "typo-agent", "opus-agent"):
            assert name in output, f"Missing {name} in audit output"

    def test_correct_severity_per_specialist(self):
        """Edge case: each specialist should have the correct severity."""
        lines = self._get_section6_lines()

        expected = {
            "good-agent": "OK",
            "no-model-agent": "WARNING",
            "typo-agent": "INFO",
            "opus-agent": "WARNING",
        }
        found = set()
        for line in lines:
            for name, severity in expected.items():
                if name in line and "specialist" in line:
                    assert severity in line, (
                        f"Expected {severity} for {name}, got line: {line}"
                    )
                    found.add(name)

        assert found == set(expected.keys()), (
            f"Not all specialists found in Section 6. Missing: {set(expected.keys()) - found}"
        )


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestAuditModelDeclaredOk,
        TestAuditModelUndeclaredWarning,
        TestAuditUnknownModelInfo,
        TestAuditOpusWarning,
        TestAuditTableFormat,
        TestAuditMixedSpecialists,
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
