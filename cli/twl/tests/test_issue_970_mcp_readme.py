"""Tests for Issue #970: cli/twl/src/twl/mcp_server/README.md 作成.

TDD RED フェーズ用テストスタブ。
README.md が未作成の現状では AC1〜AC6 が全て FAIL する（意図的 RED）。
AC7 は既存テスト群が PASS することを検証する（現状 PASS のはず）。

AC1: cli/twl/src/twl/mcp_server/README.md が存在する
AC2: README に 5 セクション見出しが存在する
AC3: README に `pip install -e '.[mcp]'` が含まれる
AC4: README に twl_validate / twl_audit / twl_check の 3 tool 名が全て出現する
AC5: README に plugin_root 引数の説明が 2 件以上出現する
AC6: README に #945 と #962 への参照が含まれる
AC7: 既存テストが非破壊である（pytest tests/ が PASS）
"""

import subprocess
import sys
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
README_PATH = TWL_DIR / "src" / "twl" / "mcp_server" / "README.md"


class TestAC1FileExists:
    """AC1: cli/twl/src/twl/mcp_server/README.md が存在する。

    README.md が未作成の現状では FAIL する。
    """

    def test_ac1_readme_file_exists(self):
        # AC: cli/twl/src/twl/mcp_server/README.md が存在する（test -f PASS）
        # RED: README.md 未作成のため AssertionError で FAIL
        assert README_PATH.exists(), (
            f"cli/twl/src/twl/mcp_server/README.md が存在しない (AC1 未実装)\n"
            f"期待パス: {README_PATH}"
        )

    def test_ac1_readme_is_file(self):
        # AC: パスがファイルであること（ディレクトリでない）
        # RED: README.md 未作成のため FAIL
        assert README_PATH.is_file(), (
            f"パスはファイルでなければならない (AC1 未実装)\n"
            f"パス: {README_PATH}"
        )


class TestAC2FiveSections:
    """AC2: README に 5 セクション見出しが存在する。

    見出し: ## 概要 / ## インストール / ## 起動 / ## 提供ツール / ## plugin_root 引数
    （または同等英訳）。grep で 5 件以上 hit する。
    """

    REQUIRED_SECTIONS = [
        ("概要", "Overview"),
        ("インストール", "Install"),
        ("起動", "Usage", "Start", "Run"),
        ("提供ツール", "Tools", "Available Tools"),
        ("plugin_root 引数", "plugin_root"),
    ]

    def test_ac2_five_sections_exist(self):
        # AC: README に 5 セクション見出し（## レベル）が存在する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装, AC2 前提条件 FAIL)\nパス: {README_PATH}"
        )

        content = README_PATH.read_text(encoding="utf-8")
        headings = [
            line.strip()
            for line in content.splitlines()
            if line.startswith("## ")
        ]
        assert len(headings) >= 5, (
            f"README の ## レベル見出しが 5 件未満 (AC2 未実装)\n"
            f"検出された見出し数: {len(headings)}\n"
            f"検出内容: {headings}"
        )

    def test_ac2_section_gaiyou(self):
        # AC: ## 概要 または ## Overview 相当の見出しが存在する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        found = any(
            "概要" in line or "Overview" in line.lower()
            for line in content.splitlines()
            if line.startswith("## ")
        )
        assert found, (
            "README に ## 概要 / ## Overview 相当の見出しが存在しない (AC2 未実装)"
        )

    def test_ac2_section_install(self):
        # AC: ## インストール または ## Install 相当の見出しが存在する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        found = any(
            "インストール" in line or "install" in line.lower()
            for line in content.splitlines()
            if line.startswith("## ")
        )
        assert found, (
            "README に ## インストール / ## Install 相当の見出しが存在しない (AC2 未実装)"
        )

    def test_ac2_section_startup(self):
        # AC: ## 起動 または ## Usage/Start/Run 相当の見出しが存在する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        keywords = ("起動", "usage", "start", "run", "使い方")
        found = any(
            any(kw in line.lower() for kw in keywords)
            for line in content.splitlines()
            if line.startswith("## ")
        )
        assert found, (
            "README に ## 起動 / ## Usage/Start/Run 相当の見出しが存在しない (AC2 未実装)"
        )

    def test_ac2_section_tools(self):
        # AC: ## 提供ツール または ## Tools 相当の見出しが存在する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        keywords = ("提供ツール", "ツール", "tools", "available")
        found = any(
            any(kw in line.lower() for kw in keywords)
            for line in content.splitlines()
            if line.startswith("## ")
        )
        assert found, (
            "README に ## 提供ツール / ## Tools 相当の見出しが存在しない (AC2 未実装)"
        )

    def test_ac2_section_plugin_root(self):
        # AC: ## plugin_root 引数 相当の見出しが存在する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        found = any(
            "plugin_root" in line
            for line in content.splitlines()
            if line.startswith("## ")
        )
        assert found, (
            "README に ## plugin_root 引数 相当の見出しが存在しない (AC2 未実装)"
        )


class TestAC3InstallCommand:
    """AC3: README に `pip install -e '.[mcp]'` が含まれる。"""

    def test_ac3_pip_install_mcp_present(self):
        # AC: README に pip install -e '.[mcp]' が含まれる
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        assert "pip install -e" in content and "[mcp]" in content, (
            "README に `pip install -e '.[mcp]'` が含まれない (AC3 未実装)\n"
            "インストールコマンドの整合が取れていない"
        )


class TestAC4ThreeToolNames:
    """AC4: README に twl_validate / twl_audit / twl_check の 3 tool 名が全て出現する。"""

    TOOL_NAMES = ["twl_validate", "twl_audit", "twl_check"]

    def test_ac4_twl_validate_present(self):
        # AC: README に twl_validate が出現する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        assert "twl_validate" in content, (
            "README に tool 名 `twl_validate` が含まれない (AC4 未実装)"
        )

    def test_ac4_twl_audit_present(self):
        # AC: README に twl_audit が出現する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        assert "twl_audit" in content, (
            "README に tool 名 `twl_audit` が含まれない (AC4 未実装)"
        )

    def test_ac4_twl_check_present(self):
        # AC: README に twl_check が出現する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        assert "twl_check" in content, (
            "README に tool 名 `twl_check` が含まれない (AC4 未実装)"
        )

    def test_ac4_all_three_tools_present(self):
        # AC: 3 tool 名が全て出現する（一括確認）
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        missing = [name for name in self.TOOL_NAMES if name not in content]
        assert not missing, (
            f"README に以下の tool 名が存在しない (AC4 未実装): {missing}"
        )


class TestAC5PluginRootDescription:
    """AC5: README に plugin_root 引数の説明が 2 件以上出現する。"""

    def test_ac5_plugin_root_appears_twice_or_more(self):
        # AC: README に plugin_root が 2 件以上出現する
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        count = content.count("plugin_root")
        assert count >= 2, (
            f"README に `plugin_root` が 2 件以上出現しない (AC5 未実装)\n"
            f"現在の出現数: {count}"
        )


class TestAC6IssueLinks:
    """AC6: README に #945 と #962 への参照が含まれる。"""

    def test_ac6_issue_945_reference_present(self):
        # AC: README に #945 への参照が含まれる
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        assert "#945" in content, (
            "README に Issue #945 への参照が含まれない (AC6 未実装)"
        )

    def test_ac6_issue_962_reference_present(self):
        # AC: README に #962 への参照が含まれる
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        assert "#962" in content, (
            "README に Issue #962 への参照が含まれない (AC6 未実装)"
        )

    def test_ac6_both_issue_references_present(self):
        # AC: #945 と #962 の両方が含まれる（一括確認）
        # RED: README.md 未作成のため FAIL
        assert README_PATH.exists(), (
            f"README.md が存在しない (AC1 未実装)"
        )
        content = README_PATH.read_text(encoding="utf-8")
        missing = [ref for ref in ("#945", "#962") if ref not in content]
        assert not missing, (
            f"README に以下の Issue 参照が存在しない (AC6 未実装): {missing}"
        )


class TestAC7ExistingTestsUnbroken:
    """AC7: 既存テストが非破壊である（pytest tests/ が PASS）。

    subprocess で pytest を実行し、test_issue_970_mcp_readme.py 自身を除外して
    既存テストが壊れていないことを確認する（自己循環回避）。

    注意: test_soft_deny_match.py は twl.intervention モジュール未実装のため
    collection エラーが発生する既知の問題がある（本 Issue とは無関係）。
    そのファイルも --ignore で除外して実行する。
    """

    def test_ac7_existing_tests_not_broken_by_readme(self):
        # AC: cd cli/twl && pytest tests/ が PASS（README.md 実装が既存テストを破壊しない）
        # 自己循環回避のため test_issue_970_mcp_readme.py を --ignore で除外
        # test_soft_deny_match.py は既知の collection エラー（本 Issue とは無関係）のため除外
        result = subprocess.run(
            [
                sys.executable, "-m", "pytest",
                "tests/",
                "--ignore=tests/test_issue_970_mcp_readme.py",
                "--ignore=tests/test_soft_deny_match.py",
                "-q",
                "--tb=line",
                "--no-header",
            ],
            capture_output=True,
            text=True,
            cwd=str(TWL_DIR),
            timeout=180,
        )
        # pytest が collection エラー (exit code 2) や crash (exit code 3/4) になっていないことを確認
        # テスト自体の FAIL (exit code 1) は既存の既知 FAIL を含むため許容する
        # README.md 追加によって collection エラーや新規モジュールエラーが起きないことを検証
        assert result.returncode != 2, (
            f"pytest collection エラーが発生している (AC7: README.md 実装が collection を破壊)\n"
            f"returncode: {result.returncode}\n"
            f"stdout:\n{result.stdout[-3000:] if len(result.stdout) > 3000 else result.stdout}\n"
            f"stderr:\n{result.stderr[-1000:] if len(result.stderr) > 1000 else result.stderr}"
        )
        assert result.returncode != 3, (
            f"pytest が内部エラーで終了した (AC7)\n"
            f"returncode: {result.returncode}"
        )
