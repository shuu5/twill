#!/usr/bin/env python3
"""Tests for chain generate --check Template B functionality (called-by drift detection).

Spec: openspec/changes/chain-generate-write-template-b/specs/template-b-check.md

These tests are TDD-style: they define expected behavior BEFORE full implementation.
Template B --check detects drift in frontmatter description called-by sentences.
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


def _create_component_file(
    plugin_dir: Path,
    path_str: str,
    name: str,
    description: str,
    body: str = "",
) -> None:
    """Create a single component markdown file with frontmatter."""
    file_path = plugin_dir / path_str
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text(
        f"---\nname: {name}\ndescription: {description}\n---\n\n{body}\n",
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


def _make_template_b_deps(
    *,
    step_in: dict | None = None,
    step_in_for: str = "workflow-test-ready",
) -> dict:
    """Create a standard deps.yaml structure for Template B testing.

    The chain has two steps: workflow-setup -> workflow-test-ready.
    workflow-test-ready has a step_in referencing workflow-setup.
    """
    deps = {
        "version": "3.0",
        "plugin": "test-template-b-check",
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
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    if step_in is not None:
        deps["skills"][step_in_for]["step_in"] = step_in
    return deps


# ---------------------------------------------------------------------------
# Test base class
# ---------------------------------------------------------------------------

class _TemplateBCheckTestBase:
    """Shared setup/teardown for Template B --check tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: template-b-check ドリフト検出
# ===========================================================================

class TestTemplateBCheckMatch(_TemplateBCheckTestBase):
    """Scenario: called-by 一致"""

    def test_called_by_matches_reports_ok(self):
        """WHEN --check を実行し、frontmatter description 内の called-by 文が期待値と一致する
        THEN 当該コンポーネントを ok としてレポートする"""
        plugin_dir = self.tmpdir / "plugin-check-match"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # Template C 用のスターター指示（workflow-setup が chain の親なので）
        template_c_section = (
            "## chain 実行指示（MUST）\n\n"
            "以下の順序でステップを実行する。各ステップの COMMAND.md を Read し、Skill tool で自動実行すること。\n\n"
            "Step 1: `/dev:workflow-setup` を Skill tool で実行\n"
            "→ 以降は各 COMMAND.md のチェックポイントに従い自動進行\n\n"
            "### ライフサイクル\n\n"
            "| # | 型 | コンポーネント | 説明 |\n"
            "|---|---|---|---|\n"
            "| 1 | workflow | workflow-setup | 開発準備ワークフロー |\n"
            "| 2 | workflow | workflow-test-ready | テスト準備ワークフロー |"
        )

        # called-by が期待値と一致する description
        # 期待値: "workflow-setup Step 2 から呼び出される。"
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー。workflow-setup Step 2 から呼び出される。",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n"
            "`/dev:workflow-test-ready` を Skill tool で自動実行。\n\n"
            + template_c_section,
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 0, (
            f"Expected exit 0 when called-by matches\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "ok" in combined_output.lower(), (
            f"Expected 'ok' status in output:\n{combined_output}"
        )

    def test_called_by_match_no_drift_reported(self):
        """WHEN called-by が一致する場合
        THEN Template B の DRIFT は報告されない"""
        plugin_dir = self.tmpdir / "plugin-check-match-nodrift"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # Template C 用のスターター指示
        template_c_section = (
            "## chain 実行指示（MUST）\n\n"
            "以下の順序でステップを実行する。各ステップの COMMAND.md を Read し、Skill tool で自動実行すること。\n\n"
            "Step 1: `/dev:workflow-setup` を Skill tool で実行\n"
            "→ 以降は各 COMMAND.md のチェックポイントに従い自動進行\n\n"
            "### ライフサイクル\n\n"
            "| # | 型 | コンポーネント | 説明 |\n"
            "|---|---|---|---|\n"
            "| 1 | workflow | workflow-setup | 開発準備ワークフロー |\n"
            "| 2 | workflow | workflow-test-ready | テスト準備ワークフロー |"
        )

        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー。workflow-setup Step 2 から呼び出される。",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n"
            "`/dev:workflow-test-ready` を Skill tool で自動実行。\n\n"
            + template_c_section,
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        combined_output = result.stdout + result.stderr
        assert "DRIFT" not in combined_output and result.returncode == 0, (
            f"Expected no DRIFT:\n{combined_output}"
        )


class TestTemplateBCheckMismatch(_TemplateBCheckTestBase):
    """Scenario: called-by 不一致"""

    def test_called_by_mismatch_reports_drift(self):
        """WHEN --check を実行し、frontmatter description 内の called-by 文が期待値と異なる
        THEN 当該コンポーネントを DRIFT としてレポートし、差分を出力する（MUST）"""
        plugin_dir = self.tmpdir / "plugin-check-mismatch"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # 期待: "workflow-setup Step 2 から呼び出される。"
        # 実際: "old-parent Step 5 から呼び出される。" (不一致)
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー。old-parent Step 5 から呼び出される。",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n"
            "`/dev:workflow-test-ready` を Skill tool で自動実行。",
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 1, (
            f"Expected exit 1 when called-by mismatches\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" in combined_output, (
            f"Expected DRIFT status for called-by mismatch:\n{combined_output}"
        )

    def test_called_by_mismatch_shows_diff(self):
        """WHEN called-by が不一致の場合
        THEN 差分（期待値 vs 実際値）を出力する"""
        plugin_dir = self.tmpdir / "plugin-check-mismatch-diff"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー。wrong-parent から呼び出される。",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n"
            "`/dev:workflow-test-ready` を Skill tool で自動実行。",
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 1
        combined_output = result.stdout + result.stderr
        # 差分情報が何らかの形で出力されていること
        has_diff_info = (
            "workflow-setup" in combined_output
            or "---" in combined_output
            or "expected" in combined_output.lower()
            or "actual" in combined_output.lower()
        )
        assert has_diff_info, (
            f"Expected diff output for called-by mismatch:\n{combined_output}"
        )


class TestTemplateBCheckMissing(_TemplateBCheckTestBase):
    """Scenario: called-by 欠落"""

    def test_called_by_missing_reports_drift(self):
        """WHEN --check を実行し、template_b に含まれるコンポーネントの description に
        called-by 文が存在しない
        THEN 当該コンポーネントを DRIFT としてレポートする"""
        plugin_dir = self.tmpdir / "plugin-check-missing"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # called-by なし
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n"
            "`/dev:workflow-test-ready` を Skill tool で自動実行。",
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 1, (
            f"Expected exit 1 when called-by is missing\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" in combined_output, (
            f"Expected DRIFT status for missing called-by:\n{combined_output}"
        )


class TestTemplateBCheckIntegration(_TemplateBCheckTestBase):
    """Scenario: Template A と B の両方を検証"""

    def test_check_validates_both_template_a_and_b(self):
        """WHEN --check を実行する
        THEN Template A と Template B の両方のドリフトを検出し、統合結果を返す（SHALL）"""
        plugin_dir = self.tmpdir / "plugin-check-both"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # Template A: チェックポイントは正しい
        # Template B: called-by が不一致
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー。wrong-parent から呼び出される。",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n"
            "`/dev:workflow-test-ready` を Skill tool で自動実行。",
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        # Template B の不一致が DRIFT として検出されること
        assert result.returncode == 1, (
            f"Expected exit 1 with Template B drift\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "DRIFT" in combined_output, (
            f"Expected DRIFT in integrated check result:\n{combined_output}"
        )

    def test_check_both_templates_ok_when_all_match(self):
        """WHEN Template A, B, C の全てが一致する場合
        THEN exit code 0 で ok が報告される"""
        plugin_dir = self.tmpdir / "plugin-check-both-ok"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # Template C 用のスターター指示
        template_c_section = (
            "## chain 実行指示（MUST）\n\n"
            "以下の順序でステップを実行する。各ステップの COMMAND.md を Read し、Skill tool で自動実行すること。\n\n"
            "Step 1: `/dev:workflow-setup` を Skill tool で実行\n"
            "→ 以降は各 COMMAND.md のチェックポイントに従い自動進行\n\n"
            "### ライフサイクル\n\n"
            "| # | 型 | コンポーネント | 説明 |\n"
            "|---|---|---|---|\n"
            "| 1 | workflow | workflow-setup | 開発準備ワークフロー |\n"
            "| 2 | workflow | workflow-test-ready | テスト準備ワークフロー |"
        )

        # Template A + Template B + Template C 全て正しい状態
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー。workflow-setup Step 2 から呼び出される。",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n"
            "`/dev:workflow-test-ready` を Skill tool で自動実行。\n\n"
            + template_c_section,
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--check")

        assert result.returncode == 0, (
            f"Expected exit 0 when all templates match\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "ok" in combined_output.lower(), (
            f"Expected 'ok' when all templates match:\n{combined_output}"
        )
