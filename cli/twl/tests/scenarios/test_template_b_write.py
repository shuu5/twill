#!/usr/bin/env python3
"""Tests for chain generate --write Template B functionality (frontmatter called-by).

Spec: openspec/changes/chain-generate-write-template-b/specs/template-b-write.md

These tests are TDD-style: they define expected behavior BEFORE full implementation.
Template B writes/updates the called-by sentence in frontmatter description.
"""

import shutil
import subprocess
import os
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
        [sys.executable, "-m", "twl"] + list(extra_args),
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
        "plugin": "test-template-b",
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

class _TemplateBWriteTestBase:
    """Shared setup/teardown for Template B --write tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: template-b-write 書き込み実装
# ===========================================================================

class TestTemplateBWriteNewCalledBy(_TemplateBWriteTestBase):
    """Scenario: 新規 called-by 追記"""

    def test_new_called_by_appended_to_description(self):
        """WHEN --write を実行し、対象コンポーネントの description に called-by 文が存在しない
        THEN description 末尾に 。{parent} Step {step} から呼び出される。 を追記する"""
        plugin_dir = self.tmpdir / "plugin-new-calledby"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # workflow-test-ready: description に called-by なし
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        # workflow-setup: Template A のみ（step_in なし）
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n古い内容。",
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0, (
            f"Expected exit 0\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        # description 内に called-by 文が追記されていること
        assert "workflow-setup" in content, (
            f"Expected parent name in called-by:\n{content}"
        )
        assert "から呼び出される" in content, (
            f"Expected called-by sentence in description:\n{content}"
        )

    def test_new_called_by_with_step_number(self):
        """WHEN step_in に step フィールドがある場合
        THEN {parent} Step {step} から呼び出される。 の形式で追記される"""
        plugin_dir = self.tmpdir / "plugin-calledby-step"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

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
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        assert "Step 2" in content, (
            f"Expected 'Step 2' in called-by sentence:\n{content}"
        )
        assert "workflow-setup Step 2 から呼び出される" in content, (
            f"Expected full called-by with step:\n{content}"
        )


class TestTemplateBWriteExistingCalledBy(_TemplateBWriteTestBase):
    """Scenario: 既存 called-by 更新"""

    def test_existing_called_by_replaced(self):
        """WHEN --write を実行し、対象コンポーネントの description に既存の called-by 文がある
        THEN 正規表現パターンで既存文を検出し、新しい called-by 文で置換する"""
        plugin_dir = self.tmpdir / "plugin-replace-calledby"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # 既存の古い called-by 文を持つ description
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
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        # 古い called-by が消え、新しいものに置換されていること
        assert "old-parent" not in content, (
            f"Old called-by should be replaced:\n{content}"
        )
        assert "workflow-setup Step 2 から呼び出される" in content, (
            f"New called-by should be present:\n{content}"
        )

    def test_existing_called_by_pattern_match(self):
        """WHEN 既存 called-by が 。\\S+ (?:Step \\d+ )?から呼び出される。 パターンに合致する
        THEN そのパターンが新しい文で置換される"""
        plugin_dir = self.tmpdir / "plugin-pattern-match"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "3"},
        )
        _write_deps(plugin_dir, deps)

        # step なしの古い called-by パターン
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー。some-other から呼び出される。",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        assert "some-other" not in content, (
            f"Old called-by pattern should be replaced:\n{content}"
        )
        assert "workflow-setup Step 3 から呼び出される" in content, (
            f"New called-by should be present:\n{content}"
        )


class TestTemplateBWriteNoStepField(_TemplateBWriteTestBase):
    """Scenario: step フィールドなしの called-by"""

    def test_called_by_without_step(self):
        """WHEN step_in に step フィールドがない（parent のみ）
        THEN 。{parent} から呼び出される。 の形式で生成する"""
        plugin_dir = self.tmpdir / "plugin-no-step"
        plugin_dir.mkdir()

        # step_in has parent only, no step field
        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup"},
        )
        _write_deps(plugin_dir, deps)

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
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        # step なしの形式であること
        assert "workflow-setup から呼び出される" in content, (
            f"Expected called-by without step:\n{content}"
        )
        assert "Step" not in content.split("から呼び出される")[0].split("workflow-setup")[-1], (
            f"Should NOT contain 'Step' when step_in has no step field:\n{content}"
        )


class TestTemplateBWriteSkipNoStepIn(_TemplateBWriteTestBase):
    """Scenario: step_in を持たないコンポーネントのスキップ"""

    def test_no_step_in_skips_template_b(self):
        """WHEN 対象コンポーネントが template_b に含まれない（step_in 未設定）
        THEN Template B の書き込み処理をスキップする"""
        plugin_dir = self.tmpdir / "plugin-no-stepin"
        plugin_dir.mkdir()

        # step_in なし -- template_b に含まれない
        deps = _make_template_b_deps(step_in=None)
        _write_deps(plugin_dir, deps)

        original_desc = "開発準備ワークフロー"
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            original_desc,
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備ワークフロー",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        # workflow-setup has no step_in -> description should not get called-by
        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        assert "から呼び出される" not in content, (
            f"Component without step_in should not get called-by:\n{content}"
        )

        # workflow-test-ready also has no step_in -> same
        file_path2 = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        content2 = file_path2.read_text(encoding="utf-8")

        assert "から呼び出される" not in content2, (
            f"Component without step_in should not get called-by:\n{content2}"
        )


class TestTemplateBWritePreserveDescription(_TemplateBWriteTestBase):
    """Scenario: 既存 description の保持"""

    def test_non_calledby_description_preserved(self):
        """WHEN description に called-by 以外のテキストがある
        THEN called-by 以外の部分を変更せず保持しなければならない（MUST）"""
        plugin_dir = self.tmpdir / "plugin-preserve-desc"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        original_prefix = "テスト準備ワークフロー。重要な説明文がここにある"
        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            original_prefix,
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        # 元の description テキストが保持されていること
        assert "テスト準備ワークフロー" in content, (
            f"Original description prefix should be preserved:\n{content}"
        )
        assert "重要な説明文がここにある" in content, (
            f"Non-called-by description text MUST be preserved:\n{content}"
        )
        # かつ called-by も追記されていること
        assert "から呼び出される" in content, (
            f"Called-by should also be present:\n{content}"
        )

    def test_description_with_existing_calledby_preserves_prefix(self):
        """WHEN description が 'テスト準備。old-parent から呼び出される。' の場合
        THEN 'テスト準備' 部分は保持し、called-by 部分のみ置換する"""
        plugin_dir = self.tmpdir / "plugin-preserve-prefix"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        _create_component_file(
            plugin_dir,
            "skills/workflow-test-ready/SKILL.md",
            "workflow-test-ready",
            "テスト準備。old-parent から呼び出される。",
            "# Test Ready\n\n## チェックポイント（MUST）\n\nチェーン完了。",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        assert "テスト準備" in content, (
            f"Description prefix should be preserved:\n{content}"
        )
        assert "old-parent" not in content, (
            f"Old called-by should be replaced:\n{content}"
        )
        assert "workflow-setup Step 2 から呼び出される" in content, (
            f"New called-by should be present:\n{content}"
        )


class TestTemplateBWriteNoDescriptionLine(_TemplateBWriteTestBase):
    """Scenario: description 行が存在しない場合"""

    def test_no_description_line_warning(self):
        """WHEN frontmatter に description: 行が存在しない
        THEN Warning を出力しスキップする"""
        plugin_dir = self.tmpdir / "plugin-no-desc"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        # description 行なしの frontmatter
        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(
            "---\nname: workflow-test-ready\n---\n\n# Test Ready\n\n"
            "## チェックポイント（MUST）\n\nチェーン完了。\n",
            encoding="utf-8",
        )
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        combined_output = result.stdout + result.stderr
        # Warning が出力されること
        assert "warning" in combined_output.lower() or "Warning" in combined_output, (
            f"Expected warning when description line is missing:\n{combined_output}"
        )

    def test_no_description_line_no_modification(self):
        """WHEN frontmatter に description: 行が存在しない
        THEN frontmatter 構造を変更してはならない"""
        plugin_dir = self.tmpdir / "plugin-no-desc-nomod"
        plugin_dir.mkdir()

        deps = _make_template_b_deps(
            step_in={"parent": "workflow-setup", "step": "2"},
        )
        _write_deps(plugin_dir, deps)

        file_path = plugin_dir / "skills/workflow-test-ready/SKILL.md"
        file_path.parent.mkdir(parents=True, exist_ok=True)
        original_content = (
            "---\nname: workflow-test-ready\n---\n\n# Test Ready\n\n"
            "## チェックポイント（MUST）\n\nチェーン完了。\n"
        )
        file_path.write_text(original_content, encoding="utf-8")
        _create_component_file(
            plugin_dir,
            "skills/workflow-setup/SKILL.md",
            "workflow-setup",
            "開発準備ワークフロー",
            "# Setup\n\n## チェックポイント（MUST）\n\n古い。",
        )

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        # frontmatter に description が追加されていないこと
        content_after = file_path.read_text(encoding="utf-8")
        # Template A は更新されうるが、description: 行が新規追加されてはならない
        # frontmatter 部分だけ比較
        fm_after = content_after.split("---")[1] if "---" in content_after else ""
        assert "description:" not in fm_after, (
            f"description line should NOT be added to frontmatter:\n{content_after}"
        )
