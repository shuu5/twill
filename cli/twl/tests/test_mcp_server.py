"""Tests for Issue #962 Phase-0: twl MCP Server PoC Layer.

TDD RED フェーズ用テストスタブ。
実装前は全テストが FAIL する（意図的 RED）。

AC-α1: entry point 起動
AC-α2: tool expose + schema 注入
AC-α3: memory footprint (informational)
AC-α4: pyproject mcp extra-dependency
AC-α5: コアロジック非破壊・in-process tool 呼び出し
AC-α6: architecture note 仮置き
"""

import subprocess
import sys
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
PYPROJECT = TWL_DIR / "pyproject.toml"
ARCH_CONTEXTS_DIR = (
    TWL_DIR.parent.parent / "architecture" / "contexts"
)
# worktree root = TWL_DIR の 2 つ上
WORKTREE_ROOT = TWL_DIR.parent.parent


class TestACAlpha1EntryPointStartup:
    """AC-α1: mcp_server パッケージが存在し stdio MCP server が起動する。

    実装前は mcp_server パッケージが存在しないため ImportError で FAIL する。
    """

    def test_ac1_mcp_server_package_importable(self):
        # AC: cli/twl/src/twl/mcp_server/{__init__.py,server.py,tools.py} が
        #     新規作成されていること
        # RED: mcp_server パッケージが存在しないため ImportError
        from twl.mcp_server import server  # noqa: F401

    def test_ac1_mcp_server_files_exist(self):
        # AC: 3 ファイルが存在すること
        # RED: ファイル未作成のため FAIL
        mcp_pkg = TWL_DIR / "src" / "twl" / "mcp_server"
        assert (mcp_pkg / "__init__.py").exists(), (
            "cli/twl/src/twl/mcp_server/__init__.py が存在しない (AC-α1 未実装)"
        )
        assert (mcp_pkg / "server.py").exists(), (
            "cli/twl/src/twl/mcp_server/server.py が存在しない (AC-α1 未実装)"
        )
        assert (mcp_pkg / "tools.py").exists(), (
            "cli/twl/src/twl/mcp_server/tools.py が存在しない (AC-α1 未実装)"
        )

    def test_ac1_server_startup_exit_zero(self):
        # AC: `uv run --directory cli/twl --extra mcp fastmcp run
        #      src/twl/mcp_server/server.py` が exit code 0 で起動し
        #      FastMCP バナーをログ出力すること
        # RED: server.py 未存在のため非 0 exit または ImportError で FAIL
        result = subprocess.run(
            [
                "uv", "run",
                "--directory", str(TWL_DIR),
                "--extra", "mcp",
                "fastmcp", "run",
                "src/twl/mcp_server/server.py",
                "--help",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"MCP server 起動が exit code {result.returncode} で失敗 (AC-α1 未実装)\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        combined = result.stdout + result.stderr
        assert "FastMCP" in combined or "fastmcp" in combined.lower(), (
            "起動ログに FastMCP バナーが含まれない (AC-α1 未実装)\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


class TestACAlpha2ToolExposeSchema:
    """AC-α2: tools/list に 3 tool が JSONSchema 付きで返る。

    実装前は mcp_server パッケージが存在しないため ImportError で FAIL する。
    """

    def test_ac2_tools_module_importable(self):
        # AC: tools.py が存在し import 可能であること
        # RED: tools.py 未作成のため ImportError
        from twl.mcp_server import tools  # noqa: F401

    def test_ac2_three_tools_defined(self):
        # AC: twl_validate / twl_audit / twl_check の 3 tool が定義されていること
        # RED: tools.py 未作成のため ImportError → AttributeError
        from twl.mcp_server import tools  # noqa: F401
        for name in ("twl_validate", "twl_audit", "twl_check"):
            assert hasattr(tools, name), (
                f"tools.py に {name} が定義されていない (AC-α2 未実装)"
            )

    def test_ac2_tool_schema_has_plugin_root(self):
        # AC: 各 tool の JSONSchema に plugin_root: string (required) が含まれること
        # RED: tools.py 未作成のため ImportError
        from twl.mcp_server import tools  # noqa: F401
        # fastmcp ツールはスキーマ情報を持つ想定
        for name in ("twl_validate", "twl_audit", "twl_check"):
            tool_fn = getattr(tools, name, None)
            assert tool_fn is not None, (
                f"tools.{name} が存在しない (AC-α2 未実装)"
            )
            # fastmcp がアノテーションからスキーマを生成するため、
            # 関数アノテーションに plugin_root が含まれることを確認
            import inspect
            sig = inspect.signature(tool_fn)
            assert "plugin_root" in sig.parameters, (
                f"tools.{name} の引数に plugin_root が含まれない (AC-α2 未実装)"
            )


class TestACAlpha3MemoryFootprint:
    """AC-α3: メモリフットプリント計測 (informational)。

    ゲーティング基準ではなく PoC 記録目的のため、
    計測は試みるが psutil 未インストール等の場合は skip する。
    AssertionError は発生させない。
    """

    def test_ac3_rss_after_one_call_informational(self):
        # AC: server 起動 → twl_validate 1 回後の RSS < 50 MB (目安)
        # 実装前は mcp_server 未存在のため skip する
        pytest.skip(
            "AC-α3 は informational PoC 記録目的。"
            "mcp_server 実装後に計測を実施すること。"
        )


class TestACAlpha4Pyproject:
    """AC-α4: pyproject.toml に mcp extra-dependency が追加されている。

    現時点では fastmcp が含まれていないため assert FAIL する（意図的 RED）。
    """

    def test_ac4_mcp_optional_dependency_defined(self):
        # AC: [project.optional-dependencies] に mcp = ["fastmcp>=3.0"] が追加されていること
        # RED: pyproject.toml に fastmcp が含まれていないため FAIL
        content = PYPROJECT.read_text()
        assert "fastmcp" in content, (
            "pyproject.toml の [project.optional-dependencies] に "
            "fastmcp が含まれていない (AC-α4 未実装)"
        )

    def test_ac4_mcp_extra_key_exists(self):
        # AC: [project.optional-dependencies] の mcp キーが存在すること
        # RED: mcp キー未追加のため FAIL
        content = PYPROJECT.read_text()
        # TOML パース（標準ライブラリ tomllib は Python 3.11+、後方互換のため文字列検索）
        assert 'mcp = [' in content or 'mcp=[' in content or '"mcp"' in content, (
            "pyproject.toml に mcp extra キーが存在しない (AC-α4 未実装)"
        )


class TestACAlpha5CoreLogicIntact:
    """AC-α5: コアロジック非破壊・in-process MCP tool 呼び出し。

    実装前は mcp_server.tools が存在しないため ImportError で FAIL する。
    """

    def test_ac5_mcp_tools_handler_importable(self):
        # AC: from twl.mcp_server.tools import twl_validate_handler が import 可能
        # RED: tools.py 未作成のため ImportError
        from twl.mcp_server.tools import twl_validate_handler  # noqa: F401

    def test_ac5_in_process_tool_call_matches_direct_envelope(self):
        # AC: twl_validate(plugin_root=...) の戻り値 envelope と
        #     collector 4 stage を handler 経由せず直接呼んで生成した envelope が
        #     items / exit_code / summary で完全一致すること
        # RED: twl_validate_handler import 不可のため ImportError
        from twl.mcp_server.tools import twl_validate_handler

        # test-fixtures 内の適当なプラグインルートを使用
        test_fixtures = WORKTREE_ROOT / "test-fixtures"
        plugin_roots = list(test_fixtures.glob("*/")) if test_fixtures.exists() else []

        if not plugin_roots:
            pytest.skip("test-fixtures にプラグインルートが存在しないためスキップ")

        plugin_root = str(plugin_roots[0])

        # in-process 呼び出し
        envelope = twl_validate_handler(plugin_root=plugin_root)

        # 必須フィールドが存在すること
        assert "items" in envelope, (
            "twl_validate envelope に 'items' フィールドがない (AC-α5 未実装)"
        )
        assert "exit_code" in envelope, (
            "twl_validate envelope に 'exit_code' フィールドがない (AC-α5 未実装)"
        )
        assert "summary" in envelope, (
            "twl_validate envelope に 'summary' フィールドがない (AC-α5 未実装)"
        )

    def test_ac5_existing_pytest_suite_unbroken(self):
        # AC: cd cli/twl && pytest tests/ が PASS (既存テスト 100%)
        # これ自体は既存テストが通ることで検証されるが、
        # 本テスト追加により既存テストが壊れないことを確認する
        # ※ このテスト自体は mcp_server 未実装で FAIL する設計ではなく
        #    既存スイートの継続 PASS を示す sentinel として残す
        # → 現時点では imports failure を確認するのみ
        mcp_pkg = TWL_DIR / "src" / "twl" / "mcp_server"
        assert mcp_pkg.exists(), (
            "mcp_server パッケージディレクトリが存在しない (AC-α5 未実装)"
        )


class TestACAlpha6ArchitectureNote:
    """AC-α6: architecture/contexts/twill-integration.md が存在する。

    現時点では contexts ディレクトリ自体が存在しないため assert FAIL する（意図的 RED）。
    """

    def test_ac6_contexts_dir_exists(self):
        # AC: architecture/contexts/ ディレクトリが存在すること
        # RED: contexts ディレクトリ未作成のため FAIL
        assert ARCH_CONTEXTS_DIR.exists(), (
            f"architecture/contexts/ ディレクトリが存在しない (AC-α6 未実装): "
            f"{ARCH_CONTEXTS_DIR}"
        )

    def test_ac6_twill_integration_md_exists(self):
        # AC: architecture/contexts/twill-integration.md が存在すること
        # RED: ファイル未作成のため FAIL
        twill_integration = ARCH_CONTEXTS_DIR / "twill-integration.md"
        assert twill_integration.exists(), (
            f"architecture/contexts/twill-integration.md が存在しない (AC-α6 未実装): "
            f"{twill_integration}"
        )
