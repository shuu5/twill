"""Tests for Issue #1335: twl_validate_commit hook が files=[] 固定で実質 no-op (RED フェーズ).

TDD RED フェーズ用テストスタブ。実装前は全テストが FAIL する（意図的 RED）。

AC 一覧:
- AC-1: twl_validate_commit_handler docstring に「files 空リストにより実質 no-op」を明記
- AC-2: tools.py コメントに Claude Code hook 仕様制約と pre-bash-commit-validate.sh 代替を明示
- AC-3: ADR/architecture/ に MCP shadow hook 責務分離を記録
- AC-4: TODO/コメントに「Claude Code hook 仕様拡張時に再検討」を記録
"""

import inspect
import re
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
WORKTREE_ROOT = TWL_DIR.parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
ARCH_DIR = TWL_DIR / "architecture"


# ---------------------------------------------------------------------------
# AC-1: twl_validate_commit_handler docstring に「files 空リストにより実質 no-op」
# ---------------------------------------------------------------------------


class TestAC1ValidateCommitHandlerDocstring:
    """AC-1: twl_validate_commit_handler の docstring に no-op 旨を明記."""

    def test_ac1_docstring_contains_files_empty_no_op(self):
        # AC: twl_validate_commit_handler の docstring に
        #     「files 空リストにより実質 no-op」を明記（現状を spec として記録）
        # RED: docstring 未更新のため fail する
        from twl.mcp_server.tools import twl_validate_commit_handler

        doc = inspect.getdoc(twl_validate_commit_handler) or ""
        assert "no-op" in doc or "no_op" in doc, (
            f"docstring に 'no-op' が見つかりません: {doc!r}"
        )

    def test_ac1_docstring_mentions_files_empty_list(self):
        # AC: docstring が files=[] / 空リストについて言及していること
        # RED: docstring 未更新のため fail する
        from twl.mcp_server.tools import twl_validate_commit_handler

        doc = inspect.getdoc(twl_validate_commit_handler) or ""
        has_empty_list = (
            "files" in doc.lower()
            and ("空" in doc or "empty" in doc.lower() or "[]" in doc)
        )
        assert has_empty_list, (
            f"docstring に 'files 空リスト' に関する記述が見つかりません: {doc!r}"
        )


# ---------------------------------------------------------------------------
# AC-2: tools.py コメントに Claude Code hook 仕様制約を明示
# ---------------------------------------------------------------------------


class TestAC2ToolsPyComment:
    """AC-2: tools.py に hook 仕様制約と代替 bash hook を明示するコメント."""

    def test_ac2_comment_mentions_tool_input_limitation(self):
        # AC: Claude Code hook 仕様で tool_input から staged files が取得不可を明示
        # RED: コメント未追加のため fail する
        assert TOOLS_PY.exists(), f"tools.py not found: {TOOLS_PY}"
        content = TOOLS_PY.read_text(encoding="utf-8")
        has_limitation = (
            "tool_input" in content and "staged" in content
        ) or "hook 仕様" in content or "hook specification" in content.lower()
        assert has_limitation, (
            "tools.py に Claude Code hook 仕様制約（tool_input / staged files 不可）の"
            "コメントが見つかりません"
        )

    def test_ac2_comment_mentions_pre_bash_commit_validate(self):
        # AC: 代替として pre-bash-commit-validate.sh (bash hook) に言及
        # RED: コメント未追加のため fail する
        assert TOOLS_PY.exists(), f"tools.py not found: {TOOLS_PY}"
        content = TOOLS_PY.read_text(encoding="utf-8")
        assert "pre-bash-commit-validate.sh" in content, (
            "tools.py に pre-bash-commit-validate.sh への言及がありません"
        )


# ---------------------------------------------------------------------------
# AC-3: ADR/architecture/ に MCP shadow hook 責務分離を記録
# ---------------------------------------------------------------------------


class TestAC3ArchitectureDocument:
    """AC-3: ADR または architecture/ に MCP shadow hook 責務分離を記録."""

    def test_ac3_architecture_doc_exists_with_shadow_hook_separation(self):
        # AC: MCP=記録専用、bash=block 専用の責務分離を記録したドキュメントが存在
        # RED: ドキュメント未作成のため fail する
        assert ARCH_DIR.exists(), f"architecture/ not found: {ARCH_DIR}"

        # ADR または context doc で shadow hook 責務分離を検索
        candidates = list(ARCH_DIR.rglob("*.md"))
        assert candidates, "architecture/ に markdown ファイルが存在しません"

        keyword_patterns = [
            r"shadow",
            r"MCP.*記録専用|記録専用.*MCP",
            r"bash.*block専用|block専用.*bash",
            r"責務分離",
            r"twl_validate_commit",
        ]
        matched_files = []
        for md_file in candidates:
            text = md_file.read_text(encoding="utf-8")
            if any(re.search(p, text) for p in keyword_patterns):
                matched_files.append(md_file)

        assert matched_files, (
            "architecture/ に MCP shadow hook 責務分離を記録したドキュメントが見つかりません。"
            f"検索対象: {[str(f.relative_to(TWL_DIR)) for f in candidates[:5]]}"
        )

    def test_ac3_shadow_doc_mentions_mcp_record_only(self):
        # AC: MCP=記録専用 の役割が明示されていること
        # RED: ドキュメント未作成のため fail する
        found_text = ""
        if ARCH_DIR.exists():
            for md_file in ARCH_DIR.rglob("*.md"):
                text = md_file.read_text(encoding="utf-8")
                if "twl_validate_commit" in text or "shadow" in text.lower():
                    found_text += text + "\n"

        assert found_text, "twl_validate_commit / shadow に関する architecture doc が見つかりません"
        has_record_role = (
            "記録" in found_text
            or "record" in found_text.lower()
            or "log" in found_text.lower()
        )
        assert has_record_role, (
            "MCP hook の記録専用ロールが architecture doc に明示されていません"
        )


# ---------------------------------------------------------------------------
# AC-4: TODO/コメントに「Claude Code hook 仕様拡張時に再検討」を記録
# ---------------------------------------------------------------------------


class TestAC4FutureConsiderationTodo:
    """AC-4: 将来対応 TODO or コメントに hook 仕様拡張時再検討を記録."""

    def test_ac4_todo_comment_exists_in_tools_py(self):
        # AC: tools.py に「Claude Code hook 仕様拡張時に再検討」または同等の TODO を記録
        # RED: TODO 未追加のため fail する
        # 注意: concurrent.futures の "future" にマッチしないよう、
        #       コメント行（#で始まる行）の中に仕様拡張・再検討の意図を確認する
        assert TOOLS_PY.exists(), f"tools.py not found: {TOOLS_PY}"
        content = TOOLS_PY.read_text(encoding="utf-8")

        comment_lines = [
            line.strip()
            for line in content.splitlines()
            if line.strip().startswith("#")
        ]
        comment_text = "\n".join(comment_lines)

        has_todo = (
            "再検討" in comment_text
            or "revisit" in comment_text.lower()
            or ("hook" in comment_text.lower() and "将来" in comment_text)
            or ("TODO" in comment_text and "hook" in comment_text.lower())
        )

        assert has_todo, (
            "tools.py のコメント行に Claude Code hook 仕様拡張時の再検討 TODO が見つかりません。"
            f"コメント行数: {len(comment_lines)}"
        )
