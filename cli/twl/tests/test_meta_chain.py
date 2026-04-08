#!/usr/bin/env python3
"""Tests for meta_chains: deps.yaml schema validation, integrity checks, and Template D generation."""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def make_meta_chain_fixture(tmpdir: Path) -> Path:
    """Create a valid v3.0 plugin fixture with meta_chains section."""
    plugin_dir = tmpdir / "test-plugin-meta"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "testmeta",
        "chains": {
            "setup": {
                "type": "A",
                "description": "Setup chain",
                "steps": ["my-workflow"],
            },
            "pr-verify": {
                "type": "B",
                "description": "PR verify chain",
                "steps": ["my-action"],
            },
        },
        "meta_chains": {
            "worker-lifecycle": {
                "type": "meta",
                "description": "Worker lifecycle meta chain",
                "flow": [
                    {
                        "id": "setup",
                        "chain": "setup",
                        "skill": "my-workflow",
                        "next": [
                            {"condition": "autopilot", "goto": "pr-verify"},
                            {"condition": "!autopilot", "stop": True,
                             "message": "setup 完了。次: /twl:my-workflow-skill"},
                        ],
                    },
                    {
                        "id": "pr-verify",
                        "chain": "pr-verify",
                        "skill": "my-workflow-skill",
                        "next": [
                            {"condition": "autopilot", "goto": "done"},
                            {"condition": "!autopilot", "stop": True,
                             "message": "pr-verify 完了。次のステップを実行してください"},
                        ],
                    },
                    {
                        "id": "done",
                        "terminal": True,
                    },
                ],
            },
        },
        "skills": {
            "my-controller": {
                "type": "controller",
                "path": "skills/my-controller/SKILL.md",
                "description": "Main controller",
                "calls": [
                    {"workflow": "my-workflow", "step": "1"},
                ],
            },
            "my-workflow-skill": {
                "type": "workflow",
                "path": "skills/my-workflow-skill/SKILL.md",
                "description": "A workflow skill",
                "calls": [],
            },
            "my-workflow": {
                "type": "workflow",
                "path": "skills/my-workflow/SKILL.md",
                "description": "A workflow",
                "chain": "setup",
                "step_in": {"parent": "my-controller"},
                "calls": [],
            },
        },
        "commands": {
            "my-action": {
                "type": "atomic",
                "path": "commands/my-action.md",
                "description": "An atomic command",
                "chain": "pr-verify",
                "calls": [],
            },
        },
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _load_deps(plugin_dir: Path) -> dict:
    return yaml.safe_load((plugin_dir / "deps.yaml").read_text())


def _create_component_files(plugin_dir: Path, deps: dict) -> None:
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


def run_twl(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    twl_wrapper = Path(__file__).parent.parent / "twl"
    if twl_wrapper.exists():
        return subprocess.run(
            [str(twl_wrapper)] + list(extra_args),
            cwd=str(plugin_dir),
            capture_output=True,
            text=True,
        )
    return subprocess.run(
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
        env={"PYTHONPATH": str(Path(__file__).parent.parent / "src"), "PATH": "/usr/bin:/bin"},
    )


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl via wrapper (uses correct PYTHONPATH for this worktree)."""
    twl_bin = Path(__file__).parent.parent / "twl"
    return subprocess.run(
        [str(twl_bin)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


class _MetaTestBase:
    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())
        self.plugin_dir = make_meta_chain_fixture(self.tmpdir)

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _modify_deps(self, mutator):
        deps = _load_deps(self.plugin_dir)
        mutator(deps)
        _write_deps(self.plugin_dir, deps)
        return deps


# ===========================================================================
# Requirement: meta_chains schema validation (v3-meta-chains-*)
# ===========================================================================

class TestMetaChainSchemaValidation(_MetaTestBase):
    """meta_chains section schema validation."""

    def test_valid_meta_chain_passes(self):
        """WHEN meta_chains has valid structure
        THEN --validate passes."""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        assert "v3-meta-chains" not in result.stdout

    def test_meta_chain_wrong_type_fails(self):
        """WHEN meta_chains entry has type != 'meta'
        THEN [v3-meta-chains-type-field] error."""
        def mutator(deps):
            deps["meta_chains"]["worker-lifecycle"]["type"] = "A"
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-meta-chains-type-field" in result.stdout

    def test_meta_chain_missing_flow_fails(self):
        """WHEN meta_chains entry has no flow field
        THEN [v3-meta-chains-flow] error."""
        def mutator(deps):
            del deps["meta_chains"]["worker-lifecycle"]["flow"]
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-meta-chains-flow" in result.stdout

    def test_meta_chain_node_missing_id_fails(self):
        """WHEN a flow node has no id field
        THEN [v3-meta-chains-node-id] error."""
        def mutator(deps):
            deps["meta_chains"]["worker-lifecycle"]["flow"][0] = {
                "chain": "setup",
                "next": [],
            }
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-meta-chains-node-id" in result.stdout

    def test_meta_chain_chain_ref_nonexistent_fails(self):
        """WHEN a flow node's chain field references non-existent chain
        THEN [v3-meta-chains-chain-ref] error."""
        def mutator(deps):
            deps["meta_chains"]["worker-lifecycle"]["flow"][0]["chain"] = "nonexistent-chain"
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-meta-chains-chain-ref" in result.stdout

    def test_meta_chain_goto_nonexistent_fails(self):
        """WHEN a flow node's next entry has goto referencing non-existent id
        THEN [v3-meta-chains-goto] error."""
        def mutator(deps):
            deps["meta_chains"]["worker-lifecycle"]["flow"][0]["next"][0]["goto"] = "ghost-id"
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode != 0
        assert "v3-meta-chains-goto" in result.stdout

    def test_meta_chain_null_chain_valid(self):
        """WHEN a flow node has chain: null
        THEN no error (null chain is valid for test-ready nodes)."""
        def mutator(deps):
            deps["meta_chains"]["worker-lifecycle"]["flow"].insert(1, {
                "id": "test-ready",
                "chain": None,
                "skill": "my-workflow-skill",
                "next": [{"goto": "pr-verify"}],
            })
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "v3-meta-chains-chain-ref" not in result.stdout


# ===========================================================================
# Requirement: meta chain integrity validation (meta-chain-integrity)
# ===========================================================================

class TestMetaChainIntegrity(_MetaTestBase):
    """meta chain transition integrity validation in chain_validate."""

    def test_valid_meta_chain_no_integrity_error(self):
        """WHEN meta chain has valid chain refs and goto targets
        THEN no meta-chain-integrity error."""
        result = run_engine(self.plugin_dir, "--validate")
        assert result.returncode == 0
        assert "[meta-chain-integrity]" not in result.stdout

    def test_meta_chain_nonexistent_chain_ref(self):
        """WHEN a meta chain flow node references non-existent chain
        THEN [meta-chain-integrity] CRITICAL."""
        def mutator(deps):
            deps["meta_chains"]["worker-lifecycle"]["flow"][0]["chain"] = "ghost-chain"
            deps["meta_chains"]["worker-lifecycle"]["flow"][0]["next"] = []
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[meta-chain-integrity]" in result.stdout or "v3-meta-chains-chain-ref" in result.stdout

    def test_meta_chain_nonexistent_goto(self):
        """WHEN a meta chain flow node's goto targets non-existent id
        THEN [meta-chain-integrity] CRITICAL."""
        def mutator(deps):
            deps["meta_chains"]["worker-lifecycle"]["flow"][0]["next"][0]["goto"] = "ghost-node"
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        assert "[meta-chain-integrity]" in result.stdout or "v3-meta-chains-goto" in result.stdout


# ===========================================================================
# Requirement: chain type guard - meta type
# ===========================================================================

class TestChainTypeGuardMeta(_MetaTestBase):
    """meta type in CHAIN_TYPE_ALLOWED skips step-level type guard."""

    def test_meta_type_in_chains_skips_type_guard(self):
        """WHEN chains section has type='meta' chain with any steps
        THEN no [chain-type] warning (meta chains skip step-level type guard)."""
        def mutator(deps):
            # Add a chain with type=meta to the regular chains section
            deps["chains"]["meta-chain"] = {
                "type": "meta",
                "description": "A meta type chain",
                "steps": [],
            }
        self._modify_deps(mutator)

        result = run_engine(self.plugin_dir, "--validate")
        # No warning about unknown chain type meta
        assert "[chain-type] chains/meta-chain: unknown chain type 'meta'" not in result.stdout


# ===========================================================================
# Requirement: Template D generation
# ===========================================================================

class TestTemplateDGeneration(_MetaTestBase):
    """Template D: chain 間遷移指示の生成。"""

    def test_chain_generate_meta_outputs_template_d(self):
        """WHEN twl chain generate <meta-chain-name> is run
        THEN Template D output includes skill names and transition instructions."""
        result = run_engine(self.plugin_dir, "chain", "generate", "worker-lifecycle")
        assert result.returncode == 0, f"stdout: {result.stdout}\nstderr: {result.stderr}"
        assert "Template D" in result.stdout
        # my-workflow (setup node with skill) and my-workflow-skill (pr-verify node)
        assert "my-workflow" in result.stdout
        assert "IS_AUTOPILOT=true" in result.stdout or "IS_AUTOPILOT=false" in result.stdout

    def test_chain_generate_meta_check_detects_drift(self):
        """WHEN SKILL.md does not have transition section
        THEN --check detects DRIFT."""
        result = run_engine(self.plugin_dir, "chain", "generate", "worker-lifecycle", "--check")
        assert result.returncode != 0, f"Expected non-zero exit. stdout: {result.stdout}"
        # DRIFT detected for skills with transitions (my-workflow and my-workflow-skill)
        assert "DRIFT" in result.stdout

    def test_chain_generate_meta_write_injects_section(self):
        """WHEN --write is run
        THEN SKILL.md gets the transition section injected."""
        run_engine(self.plugin_dir, "chain", "generate", "worker-lifecycle", "--write")
        # my-workflow (setup node) should get transition section
        skill_path = self.plugin_dir / "skills" / "my-workflow" / "SKILL.md"
        content = skill_path.read_text(encoding="utf-8")
        assert "完了後の遷移（meta chain 定義から自動生成）" in content
        assert "IS_AUTOPILOT" in content

    def test_chain_generate_meta_check_ok_after_write(self):
        """WHEN --write is run, then --check is run
        THEN --check passes (no drift)."""
        run_engine(self.plugin_dir, "chain", "generate", "worker-lifecycle", "--write")
        result = run_engine(self.plugin_dir, "chain", "generate", "worker-lifecycle", "--check")
        assert result.returncode == 0
        assert "All files are in sync" in result.stdout

    def test_chain_generate_transition_contains_skill_ref(self):
        """WHEN Template D is generated
        THEN skill references use /twl:<skill-name> format."""
        result = run_engine(self.plugin_dir, "chain", "generate", "worker-lifecycle")
        assert result.returncode == 0
        # setup node (my-workflow) has next -> pr-verify (skill: my-workflow-skill)
        # so the transition for my-workflow should reference /twl:my-workflow-skill
        assert "/twl:my-workflow-skill" in result.stdout

    def test_chain_generate_all_includes_meta_chains(self):
        """WHEN --all is run
        THEN meta chains are also processed (Template D output or summary)."""
        result = run_engine(self.plugin_dir, "chain", "generate", "--all")
        assert result.returncode == 0
        # Template D should appear (setup and pr-verify nodes both have skills)
        assert "Template D" in result.stdout

    def test_chain_generate_all_check_includes_meta_chains(self):
        """WHEN --all --check is run
        THEN meta chains appear in summary output."""
        result = run_engine(self.plugin_dir, "chain", "generate", "--all", "--check")
        # Should detect drift (SKILL.md doesn't have transition section yet)
        # Summary line should mention chains total
        assert "Summary:" in result.stdout


# ===========================================================================
# main runner
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestMetaChainSchemaValidation,
        TestMetaChainIntegrity,
        TestChainTypeGuardMeta,
        TestTemplateDGeneration,
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
