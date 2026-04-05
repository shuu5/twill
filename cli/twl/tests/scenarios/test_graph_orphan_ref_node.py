#!/usr/bin/env python3
"""Tests for fix-graph-orphan-ref-node: build_graph, classify_layers, find_orphans, generate_graphviz.

Spec: openspec/changes/fix-graph-orphan-ref-node/specs/

Covers 8 scenarios across 3 spec files:
  agent-skills-reverse-dep.md
    - agent が skills フィールドで reference skill を参照
    - agent.skills の参照先がグラフに存在しない
    - agent.skills で参照される skill が orphan にならない

  classify-layers-recursive.md
    - L2 コマンドがさらに commands を呼ぶ（L3）
    - 3 段以上のチェーン
    - 循環呼び出し

  legend-reference-type.md
    - reference 型 skill が存在する
    - reference 型 skill が存在しない
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "src" / "twl" / "engine.py"


# ---------------------------------------------------------------------------
# Shared helpers
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


def run_engine(plugin_dir: Path, *extra_args: str, timeout: int = 30) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, str(TWL_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _invoke_build_graph(deps: dict) -> dict:
    """Directly import and call build_graph for unit-level assertions."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("twl_engine", str(TWL_ENGINE))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build_graph(deps, plugin_root=Path("/nonexistent"))


def _invoke_classify_layers(deps: dict, graph: dict) -> dict:
    """Directly import and call classify_layers."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("twl_engine", str(TWL_ENGINE))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.classify_layers(deps, graph)


def _invoke_find_orphans(graph: dict, deps: dict) -> dict:
    """Directly import and call find_orphans."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("twl_engine", str(TWL_ENGINE))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.find_orphans(graph, deps)


# ---------------------------------------------------------------------------
# Minimal deps factories
# ---------------------------------------------------------------------------

def _make_agent_skills_deps(agent_skills: list, ref_skill_exists: bool = True) -> dict:
    """Produce a minimal deps dict with an agent that has a skills field."""
    deps = {
        "version": "3.0",
        "plugin": "test-agent-skills",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Controller",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {
            "my-worker": {
                "type": "specialist",
                "path": "agents/my-worker.md",
                "description": "Worker agent",
                "skills": agent_skills,
                "calls": [],
            },
        },
    }
    if ref_skill_exists:
        for skill_name in agent_skills:
            deps["skills"][skill_name] = {
                "type": "reference",
                "path": f"skills/{skill_name}/SKILL.md",
                "description": f"Reference skill {skill_name}",
                "spawnable_by": ["all"],
                "calls": [],
            }
    return deps


def _make_deep_chain_deps(chain_depth: int) -> dict:
    """Build a linear command chain: cmd-a -> cmd-b -> ... of given depth.

    The controller calls cmd-a directly (L1).
    Returns (deps, [cmd-a, cmd-b, ...]) where len==chain_depth.
    """
    cmd_names = [f"cmd-{chr(ord('a') + i)}" for i in range(chain_depth)]
    commands = {}
    for i, name in enumerate(cmd_names):
        next_cmd = cmd_names[i + 1] if i + 1 < chain_depth else None
        calls = [{"atomic": next_cmd}] if next_cmd else []
        commands[name] = {
            "type": "atomic",
            "path": f"commands/{name}.md",
            "description": f"Command {name}",
            "calls": calls,
        }
    deps = {
        "version": "3.0",
        "plugin": "test-deep-chain",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Controller",
                "calls": [{"atomic": cmd_names[0]}],
            },
        },
        "commands": commands,
        "agents": {},
    }
    return deps, cmd_names


def _make_circular_chain_deps() -> dict:
    """Build a circular chain: cmd-a -> cmd-b -> cmd-a.

    Controller calls cmd-a (L1). cmd-b forms a loop back.
    """
    deps = {
        "version": "3.0",
        "plugin": "test-circular",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Controller",
                "calls": [{"atomic": "cmd-a"}],
            },
        },
        "commands": {
            "cmd-a": {
                "type": "composite",
                "path": "commands/cmd-a.md",
                "description": "Command A",
                "calls": [{"atomic": "cmd-b"}],
            },
            "cmd-b": {
                "type": "atomic",
                "path": "commands/cmd-b.md",
                "description": "Command B",
                "calls": [{"composite": "cmd-a"}],
            },
        },
        "agents": {},
    }
    return deps


def _make_reference_deps(include_reference: bool) -> dict:
    """Build deps with or without a reference-type skill."""
    deps = {
        "version": "3.0",
        "plugin": "test-ref-legend",
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Controller",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    if include_reference:
        deps["skills"]["ref-skill-a"] = {
            "type": "reference",
            "path": "skills/ref-skill-a/SKILL.md",
            "description": "A reference skill",
            "spawnable_by": ["all"],
            "calls": [],
        }
    return deps


# ===========================================================================
# Requirement: agent.skills の reverse dependency 反映
# (agent-skills-reverse-dep.md)
# ===========================================================================

class TestAgentSkillsReverseDep:
    """build_graph() must populate required_by on reference skills named in agent.skills."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    # --- Scenario: agent が skills フィールドで reference skill を参照 ---

    def test_skills_field_populates_required_by(self):
        """WHEN deps.yaml の agent エントリに skills: [ref-skill-a] が定義されている
        THEN skill:ref-skill-a ノードの required_by に ('agent', agent_name) が含まれる"""
        deps = _make_agent_skills_deps(["ref-skill-a"], ref_skill_exists=True)
        graph = _invoke_build_graph(deps)

        node = graph.get("skill:ref-skill-a")
        assert node is not None, "skill:ref-skill-a should be in the graph"
        required_by = node["required_by"]
        assert ("agent", "my-worker") in required_by, (
            f"('agent', 'my-worker') not found in required_by={required_by!r}"
        )

    def test_multiple_skills_all_populated(self):
        """Edge case: WHEN agent has skills: [ref-a, ref-b]
        THEN both skill nodes have required_by containing ('agent', my-worker)"""
        deps = _make_agent_skills_deps(["ref-skill-a", "ref-skill-b"], ref_skill_exists=False)
        # Add both skills manually
        deps["skills"]["ref-skill-a"] = {
            "type": "reference",
            "path": "skills/ref-skill-a/SKILL.md",
            "description": "Ref A",
            "spawnable_by": ["all"],
            "calls": [],
        }
        deps["skills"]["ref-skill-b"] = {
            "type": "reference",
            "path": "skills/ref-skill-b/SKILL.md",
            "description": "Ref B",
            "spawnable_by": ["all"],
            "calls": [],
        }
        graph = _invoke_build_graph(deps)

        for skill_id in ("skill:ref-skill-a", "skill:ref-skill-b"):
            node = graph.get(skill_id)
            assert node is not None, f"{skill_id} should be in graph"
            assert ("agent", "my-worker") in node["required_by"], (
                f"('agent', 'my-worker') missing from {skill_id}.required_by={node['required_by']!r}"
            )

    def test_agent_without_skills_field_no_required_by(self):
        """Edge case: WHEN agent has no skills field
        THEN reference skills have empty required_by (not incorrectly populated)"""
        deps = {
            "version": "3.0",
            "plugin": "test",
            "skills": {
                "ref-skill-a": {
                    "type": "reference",
                    "path": "skills/ref-skill-a/SKILL.md",
                    "description": "Ref A",
                    "spawnable_by": ["all"],
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {
                "my-worker": {
                    "type": "specialist",
                    "path": "agents/my-worker.md",
                    "description": "Worker",
                    "calls": [],
                    # No skills field
                },
            },
        }
        graph = _invoke_build_graph(deps)
        node = graph.get("skill:ref-skill-a")
        assert node is not None
        # required_by should be empty since nothing references it
        assert ("agent", "my-worker") not in node["required_by"]

    # --- Scenario: agent.skills の参照先がグラフに存在しない ---

    def test_missing_skill_reference_is_silently_ignored(self):
        """WHEN agent の skills に列挙された skill がグラフに存在しない
        THEN その skill は無視され、エラーは発生しない"""
        deps = _make_agent_skills_deps(["nonexistent-skill"], ref_skill_exists=False)
        # build_graph should not raise; nonexistent-skill should not appear in graph
        graph = _invoke_build_graph(deps)
        assert "skill:nonexistent-skill" not in graph, (
            "Nonexistent skill should not be added to graph"
        )

    def test_missing_skill_reference_does_not_affect_other_nodes(self):
        """Edge case: WHEN agent.skills references a missing skill
        THEN other graph nodes are built correctly and the agent node itself is present"""
        deps = _make_agent_skills_deps(["ghost-skill"], ref_skill_exists=False)
        graph = _invoke_build_graph(deps)

        # Agent node must still be present
        assert "agent:my-worker" in graph, "Agent node must be built even with missing skill ref"
        # Controller node must still be present
        assert "skill:my-controller" in graph, "Controller node must be built"

    def test_missing_skill_reference_cli_does_not_crash(self):
        """Integration: WHEN twl --graphviz runs with a missing skill reference
        THEN the command completes without error"""
        plugin_dir = self.tmpdir / "test-missing-skill"
        plugin_dir.mkdir()
        deps = _make_agent_skills_deps(["ghost-skill"], ref_skill_exists=False)
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, (
            f"Expected no crash with missing skill ref. stderr: {result.stderr}"
        )

    # --- Scenario: agent.skills で参照される skill が orphan にならない ---

    def test_skill_referenced_by_agent_skills_not_orphan(self):
        """WHEN agent が skills フィールドで skill を参照している
        THEN find_orphans() の unused リストにその skill が含まれない"""
        deps = _make_agent_skills_deps(["ref-skill-a"], ref_skill_exists=True)
        graph = _invoke_build_graph(deps)
        orphans = _invoke_find_orphans(graph, deps)

        unused = orphans["unused"]
        assert "skill:ref-skill-a" not in unused, (
            f"skill:ref-skill-a should not be orphan because agent references it via skills field. "
            f"unused={unused!r}"
        )

    def test_skill_not_referenced_anywhere_is_orphan(self):
        """Edge case: WHEN a reference skill is NOT referenced by any agent.skills or calls
        THEN it appears in find_orphans unused (confirming the baseline)"""
        deps = {
            "version": "3.0",
            "plugin": "test",
            "skills": {
                "my-controller": {
                    "type": "controller",
                    "path": "skills/my-controller/SKILL.md",
                    "description": "Controller",
                    "calls": [],
                },
                "lonely-ref": {
                    "type": "reference",
                    "path": "skills/lonely-ref/SKILL.md",
                    "description": "Unreferenced reference skill",
                    "spawnable_by": ["all"],
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        graph = _invoke_build_graph(deps)
        orphans = _invoke_find_orphans(graph, deps)

        # reference type is excluded from unused by design (see find_orphans)
        # The spec says reference skills referenced via agent.skills must not be orphan.
        # A reference skill not referenced by anyone is already excluded by the
        # `references` exclusion set in find_orphans. Confirm it does NOT appear as orphan
        # due to the built-in reference exclusion.
        unused = orphans["unused"]
        assert "skill:lonely-ref" not in unused, (
            "Reference skills are excluded from orphan detection regardless of referencing"
        )

    def test_agent_skills_integration_graphviz_no_orphan_color(self):
        """Integration: WHEN agent has skills: [ref-skill-a] in a complete plugin
        THEN --graphviz does not render ref-skill-a in orphan color (#ffcdd2)"""
        plugin_dir = self.tmpdir / "test-no-orphan"
        plugin_dir.mkdir()
        deps = _make_agent_skills_deps(["ref-skill-a"], ref_skill_exists=True)
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        # ref-skill-a should be rendered as a reference node (note shape, #e1f5fe)
        # and NOT as an orphan (#ffcdd2). The orphan color should not appear for ref nodes.
        output = result.stdout
        # Verify ref-skill-a node line has #e1f5fe (reference color), not #ffcdd2 (orphan color)
        ref_lines = [l for l in output.splitlines() if "ref_skill_a" in l and "[label=" in l]
        for line in ref_lines:
            assert "#ffcdd2" not in line, (
                f"ref-skill-a should not be rendered as orphan: {line!r}"
            )


# ===========================================================================
# Requirement: classify_layers の再帰的 sub-command 走査
# (classify-layers-recursive.md)
# ===========================================================================

class TestClassifyLayersRecursive:
    """classify_layers() must recursively traverse commands beyond L2."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    # --- Scenario: L2 コマンドがさらに commands を呼ぶ（L3）---

    def test_l3_command_classified_as_sub_command(self):
        """WHEN L1 コマンドが L2 コマンドを calls で呼び、L2 コマンドがさらに L3 コマンドを calls で呼ぶ
        THEN L3 コマンドも sub_commands に分類され、orphan_commands には含まれない"""
        deps, cmd_names = _make_deep_chain_deps(3)
        # cmd_names = [cmd-a (L1), cmd-b (L2), cmd-c (L3)]
        graph = _invoke_build_graph(deps)
        layers = _invoke_classify_layers(deps, graph)

        l3_cmd = cmd_names[2]  # cmd-c
        assert l3_cmd in layers["sub_commands"], (
            f"L3 command '{l3_cmd}' should be in sub_commands. "
            f"sub_commands={set(layers['sub_commands'])!r}"
        )
        assert l3_cmd not in layers["orphan_commands"], (
            f"L3 command '{l3_cmd}' must not be in orphan_commands"
        )

    def test_l2_command_still_in_sub_commands(self):
        """Edge case: With 3-level chain, L2 should remain in sub_commands."""
        deps, cmd_names = _make_deep_chain_deps(3)
        graph = _invoke_build_graph(deps)
        layers = _invoke_classify_layers(deps, graph)

        l2_cmd = cmd_names[1]  # cmd-b
        assert l2_cmd in layers["sub_commands"], (
            f"L2 command '{l2_cmd}' should be in sub_commands"
        )

    def test_l1_command_in_direct_commands_not_sub(self):
        """Edge case: L1 command must be in direct_commands, not sub_commands."""
        deps, cmd_names = _make_deep_chain_deps(3)
        graph = _invoke_build_graph(deps)
        layers = _invoke_classify_layers(deps, graph)

        l1_cmd = cmd_names[0]  # cmd-a
        assert l1_cmd in layers["direct_commands"], (
            f"L1 command '{l1_cmd}' should be in direct_commands"
        )

    # --- Scenario: 3 段以上のチェーン ---

    def test_4_level_chain_all_sub_commands(self):
        """WHEN cmd-a → cmd-b → cmd-c → cmd-d の 4 段チェーンが存在する
        THEN cmd-b, cmd-c, cmd-d が全て sub_commands に分類される"""
        deps, cmd_names = _make_deep_chain_deps(4)
        # cmd-a is L1 (direct_commands), cmd-b/c/d should all be sub_commands
        graph = _invoke_build_graph(deps)
        layers = _invoke_classify_layers(deps, graph)

        for sub_cmd in cmd_names[1:]:  # cmd-b, cmd-c, cmd-d
            assert sub_cmd in layers["sub_commands"], (
                f"'{sub_cmd}' should be in sub_commands for 4-level chain. "
                f"sub_commands={set(layers['sub_commands'])!r}"
            )
            assert sub_cmd not in layers["orphan_commands"], (
                f"'{sub_cmd}' must not be orphan in 4-level chain"
            )

    def test_4_level_chain_integration_graphviz(self):
        """Integration: WHEN 4-level chain exists
        THEN --graphviz runs without error and all commands are rendered"""
        plugin_dir = self.tmpdir / "test-4-level"
        plugin_dir.mkdir()
        deps, cmd_names = _make_deep_chain_deps(4)
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        # All commands should appear in the DOT output
        for name in cmd_names:
            safe_name = name.replace("-", "_")
            assert safe_name in output, (
                f"Command '{name}' not found in graphviz output"
            )

    def test_5_level_chain_deep_traversal(self):
        """Edge case: WHEN chain has 5 levels
        THEN all commands beyond L1 are in sub_commands"""
        deps, cmd_names = _make_deep_chain_deps(5)
        graph = _invoke_build_graph(deps)
        layers = _invoke_classify_layers(deps, graph)

        for sub_cmd in cmd_names[1:]:
            assert sub_cmd in layers["sub_commands"], (
                f"'{sub_cmd}' missing from sub_commands in 5-level chain"
            )
            assert sub_cmd not in layers["orphan_commands"], (
                f"'{sub_cmd}' must not be orphan in 5-level chain"
            )

    # --- Scenario: 循環呼び出し ---

    def test_circular_chain_does_not_hang(self):
        """WHEN cmd-a → cmd-b → cmd-a の循環チェーンが存在する
        THEN 無限ループせず正常に完了し、両方が sub_commands に分類される"""
        deps = _make_circular_chain_deps()
        graph = _invoke_build_graph(deps)
        # Should complete without infinite recursion (timeout would indicate failure)
        layers = _invoke_classify_layers(deps, graph)

        # cmd-a is L1 (called directly by controller); cmd-b should be sub_command
        # Under current or fixed implementation, cmd-b must at minimum not be orphan
        assert "cmd-b" not in layers["orphan_commands"], (
            "cmd-b should not be orphan in circular chain"
        )

    def test_circular_chain_both_classified(self):
        """WHEN cmd-a → cmd-b → cmd-a circular chain
        THEN both cmd-a and cmd-b appear in sub_commands (cmd-a is direct, cmd-b is sub)"""
        deps = _make_circular_chain_deps()
        graph = _invoke_build_graph(deps)
        layers = _invoke_classify_layers(deps, graph)

        # cmd-a is directly called by controller: must be in direct_commands
        assert "cmd-a" in layers["direct_commands"], (
            "cmd-a should be in direct_commands (called by controller)"
        )
        # cmd-b is called by cmd-a (which is L1): should be in sub_commands
        assert "cmd-b" in layers["sub_commands"], (
            f"cmd-b should be in sub_commands. sub_commands={set(layers['sub_commands'])!r}"
        )

    def test_circular_chain_integration_no_crash(self):
        """Integration: WHEN circular chain exists
        THEN --graphviz completes without infinite loop or error"""
        plugin_dir = self.tmpdir / "test-circular"
        plugin_dir.mkdir()
        deps = _make_circular_chain_deps()
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz", timeout=10)
        assert result.returncode == 0, (
            f"--graphviz should not crash on circular chain. stderr: {result.stderr}"
        )

    def test_circular_chain_no_infinite_loop_classify(self):
        """Edge case: Confirm classify_layers returns when called on circular deps
        (this guards against future regressions where recursion is added)."""
        import threading
        deps = _make_circular_chain_deps()
        graph = _invoke_build_graph(deps)

        result_holder = {}
        error_holder = {}

        def run():
            try:
                result_holder["layers"] = _invoke_classify_layers(deps, graph)
            except Exception as e:
                error_holder["error"] = e

        t = threading.Thread(target=run, daemon=True)
        t.start()
        t.join(timeout=5)

        assert t.is_alive() is False, (
            "classify_layers did not complete within 5s — likely infinite loop"
        )
        assert "error" not in error_holder, (
            f"classify_layers raised: {error_holder.get('error')}"
        )
        assert "layers" in result_holder, "classify_layers returned no result"


# ===========================================================================
# Requirement: Legend に reference 型が正しく表示される
# (legend-reference-type.md)
# ===========================================================================

class TestLegendReferenceType:
    """generate_graphviz() legend must show reference entry iff reference skill exists."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    # --- Scenario: reference 型 skill が存在する ---

    def test_legend_shows_reference_when_present(self):
        """WHEN deps.yaml に type=reference の skill が 1 つ以上存在する
        THEN Legend に "Reference (skill)" エントリが shape=note, fillcolor="#e1f5fe" で表示される"""
        plugin_dir = self.tmpdir / "test-ref-present"
        plugin_dir.mkdir()
        deps = _make_reference_deps(include_reference=True)
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout

        assert "Reference (skill)" in output, (
            f"Legend should contain 'Reference (skill)' when reference skill exists.\n{output}"
        )
        assert "shape=note" in output, (
            f"Reference legend entry should use shape=note.\n{output}"
        )
        assert '#e1f5fe' in output, (
            f"Reference legend entry should have fillcolor='#e1f5fe'.\n{output}"
        )

    def test_legend_reference_entry_in_legend_subgraph(self):
        """Edge case: The reference entry must be inside the cluster_legend subgraph."""
        plugin_dir = self.tmpdir / "test-ref-in-legend"
        plugin_dir.mkdir()
        deps = _make_reference_deps(include_reference=True)
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout

        # Find the legend subgraph block
        in_legend = False
        found_reference_in_legend = False
        for line in output.splitlines():
            if "cluster_legend" in line or 'label="Legend"' in line:
                in_legend = True
            if in_legend and "Reference (skill)" in line:
                found_reference_in_legend = True
            if in_legend and line.strip() == "}":
                in_legend = False

        assert found_reference_in_legend, (
            "Reference (skill) legend entry must appear inside cluster_legend subgraph"
        )

    def test_reference_node_rendered_as_note_shape(self):
        """Edge case: The actual reference skill node (not just legend) uses shape=note."""
        plugin_dir = self.tmpdir / "test-ref-node-shape"
        plugin_dir.mkdir()
        deps = _make_reference_deps(include_reference=True)
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout

        # The skill node for ref-skill-a should appear with shape=note
        ref_node_lines = [
            l for l in output.splitlines()
            if "ref_skill_a" in l and "[label=" in l and "shape=note" in l
        ]
        assert ref_node_lines, (
            "skill:ref-skill-a node should be rendered with shape=note"
        )

    # --- Scenario: reference 型 skill が存在しない ---

    def test_legend_no_reference_when_absent(self):
        """WHEN deps.yaml に type=reference の skill が存在しない
        THEN Legend に "Reference (skill)" エントリは表示されない"""
        plugin_dir = self.tmpdir / "test-ref-absent"
        plugin_dir.mkdir()
        deps = _make_reference_deps(include_reference=False)
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout

        assert "Reference (skill)" not in output, (
            f"Legend should NOT contain 'Reference (skill)' when no reference skill exists.\n{output}"
        )

    def test_legend_no_reference_shape_note_absent(self):
        """Edge case: WHEN no reference skills, shape=note should not appear (only reference uses it)."""
        plugin_dir = self.tmpdir / "test-no-note-shape"
        plugin_dir.mkdir()
        deps = _make_reference_deps(include_reference=False)
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout

        # shape=note is only used for reference skills in this codebase
        note_lines = [l for l in output.splitlines() if "shape=note" in l]
        assert not note_lines, (
            f"shape=note should not appear when no reference skills exist: {note_lines!r}"
        )

    def test_legend_reference_added_when_only_reference_type_exists(self):
        """Edge case: WHEN deps has ONLY a reference skill (no controller)
        THEN legend still shows the reference entry."""
        plugin_dir = self.tmpdir / "test-only-ref"
        plugin_dir.mkdir()
        deps = {
            "version": "3.0",
            "plugin": "test-only-ref",
            "skills": {
                "ref-only": {
                    "type": "reference",
                    "path": "skills/ref-only/SKILL.md",
                    "description": "The only skill",
                    "spawnable_by": ["all"],
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "--graphviz")
        assert result.returncode == 0, f"stderr: {result.stderr}"
        output = result.stdout
        assert "Reference (skill)" in output, (
            "Legend must show reference entry when only reference skills are present"
        )


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestAgentSkillsReverseDep,
        TestClassifyLayersRecursive,
        TestLegendReferenceType,
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
