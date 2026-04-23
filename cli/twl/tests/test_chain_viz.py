"""Tests for twl chain viz: Mermaid flowchart generation from deps.yaml chains."""

import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def make_viz_fixture(tmpdir: Path) -> Path:
    """Create a minimal v3.0 plugin fixture with dispatch_mode metadata."""
    plugin_dir = tmpdir / "test-plugin-viz"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-viz",
        "chains": {
            "setup": {
                "description": "Setup chain",
                "type": "A",
                "steps": ["init", "crg-auto-build", "change-propose", "ac-extract"],
            },
            "pr-verify": {
                "description": "PR verify chain",
                "steps": ["ts-preflight", "phase-review"],
            },
        },
        "skills": {},
        "commands": {
            "init": {
                "type": "atomic",
                "dispatch_mode": "runner",
                "path": "commands/init.md",
                "description": "Init step",
            },
            "crg-auto-build": {
                "type": "atomic",
                "dispatch_mode": "runner",
                "path": "commands/crg-auto-build.md",
                "description": "CRG build",
            },
            "change-propose": {
                "type": "atomic",
                "dispatch_mode": "llm",
                "path": "commands/change-propose.md",
                "description": "Change propose",
            },
            "ac-extract": {
                "type": "atomic",
                "dispatch_mode": "runner",
                "path": "commands/ac-extract.md",
                "description": "AC extract",
            },
            "ts-preflight": {
                "type": "atomic",
                "dispatch_mode": "runner",
                "path": "commands/ts-preflight.md",
                "description": "TS preflight",
            },
            "phase-review": {
                "type": "composite",
                "dispatch_mode": "composite",
                "path": "commands/phase-review.md",
                "description": "Phase review",
            },
        },
        "agents": {},
    }

    (plugin_dir / "deps.yaml").write_text(yaml.dump(deps), encoding="utf-8")
    (plugin_dir / "README.md").write_text(
        "# Test\n\n<!-- CHAIN-FLOW-START -->\n<!-- CHAIN-FLOW-END -->\n",
        encoding="utf-8",
    )
    return plugin_dir


# ---------------------------------------------------------------------------
# Unit tests (import-based)
# ---------------------------------------------------------------------------

class TestChainVizSingle:
    def setup_method(self):
        self._tmpdir_obj = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmpdir_obj.name)
        self.plugin_dir = make_viz_fixture(self.tmpdir)
        deps_path = self.plugin_dir / "deps.yaml"
        with open(deps_path, encoding="utf-8") as f:
            self.deps = yaml.safe_load(f)

    def teardown_method(self):
        self._tmpdir_obj.cleanup()

    def test_single_chain_returns_mermaid_fenced(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "setup")
        assert output.startswith("```mermaid")
        assert output.strip().endswith("```")

    def test_single_chain_contains_flowchart_td(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "setup")
        assert "flowchart TD" in output

    def test_single_chain_has_subgraph(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "setup")
        assert "subgraph" in output
        assert "setup" in output

    def test_single_chain_all_steps_present(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "setup")
        for step in ["init", "crg-auto-build", "change-propose", "ac-extract"]:
            assert step in output

    def test_dispatch_mode_classes_applied(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "setup")
        # runner → script class
        assert ":::script" in output
        # llm → llm class
        assert ":::llm" in output

    def test_classdefs_present_no_quick(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "setup")
        assert "classDef script" in output
        assert "classDef llm" in output

    def test_classdefs_present(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "setup")
        assert "classDef script fill:#2e7d32" in output
        assert "classDef llm fill:#1565c0" in output
        assert "classDef composite fill:#7b1fa2" in output
        assert "classDef marker fill:#616161" in output

    def test_unknown_chain_returns_error_comment(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "nonexistent")
        assert "Error" in output or "not found" in output

    def test_normal_flow_arrows(self):
        from twl.chain.viz import chain_viz_single
        output = chain_viz_single(self.deps, "setup")
        # Should have --> arrows between consecutive steps
        assert "-->" in output


class TestChainVizAll:
    def setup_method(self):
        self._tmpdir_obj = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmpdir_obj.name)
        self.plugin_dir = make_viz_fixture(self.tmpdir)
        deps_path = self.plugin_dir / "deps.yaml"
        with open(deps_path, encoding="utf-8") as f:
            self.deps = yaml.safe_load(f)

    def teardown_method(self):
        self._tmpdir_obj.cleanup()

    def test_all_chains_returns_mermaid(self):
        from twl.chain.viz import chain_viz_all
        output = chain_viz_all(self.deps)
        assert "```mermaid" in output
        assert "flowchart TD" in output

    def test_all_chains_contains_both_chains(self):
        from twl.chain.viz import chain_viz_all
        output = chain_viz_all(self.deps)
        assert "setup" in output
        assert "pr-verify" in output

    def test_all_chains_has_multiple_subgraphs(self):
        from twl.chain.viz import chain_viz_all
        output = chain_viz_all(self.deps)
        assert output.count("subgraph") >= 2

    def test_empty_chains_returns_no_chains(self):
        from twl.chain.viz import chain_viz_all
        output = chain_viz_all({"chains": {}})
        assert "No chains" in output




class TestUpdateReadme:
    def setup_method(self):
        self._tmpdir_obj = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmpdir_obj.name)
        self.plugin_dir = make_viz_fixture(self.tmpdir)

    def teardown_method(self):
        self._tmpdir_obj.cleanup()

    def test_update_readme_inserts_content(self):
        from twl.chain.viz import update_readme_chain_flow
        result = update_readme_chain_flow(self.plugin_dir, "```mermaid\nflowchart TD\n```")
        assert result is True
        content = (self.plugin_dir / "README.md").read_text(encoding="utf-8")
        assert "<!-- CHAIN-FLOW-START -->" in content
        assert "<!-- CHAIN-FLOW-END -->" in content
        assert "flowchart TD" in content

    def test_update_readme_fails_when_markers_missing(self):
        from twl.chain.viz import update_readme_chain_flow
        readme = self.plugin_dir / "README.md"
        readme.write_text("# No markers here\n", encoding="utf-8")
        result = update_readme_chain_flow(self.plugin_dir, "content")
        assert result is False

    def test_update_readme_fails_when_no_readme(self):
        from twl.chain.viz import update_readme_chain_flow
        result = update_readme_chain_flow(self.tmpdir / "nonexistent", "content")
        assert result is False


# ---------------------------------------------------------------------------
# CLI integration tests
# ---------------------------------------------------------------------------

def run_twl(args: list, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "twl"] + args,
        cwd=cwd,
        capture_output=True,
        text=True,
    )


class TestChainVizCLI:
    def setup_method(self):
        self._tmpdir_obj = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmpdir_obj.name)
        self.plugin_dir = make_viz_fixture(self.tmpdir)

    def teardown_method(self):
        self._tmpdir_obj.cleanup()

    def test_cli_single_chain_exits_0(self):
        result = run_twl(["chain", "viz", "setup"], cwd=self.plugin_dir)
        assert result.returncode == 0, result.stderr

    def test_cli_single_chain_outputs_mermaid(self):
        result = run_twl(["chain", "viz", "setup"], cwd=self.plugin_dir)
        assert "mermaid" in result.stdout
        assert "flowchart TD" in result.stdout

    def test_cli_all_chains_exits_0(self):
        result = run_twl(["chain", "viz", "--all"], cwd=self.plugin_dir)
        assert result.returncode == 0, result.stderr

    def test_cli_unknown_chain_exits_1(self):
        result = run_twl(["chain", "viz", "nonexistent"], cwd=self.plugin_dir)
        assert result.returncode == 1

    def test_cli_update_readme(self):
        result = run_twl(["chain", "viz", "--all", "--update-readme"], cwd=self.plugin_dir)
        assert result.returncode == 0, result.stderr
        content = (self.plugin_dir / "README.md").read_text(encoding="utf-8")
        assert "flowchart TD" in content

    def test_cli_no_args_exits_1(self):
        result = run_twl(["chain", "viz"], cwd=self.plugin_dir)
        assert result.returncode == 1

    def test_cli_all_and_name_mutually_exclusive(self):
        result = run_twl(["chain", "viz", "--all", "setup"], cwd=self.plugin_dir)
        assert result.returncode == 1
