"""Tests for Issue #1334: fix(hooks/mcp): twl_validate_commit command-based invocation.

TDD RED phase test stubs.
All tests FAIL before implementation (intentional RED).

AC list:
  AC-1: twl_validate_commit_handler の引数を command: str に変更し、
        内部で git commit -m "..." または --message 引数から commit message 本文を抽出する
        ロジックを追加（実装 option 2）
  AC-2: 引数変更に伴い cli/twl/src/twl/mcp_server/tools.py の inputSchema 更新
        （properties.command の type/required）
  AC-3: .claude/settings.json の hook 設定を "command": "${tool_input.command}" に同期更新
"""

from __future__ import annotations

import inspect
import json
from pathlib import Path

import pytest

WORKTREE_ROOT = Path(__file__).resolve().parent.parent
TOOLS_PY = WORKTREE_ROOT / "src" / "twl" / "mcp_server" / "tools.py"
SETTINGS_JSON = WORKTREE_ROOT.parent.parent / ".claude" / "settings.json"


# ---------------------------------------------------------------------------
# AC-1: twl_validate_commit_handler が command: str パラメータを受け付けること
# ---------------------------------------------------------------------------


class TestAC1ValidateCommitHandlerCommandParam:
    """AC-1: twl_validate_commit_handler の引数が command: str に変更されていること."""

    def test_ac1_handler_accepts_command_param(self):
        # AC: twl_validate_commit_handler が command キーワード引数を受け付けること
        # RED: 現在の signature は message: str なので TypeError が発生する
        from twl.mcp_server.tools import twl_validate_commit_handler

        sig = inspect.signature(twl_validate_commit_handler)
        assert "command" in sig.parameters, (
            "AC-1 未実装: twl_validate_commit_handler シグネチャに 'command' 引数が存在しない。"
            f"現在のパラメータ: {list(sig.parameters.keys())}"
        )

    def test_ac1_handler_does_not_have_message_param(self):
        # AC: 変更後、message 引数が削除されていること（command に置き換え）
        # RED: 現在の signature に message が存在するため FAIL する
        from twl.mcp_server.tools import twl_validate_commit_handler

        sig = inspect.signature(twl_validate_commit_handler)
        assert "message" not in sig.parameters, (
            "AC-1 未実装: twl_validate_commit_handler シグネチャにまだ 'message' 引数が存在する。"
            "command に置き換える必要がある。"
        )

    def test_ac1_handler_extracts_message_from_git_commit_m(self):
        # AC: "git commit -m 'feat: X'" を command に渡すと message="feat: X" を内部抽出すること
        # RED: handler が command パラメータを受け付けないため TypeError または AssertionError で FAIL
        from twl.mcp_server.tools import twl_validate_commit_handler

        result = twl_validate_commit_handler(
            command='git commit -m "feat: add new feature"',
            files=[],
        )
        # ok=True（バリデーション対象なし）かつエラーなく実行できること
        assert isinstance(result, dict), (
            f"AC-1 未実装: 戻り値が dict でない。got={result!r}"
        )
        assert "ok" in result, (
            f"AC-1 未実装: 戻り値に 'ok' キーが存在しない。got={result}"
        )

    def test_ac1_handler_extracts_message_from_git_commit_long_message(self):
        # AC: "git commit --message 'fix: Y'" を command に渡して動作すること
        # RED: handler が command パラメータを受け付けないため FAIL
        from twl.mcp_server.tools import twl_validate_commit_handler

        result = twl_validate_commit_handler(
            command='git commit --message "fix: resolve bug"',
            files=[],
        )
        assert isinstance(result, dict), (
            f"AC-1 未実装: --message 形式で戻り値が dict でない。got={result!r}"
        )

    def test_ac1_source_has_extract_commit_message_logic(self):
        # AC: tools.py に extract_commit_message_from_command 関数または同等の抽出ロジックが存在すること
        # RED: 現在は message パラメータを直接使用するため抽出ロジックが存在しない
        source = TOOLS_PY.read_text(encoding="utf-8")
        has_extract_function = "extract_commit_message_from_command" in source
        has_inline_extraction = (
            "-m " in source
            and "command" in source
            and "def twl_validate_commit_handler" in source
        )
        # extract 関数存在 or handler 内に -m/--message 抽出ロジックがあること
        assert has_extract_function or (
            "twl_validate_commit_handler" in source
            and any(pat in source for pat in [
                'shlex.split',
                'argparse',
                'r"(-m|--message)"',
                "'-m'",
                '"-m"',
                '"--message"',
            ])
        ), (
            "AC-1 未実装: tools.py に commit message 抽出ロジック（extract 関数 or "
            "-m/--message パース）が存在しない"
        )


# ---------------------------------------------------------------------------
# AC-2: MCP tool twl_validate_commit の signature が command パラメータを持つこと
# ---------------------------------------------------------------------------


class TestAC2ValidateCommitMCPToolSignature:
    """AC-2: MCP wrapper の twl_validate_commit 関数シグネチャが command: str に変更されていること."""

    def test_ac2_try_branch_validate_commit_has_command_param(self):
        # AC: try branch (L1274 周辺) の twl_validate_commit 関数シグネチャに command があること
        # RED: 現在のシグネチャは message: str なので FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")

        # try branch は except ImportError より前
        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        validate_commit_pos = try_branch_source.rfind("def twl_validate_commit(")
        assert validate_commit_pos != -1, (
            "AC-2 未実装: try branch に twl_validate_commit 定義が見つからない"
        )

        def_line_end = try_branch_source.find("\n", validate_commit_pos)
        def_line = try_branch_source[validate_commit_pos:def_line_end]

        assert "command" in def_line, (
            f"AC-2 未実装: try branch の twl_validate_commit シグネチャに 'command' が存在しない。"
            f"got={def_line}"
        )

    def test_ac2_try_branch_validate_commit_does_not_have_message_param(self):
        # AC: try branch の twl_validate_commit シグネチャから message が除去されていること
        # RED: 現在の def 行に message が存在するため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        validate_commit_pos = try_branch_source.rfind("def twl_validate_commit(")
        assert validate_commit_pos != -1, (
            "AC-2 未実装: try branch に twl_validate_commit 定義が見つからない"
        )

        def_line_end = try_branch_source.find("\n", validate_commit_pos)
        def_line = try_branch_source[validate_commit_pos:def_line_end]

        assert "message" not in def_line, (
            f"AC-2 未実装: try branch の twl_validate_commit シグネチャにまだ 'message' が存在する。"
            f"got={def_line}"
        )

    def test_ac2_except_importerror_branch_validate_commit_has_command_param(self):
        # AC: except-ImportError branch (L1408 周辺) の twl_validate_commit にも command があること
        # RED: 現在の except-ImportError branch シグネチャも message: str なので FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        except_branch_source = source[except_import_pos:]

        validate_commit_pos = except_branch_source.find("def twl_validate_commit(")
        assert validate_commit_pos != -1, (
            "AC-2 未実装: except-ImportError branch に twl_validate_commit 定義が見つからない"
        )

        def_line_end = except_branch_source.find("\n", validate_commit_pos)
        def_line = except_branch_source[validate_commit_pos:def_line_end]

        assert "command" in def_line, (
            f"AC-2 未実装: except-ImportError branch の twl_validate_commit シグネチャに "
            f"'command' が存在しない。got={def_line}"
        )

    def test_ac2_try_branch_handler_call_passes_command(self):
        # AC: try branch の handler 呼び出しに command=command が渡されていること
        # RED: 現在は message=message を渡しているため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        validate_commit_pos = try_branch_source.rfind("def twl_validate_commit(")
        next_def_pos = try_branch_source.find("\n    @mcp.tool()", validate_commit_pos + 1)
        if next_def_pos == -1:
            next_def_pos = len(try_branch_source)
        body_source = try_branch_source[validate_commit_pos:next_def_pos]

        assert "command=command" in body_source, (
            "AC-2 未実装: try branch の twl_validate_commit_handler 呼び出しに "
            "'command=command' が含まれていない"
        )


# ---------------------------------------------------------------------------
# AC-3: .claude/settings.json の hook が "command" キーを持つこと
# ---------------------------------------------------------------------------


class TestAC3SettingsJsonHookCommand:
    """AC-3: .claude/settings.json の twl_validate_commit hook input が command キーを持つこと."""

    def test_ac3_settings_json_exists(self):
        # 前提: settings.json が存在すること
        assert SETTINGS_JSON.exists(), (
            f"settings.json が存在しない: {SETTINGS_JSON}"
        )

    def test_ac3_validate_commit_hook_has_command_key(self):
        # AC: twl_validate_commit hook の input に "command" キーが存在すること
        # RED: 現在の hook input は {"message": ..., "files": []} なので FAIL する
        data = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))

        pretooluse_hooks = data.get("hooks", {}).get("PreToolUse", [])
        validate_commit_input = None
        for hook_group in pretooluse_hooks:
            for hook in hook_group.get("hooks", []):
                if (
                    hook.get("type") == "mcp_tool"
                    and hook.get("tool") == "twl_validate_commit"
                ):
                    validate_commit_input = hook.get("input", {})
                    break

        assert validate_commit_input is not None, (
            "AC-3 未実装: settings.json に twl_validate_commit の mcp_tool hook が見つからない"
        )
        assert "command" in validate_commit_input, (
            f"AC-3 未実装: twl_validate_commit hook の input に 'command' キーが存在しない。"
            f"現在の input={validate_commit_input}"
        )

    def test_ac3_validate_commit_hook_does_not_have_message_key(self):
        # AC: 変更後、hook input から "message" キーが除去されていること
        # RED: 現在の hook input に "message" が存在するため FAIL する
        data = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))

        pretooluse_hooks = data.get("hooks", {}).get("PreToolUse", [])
        validate_commit_input = None
        for hook_group in pretooluse_hooks:
            for hook in hook_group.get("hooks", []):
                if (
                    hook.get("type") == "mcp_tool"
                    and hook.get("tool") == "twl_validate_commit"
                ):
                    validate_commit_input = hook.get("input", {})
                    break

        assert validate_commit_input is not None, (
            "AC-3 未実装: settings.json に twl_validate_commit の mcp_tool hook が見つからない"
        )
        assert "message" not in validate_commit_input, (
            f"AC-3 未実装: twl_validate_commit hook の input にまだ 'message' キーが存在する。"
            f"'command' キーに置き換える必要がある。現在の input={validate_commit_input}"
        )

    def test_ac3_validate_commit_hook_command_value_references_tool_input(self):
        # AC: command の値が "${tool_input.command}" であること
        # RED: 現在の値は "${tool_input.command}" (message キーの値) なので FAIL する（keyが変わるだけ）
        data = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))

        pretooluse_hooks = data.get("hooks", {}).get("PreToolUse", [])
        validate_commit_input = None
        for hook_group in pretooluse_hooks:
            for hook in hook_group.get("hooks", []):
                if (
                    hook.get("type") == "mcp_tool"
                    and hook.get("tool") == "twl_validate_commit"
                ):
                    validate_commit_input = hook.get("input", {})
                    break

        assert validate_commit_input is not None, (
            "AC-3 未実装: settings.json に twl_validate_commit の mcp_tool hook が見つからない"
        )
        command_value = validate_commit_input.get("command")
        assert command_value == "${tool_input.command}", (
            f"AC-3 未実装: twl_validate_commit hook の command 値が '{{tool_input.command}}' でない。"
            f"got={command_value!r}"
        )
