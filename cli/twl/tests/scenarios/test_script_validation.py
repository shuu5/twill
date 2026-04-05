#!/usr/bin/env python3
"""Tests for deps.yaml scripts SSOT: Validation scenarios.

Spec: openspec/changes/depsyaml-scripts-ssot/specs/validation/spec.md

Covers:
- validate_types: scripts section checks (section placement, edge checks)
- validate_v3_schema: script key in calls, legacy scripts field WARNING
- deep_validate: script type skip for frontmatter-body checks
- audit_report: script type skip for inline/tools/self-contained checks
- validate_body_refs: script type skip for body reference checks
"""

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


def make_script_fixture(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture with scripts section for validation tests."""
    plugin_dir = tmpdir / "test-plugin-val"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-val",
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
                    {"script": "my-script"},
                ],
            },
        },
        "agents": {},
        "scripts": {
            "my-script": {
                "type": "script",
                "path": "scripts/my-script.sh",
                "description": "A test script",
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

class _ValidationTestBase:
    """Shared setup/teardown for validation tests."""

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
# Requirement: validate_types で scripts セクションを検証する
# ===========================================================================

class TestValidateTypesScripts(_ValidationTestBase):
    """validate_types should check scripts section components."""

    def test_script_section_placement_ok(self):
        """Scenario: script のセクション配置チェック
        WHEN scripts セクションに type=script のコンポーネントが定義されている
        THEN セクション配置チェックが OK となる (script 型の section は scripts)"""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        # No section placement violation for scripts
        assert "[section] scripts/" not in result.stdout

    def test_script_invalid_caller_edge(self):
        """Scenario: script の不正な呼び出しエッジ
        WHEN type=controller のコンポーネントが {script: name} を calls に持つ
        THEN edge チェックで violation が報告される (controller は script を can_spawn に含まない)"""
        def mutator(deps):
            deps["skills"]["my-controller"]["calls"] = [
                {"script": "my-script"},
            ]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        # controller cannot spawn script -> violation expected
        assert "[edge]" in result.stdout
        assert "controller" in result.stdout
        assert "script" in result.stdout

    def test_script_valid_caller_edge_from_atomic(self):
        """Scenario: script の正当な呼び出しエッジ
        WHEN type=atomic のコンポーネントが {script: name} を calls に持つ
        THEN edge チェックが OK となる (atomic の can_spawn に script が含まれる必要がある)"""
        # The default fixture already has atomic -> script call
        result = run_engine(self.plugin_dir, "--validate")
        # Check that there's no edge violation for atomic -> script
        # (This depends on types.yaml having script in atomic's can_spawn or
        # the appropriate spawnable_by - the spec says spawnable_by includes atomic)
        lines = [l for l in result.stdout.splitlines()
                 if "[edge]" in l and "my-action" in l and "script" in l.lower()]
        # If atomic can call script (via spawnable_by), no violation
        # NOTE: This test verifies the requirement.
        # If it fails, atomic needs script in can_spawn or script needs atomic in spawnable_by
        assert len(lines) == 0, f"Unexpected edge violation for atomic->script:\n{result.stdout}"

    def test_script_valid_caller_edge_from_composite(self):
        """Edge case: composite should also be able to call script (spawnable_by includes composite)."""
        def mutator(deps):
            deps["commands"]["my-composite"] = {
                "type": "composite",
                "path": "commands/my-composite.md",
                "description": "A composite command",
                "calls": [{"script": "my-script"}],
            }
            deps["skills"]["my-controller"]["calls"].append(
                {"composite": "my-composite"}
            )
        self._modify_deps(mutator)
        (self.plugin_dir / "commands" / "my-composite.md").write_text(
            "---\nname: my-composite\ndescription: Test\n---\n\nContent.\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--validate")
        lines = [l for l in result.stdout.splitlines()
                 if "[edge]" in l and "my-composite" in l and "script" in l.lower()]
        assert len(lines) == 0, f"Unexpected edge violation for composite->script:\n{result.stdout}"


# ===========================================================================
# Requirement: validate_v3_schema で script キーを許可する
# ===========================================================================

class TestV3SchemaScriptKey(_ValidationTestBase):
    """validate_v3_schema should accept 'script' as a valid calls key in v3.0."""

    def test_v3_calls_script_key_accepted(self):
        """Scenario: v3.0 calls キー検証
        WHEN v3.0 deps.yaml のコンポーネントが {script: name} を calls に持つ
        THEN validate_v3_schema が violation を報告しない"""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        # No v3-calls-key violation for script
        assert "[v3-calls-key]" not in result.stdout

    def test_v3_calls_script_key_not_unknown(self):
        """Edge case: 'script' should not be flagged as unknown key."""
        result = run_engine(self.plugin_dir, "--validate")
        lines = [l for l in result.stdout.splitlines()
                 if "unknown key 'script'" in l]
        assert len(lines) == 0, f"script key wrongly flagged as unknown:\n{result.stdout}"


# ===========================================================================
# Requirement: 旧形式 scripts フィールドに WARNING を出す
# ===========================================================================

class TestLegacyScriptsFieldWarning(_ValidationTestBase):
    """v3.0 should warn about legacy scripts: field in components."""

    def test_legacy_scripts_field_detected(self):
        """Scenario: コンポーネント内の旧 scripts フィールド検出
        WHEN skills/commands/agents セクション内のコンポーネントが scripts: [name.sh] フィールドを持つ
        THEN validate_v3_schema が [v3-legacy-scripts] WARNING を報告する"""
        def mutator(deps):
            deps["commands"]["my-action"]["scripts"] = ["deploy.sh"]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[v3-legacy-scripts]" in result.stdout
        assert "my-action" in result.stdout

    def test_no_scripts_field_no_warning(self):
        """Scenario: scripts フィールドがないコンポーネント
        WHEN コンポーネントに scripts: フィールドがない
        THEN WARNING は報告されない"""
        result = run_engine(self.plugin_dir, "--validate")
        assert "[v3-legacy-scripts]" not in result.stdout

    def test_legacy_scripts_field_in_skills(self):
        """Edge case: legacy scripts field in skills section."""
        def mutator(deps):
            deps["skills"]["my-controller"]["scripts"] = ["init.sh"]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[v3-legacy-scripts]" in result.stdout
        assert "my-controller" in result.stdout


# ===========================================================================
# Requirement: deep_validate で script 型をスキップする
# ===========================================================================

class TestDeepValidateScriptSkip(_ValidationTestBase):
    """deep_validate should skip frontmatter-body checks for script components."""

    def test_script_tools_check_skipped(self):
        """Scenario: script 型の tools チェックスキップ
        WHEN deep_validate が実行され、scripts セクションにコンポーネントが存在する
        THEN そのコンポーネントに対して frontmatter/tools 整合性チェックは実行されない"""
        # Run deep validation (--validate triggers it)
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        # No tool-mismatch or frontmatter errors for script components
        lines = [l for l in result.stdout.splitlines()
                 if "my-script" in l and ("tool" in l.lower() or "frontmatter" in l.lower())]
        assert len(lines) == 0, f"Unexpected deep_validate check for script:\n{result.stdout}"

    def test_script_no_body_check(self):
        """Edge case: script with no body content should not trigger body-related checks."""
        # Override the script file to have no content
        (self.plugin_dir / "scripts" / "my-script.sh").write_text("", encoding="utf-8")
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"


# ===========================================================================
# Requirement: audit_report で script 型をスキップする
# ===========================================================================

class TestAuditReportScriptSkip(_ValidationTestBase):
    """audit_report should skip script components in specific sections."""

    def test_audit_script_skip(self):
        """Scenario: audit の script スキップ
        WHEN twl --audit を実行し、scripts セクションにコンポーネントが存在する
        THEN Section 2 (Inline Implementation), Section 4 (Tools Accuracy),
             Section 5 (Self-Contained) の各テーブルに script コンポーネントの行が含まれない"""
        result = run_engine(self.plugin_dir, "--audit")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        # The script name should NOT appear in audit sections 2, 4, 5
        # Parse sections - look for script name in those sections
        output = result.stdout
        # Split by sections (## N.)
        sections = {}
        current_section = ""
        for line in output.splitlines():
            if line.startswith("## "):
                current_section = line
            else:
                sections.setdefault(current_section, []).append(line)

        # Find Section 2, 4, 5 content
        for section_header, section_lines in sections.items():
            if any(s in section_header for s in ["2.", "4.", "5."]):
                section_text = "\n".join(section_lines)
                assert "my-script" not in section_text, (
                    f"Script 'my-script' found in {section_header}:\n{section_text}"
                )


# ===========================================================================
# Requirement: validate_body_refs で script 型をスキップする
# ===========================================================================

class TestBodyRefsScriptSkip(_ValidationTestBase):
    """validate_body_refs should skip scripts section components."""

    def test_script_body_ref_skip(self):
        """Scenario: script の body-ref スキップ
        WHEN validate_body_refs が実行される
        THEN scripts セクションのコンポーネントは走査対象に含まれない"""
        # Add an invalid reference in the script file - should be ignored
        (self.plugin_dir / "scripts" / "my-script.sh").write_text(
            "#!/bin/bash\n# References /test-val:nonexistent\necho ok\n",
            encoding="utf-8",
        )

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        # No body-ref violation for the script file
        lines = [l for l in result.stdout.splitlines()
                 if "[body-ref]" in l and "my-script" in l]
        assert len(lines) == 0, f"Unexpected body-ref check for script:\n{result.stdout}"


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestValidateTypesScripts,
        TestV3SchemaScriptKey,
        TestLegacyScriptsFieldWarning,
        TestDeepValidateScriptSkip,
        TestAuditReportScriptSkip,
        TestBodyRefsScriptSkip,
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
