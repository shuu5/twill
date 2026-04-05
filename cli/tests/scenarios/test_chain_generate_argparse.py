#!/usr/bin/env python3
"""Tests for handle_chain_subcommand argparse extension (--check, --all, exclusion).

Spec: openspec/changes/chain-generate-check-all/specs/argparse-update.md

These tests verify backward compatibility (existing stdout/--write behavior)
and the exit code system for all command variations.
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


def _create_component_files(plugin_dir: Path, deps: dict, *, body_overrides: dict | None = None) -> None:
    """Create markdown files for every component in deps.

    body_overrides: {component_name: body_text} for custom file content.
    """
    body_overrides = body_overrides or {}
    for section in ("skills", "commands", "agents"):
        for name, data in deps.get(section, {}).items():
            path_str = data.get("path", "")
            if not path_str:
                continue
            file_path = plugin_dir / path_str
            file_path.parent.mkdir(parents=True, exist_ok=True)

            if name in body_overrides:
                body = body_overrides[name]
            else:
                body = (
                    f"# {name}\n\n"
                    f"## チェックポイント（MUST）\n\n"
                    f"デフォルトチェックポイント。\n"
                )

            file_path.write_text(
                f"---\nname: {name}\ndescription: {data.get('description', 'Test')}\n---\n\n{body}\n",
                encoding="utf-8",
            )


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, str(TWL_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def make_argparse_fixture(tmpdir: Path, *, body_overrides: dict | None = None) -> Path:
    """Create a v3.0 plugin fixture for argparse extension testing.

    Chain: dev-pr-cycle (type A)
      steps: [workflow-setup, workflow-test-ready]
    """
    plugin_dir = tmpdir / "test-plugin-argparse"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-argparse",
        "chains": {
            "dev-pr-cycle": {
                "description": "Dev PR cycle",
                "type": "A",
                "steps": ["workflow-setup", "workflow-test-ready"],
            },
        },
        "skills": {
            "workflow-setup": {
                "type": "workflow",
                "path": "skills/workflow-setup/SKILL.md",
                "description": "開発準備ワークフロー",
                "chain": "dev-pr-cycle",
                "calls": [
                    {"workflow": "workflow-test-ready", "step": "2"},
                ],
            },
            "workflow-test-ready": {
                "type": "workflow",
                "path": "skills/workflow-test-ready/SKILL.md",
                "description": "テスト準備ワークフロー",
                "chain": "dev-pr-cycle",
                "step_in": {"parent": "workflow-setup"},
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps, body_overrides=body_overrides)
    return plugin_dir


# ---------------------------------------------------------------------------
# Test base class
# ---------------------------------------------------------------------------

class _ArgparseTestBase:
    """Shared setup/teardown for argparse tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: handle_chain_subcommand の引数パース拡張
# ===========================================================================

class TestArgparseBackwardCompatibility(_ArgparseTestBase):
    """Tests for backward compatibility of existing stdout/--write behavior."""

    # --- Scenario: 単一 chain の stdout 出力（既存動作の維持） ---

    def test_single_chain_stdout_backward_compatible(self):
        """WHEN `twl chain generate <name>` を実行する
        THEN 指定 chain の Template A/B/C を stdout に出力する（既存動作と同一）"""
        plugin_dir = make_argparse_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0, (
            f"Expected exit code 0\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        stdout = result.stdout
        assert len(stdout.strip()) > 0, "Expected non-empty stdout output"
        # Should contain component names from the chain
        assert "workflow-setup" in stdout, (
            f"Expected 'workflow-setup' in stdout:\n{stdout}"
        )
        assert "workflow-test-ready" in stdout, (
            f"Expected 'workflow-test-ready' in stdout:\n{stdout}"
        )

    def test_single_chain_stdout_contains_templates(self):
        """WHEN 単一 chain を stdout に出力する
        THEN Template A (チェックポイント) が含まれる"""
        plugin_dir = make_argparse_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0
        stdout = result.stdout
        assert "チェックポイント" in stdout or "Checkpoint" in stdout, (
            f"Expected Template A checkpoint content:\n{stdout}"
        )

    def test_single_chain_stdout_no_file_changes(self):
        """WHEN 単一 chain を stdout 出力する（--write なし）
        THEN ファイルは変更されない"""
        plugin_dir = make_argparse_fixture(self.tmpdir)

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content_before = file_path.read_text(encoding="utf-8")

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        content_after = file_path.read_text(encoding="utf-8")
        assert content_before == content_after, (
            "File should not be modified without --write flag"
        )

    # --- Scenario: 単一 chain の書き込み（既存動作の維持） ---

    def test_single_chain_write_backward_compatible(self):
        """WHEN `twl chain generate <name> --write` を実行する
        THEN 指定 chain のテンプレートをファイルに書き込む（既存動作と同一）"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いチェックポイント。\n"
            ),
        }
        plugin_dir = make_argparse_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0, (
            f"Expected exit code 0\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

        # File should have been updated
        content = (plugin_dir / "skills/workflow-setup/SKILL.md").read_text(encoding="utf-8")
        assert "古いチェックポイント" not in content, (
            f"Old checkpoint should be replaced:\n{content}"
        )
        assert "/dev:workflow-test-ready" in content, (
            f"New checkpoint reference should be present:\n{content}"
        )

    def test_single_chain_write_preserves_frontmatter(self):
        """WHEN --write でファイルを更新する
        THEN frontmatter は保持される"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
        }
        plugin_dir = make_argparse_fixture(self.tmpdir, body_overrides=body_overrides)

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        content = (plugin_dir / "skills/workflow-setup/SKILL.md").read_text(encoding="utf-8")
        assert content.startswith("---\n"), "Frontmatter should be preserved"
        assert "name: workflow-setup" in content, "Frontmatter name field should be preserved"


# ===========================================================================
# Requirement: exit code の体系
# ===========================================================================

class TestExitCodeSystem(_ArgparseTestBase):
    """Tests for the exit code system across all command variations."""

    # --- Scenario: exit code の体系 ---

    def test_normal_completion_exit_zero(self):
        """WHEN 正常完了する（stdout 出力）
        THEN exit code 0"""
        plugin_dir = make_argparse_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0

    def test_write_success_exit_zero(self):
        """WHEN --write が正常に完了する
        THEN exit code 0"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
        }
        plugin_dir = make_argparse_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0

    def test_check_no_drift_exit_zero(self):
        """WHEN --check で乖離なし
        THEN exit code 0"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
        }
        plugin_dir = make_argparse_fixture(self.tmpdir, body_overrides=body_overrides)

        # Write first to match
        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 0, (
            f"Expected exit code 0 (no drift)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_check_drift_exit_one(self):
        """WHEN --check で乖離あり
        THEN exit code 1"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "手動変更された内容。\n"
            ),
        }
        plugin_dir = make_argparse_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 1, (
            f"Expected exit code 1 (drift)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_error_exit_one_with_stderr(self):
        """WHEN エラーが発生する（存在しない chain 名）
        THEN exit code 1 かつ stderr に出力あり"""
        plugin_dir = make_argparse_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "nonexistent-chain")

        assert result.returncode == 1, (
            f"Expected exit code 1 (error)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert len(result.stderr.strip()) > 0, (
            f"Expected error message in stderr:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_mutual_exclusion_error_exit_nonzero(self):
        """WHEN --check と --write を同時指定する
        THEN exit code 非ゼロかつ stderr にエラー出力"""
        plugin_dir = make_argparse_fixture(self.tmpdir)

        result = run_engine(
            plugin_dir, "chain", "generate", "dev-pr-cycle", "--check", "--write"
        )

        assert result.returncode != 0, (
            f"Expected non-zero exit code for --check --write\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
