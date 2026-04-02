#!/usr/bin/env python3
"""Tests for deep_validate() section E path traversal guard.

Spec: openspec/changes/deep-validate-section-e-iswith/specs/section-e-path-traversal-guard.md

Coverage: edge-cases
- Scenario 1: 正常な path はスキーマ検証される
- Scenario 2: パストラバーサルを含む path は拒否される
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

import yaml

LOOM_ENGINE = Path(__file__).parent.parent.parent / "loom-engine.py"


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _make_plugin_fixture(
    tmpdir: Path,
    *,
    specialist_path: str = "agents/my-specialist/AGENT.md",
    create_file: bool = True,
    body: str = (
        "## Purpose\nAnalyze code.\n\n"
        "## Output\nReturn PASS or FAIL.\n\n"
        "## Constraint\nMUST NOT skip.\n\n"
        "Report findings with severity and confidence.\n"
    ),
    output_schema: Optional[str] = None,
) -> Path:
    """Create a minimal plugin fixture for section E tests.

    Args:
        specialist_path: The path value to use in deps.yaml for the specialist.
        create_file: Whether to physically create the file at specialist_path.
        body: Body text of the specialist AGENT.md (used only when create_file=True).
        output_schema: If set, add output_schema field to the specialist entry.
    """
    plugin_dir = tmpdir / "test-plugin-traversal"
    plugin_dir.mkdir(exist_ok=True)

    agent_spec: dict = {
        "type": "specialist",
        "path": specialist_path,
        "description": "Test specialist agent",
        "calls": [],
    }
    if output_schema is not None:
        agent_spec["output_schema"] = output_schema

    deps = {
        "version": "3.0",
        "plugin": "test-traversal",
        "skills": {
            "main-controller": {
                "type": "controller",
                "path": "skills/main-controller/SKILL.md",
                "description": "Main controller",
                "calls": [{"specialist": "my-specialist"}],
            },
        },
        "commands": {},
        "agents": {
            "my-specialist": agent_spec,
        },
    }
    _write_deps(plugin_dir, deps)

    # Create controller file
    ctrl_dir = plugin_dir / "skills" / "main-controller"
    ctrl_dir.mkdir(parents=True, exist_ok=True)
    (ctrl_dir / "SKILL.md").write_text(
        "---\nname: main-controller\ndescription: Controller\n---\n\n## Step 0\nRoute.\n",
        encoding="utf-8",
    )

    # Create specialist file only when requested (and path is within the plugin root)
    if create_file:
        file_path = plugin_dir / specialist_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(
            f"---\nname: my-specialist\ndescription: Test specialist\n---\n\n{body}\n",
            encoding="utf-8",
        )

    return plugin_dir


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run loom-engine.py with the given arguments."""
    return subprocess.run(
        [sys.executable, str(LOOM_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# Test base class with setup/teardown
# ---------------------------------------------------------------------------

class _TraversalTestBase:
    """Shared setup/teardown for path traversal guard tests."""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)


# ===========================================================================
# Requirement: section E パストラバーサル防御
# ===========================================================================

class TestSectionEPathTraversalGuard(_TraversalTestBase):
    """deep_validate() section E applies _is_within_root() before path.exists()."""

    # --- Scenario 1: 正常な path はスキーマ検証される ---

    def test_valid_path_within_root_runs_schema_validation(self):
        """WHEN specialist の path がプラグインルート内の既存ファイルを指す
        THEN _is_within_root() チェックを通過し、出力スキーマキーワード検証が実行される"""
        # All output schema keywords present → no [specialist-output-schema] warning
        body = (
            "## Purpose\nAnalyze code quality.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "## Constraint\nMUST NOT skip.\n\n"
            "Report findings with severity and confidence scores.\n"
        )
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="agents/my-specialist/AGENT.md",
            create_file=True,
            body=body,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected no schema warning for valid in-root path, but got:\n{result.stdout}"
        )

    def test_valid_path_within_root_detects_missing_keywords(self):
        """WHEN specialist の path がプラグインルート内の既存ファイルを指し、キーワード不足の場合
        THEN スキーマ検証が実行され [specialist-output-schema] WARNING が報告される

        (副証明: _is_within_root() を通過して検証ロジックに到達していることの確認)
        """
        body = "## Purpose\nDo something.\n\nNo schema keywords here.\n"
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="agents/my-specialist/AGENT.md",
            create_file=True,
            body=body,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" in result.stdout, (
            f"Expected schema warning for in-root path with missing keywords, but got:\n{result.stdout}"
        )
        assert "my-specialist" in result.stdout

    # --- Scenario 2: パストラバーサルを含む path は拒否される ---

    def test_path_traversal_etc_passwd_is_silently_skipped(self):
        """WHEN specialist の path が '../../etc/passwd' を含むルート外の値を持つ
        THEN _is_within_root() が False を返し、当該コンポーネントの検証はスキップされる
        （エラー・WARNING のいずれも出力しない）"""
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="../../etc/passwd",
            create_file=False,  # ファイルは作成しない（ルート外ファイルのシミュレーション）
        )
        result = run_engine(plugin_dir, "--deep-validate")

        # スキーマ警告が出ないこと（スキップ済み）
        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected silent skip for path traversal, but got:\n{result.stdout}"
        )
        # エンジン自体はエラー終了しないこと
        assert result.returncode == 0, (
            f"Expected returncode 0 for traversal path, got {result.returncode}.\n"
            f"stderr: {result.stderr}"
        )

    def test_path_traversal_parent_dir_is_silently_skipped(self):
        """WHEN specialist の path が '../outside-plugin/secret.md' のようなルート外を指す
        THEN _is_within_root() が False を返し、検証はスキップされる（エラーなし）"""
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="../outside-plugin/secret.md",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected silent skip for parent dir traversal, but got:\n{result.stdout}"
        )
        assert result.returncode == 0, (
            f"Expected returncode 0 for traversal path, got {result.returncode}.\n"
            f"stderr: {result.stderr}"
        )

    def test_path_traversal_absolute_path_is_silently_skipped(self):
        """WHEN specialist の path が絶対パス（/etc/passwd 等）を指す
        THEN _is_within_root() が False を返し、検証はスキップされる（エラーなし）"""
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="/etc/passwd",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected silent skip for absolute path, but got:\n{result.stdout}"
        )
        assert result.returncode == 0, (
            f"Expected returncode 0 for absolute path, got {result.returncode}.\n"
            f"stderr: {result.stderr}"
        )

    def test_path_traversal_does_not_emit_error_or_warning_for_traversal(self):
        """WHEN path traversal が検出された場合
        THEN エラーメッセージや path traversal に関する WARNING は出力されない（サイレントスキップ）"""
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="../../etc/passwd",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        # パストラバーサル関連のエラーメッセージが含まれないこと
        for keyword in ("traversal", "outside", "path escape", "security"):
            assert keyword not in result.stdout.lower(), (
                f"Expected no '{keyword}' in output but got:\n{result.stdout}"
            )


# ===========================================================================
# Edge cases
# ===========================================================================

class TestSectionEPathTraversalEdgeCases(_TraversalTestBase):
    """Edge cases for section E path traversal guard."""

    def test_path_with_encoded_traversal_in_dir_is_handled(self):
        """Edge case: path が 'subdir/../../etc/passwd' のような中間ディレクトリ経由のトラバーサル
        THEN _is_within_root() が False を返し、サイレントスキップされる"""
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="agents/../../etc/passwd",
            create_file=False,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected silent skip for mid-path traversal, but got:\n{result.stdout}"
        )
        assert result.returncode == 0

    def test_valid_deep_nested_path_within_root_is_validated(self):
        """Edge case: プラグインルート内の深いネストパスは正常に検証される"""
        body = (
            "## Purpose\nDeep analysis.\n\n"
            "## Output\nReturn PASS or FAIL.\n\n"
            "## Constraint\nMUST NOT skip.\n\n"
            "Report findings with severity and confidence.\n"
        )
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="agents/sub/deep/nested/AGENT.md",
            create_file=True,
            body=body,
        )
        result = run_engine(plugin_dir, "--deep-validate")

        # 有効なファイルなので検証が走り、キーワード揃っているため WARNING なし
        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected no warning for valid deep nested path, but got:\n{result.stdout}"
        )

    def test_nonexistent_path_within_root_is_skipped_without_schema_warning(self):
        """Edge case: プラグインルート内でも存在しないファイルは schema 検証をスキップする
        （_is_within_root() は通過するが path.exists() で弾かれる）"""
        plugin_dir = _make_plugin_fixture(
            self.tmpdir,
            specialist_path="agents/nonexistent/AGENT.md",
            create_file=False,  # ルート内だが存在しない
        )
        result = run_engine(plugin_dir, "--deep-validate")

        # 存在しないファイルは schema 検証をスキップ → WARNING なし
        assert "[specialist-output-schema]" not in result.stdout, (
            f"Expected no schema warning for nonexistent in-root path, but got:\n{result.stdout}"
        )


# ===========================================================================
# main runner (for direct invocation without pytest)
# ===========================================================================

if __name__ == "__main__":
    import traceback

    classes = [
        TestSectionEPathTraversalGuard,
        TestSectionEPathTraversalEdgeCases,
    ]
    passed = 0
    failed = 0
    errors = []

    for cls in classes:
        for method_name in sorted(dir(cls)):
            if not method_name.startswith("test_"):
                continue
            instance = cls()
            try:
                instance.setup_method()
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
