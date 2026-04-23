"""Tests for chain/integrity.py — deps-integrity hash comparison."""

import textwrap
from pathlib import Path

import pytest

from twl.chain.integrity import (
    _hash_list,
    _hash_set,
    _parse_bash_array,
    _expected_chains,
    check_deps_integrity,
)


class TestHashHelpers:
    def test_hash_list_identical(self):
        assert _hash_list(["a", "b", "c"]) == _hash_list(["a", "b", "c"])

    def test_hash_list_order_matters(self):
        assert _hash_list(["a", "b"]) != _hash_list(["b", "a"])

    def test_hash_set_order_independent(self):
        assert _hash_set({"a", "b", "c"}) == _hash_set({"c", "a", "b"})

    def test_hash_set_diff(self):
        assert _hash_set({"a", "b"}) != _hash_set({"a", "c"})


class TestParseBashArray:
    def test_simple_array(self):
        content = "CHAIN_STEPS=(\n  init\n  check\n  done\n)"
        result = _parse_bash_array(content, "CHAIN_STEPS")
        assert result == ["init", "check", "done"]

    def test_missing_var(self):
        assert _parse_bash_array("OTHER_VAR=(foo bar)", "CHAIN_STEPS") is None

    def test_skips_comments(self):
        content = "CHAIN_STEPS=(\n  init\n  # skip this\n  check\n)"
        result = _parse_bash_array(content, "CHAIN_STEPS")
        assert result == ["init", "check"]



class TestExpectedChains:
    def test_basic_grouping(self):
        step_to_workflow = {
            "init": "setup",
            "check": "test-ready",
            "verify": "test-ready",
        }
        chain_steps = ["init", "check", "verify"]
        result = _expected_chains(step_to_workflow, chain_steps)
        assert result == {"setup": ["init"], "test-ready": ["check", "verify"]}

    def test_order_preserved(self):
        step_to_workflow = {"a": "wf", "b": "wf", "c": "wf"}
        result = _expected_chains(step_to_workflow, ["c", "a", "b"])
        assert result["wf"] == ["c", "a", "b"]

    def test_unmapped_step_skipped(self):
        result = _expected_chains({}, ["init", "check"])
        assert result == {}


class TestCheckDepsIntegrity:
    @pytest.fixture()
    def plugin_dir(self, tmp_path):
        """Minimal plugin dir with chain.py + chain-steps.sh + deps.yaml in sync."""
        # chain.py
        cli_path = tmp_path / "cli" / "twl" / "src" / "twl" / "autopilot"
        cli_path.mkdir(parents=True)
        (cli_path / "chain.py").write_text(textwrap.dedent("""\
            CHAIN_STEPS: list[str] = ["init", "check", "done"]
            DIRECT_SKIP_STEPS: frozenset[str] = frozenset(["done"])
            STEP_TO_WORKFLOW: dict[str, str] = {
                "init": "setup",
                "check": "test-ready",
                "done": "pr-merge",
            }
        """))

        # chain-steps.sh (in sync)
        scripts = tmp_path / "scripts"
        scripts.mkdir()
        (scripts / "chain-steps.sh").write_text(textwrap.dedent("""\
            CHAIN_STEPS=(
              init
              check
              done
            )
            DIRECT_SKIP_STEPS=(
              done
            )
        """))

        # deps.yaml (in sync)
        import yaml
        deps = {
            "version": "3.0",
            "chains": {
                "setup": {"steps": ["init"]},
                "test-ready": {"steps": ["check"]},
                "pr-merge": {"steps": ["done"]},
            },
        }
        (tmp_path / "deps.yaml").write_text(yaml.dump(deps))

        return tmp_path

    def test_no_drift_returns_no_errors(self, plugin_dir):
        errors, warnings = check_deps_integrity(plugin_dir)
        assert errors == [], f"Unexpected errors: {errors}"

    def test_chain_steps_drift_detected(self, plugin_dir):
        # Introduce drift: add extra step to chain-steps.sh
        sh = plugin_dir / "scripts" / "chain-steps.sh"
        sh.write_text(textwrap.dedent("""\
            CHAIN_STEPS=(
              init
              check
              extra-step
              done
            )
            DIRECT_SKIP_STEPS=(
              done
            )
        """))
        errors, _ = check_deps_integrity(plugin_dir)
        assert any("CHAIN_STEPS mismatch" in e for e in errors)

    def test_direct_skip_drift_detected(self, plugin_dir):
        sh = plugin_dir / "scripts" / "chain-steps.sh"
        original = sh.read_text()
        sh.write_text(original.replace("DIRECT_SKIP_STEPS=(\n  done\n)", "DIRECT_SKIP_STEPS=(\n  init\n)"))
        errors, _ = check_deps_integrity(plugin_dir)
        assert any("DIRECT_SKIP_STEPS mismatch" in e for e in errors)

    def test_deps_yaml_chain_drift_detected(self, plugin_dir):
        """chain.py CHAIN_STEPS に含まれる step が deps.yaml 全 chain から欠落すると error。"""
        import yaml
        deps = {
            "version": "3.0",
            "chains": {
                "setup": {"steps": ["init"]},
                "test-ready": {"steps": ["wrong-step"]},  # "check" が全 chain から missing
                "pr-merge": {"steps": ["done"]},
            },
        }
        (plugin_dir / "deps.yaml").write_text(yaml.dump(deps))
        errors, _ = check_deps_integrity(plugin_dir)
        assert any("missing" in e and "check" in e for e in errors)

    def test_deps_yaml_extra_step_allowed(self, plugin_dir):
        """ADR-022: deps.yaml に chain.py にない step (workflow skill 内 orchestrate) は許容。"""
        import yaml
        deps = {
            "version": "3.0",
            "chains": {
                "setup": {"steps": ["init", "extra-workflow-step"]},  # extra 許容
                "test-ready": {"steps": ["check", "another-extra"]},  # extra 許容
                "pr-merge": {"steps": ["done", "merge-gate", "auto-merge"]},  # extra 許容
            },
        }
        (plugin_dir / "deps.yaml").write_text(yaml.dump(deps))
        errors, _ = check_deps_integrity(plugin_dir)
        assert errors == [], f"Extra steps should be allowed: {errors}"

    def test_deps_yaml_chain_reassignment_allowed(self, plugin_dir):
        """ADR-022: step が別 chain に移動しても、全 chain flatten で包含されれば OK。"""
        import yaml
        deps = {
            "version": "3.0",
            "chains": {
                "setup": {"steps": ["init", "check"]},  # "check" を setup に移動
                "test-ready": {"steps": []},            # test-ready は空でも
                "pr-merge": {"steps": ["done"]},
            },
        }
        (plugin_dir / "deps.yaml").write_text(yaml.dump(deps))
        errors, _ = check_deps_integrity(plugin_dir)
        assert errors == [], f"Chain reassignment should be allowed: {errors}"

    def test_missing_chain_py_returns_warning(self, plugin_dir):
        import shutil
        shutil.rmtree(plugin_dir / "cli")
        errors, warnings = check_deps_integrity(plugin_dir)
        assert errors == []
        assert any("chain.py" in w for w in warnings)

    def test_missing_chain_steps_sh_returns_warning(self, plugin_dir):
        (plugin_dir / "scripts" / "chain-steps.sh").unlink()
        errors, warnings = check_deps_integrity(plugin_dir)
        assert any("chain-steps.sh" in w for w in warnings)

    def test_fix_hint_in_error(self, plugin_dir):
        sh = plugin_dir / "scripts" / "chain-steps.sh"
        original = sh.read_text()
        sh.write_text(original.replace("init\n  check\n  done", "init\n  check"))
        errors, _ = check_deps_integrity(plugin_dir)
        assert any("twl chain export --yaml --shell" in e for e in errors)
