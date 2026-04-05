#!/usr/bin/env python3
"""Tests for chain generate --write functionality (file writing, section detection).

Spec: openspec/changes/chain-generate/specs/chain-generate-write.md

These tests are TDD-style: they define expected behavior BEFORE implementation.
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
                body = f"Content for {name}."

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


def make_write_fixture(tmpdir: Path, *, body_overrides: dict | None = None) -> Path:
    """Create a v3.0 plugin fixture for --write testing.

    Chain: dev-pr-cycle (type A)
      steps: [workflow-setup, workflow-test-ready]

    Each component has a path so --write can target them.
    """
    plugin_dir = tmpdir / "test-plugin-write"
    plugin_dir.mkdir()

    deps = {
        "version": "3.0",
        "plugin": "test-write",
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

class _WriteTestBase:
    """Shared setup/teardown for --write tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: --write フラグによるプロンプトファイル書き込み
# ===========================================================================

class TestWriteFlag(_WriteTestBase):
    """Tests for --write flag functionality."""

    # --- Scenario: --write でチェックポイントセクション置換 ---

    def test_write_replaces_checkpoint_section(self):
        """WHEN `twl chain generate dev-pr-cycle --write` を実行し、
        プロンプトファイルに `## チェックポイント` セクションが存在する
        THEN 既存のチェックポイントセクションが生成されたテンプレートで置換される"""
        body_overrides = {
            "workflow-setup": (
                "# Workflow Setup\n\n"
                "本体テキスト。\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いチェックポイント内容。\n\n"
                "`/dev:old-reference` を Skill tool で自動実行。\n\n"
                "## 次のセクション\n\n"
                "この部分は保持される。"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0, (
            f"Expected exit code 0\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

        # ファイル内容を検証
        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        # 古い参照が消え、新しい参照が入っていること
        assert "/dev:old-reference" not in content, (
            f"Old checkpoint reference should be replaced:\n{content}"
        )
        assert "/dev:workflow-test-ready" in content, (
            f"New checkpoint reference should be present:\n{content}"
        )

    def test_write_preserves_other_sections(self):
        """WHEN --write でチェックポイントセクションを置換する
        THEN チェックポイント以外のセクションは保持される"""
        body_overrides = {
            "workflow-setup": (
                "# Workflow Setup\n\n"
                "本体テキスト。\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いチェックポイント。\n\n"
                "## 次のセクション\n\n"
                "保持されるべき内容。"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        assert "保持されるべき内容" in content, (
            f"Other sections should be preserved:\n{content}"
        )
        assert "## 次のセクション" in content, (
            f"Next section header should be preserved:\n{content}"
        )

    def test_write_preserves_frontmatter(self):
        """WHEN --write でファイルを書き込む
        THEN frontmatter は変更されない"""
        body_overrides = {
            "workflow-setup": (
                "# Workflow Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いチェックポイント。\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")

        assert content.startswith("---\n"), "Frontmatter should be preserved"
        assert "name: workflow-setup" in content, "Frontmatter name should be preserved"

    def test_write_exit_code_zero_on_success(self):
        """WHEN --write が正常に完了する
        THEN 終了コードは 0"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "置換対象。\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0

    # --- Scenario: セクション未検出時の警告 ---

    def test_write_section_not_found_warning(self):
        """WHEN --write 実行時にプロンプトファイルに対応するセクションマーカーが存在しない
        THEN 警告メッセージ "Section marker not found in {path}, skipping" が出力される"""
        # セクションマーカーなしのファイル
        body_overrides = {
            "workflow-setup": (
                "# Workflow Setup\n\n"
                "チェックポイントセクションが存在しないコンテンツ。\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        combined_output = result.stdout + result.stderr
        assert "Section marker not found" in combined_output or "skipping" in combined_output.lower(), (
            f"Expected section-not-found warning:\n{combined_output}"
        )

    def test_write_section_not_found_template_a_unchanged(self):
        """WHEN チェックポイントセクションマーカーが見つからない場合
        THEN Template A は書き込まれないが、Template C（スターター指示）は追加される"""
        original_body = (
            "# Workflow Setup\n\n"
            "マーカーなしの本体テキスト。\n"
        )
        body_overrides = {
            "workflow-setup": original_body,
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content_after = file_path.read_text(encoding="utf-8")
        # Template A (チェックポイント) は書き込まれない
        assert "## チェックポイント" not in content_after
        # Template C (chain 実行指示) は追加される
        assert "## chain 実行指示" in content_after

    def test_write_section_not_found_warning_includes_path(self):
        """WHEN セクションマーカーが見つからない場合
        THEN 警告メッセージにファイルパスが含まれる"""
        body_overrides = {
            "workflow-setup": "# No markers\n\nPlain content.\n",
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        combined_output = result.stdout + result.stderr
        # パス情報が何らかの形で含まれること
        assert "workflow-setup" in combined_output or "SKILL.md" in combined_output, (
            f"Warning should include file path information:\n{combined_output}"
        )

    # --- Edge: --write with multiple components, some missing markers ---

    def test_write_partial_success_continues_processing(self):
        """WHEN 複数のコンポーネントのうち、一部だけにセクションマーカーがある場合
        THEN マーカーありのファイルは更新され、なしのファイルはスキップされ、処理は継続する"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古い内容。\n"
            ),
            "workflow-test-ready": (
                "# Test Ready\n\n"
                "マーカーなし。\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        # 処理は正常終了すること（エラー終了しないこと）
        assert result.returncode == 0, f"stderr: {result.stderr}"

        # マーカーありのファイルは更新されている
        setup_content = (plugin_dir / "skills/workflow-setup/SKILL.md").read_text(encoding="utf-8")
        assert "古い内容" not in setup_content or "/dev:" in setup_content, (
            f"File with marker should be updated:\n{setup_content}"
        )


# ===========================================================================
# Requirement: セクション検出パターン
# ===========================================================================

class TestSectionDetectionPatterns(_WriteTestBase):
    """Tests for section header pattern matching."""

    # --- Scenario: 日本語セクションヘッダー ---

    def test_japanese_checkpoint_header_detected(self):
        """WHEN プロンプトファイルに `## チェックポイント（MUST）` が存在する
        THEN セクションが正しく検出され、置換対象となる"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "古いチェックポイント内容。\n\n"
                "## 次のセクション\n\n"
                "保持。"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0, f"stderr: {result.stderr}"

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        assert "古いチェックポイント内容" not in content, (
            f"Old checkpoint content should be replaced:\n{content}"
        )

    def test_japanese_checkpoint_header_bare(self):
        """WHEN プロンプトファイルに `## チェックポイント` が存在する（修飾語なし）
        THEN セクションが正しく検出される"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント\n\n"
                "古い内容。\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0, f"stderr: {result.stderr}"

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        assert "古い内容" not in content, (
            f"Old content should be replaced:\n{content}"
        )

    # --- Scenario: 英語セクションヘッダー ---

    def test_english_checkpoint_header_detected(self):
        """WHEN プロンプトファイルに `## Checkpoint` が存在する
        THEN セクションが正しく検出され、置換対象となる"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## Checkpoint\n\n"
                "Old checkpoint content.\n\n"
                "## Next Section\n\n"
                "Preserved."
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0, f"stderr: {result.stderr}"

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        assert "Old checkpoint content" not in content, (
            f"Old English checkpoint content should be replaced:\n{content}"
        )

    def test_english_checkpoint_with_must_annotation(self):
        """WHEN プロンプトファイルに `## Checkpoint (MUST)` が存在する
        THEN セクションが正しく検出される"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## Checkpoint (MUST)\n\n"
                "Old content.\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0, f"stderr: {result.stderr}"

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        assert "Old content" not in content, (
            f"Old content should be replaced with (MUST) variant:\n{content}"
        )

    # --- Edge: case sensitivity for English headers ---

    def test_english_checkpoint_case_insensitive(self):
        """WHEN プロンプトファイルに `## checkpoint` (小文字) が存在する
        THEN セクション検出が成功するかどうかは実装依存だが、大文字 Checkpoint は確実に検出される"""
        # この テストは `## Checkpoint` (大文字C) が確実に検出されることの二重確認
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## Checkpoint\n\n"
                "Original.\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0
        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        assert "Original" not in content

    # --- Edge: h3 (###) checkpoint header should NOT match ---

    def test_h3_checkpoint_header_not_matched(self):
        """WHEN プロンプトファイルに `### チェックポイント` (h3) が存在する
        THEN h2 パターンのみ検出するため、h3 はマッチしない"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "### チェックポイント\n\n"
                "h3のチェックポイント。\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        # h3 はマッチしないので、セクション未検出の警告が出るか、
        # ファイルが変更されないことを確認
        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        assert "h3のチェックポイント" in content, (
            f"h3 checkpoint section should NOT be replaced:\n{content}"
        )

    # --- Edge: multiple checkpoint sections (first one wins) ---

    def test_multiple_checkpoint_sections_first_replaced(self):
        """WHEN プロンプトファイルに複数のチェックポイントセクションがある場合
        THEN 最初のセクションが置換される"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "最初のチェックポイント。\n\n"
                "## その他\n\n"
                "中間セクション。\n\n"
                "## チェックポイント\n\n"
                "2番目のチェックポイント。\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle", "--write")

        assert result.returncode == 0, f"stderr: {result.stderr}"
        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content = file_path.read_text(encoding="utf-8")
        assert "最初のチェックポイント" not in content, (
            f"First checkpoint section should be replaced:\n{content}"
        )


# ===========================================================================
# Requirement: path フィールド未設定時のスキップ
# ===========================================================================

class TestPathFieldSkip(_WriteTestBase):
    """Tests for skipping components without path field during --write."""

    # --- Scenario: path なしコンポーネント ---

    def test_no_path_component_warning(self):
        """WHEN chain 参加者のコンポーネントに path フィールドがない
        THEN 警告 "No path defined for {component}, skipping --write" が出力される"""
        plugin_dir = self.tmpdir / "test-plugin-no-path"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "test-no-path",
            "chains": {
                "test-chain": {
                    "description": "Test",
                    "type": "A",
                    "steps": ["with-path", "no-path-comp"],
                },
            },
            "skills": {
                "with-path": {
                    "type": "workflow",
                    "path": "skills/with-path/SKILL.md",
                    "description": "Has path",
                    "chain": "test-chain",
                    "calls": [],
                },
                "no-path-comp": {
                    "type": "workflow",
                    "description": "No path defined",
                    "chain": "test-chain",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)
        _create_component_files(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "test-chain", "--write")

        combined_output = result.stdout + result.stderr
        assert "no-path-comp" in combined_output, (
            f"Warning should mention the component name:\n{combined_output}"
        )
        assert "skipping" in combined_output.lower() or "skip" in combined_output.lower(), (
            f"Warning should indicate skipping:\n{combined_output}"
        )

    def test_no_path_component_exact_warning_message(self):
        """WHEN path なしのコンポーネントがある
        THEN 正確に "No path defined for {component}, skipping --write" が出力される"""
        plugin_dir = self.tmpdir / "test-plugin-no-path-exact"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "test-no-path-exact",
            "chains": {
                "test-chain": {
                    "description": "Test",
                    "type": "A",
                    "steps": ["pathless"],
                },
            },
            "skills": {
                "pathless": {
                    "type": "workflow",
                    "description": "Pathless component",
                    "chain": "test-chain",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "test-chain", "--write")

        combined_output = result.stdout + result.stderr
        assert "No path defined for pathless, skipping --write" in combined_output, (
            f"Expected exact warning message:\n{combined_output}"
        )

    def test_no_path_component_others_continue(self):
        """WHEN chain に path なしコンポーネントがある
        THEN 他のコンポーネントの --write 処理は継続される"""
        plugin_dir = self.tmpdir / "test-plugin-mixed-path"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "test-mixed",
            "chains": {
                "test-chain": {
                    "description": "Test",
                    "type": "A",
                    "steps": ["has-path", "no-path"],
                },
            },
            "skills": {
                "has-path": {
                    "type": "workflow",
                    "path": "skills/has-path/SKILL.md",
                    "description": "Has path",
                    "chain": "test-chain",
                    "calls": [],
                },
                "no-path": {
                    "type": "workflow",
                    "description": "No path",
                    "chain": "test-chain",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        # has-path のファイルを作成（チェックポイントセクション付き）
        file_path = plugin_dir / "skills/has-path/SKILL.md"
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(
            "---\nname: has-path\ndescription: Has path\n---\n\n"
            "# Has Path\n\n"
            "## チェックポイント（MUST）\n\n"
            "古い内容。\n",
            encoding="utf-8",
        )

        result = run_engine(plugin_dir, "chain", "generate", "test-chain", "--write")

        # 処理は継続し、正常終了すること
        assert result.returncode == 0, f"stderr: {result.stderr}"

        # has-path のファイルは処理されていること
        content = file_path.read_text(encoding="utf-8")
        # 何らかの更新が行われていることを確認（古い内容が置換されているか）
        assert "古い内容" not in content or "チェーン完了" in content or "/dev:" in content, (
            f"File with path should be processed:\n{content}"
        )

    # --- Edge: all components without path ---

    def test_all_components_no_path_only_warnings(self):
        """WHEN chain の全コンポーネントに path がない場合
        THEN 全てスキップされ、警告のみ出力され、エラー終了しない"""
        plugin_dir = self.tmpdir / "test-plugin-all-no-path"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "test-all-no-path",
            "chains": {
                "test-chain": {
                    "description": "Test",
                    "type": "A",
                    "steps": ["comp-a", "comp-b"],
                },
            },
            "skills": {
                "comp-a": {
                    "type": "workflow",
                    "description": "No path A",
                    "chain": "test-chain",
                    "calls": [],
                },
                "comp-b": {
                    "type": "workflow",
                    "description": "No path B",
                    "chain": "test-chain",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "test-chain", "--write")

        # エラー終了しない（スキップだけ）
        assert result.returncode == 0, (
            f"All-skipped should still exit 0\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined_output = result.stdout + result.stderr
        assert "comp-a" in combined_output, "Should warn about comp-a"
        assert "comp-b" in combined_output, "Should warn about comp-b"

    # --- Edge: path field is empty string ---

    def test_empty_path_string_treated_as_no_path(self):
        """WHEN path フィールドが空文字列の場合
        THEN path なしと同様にスキップされる"""
        plugin_dir = self.tmpdir / "test-plugin-empty-path"
        plugin_dir.mkdir()

        deps = {
            "version": "3.0",
            "plugin": "test-empty-path",
            "chains": {
                "test-chain": {
                    "description": "Test",
                    "type": "A",
                    "steps": ["empty-path-comp"],
                },
            },
            "skills": {
                "empty-path-comp": {
                    "type": "workflow",
                    "path": "",
                    "description": "Empty path",
                    "chain": "test-chain",
                    "calls": [],
                },
            },
            "commands": {},
            "agents": {},
        }
        _write_deps(plugin_dir, deps)

        result = run_engine(plugin_dir, "chain", "generate", "test-chain", "--write")

        combined_output = result.stdout + result.stderr
        assert "empty-path-comp" in combined_output or "skipping" in combined_output.lower(), (
            f"Empty path should be treated as no path:\n{combined_output}"
        )

    # --- Edge: --write without --write flag just outputs to stdout ---

    def test_no_write_flag_only_stdout(self):
        """WHEN --write フラグなしで chain generate を実行する
        THEN ファイルは変更されず、stdout にのみ出力される"""
        body_overrides = {
            "workflow-setup": (
                "# Setup\n\n"
                "## チェックポイント（MUST）\n\n"
                "元の内容。\n"
            ),
        }
        plugin_dir = make_write_fixture(self.tmpdir, body_overrides=body_overrides)

        file_path = plugin_dir / "skills/workflow-setup/SKILL.md"
        content_before = file_path.read_text(encoding="utf-8")

        result = run_engine(plugin_dir, "chain", "generate", "dev-pr-cycle")

        assert result.returncode == 0
        content_after = file_path.read_text(encoding="utf-8")
        assert content_before == content_after, (
            "File should not be modified without --write flag"
        )
        # stdout には出力があること
        assert len(result.stdout.strip()) > 0, "Should have stdout output"
