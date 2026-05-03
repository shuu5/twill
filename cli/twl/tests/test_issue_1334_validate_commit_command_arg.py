"""Tests for Issue #1334: twl_validate_commit_handler の引数を command: str に変更 (RED フェーズ).

TDD RED フェーズ用テストスタブ。
実装前は全テストが FAIL する（意図的 RED）。

AC 一覧:
- AC-1: twl_validate_commit_handler の引数を command: str に変更し、
        git commit -m / --message からメッセージを抽出するロジックを追加
- AC-2: cli/twl/src/twl/mcp_server/tools.py の inputSchema を
        properties.command: {type: str, required: true} に更新
- AC-3: .claude/settings.json の twl_validate_commit hook を
        "command": "${tool_input.command}" に同期更新
- AC-4: bats regression テストは plugins/twl/tests/bats/hooks/
        twl-validate-commit-message-extract.bats で管理（本ファイルは Python 分）
- AC-5: 既存 bash hook pre-bash-commit-validate.sh との責務分離を
        README/ADR に明記（MCP shadow = 記録専用、bash = block 専用）
"""

import inspect
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = TWL_DIR.parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
SETTINGS_JSON = REPO_ROOT / ".claude" / "settings.json"


# ---------------------------------------------------------------------------
# AC-1: twl_validate_commit_handler の引数が command: str に変更されていること
# ---------------------------------------------------------------------------

class TestAC1CommandArgSignature:
    """AC-1: twl_validate_commit_handler(command: str, ...) に引数が変更されていること."""

    def test_ac1_handler_has_command_arg(self):
        # AC: twl_validate_commit_handler の第1引数が command: str であること
        # RED: 現在は message: str, files: list[str] であり command がないため FAIL
        from twl.mcp_server.tools import twl_validate_commit_handler

        sig = inspect.signature(twl_validate_commit_handler)
        params = sig.parameters

        assert "command" in params, (
            "twl_validate_commit_handler に command 引数がない (AC-1 未実装): "
            f"現在の引数: {list(params.keys())}"
        )

    def test_ac1_handler_does_not_have_message_arg(self):
        # AC: 変更後は message 引数が独立パラメータとして存在しないこと
        #     （command から内部で抽出するため）
        # RED: 現在は message 引数が存在するため FAIL
        from twl.mcp_server.tools import twl_validate_commit_handler

        sig = inspect.signature(twl_validate_commit_handler)
        params = sig.parameters

        assert "message" not in params, (
            "twl_validate_commit_handler に message 引数がまだ残っている (AC-1 未実装): "
            "command: str に変更後は message は内部変数として扱うこと"
        )

    def test_ac1_handler_does_not_have_files_arg(self):
        # AC: 変更後は files 引数が独立パラメータとして存在しないこと
        #     （command から内部で抽出するため）
        # RED: 現在は files 引数が存在するため FAIL
        from twl.mcp_server.tools import twl_validate_commit_handler

        sig = inspect.signature(twl_validate_commit_handler)
        params = sig.parameters

        assert "files" not in params, (
            "twl_validate_commit_handler に files 引数がまだ残っている (AC-1 未実装): "
            "command: str に変更後は files は内部変数として扱うこと"
        )

    def test_ac1_extract_message_from_short_flag(self):
        # AC: command = 'git commit -m "feat: X"' のとき message="feat: X" が抽出されること
        # RED: 現在の handler は message/files 引数を受け取るため、
        #      command 引数で呼び出すと TypeError になり FAIL
        from twl.mcp_server.tools import twl_validate_commit_handler

        # command: str を渡す新しいインターフェースで呼び出す
        result = twl_validate_commit_handler(command='git commit -m "feat: X"')

        assert isinstance(result, dict), (
            f"戻り値が dict でない: {type(result)} (AC-1 未実装)"
        )
        # 抽出されたメッセージが結果に含まれること（extracted_message フィールド等）
        # 実装詳細によって変わりうるが、少なくとも ok フィールドが返ること
        assert "ok" in result, (
            f"結果に ok フィールドがない: {result} (AC-1 未実装)"
        )

    def test_ac1_extract_message_from_long_flag(self):
        # AC: command = 'git commit --message "fix: Y"' のとき message="fix: Y" が抽出されること
        # RED: 現在の handler は command 引数を受け取らないため TypeError で FAIL
        from twl.mcp_server.tools import twl_validate_commit_handler

        result = twl_validate_commit_handler(command='git commit --message "fix: Y"')

        assert isinstance(result, dict), (
            f"戻り値が dict でない: {type(result)} (AC-1 未実装)"
        )
        assert "ok" in result, (
            f"結果に ok フィールドがない: {result} (AC-1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC-2: tools.py の MCP tool 定義（inputSchema）が command: str に更新されていること
# ---------------------------------------------------------------------------

class TestAC2InputSchemaUpdated:
    """AC-2: tools.py の twl_validate_commit MCP tool 定義が command: str を受け取ること."""

    def test_ac2_mcp_tool_accepts_command_arg(self):
        # AC: @mcp.tool() デコレータ付き twl_validate_commit が command: str 引数を受け取ること
        # RED: 現在は message, files 引数のため、command だと schema mismatch で FAIL
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_validate_commit", None)
        assert fn is not None, (
            "tools.twl_validate_commit が存在しない (AC-2 前提条件失敗)"
        )

        sig = inspect.signature(fn)
        params = sig.parameters

        assert "command" in params, (
            f"twl_validate_commit MCP tool に command 引数がない (AC-2 未実装): "
            f"現在の引数: {list(params.keys())}"
        )

    def test_ac2_mcp_tool_does_not_accept_message_arg(self):
        # AC: 変更後の twl_validate_commit MCP tool が message 引数を持たないこと
        # RED: 現在は message 引数があるため FAIL
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_validate_commit", None)
        assert fn is not None, (
            "tools.twl_validate_commit が存在しない (AC-2 前提条件失敗)"
        )

        sig = inspect.signature(fn)
        params = sig.parameters

        assert "message" not in params, (
            "twl_validate_commit MCP tool に message 引数がまだ残っている (AC-2 未実装)"
        )

    def test_ac2_mcp_tool_does_not_accept_files_arg(self):
        # AC: 変更後の twl_validate_commit MCP tool が files 引数を持たないこと
        # RED: 現在は files 引数があるため FAIL
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_validate_commit", None)
        assert fn is not None, (
            "tools.twl_validate_commit が存在しない (AC-2 前提条件失敗)"
        )

        sig = inspect.signature(fn)
        params = sig.parameters

        assert "files" not in params, (
            "twl_validate_commit MCP tool に files 引数がまだ残っている (AC-2 未実装)"
        )

    def test_ac2_fallback_mcp_tool_definition_also_updated(self):
        # AC: fallback (try/except ImportError 後の) 定義も command 引数に更新されていること
        # RED: tools.py の fallback 定義（line 1408 付近）も確認
        content = TOOLS_PY.read_text(encoding="utf-8")

        # "def twl_validate_commit(" の全出現箇所を取得
        import re
        matches = re.findall(
            r"def twl_validate_commit\(([^)]+)\)",
            content,
            re.DOTALL,
        )
        assert len(matches) >= 1, (
            "tools.py に twl_validate_commit 定義が見つからない (AC-2 前提条件失敗)"
        )

        for i, args_str in enumerate(matches):
            assert "command" in args_str, (
                f"twl_validate_commit の定義 #{i+1} に command 引数がない (AC-2 未実装): "
                f"現在の引数: {args_str.strip()}"
            )
            assert "message" not in args_str, (
                f"twl_validate_commit の定義 #{i+1} に message 引数がまだある (AC-2 未実装)"
            )


# ---------------------------------------------------------------------------
# AC-3: settings.json の twl_validate_commit hook input が command に更新されていること
# ---------------------------------------------------------------------------

class TestAC3SettingsJsonUpdated:
    """AC-3: .claude/settings.json の twl_validate_commit hook が command: str に更新されていること."""

    def test_ac3_settings_json_hook_has_command_field(self):
        # AC: settings.json の twl_validate_commit hook input に command フィールドがあること
        # RED: 現在は message: "${tool_input.command}", files: [] となっているため
        #      command フィールドがなく FAIL
        import json

        assert SETTINGS_JSON.exists(), f"settings.json が存在しない: {SETTINGS_JSON}"
        data = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))

        hook_input = None
        for hooks in data.get("hooks", {}).values():
            for hook_group in hooks:
                for h in hook_group.get("hooks", []):
                    if h.get("tool") == "twl_validate_commit":
                        hook_input = h.get("input", {})
                        break

        assert hook_input is not None, (
            "settings.json に twl_validate_commit hook が見つからない (AC-3 前提条件失敗)"
        )
        assert "command" in hook_input, (
            f"settings.json の twl_validate_commit hook input に command フィールドがない (AC-3 未実装): "
            f"現在の input: {hook_input}"
        )

    def test_ac3_settings_json_hook_command_value(self):
        # AC: command フィールドの値が "${tool_input.command}" であること
        # RED: 現在は message フィールドに "${tool_input.command}" が設定されているため
        #      command フィールドが存在せず FAIL
        import json

        assert SETTINGS_JSON.exists(), f"settings.json が存在しない: {SETTINGS_JSON}"
        data = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))

        hook_input = None
        for hooks in data.get("hooks", {}).values():
            for hook_group in hooks:
                for h in hook_group.get("hooks", []):
                    if h.get("tool") == "twl_validate_commit":
                        hook_input = h.get("input", {})
                        break

        assert hook_input is not None, (
            "settings.json に twl_validate_commit hook が見つからない (AC-3 前提条件失敗)"
        )
        command_value = hook_input.get("command", "MISSING")
        assert command_value == "${tool_input.command}", (
            f"settings.json の twl_validate_commit hook の command 値が期待値と異なる (AC-3 未実装): "
            f"期待: '${{tool_input.command}}', 実際: '{command_value}'"
        )

    def test_ac3_settings_json_hook_does_not_have_message_field(self):
        # AC: 変更後の hook input に message フィールドが存在しないこと
        # RED: 現在は message フィールドがあるため、削除されていない場合に FAIL
        import json

        assert SETTINGS_JSON.exists(), f"settings.json が存在しない: {SETTINGS_JSON}"
        data = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))

        hook_input = None
        for hooks in data.get("hooks", {}).values():
            for hook_group in hooks:
                for h in hook_group.get("hooks", []):
                    if h.get("tool") == "twl_validate_commit":
                        hook_input = h.get("input", {})
                        break

        assert hook_input is not None, (
            "settings.json に twl_validate_commit hook が見つからない (AC-3 前提条件失敗)"
        )
        assert "message" not in hook_input, (
            f"settings.json の twl_validate_commit hook input に message フィールドが残っている (AC-3 未実装): "
            f"現在の input: {hook_input}"
        )

    def test_ac3_settings_json_hook_does_not_have_files_field(self):
        # AC: 変更後の hook input に files フィールドが存在しないこと
        # RED: 現在は files: [] フィールドがあるため FAIL
        import json

        assert SETTINGS_JSON.exists(), f"settings.json が存在しない: {SETTINGS_JSON}"
        data = json.loads(SETTINGS_JSON.read_text(encoding="utf-8"))

        hook_input = None
        for hooks in data.get("hooks", {}).values():
            for hook_group in hooks:
                for h in hook_group.get("hooks", []):
                    if h.get("tool") == "twl_validate_commit":
                        hook_input = h.get("input", {})
                        break

        assert hook_input is not None, (
            "settings.json に twl_validate_commit hook が見つからない (AC-3 前提条件失敗)"
        )
        assert "files" not in hook_input, (
            f"settings.json の twl_validate_commit hook input に files フィールドが残っている (AC-3 未実装): "
            f"現在の input: {hook_input}"
        )


# ---------------------------------------------------------------------------
# AC-5: pre-bash-commit-validate.sh が存在し、责務分離に関する記述が ADR/README にあること
# ---------------------------------------------------------------------------

class TestAC5ResponsibilitySeparationDocumented:
    """AC-5: MCP shadow = 記録専用、bash = block 専用 の責務分離が文書化されていること."""

    def test_ac5_pre_bash_commit_validate_sh_still_exists(self):
        # AC: 既存 bash hook pre-bash-commit-validate.sh が削除されていないこと
        # RED: ファイルが削除された場合のみ FAIL（現在は存在するため PASS になりうる）
        #      ただし責務分離ドキュメントが存在するか確認するのがメインの AC-5 テスト
        hook = REPO_ROOT / "plugins" / "twl" / "scripts" / "hooks" / "pre-bash-commit-validate.sh"
        assert hook.exists(), (
            f"pre-bash-commit-validate.sh が消滅している (AC-5 破壊): {hook}"
        )

    def test_ac5_responsibility_separation_documented(self):
        # AC: MCP shadow = 記録専用、bash = block 専用 の責務分離が
        #     ADR または README に明記されていること
        # RED: 文書が存在しないか、責務分離の記述がないため FAIL
        #
        # 検索対象:
        #   1. plugins/twl/scripts/hooks/pre-bash-commit-validate.sh のコメント
        #   2. docs/adr/ 配下の ADR ファイル
        #   3. plugins/twl/README.md や類似ファイル
        raise NotImplementedError(
            "AC-5 未実装: MCP shadow (記録専用) と bash hook (block 専用) の責務分離が "
            "ADR または README に明記されていないため FAIL。"
            "実装時は以下のいずれかに記述すること:\n"
            "  - plugins/twl/scripts/hooks/pre-bash-commit-validate.sh のコメント\n"
            "  - docs/adr/ADR-NNN-commit-validation-responsibilities.md\n"
            "  - plugins/twl/README.md の hooks セクション"
        )
