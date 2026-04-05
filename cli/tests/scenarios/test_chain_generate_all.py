#!/usr/bin/env python3
"""Tests for chain generate --all functionality (batch operations across all chains).

Spec: openspec/changes/chain-generate-check-all/specs/all-flag.md

These tests are TDD-style: they define expected behavior BEFORE implementation.
The `chain generate --all` subcommand operates on every chain in deps.yaml.
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


def make_multi_chain_fixture(tmpdir: Path, *, body_overrides: dict | None = None) -> Path:
    """Create a v3.0 plugin fixture with multiple chains for --all testing.

    Chains:
      - dev-pr-cycle (type A): steps [wf-setup, wf-test-ready]
      - review-flow (type A): steps [wf-review, wf-approve]
      - deploy-chain (type A): steps [wf-deploy]
    """
    plugin_dir = tmpdir / "test-plugin-all"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-all",
        "chains": {
            "dev-pr-cycle": {
                "description": "Dev PR cycle",
                "type": "A",
                "steps": ["wf-setup", "wf-test-ready"],
            },
            "review-flow": {
                "description": "Review flow",
                "type": "A",
                "steps": ["wf-review", "wf-approve"],
            },
            "deploy-chain": {
                "description": "Deploy chain",
                "type": "A",
                "steps": ["wf-deploy"],
            },
        },
        "skills": {
            "wf-setup": {
                "type": "workflow",
                "path": "skills/wf-setup/SKILL.md",
                "description": "セットアップ",
                "chain": "dev-pr-cycle",
                "calls": [
                    {"workflow": "wf-test-ready", "step": "2"},
                ],
            },
            "wf-test-ready": {
                "type": "workflow",
                "path": "skills/wf-test-ready/SKILL.md",
                "description": "テスト準備",
                "chain": "dev-pr-cycle",
                "step_in": {"parent": "wf-setup"},
                "calls": [],
            },
            "wf-review": {
                "type": "workflow",
                "path": "skills/wf-review/SKILL.md",
                "description": "レビュー",
                "chain": "review-flow",
                "calls": [
                    {"workflow": "wf-approve", "step": "2"},
                ],
            },
            "wf-approve": {
                "type": "workflow",
                "path": "skills/wf-approve/SKILL.md",
                "description": "承認",
                "chain": "review-flow",
                "step_in": {"parent": "wf-review"},
                "calls": [],
            },
            "wf-deploy": {
                "type": "workflow",
                "path": "skills/wf-deploy/SKILL.md",
                "description": "デプロイ",
                "chain": "deploy-chain",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps, body_overrides=body_overrides)
    return plugin_dir


def make_empty_chains_fixture(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture with empty chains section."""
    plugin_dir = tmpdir / "test-plugin-empty-chains"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-empty-chains",
        "chains": {},
        "skills": {},
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    return plugin_dir


def make_no_chains_fixture(tmpdir: Path) -> Path:
    """Create a v3.0 plugin fixture with no chains key at all."""
    plugin_dir = tmpdir / "test-plugin-no-chains"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-no-chains",
        "skills": {},
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Test base class
# ---------------------------------------------------------------------------

class _AllTestBase:
    """Shared setup/teardown for --all tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: --all による全 chain 一括操作
# ===========================================================================

class TestAllBatchOperations(_AllTestBase):
    """Tests for --all flag: stdout, --write, --check across all chains."""

    # --- Scenario: --all で全 chain を stdout 出力 ---

    def test_all_stdout_outputs_all_chains(self):
        """WHEN `twl chain generate --all` を実行する
        THEN deps.yaml 内の全 chain の Template A/B/C を順次 stdout に出力する"""
        plugin_dir = make_multi_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "--all")

        assert result.returncode == 0, (
            f"Expected exit code 0\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        stdout = result.stdout
        # All chain names or their components should appear in output
        for chain_name in ["dev-pr-cycle", "review-flow", "deploy-chain"]:
            assert chain_name in stdout, (
                f"Expected chain '{chain_name}' in stdout output:\n{stdout}"
            )

    def test_all_stdout_contains_all_components(self):
        """WHEN --all で stdout 出力する
        THEN 全 chain のコンポーネントが出力に含まれる"""
        plugin_dir = make_multi_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "--all")

        assert result.returncode == 0
        stdout = result.stdout
        for comp_name in ["wf-setup", "wf-test-ready", "wf-review", "wf-approve", "wf-deploy"]:
            assert comp_name in stdout, (
                f"Expected component '{comp_name}' in output:\n{stdout}"
            )

    # --- Scenario: --all --write で全 chain を一括書き込み ---

    def test_all_write_updates_all_files(self):
        """WHEN `twl chain generate --all --write` を実行する
        THEN 全 chain のテンプレートを対応ファイルに書き込む"""
        body_overrides = {
            "wf-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いチェックポイント。\n"
            ),
            "wf-review": (
                "# Review\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いレビューチェックポイント。\n"
            ),
        }
        plugin_dir = make_multi_chain_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "--all", "--write")

        assert result.returncode == 0, (
            f"Expected exit code 0\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

        # Check that files were updated
        setup_content = (plugin_dir / "skills/wf-setup/SKILL.md").read_text(encoding="utf-8")
        assert "古いチェックポイント" not in setup_content, (
            f"wf-setup should have been updated:\n{setup_content}"
        )

        review_content = (plugin_dir / "skills/wf-review/SKILL.md").read_text(encoding="utf-8")
        assert "古いレビューチェックポイント" not in review_content, (
            f"wf-review should have been updated:\n{review_content}"
        )

    # --- Scenario: --all --check で全 chain を一括チェック ---

    def test_all_check_reports_per_chain(self):
        """WHEN `twl chain generate --all --check` を実行する
        THEN ファイルレベルのサマリー（chain ごとに ok/DRIFT）を表示する"""
        body_overrides = {
            "wf-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
        }
        plugin_dir = make_multi_chain_fixture(self.tmpdir, body_overrides=body_overrides)

        # Write correct content for all chains
        run_engine(plugin_dir, "chain", "generate", "--all", "--write")

        # Now check - should all be ok
        result = run_engine(plugin_dir, "chain", "generate", "--all", "--check")

        assert result.returncode == 0, (
            f"Expected exit code 0 (all match)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "ok" in combined_output.lower(), (
            f"Expected 'ok' status in output:\n{combined_output}"
        )

    def test_all_check_with_drift_reports_drift(self):
        """WHEN --all --check で一部の chain にドリフトがある
        THEN DRIFT を検出し、exit code 1 で終了する"""
        body_overrides = {
            "wf-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "手動で変更された内容。\n"
            ),
        }
        plugin_dir = make_multi_chain_fixture(self.tmpdir, body_overrides=body_overrides)

        # Do NOT run --write, so wf-setup will drift
        result = run_engine(plugin_dir, "chain", "generate", "--all", "--check")

        assert result.returncode == 1, (
            f"Expected exit code 1 (drift detected)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" in combined_output, (
            f"Expected 'DRIFT' in output:\n{combined_output}"
        )

    # --- Scenario: chains が 0 件の場合 ---

    def test_all_empty_chains_section(self):
        """WHEN deps.yaml に chains セクションが空の場合
        THEN `0 chains found` と表示し、exit code 0 で正常終了する"""
        plugin_dir = make_empty_chains_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "--all")

        assert result.returncode == 0, (
            f"Expected exit code 0 for empty chains\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "0 chains" in combined_output.lower() or "0 chain" in combined_output.lower(), (
            f"Expected '0 chains found' message:\n{combined_output}"
        )

    def test_all_no_chains_key(self):
        """WHEN deps.yaml に chains キー自体が存在しない場合
        THEN 0 件として処理し、exit code 0 で正常終了する"""
        plugin_dir = make_no_chains_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate", "--all")

        assert result.returncode == 0, (
            f"Expected exit code 0 for missing chains key\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "0 chains" in combined_output.lower() or "0 chain" in combined_output.lower(), (
            f"Expected '0 chains found' message:\n{combined_output}"
        )


# ===========================================================================
# Requirement: --all と chain name の排他制御
# ===========================================================================

class TestAllChainNameExclusion(_AllTestBase):
    """Tests for mutual exclusion of --all and chain name argument."""

    # --- Scenario: --all と chain name の同時指定 ---

    def test_all_with_chain_name_error(self):
        """WHEN `twl chain generate --all workflow-setup` を実行する
        THEN エラーメッセージを stderr に出力し、exit code 1 で終了する"""
        plugin_dir = make_multi_chain_fixture(self.tmpdir)

        result = run_engine(
            plugin_dir, "chain", "generate", "--all", "dev-pr-cycle"
        )

        assert result.returncode != 0, (
            f"Expected non-zero exit code for --all with chain name\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "error" in combined_output.lower() or len(result.stderr.strip()) > 0, (
            f"Expected error message for --all + chain name:\n{combined_output}"
        )

    def test_chain_name_with_all_error(self):
        """WHEN `twl chain generate dev-pr-cycle --all` を実行する（逆順）
        THEN 同様にエラーとなる"""
        plugin_dir = make_multi_chain_fixture(self.tmpdir)

        result = run_engine(
            plugin_dir, "chain", "generate", "dev-pr-cycle", "--all"
        )

        assert result.returncode != 0, (
            f"Expected non-zero exit code for chain name with --all\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


# ===========================================================================
# Requirement: --all も chain name もなしの場合のエラー
# ===========================================================================

class TestNoArgumentError(_AllTestBase):
    """Tests for error when neither --all nor chain name is provided."""

    # --- Scenario: 引数なし実行 ---

    def test_no_arguments_error(self):
        """WHEN `twl chain generate` を引数なしで実行する
        THEN usage メッセージを表示し、exit code 非ゼロで終了する"""
        plugin_dir = make_multi_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate")

        assert result.returncode != 0, (
            f"Expected non-zero exit code for no arguments\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "usage" in combined_output.lower() or "error" in combined_output.lower(), (
            f"Expected usage or error message:\n{combined_output}"
        )

    def test_no_arguments_shows_usage(self):
        """WHEN 引数なしで実行する
        THEN usage メッセージにコマンドの使い方が含まれる"""
        plugin_dir = make_multi_chain_fixture(self.tmpdir)

        result = run_engine(plugin_dir, "chain", "generate")

        assert result.returncode != 0
        combined_output = result.stdout + result.stderr
        # usage message should mention chain_name or --all
        assert "chain" in combined_output.lower() or "--all" in combined_output.lower(), (
            f"Expected usage to mention chain_name or --all:\n{combined_output}"
        )


# ===========================================================================
# Requirement: --all --check のサマリー出力形式
# ===========================================================================

class TestAllCheckSummary(_AllTestBase):
    """Tests for --all --check summary output format."""

    # --- Scenario: 複数 chain で一部ドリフトあり ---

    def test_partial_drift_summary_format(self):
        """WHEN 複数 chain 中一部にドリフトがある状態で `--all --check` を実行する
        THEN 各 chain のファイルごとに ok/DRIFT を表示し、サマリー行を出力する"""
        body_overrides = {
            "wf-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
            "wf-review": (
                "# Review\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いレビュー。\n"
            ),
        }
        plugin_dir = make_multi_chain_fixture(self.tmpdir, body_overrides=body_overrides)

        # Write only dev-pr-cycle chain to create partial match
        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        # Now modify wf-setup back to create drift in dev-pr-cycle
        file_path = plugin_dir / "skills/wf-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        # Replace the checkpoint section with something different
        modified = content.replace("/dev:wf-test-ready", "/dev:MODIFIED-REFERENCE")
        file_path.write_text(modified, encoding="utf-8")

        result = run_engine(plugin_dir, "chain", "generate", "--all", "--check")

        assert result.returncode == 1, (
            f"Expected exit code 1 (drift detected)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" in combined_output, (
            f"Expected DRIFT in output:\n{combined_output}"
        )

    def test_partial_drift_shows_summary_line(self):
        """WHEN 一部ドリフトがある場合
        THEN Summary 行が出力される"""
        body_overrides = {
            "wf-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "手動変更。\n"
            ),
        }
        plugin_dir = make_multi_chain_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "--all", "--check")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        # Summary line should contain statistics
        assert "summary" in combined_output.lower() or "chain" in combined_output.lower(), (
            f"Expected summary output:\n{combined_output}"
        )

    def test_partial_drift_diff_at_end(self):
        """WHEN 一部ドリフトがある場合
        THEN diff は末尾にまとめて出力される"""
        body_overrides = {
            "wf-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "手動変更。\n"
            ),
        }
        plugin_dir = make_multi_chain_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "--all", "--check")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        # diff markers should exist somewhere in the output
        assert "---" in combined_output or "+++" in combined_output or "DRIFT" in combined_output, (
            f"Expected diff output:\n{combined_output}"
        )

    def test_all_ok_summary(self):
        """WHEN 全 chain にドリフトがない場合
        THEN 全て ok のサマリーを表示し、exit code 0"""
        body_overrides = {
            "wf-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
            "wf-review": (
                "# Review\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いレビュー。\n"
            ),
        }
        plugin_dir = make_multi_chain_fixture(self.tmpdir, body_overrides=body_overrides)

        # Write all chains first
        run_engine(plugin_dir, "chain", "generate", "--all", "--write")

        # Check - should all pass
        result = run_engine(plugin_dir, "chain", "generate", "--all", "--check")

        assert result.returncode == 0, (
            f"Expected exit code 0 (all ok)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" not in combined_output, (
            f"Expected no DRIFT when all chains match:\n{combined_output}"
        )
