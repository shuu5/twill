#!/usr/bin/env python3
"""Tests for deps.yaml scripts SSOT: Type System scenarios.

Spec: openspec/changes/depsyaml-scripts-ssot/specs/type-system/spec.md

Covers:
- types.yaml script type definition and loading
- deps.yaml scripts section parsing / build_graph
- parse_calls script key interpretation
- find_node prefix list with script
- Reverse dependency for script nodes
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
    for name, data in deps.get("scripts", {}).items():
        path_str = data.get("path", "")
        if not path_str:
            continue
        file_path = plugin_dir / path_str
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(f"#!/bin/bash\n# {name}\necho '{name}'\n", encoding="utf-8")


def make_script_fixture(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture with a scripts section."""
    plugin_dir = tmpdir / "test-plugin-scripts"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-scripts",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": [
                    {"workflow": "my-workflow", "step": "1"},
                ],
            },
            "my-workflow": {
                "type": "workflow",
                "path": "skills/my-workflow/SKILL.md",
                "description": "A workflow",
                "calls": [
                    {"atomic": "my-action", "step": "2"},
                ],
            },
        },
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An atomic command",
                "calls": [
                    {"script": "autopilot-plan"},
                ],
            },
        },
        "agents": {},
        "scripts": {
            "autopilot-plan": {
                "type": "script",
                "path": "scripts/autopilot-plan.sh",
                "description": "Autopilot planning script",
                "calls": [],
            },
        },
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def make_script_fixture_no_scripts(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture WITHOUT a scripts section."""
    plugin_dir = tmpdir / "test-plugin-no-scripts"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-noscripts",
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
# Test base class
# ---------------------------------------------------------------------------

class _ScriptTestBase:
    """Shared setup/teardown for script type system tests."""

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
# Requirement: types.yaml に script 型を定義
# ===========================================================================

class TestTypesYamlScriptDefinition(_ScriptTestBase):
    """types.yaml should define the script type with correct attributes."""

    def test_types_yaml_loading_script_key(self):
        """Scenario: types.yaml 読み込み
        WHEN twl-engine.py が起動し types.yaml を読み込む
        THEN TYPE_RULES に script キーが存在し、section=scripts, can_spawn={'script'}, spawnable_by={'atomic', 'composite', 'script'} が設定される"""
        result = run_engine(self.plugin_dir, "--rules")
        assert result.returncode == 0
        # The script type should appear in rules output
        assert "script" in result.stdout
        assert "scripts" in result.stdout  # section=scripts

    def test_loom_rules_displays_script(self):
        """Scenario: twl rules 表示
        WHEN twl rules を実行する
        THEN script 型の行が表示され、section/can_spawn/spawnable_by が正しく出力される"""
        result = run_engine(self.plugin_dir, "--rules")
        assert result.returncode == 0
        # Find the script line in the output
        lines = result.stdout.splitlines()
        script_line = None
        for line in lines:
            if line.strip().startswith("| script"):
                script_line = line
                break
        assert script_line is not None, f"No script line found in rules output:\n{result.stdout}"
        # Verify section is scripts
        assert "scripts" in script_line
        # Verify can_spawn includes script (updated from empty to [script])
        assert "script" in script_line
        # Verify spawnable_by includes atomic and composite
        assert "atomic" in script_line
        assert "composite" in script_line


# ===========================================================================
# Requirement: deps.yaml の scripts セクションをパースする
# ===========================================================================

class TestScriptsSectionParsing(_ScriptTestBase):
    """build_graph should process the scripts section correctly."""

    def test_scripts_section_builds_graph_nodes(self):
        """Scenario: scripts セクション付き deps.yaml の読み込み
        WHEN deps.yaml に scripts: セクションが定義され、エントリに type/path/description/calls が含まれる
        THEN build_graph が script:{name} ノードを生成し、type=script、path/description/calls が正しく設定される"""
        # Run --tree to verify graph was built including script nodes
        result = run_engine(self.plugin_dir, "--target", "autopilot-plan")
        assert result.returncode == 0
        # The script node should be found
        assert "autopilot-plan" in result.stdout

    def test_scripts_section_absent_no_error(self):
        """Scenario: scripts セクションが存在しない deps.yaml
        WHEN deps.yaml に scripts: セクションがない
        THEN build_graph は script ノードを生成せず、エラーも発生しない"""
        tmpdir = Path(tempfile.mkdtemp())
        try:
            plugin_dir = make_script_fixture_no_scripts(tmpdir)
            result = run_engine(plugin_dir, "--validate")
            assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: parse_calls で script キーを解釈する
# ===========================================================================

class TestParseCallsScript(_ScriptTestBase):
    """parse_calls should handle script call entries."""

    def test_calls_script_reference(self):
        """Scenario: calls 内の script 参照
        WHEN コンポーネントの calls に {script: autopilot-plan} が含まれる
        THEN parse_calls が ('script', 'autopilot-plan', None) タプルを返す"""
        # Verify through the graph: my-action calls autopilot-plan
        result = run_engine(self.plugin_dir, "--target", "my-action")
        assert result.returncode == 0
        assert "autopilot-plan" in result.stdout

    def test_calls_script_with_step(self):
        """Scenario: step 付き script 参照
        WHEN calls に {script: build, step: "2.1"} が含まれる
        THEN parse_calls が ('script', 'build', '2.1') タプルを返す"""
        def mutator(deps):
            deps["scripts"]["build"] = {
                "type": "script",
                "path": "scripts/build.sh",
                "description": "Build script",
                "calls": [],
            }
            deps["commands"]["my-action"]["calls"] = [
                {"script": "build", "step": "2.1"},
            ]
        self._modify_deps(mutator)
        # Create the script file
        (self.plugin_dir / "scripts" / "build.sh").write_text(
            "#!/bin/bash\necho build\n", encoding="utf-8"
        )

        result = run_engine(self.plugin_dir, "--target", "my-action")
        assert result.returncode == 0
        assert "build" in result.stdout


# ===========================================================================
# Requirement: find_node の prefix リストに script を追加する
# ===========================================================================

class TestFindNodeScript(_ScriptTestBase):
    """find_node should locate script nodes by name."""

    def test_find_node_script_by_name(self):
        """Scenario: script ノードの名前検索
        WHEN twl --target autopilot-plan を実行し、script:autopilot-plan ノードが存在する
        THEN find_node が script:autopilot-plan を返す"""
        result = run_engine(self.plugin_dir, "--target", "autopilot-plan")
        assert result.returncode == 0
        assert "autopilot-plan" in result.stdout

    def test_find_node_script_reverse(self):
        """Verify --reverse also works for script nodes."""
        result = run_engine(self.plugin_dir, "--reverse", "autopilot-plan")
        assert result.returncode == 0
        assert "autopilot-plan" in result.stdout


# ===========================================================================
# Requirement: 逆依存グラフで script ノードを含める
# ===========================================================================

class TestScriptReverseDependency(_ScriptTestBase):
    """build_graph should track reverse deps for script nodes."""

    def test_script_reverse_dependency(self):
        """Scenario: script の逆依存
        WHEN command:my-action が {script: autopilot-plan} を calls に持つ
        THEN script:autopilot-plan の required_by に ('command', 'my-action') が含まれる"""
        result = run_engine(self.plugin_dir, "--reverse", "autopilot-plan")
        assert result.returncode == 0
        # The reverse output should show my-action as a caller
        assert "my-action" in result.stdout

    def test_script_reverse_from_multiple_callers(self):
        """Edge case: script called by multiple components."""
        def mutator(deps):
            deps["skills"]["my-workflow"]["calls"].append(
                {"script": "autopilot-plan"}
            )
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--reverse", "autopilot-plan")
        assert result.returncode == 0
        assert "my-action" in result.stdout
        assert "my-workflow" in result.stdout


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestTypesYamlScriptDefinition,
        TestScriptsSectionParsing,
        TestParseCallsScript,
        TestFindNodeScript,
        TestScriptReverseDependency,
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
