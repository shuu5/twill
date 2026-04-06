#!/usr/bin/env python3
"""Tests for chain generate --check functionality (drift detection, normalization).

Spec: openspec/changes/chain-generate-check-all/specs/check-flag.md

These tests are TDD-style: they define expected behavior BEFORE implementation.
The `chain generate --check` subcommand compares generated Template A against
the current file content and reports ok/DRIFT status.
"""

import shutil
import subprocess
import os
import sys
import tempfile
from pathlib import Path

import yaml



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
        [sys.executable, "-m", "twl"] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def make_check_fixture(tmpdir: Path, *, body_overrides: dict | None = None) -> Path:
    """Create a v3.0 plugin fixture for --check testing.

    Chain: dev-pr-cycle (type A)
      steps: [workflow-setup, workflow-test-ready]

    Each component has a path so --check can compare files.
    """
    plugin_dir = tmpdir / "test-plugin-check"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-check",
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


def _write_generated_checkpoint_to_file(plugin_dir: Path) -> None:
    """Run chain generate once in stdout mode, extract the generated checkpoint,
    and write it into the component files so --check will find a match.

    This is a helper to create the 'matching' state for ok tests.
    """
    # First, generate to stdout to capture expected content
    result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")
    assert result.returncode == 0, (
        f"Setup failed: --write returned {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


# ---------------------------------------------------------------------------
# Test base class
# ---------------------------------------------------------------------------

class _CheckTestBase:
    """Shared setup/teardown for --check tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: --check による Template A ドリフト検出
# ===========================================================================

class TestCheckDriftDetection(_CheckTestBase):
    """Tests for --check drift detection: ok/DRIFT status and unified diff."""

    # --- Scenario: チェックポイントが一致する場合 ---

    def test_check_all_match_ok_status(self):
        """WHEN `twl chain generate <name> --check` を実行し、
        全ファイルの Template A が生成結果と一致する
        THEN 各ファイルに `ok` ステータスを表示し、exit code 0 で終了する"""
        body_overrides = {
            "workflow-setup": (
                "# Workflow Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いチェックポイント。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        # First --write to establish matching state
        _write_generated_checkpoint_to_file(plugin_dir)

        # Now --check should report ok
        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 0, (
            f"Expected exit code 0 (all match)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "ok" in combined_output.lower(), (
            f"Expected 'ok' status in output:\n{combined_output}"
        )

    def test_check_all_match_no_drift(self):
        """WHEN 全ファイルが一致する場合
        THEN DRIFT ステータスは出力されない"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)
        _write_generated_checkpoint_to_file(plugin_dir)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 0
        combined_output = result.stdout + result.stderr
        assert "DRIFT" not in combined_output, (
            f"Expected no DRIFT when all files match:\n{combined_output}"
        )

    # --- Scenario: チェックポイントが不一致の場合 ---

    def test_check_mismatch_drift_status(self):
        """WHEN `twl chain generate <name> --check` を実行し、
        いずれかのファイルで Template A が不一致
        THEN 不一致ファイルに `DRIFT` ステータスを表示し、exit code 1 で終了する"""
        body_overrides = {
            "workflow-setup": (
                "# Workflow Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "手動で書き換えた古いチェックポイント。\n\n"
                "`/dev:obsolete-reference` を Skill tool で自動実行。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        # Do NOT run --write first, so file content mismatches generated content
        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 1, (
            f"Expected exit code 1 (drift detected)\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" in combined_output, (
            f"Expected 'DRIFT' status in output:\n{combined_output}"
        )

    def test_check_mismatch_shows_unified_diff(self):
        """WHEN ファイルが不一致の場合
        THEN unified diff が出力される"""
        body_overrides = {
            "workflow-setup": (
                "# Workflow Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "手動で編集されたチェックポイント。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        # unified diff markers: --- / +++ or - / + lines
        assert "---" in combined_output or "+++" in combined_output or "-" in combined_output, (
            f"Expected unified diff output:\n{combined_output}"
        )

    # --- Scenario: チェックポイントセクションが存在しない場合 ---

    def test_check_no_checkpoint_section_drift(self):
        """WHEN 対象ファイルに `## チェックポイント` / `## Checkpoint` セクションが存在しない
        THEN DRIFT として検出し、期待される内容を diff で表示する"""
        body_overrides = {
            "workflow-setup": (
                "# Workflow Setup\n\n"
                "チェックポイントセクションが存在しない。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 1, (
            f"Expected exit code 1 (no checkpoint section = drift)\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" in combined_output, (
            f"Expected DRIFT when checkpoint section is missing:\n{combined_output}"
        )

    def test_check_no_checkpoint_section_shows_expected_content(self):
        """WHEN チェックポイントセクションが存在しない場合
        THEN diff 出力に期待される内容（生成されるべきチェックポイント）が含まれる"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "マーカーなしのコンテンツ。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        # diff には期待される内容（次のステップへの参照等）が含まれるべき
        assert "/dev:workflow-test-ready" in combined_output or "チェックポイント" in combined_output, (
            f"Expected diff to show expected checkpoint content:\n{combined_output}"
        )


# ===========================================================================
# Requirement: --check の正規化処理
# ===========================================================================

class TestCheckNormalization(_CheckTestBase):
    """Tests for normalization before comparison: trailing whitespace, CRLF."""

    # --- Scenario: trailing whitespace の差異を無視 ---

    def test_trailing_whitespace_ignored_ok(self):
        """WHEN ファイルの内容が trailing whitespace のみ異なる
        THEN `ok` と判定し、DRIFT を報告しない"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        # Write correct content first
        _write_generated_checkpoint_to_file(plugin_dir)

        # Now add trailing whitespace to the file
        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        # Add trailing spaces to several lines
        lines = content.split("\n")
        modified_lines = [line + "   " if line.strip() else line for line in lines]
        file_path.write_text("\n".join(modified_lines), encoding="utf-8")

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 0, (
            f"Expected exit code 0 (trailing whitespace should be ignored)\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" not in combined_output, (
            f"Expected no DRIFT for trailing whitespace difference:\n{combined_output}"
        )

    # --- Scenario: 改行コードの差異を無視 ---

    def test_crlf_vs_lf_ignored_ok(self):
        """WHEN ファイルの内容が CRLF と LF の違いのみ
        THEN `ok` と判定し、DRIFT を報告しない"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        # Write correct content first
        _write_generated_checkpoint_to_file(plugin_dir)

        # Convert LF to CRLF in the file
        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        crlf_content = content.replace("\n", "\r\n")
        file_path.write_bytes(crlf_content.encode("utf-8"))

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 0, (
            f"Expected exit code 0 (CRLF vs LF should be ignored)\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" not in combined_output, (
            f"Expected no DRIFT for CRLF vs LF difference:\n{combined_output}"
        )


# ===========================================================================
# Requirement: --check と --write の排他制御
# ===========================================================================

class TestCheckWriteExclusion(_CheckTestBase):
    """Tests for mutual exclusion of --check and --write flags."""

    # --- Scenario: --check と --write の同時指定 ---

    def test_check_and_write_simultaneous_error(self):
        """WHEN `twl chain generate <name> --check --write` を実行する
        THEN エラーメッセージを stderr に出力し、exit code 1 で終了する"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "内容。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(
            plugin_dir, "chain", "generate", "dev-pr-cycle", "--check", "--write"
        )

        assert result.returncode != 0, (
            f"Expected non-zero exit code for --check --write\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        # Error should be in stderr
        assert len(result.stderr.strip()) > 0 or "error" in (result.stdout + result.stderr).lower(), (
            f"Expected error message for mutual exclusion:\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_check_and_write_reverse_order_also_error(self):
        """WHEN `twl chain generate <name> --write --check` を実行する（逆順）
        THEN 同様にエラーとなる"""
        plugin_dir = make_check_fixture(self.tmpdir)

        result = run_engine(
            plugin_dir, "chain", "generate", "dev-pr-cycle", "--write", "--check"
        )

        assert result.returncode != 0, (
            f"Expected non-zero exit code for --write --check\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    def test_check_and_write_no_file_modification(self):
        """WHEN --check と --write を同時に指定した場合
        THEN ファイルは一切変更されない"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "元の内容。\n"
            ),
        }
        plugin_dir = make_check_fixture(self.tmpdir, body_overrides=body_overrides)

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content_before = file_path.read_text(encoding="utf-8")

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check", "--write")

        content_after = file_path.read_text(encoding="utf-8")
        assert content_before == content_after, (
            "File should not be modified when --check and --write are both specified"
        )
