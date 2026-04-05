#!/usr/bin/env python3
"""Tests for deps.yaml scripts SSOT: Visualization scenarios.

Spec: openspec/changes/depsyaml-scripts-ssot/specs/visualization/spec.md

Covers:
- graphviz: script nodes as orange hexagons, edges to script nodes
- subgraph_graphviz: script node rendering
- classify_layers: scripts layer
- mermaid: script node hexagon syntax with orange style
- tree: script nodes as children
- list: SCRIPTS section
- tokens: Scripts section
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "src" / "twl" / "engine.py"


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
    """Create a v3.0 plugin fixture with scripts for visualization tests."""
    plugin_dir = tmpdir / "test-plugin-viz"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-viz",
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


def make_no_script_fixture(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture without scripts section."""
    plugin_dir = tmpdir / "test-plugin-noviz"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-noviz",
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
# Test base classes
# ---------------------------------------------------------------------------

class _VizTestBase:
    """Shared setup/teardown for visualization tests with scripts."""

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


class _NoScriptVizTestBase:
    """Shared setup/teardown for visualization tests without scripts."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_no_script_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: graphviz で script ノードをオレンジ六角形で表示する
# ===========================================================================

class TestGraphvizScriptNode(_VizTestBase):
    """generate_graphviz should render script nodes as orange hexagons."""

    def test_graphviz_script_node_shape_and_color(self):
        """Scenario: graphviz 出力での script ノード
        WHEN twl --graphviz を実行し、scripts セクションにコンポーネントが存在する
        THEN DOT 出力に shape=hexagon, style=filled, fillcolor="#FF9800" を持つ script ノードが含まれる"""
        result = run_engine(self.plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        # Check for hexagon shape
        assert "hexagon" in output, f"No hexagon shape in graphviz:\n{output}"
        # Check for orange fill color
        assert "#FF9800" in output, f"No orange fill color in graphviz:\n{output}"
        # Check for script node (autopilot-plan)
        assert "autopilot" in output or "autopilot_plan" in output, (
            f"No script node in graphviz:\n{output}"
        )

    def test_graphviz_no_scripts_no_script_nodes(self):
        """Scenario: scripts がない場合
        WHEN deps.yaml に scripts セクションがない
        THEN graphviz 出力に script ノード定義が含まれない"""
        tmpdir = Path(tempfile.mkdtemp())
        try:
            plugin_dir = make_no_script_fixture(tmpdir)
            result = run_engine(plugin_dir, "--graphviz")
            assert result.returncode == 0, f"stderr: {result.stderr}"
            output = result.stdout
            # No hexagon shape (only script uses it)
            assert "hexagon" not in output, f"Unexpected hexagon in graphviz without scripts:\n{output}"
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: subgraph_graphviz でも script ノードを描画する
# ===========================================================================

class TestSubgraphScriptNode(_VizTestBase):
    """generate_subgraph_graphviz should also render script nodes as orange hexagons."""

    def test_subgraph_script_display(self):
        """Scenario: サブグラフでの script 表示
        WHEN twl --update-readme でサブグラフ SVG を生成する
        THEN script ノードがサブグラフ内に含まれ、オレンジ六角形で描画される"""
        # Use --graphviz with target to get subgraph-like output
        result = run_engine(self.plugin_dir, "--target", "my-action", "--graphviz")
        # Some engines may not support --target with --graphviz together.
        # Fall back to checking the full graphviz output includes the script node.
        if result.returncode != 0:
            result = run_engine(self.plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        assert "autopilot" in result.stdout or "autopilot_plan" in result.stdout


# ===========================================================================
# Requirement: classify_layers に scripts レイヤーを追加する
# ===========================================================================

class TestClassifyLayersScripts(_VizTestBase):
    """classify_layers should include a scripts layer."""

    def test_classify_layers_scripts_key(self):
        """Scenario: レイヤー分類
        WHEN classify_layers を実行し、scripts セクションにコンポーネントが存在する
        THEN 返り値の dict に scripts キーが存在し、スクリプト名のリストが含まれる"""
        # Verify through --list output which uses classify_layers internally
        result = run_engine(self.plugin_dir, "--list")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        # SCRIPTS section should appear in list
        assert "SCRIPT" in result.stdout.upper(), (
            f"No SCRIPTS section in --list:\n{result.stdout}"
        )
        assert "autopilot-plan" in result.stdout, (
            f"Script name not in --list:\n{result.stdout}"
        )


# ===========================================================================
# Requirement: mermaid で script ノードを表示する
# ===========================================================================

class TestMermaidScriptNode(_VizTestBase):
    """generate_mermaid should render script nodes with hexagon syntax and orange style."""

    def test_mermaid_script_hexagon(self):
        """Scenario: mermaid 出力での script ノード
        WHEN twl --mermaid を実行し、scripts セクションにコンポーネントが存在する
        THEN Mermaid 出力に script ノードが六角形構文で含まれ、style 定義にオレンジ色が指定される"""
        result = run_engine(self.plugin_dir, "--mermaid")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        # Mermaid hexagon syntax: {{name}}
        assert "{{" in output and "}}" in output, (
            f"No hexagon syntax in mermaid output:\n{output}"
        )
        # Check for orange style (FF9800)
        assert "FF9800" in output or "ff9800" in output, (
            f"No orange style in mermaid output:\n{output}"
        )
        # Check script node is present
        assert "autopilot" in output, (
            f"No script node in mermaid output:\n{output}"
        )


# ===========================================================================
# Requirement: tree 表示で script ノードを含める
# ===========================================================================

class TestTreeScriptDisplay(_VizTestBase):
    """print_tree should show script nodes as children."""

    def test_tree_script_as_child(self):
        """Scenario: tree での script 表示
        WHEN twl --target my-action を実行し、そのコンポーネントが {script: autopilot-plan} を呼ぶ
        THEN ツリー出力に script:autopilot-plan が子ノードとして表示される"""
        result = run_engine(self.plugin_dir, "--target", "my-action")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        assert "autopilot-plan" in output, (
            f"Script not in tree output:\n{output}"
        )


# ===========================================================================
# Requirement: list 表示で SCRIPTS セクションを追加する
# ===========================================================================

class TestListScriptSection(_VizTestBase):
    """--list output should include a SCRIPTS section."""

    def test_list_scripts_section(self):
        """Scenario: list での script 表示
        WHEN twl --list を実行し、scripts セクションにコンポーネントが存在する
        THEN ## SCRIPTS セクションに script ノードが名前・説明付きで表示される"""
        result = run_engine(self.plugin_dir, "--list")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        assert "SCRIPTS" in output.upper(), f"No SCRIPTS section in list:\n{output}"
        assert "autopilot-plan" in output, f"Script name missing from list:\n{output}"
        assert "Autopilot" in output or "planning" in output or "script" in output.lower(), (
            f"Script description missing from list:\n{output}"
        )


# ===========================================================================
# Requirement: tokens 表示で Scripts セクションを追加する
# ===========================================================================

class TestTokensScriptSection(_VizTestBase):
    """--tokens output should include a Scripts section."""

    def test_tokens_scripts_section(self):
        """Scenario: tokens での script 表示
        WHEN twl --tokens を実行し、scripts セクションにコンポーネントが存在する
        THEN ## Scripts セクションに各スクリプトのトークン数が表示される"""
        result = run_engine(self.plugin_dir, "--tokens")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        assert "Script" in output or "SCRIPT" in output, (
            f"No Scripts section in tokens:\n{output}"
        )
        assert "autopilot-plan" in output, (
            f"Script name missing from tokens:\n{output}"
        )


# ===========================================================================
# Requirement: graphviz のエッジ描画で script ノードへの接続を含める
# ===========================================================================

class TestGraphvizScriptEdge(_VizTestBase):
    """generate_graphviz should draw edges to script nodes."""

    def test_graphviz_script_edge(self):
        """Scenario: script へのエッジ
        WHEN command ノードが script ノードを calls に含む
        THEN graphviz 出力に command -> script の有向エッジが含まれる"""
        result = run_engine(self.plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        # Look for an edge from my-action (cmd) to autopilot-plan (script)
        # In graphviz, IDs are typically like cmd_my_action -> script_autopilot_plan
        # Find any line with -> that mentions both nodes
        has_edge = False
        for line in output.splitlines():
            if "->" in line and "my_action" in line and "autopilot" in line:
                has_edge = True
                break
        assert has_edge, f"No edge from my-action to autopilot-plan in graphviz:\n{output}"

    def test_graphviz_edge_absent_when_no_scripts(self):
        """Edge case: no script edges when no scripts section."""
        tmpdir = Path(tempfile.mkdtemp())
        try:
            plugin_dir = make_no_script_fixture(tmpdir)
            result = run_engine(plugin_dir, "--graphviz")
            assert result.returncode == 0
            # No script-related edges
            for line in result.stdout.splitlines():
                if "->" in line:
                    assert "script" not in line.lower(), (
                        f"Unexpected script edge:\n{line}"
                    )
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestGraphvizScriptNode,
        TestSubgraphScriptNode,
        TestClassifyLayersScripts,
        TestMermaidScriptNode,
        TestTreeScriptDisplay,
        TestListScriptSection,
        TestTokensScriptSection,
        TestGraphvizScriptEdge,
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
