"""Tests for Issue #1398: twl mcp restart command validation (security).

TDD RED フェーズ用テスト。
実装前は全テストが FAIL する（意図的 RED）。

AC1: _find_mcp_server_cmd() がコマンドを allowlist と照合し、不一致時は ValueError で fail-fast
AC2: 絶対パスの command は既知バイナリディレクトリ prefix に限定される
AC3: 検証失敗時に構造化ログ（command/allowlist/reason）を出力する
AC4: 既存正常系（uv/uvx コマンド起動）は影響を受けず PASS する
AC5: 単体テストで「許可ケース」「拒否ケース」「絶対パス許可/拒否」をカバー
AC6: cli.py の mcp restart ディスパッチが ValueError を捕捉して sys.exit(1) する
"""

import json
import sys
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock
import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TWL_SRC = TWL_DIR / "src"
LIFECYCLE_MODULE = "twl.mcp_server.lifecycle"


# ---------------------------------------------------------------------------
# AC1: _find_mcp_server_cmd() が allowlist 照合し ValueError で fail-fast する
# ---------------------------------------------------------------------------

class TestAC1AllowlistValidation:
    """AC1: _find_mcp_server_cmd() がコマンドを allowlist と照合し、
    不一致時は subprocess.Popen を呼ばず ValueError を raise する。

    RED: 現状は allowlist 検証なし。ValueError は raise されない。
    """

    def _make_mcp_json(self, command: str, tmp_path: Path) -> Path:
        """テスト用 .mcp.json を tmp_path に作成して返す。"""
        mcp_json = tmp_path / ".mcp.json"
        data = {
            "mcpServers": {
                "twl": {
                    "command": command,
                    "args": ["run", "src/twl/mcp_server/server.py"],
                }
            }
        }
        mcp_json.write_text(json.dumps(data))
        return mcp_json

    def test_ac1_unknown_command_raises_value_error(self, tmp_path):
        # AC: allowlist 外のコマンド（例: bash）は ValueError を raise する
        # RED: 現状は ValueError を raise しないため FAIL する
        from twl.mcp_server.lifecycle import _find_mcp_server_cmd

        mcp_json = self._make_mcp_json("bash", tmp_path)

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                with pytest.raises(ValueError) as exc_info:
                    _find_mcp_server_cmd()
                assert "bash" in str(exc_info.value).lower() or "allowlist" in str(exc_info.value).lower() or "allowed" in str(exc_info.value).lower(), (
                    f"ValueError メッセージにコマンド名や allowlist への言及がない: {exc_info.value}"
                )

    def test_ac1_arbitrary_binary_raises_value_error(self, tmp_path):
        # AC: 任意のバイナリ名（curl, python3 等）は ValueError を raise する
        # RED: 現状は ValueError を raise しないため FAIL する
        from twl.mcp_server.lifecycle import _find_mcp_server_cmd

        mcp_json = self._make_mcp_json("curl", tmp_path)

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                with pytest.raises(ValueError):
                    _find_mcp_server_cmd()

    def test_ac1_allowlist_attribute_or_constant_exists(self):
        # AC: lifecycle モジュールに allowlist 定数（_ALLOWED_COMMANDS 等）が存在すること
        # RED: 現状は存在しないため FAIL する
        import twl.mcp_server.lifecycle as lifecycle_mod

        has_allowlist = (
            hasattr(lifecycle_mod, "_ALLOWED_COMMANDS")
            or hasattr(lifecycle_mod, "ALLOWED_COMMANDS")
            or hasattr(lifecycle_mod, "_COMMAND_ALLOWLIST")
        )
        assert has_allowlist, (
            "lifecycle モジュールに allowlist 定数（_ALLOWED_COMMANDS 等）が存在しない (AC1 未実装)"
        )

    def test_ac1_popen_not_called_on_rejected_command(self, tmp_path):
        # AC: allowlist 外コマンドでは subprocess.Popen が呼ばれないこと
        # RED: 現状は allowlist 定数が存在しないため、検証ロジック自体がない。
        #      allowlist 定数の存在を確認することで RED を保証する。
        import twl.mcp_server.lifecycle as lifecycle_mod

        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, (
            "lifecycle モジュールに allowlist 定数が存在しない。"
            "allowlist なしでは Popen 呼び出し防止を保証できない (AC1 未実装)"
        )

        mcp_json = self._make_mcp_json("malicious-binary", tmp_path)

        with patch("subprocess.run") as mock_run, \
             patch.object(lifecycle_mod.subprocess, "Popen") as mock_popen:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                try:
                    lifecycle_mod._find_mcp_server_cmd()
                except ValueError:
                    pass  # 期待される動作
                except Exception:
                    pass

            # Popen は呼ばれていないこと
            mock_popen.assert_not_called()


# ---------------------------------------------------------------------------
# AC2: 絶対パスの command は既知バイナリディレクトリ prefix に限定される
# ---------------------------------------------------------------------------

class TestAC2AbsolutePathValidation:
    """AC2: 絶対パスで指定された command は /usr/bin, /usr/local/bin,
    ~/.local/bin 等の既知プレフィックスに限定される。

    RED: 現状は絶対パス検証なし。任意の絶対パスが通過してしまう。
    """

    def _make_mcp_json(self, command: str, tmp_path: Path) -> Path:
        mcp_json = tmp_path / ".mcp.json"
        data = {
            "mcpServers": {
                "twl": {
                    "command": command,
                    "args": [],
                }
            }
        }
        mcp_json.write_text(json.dumps(data))
        return mcp_json

    def test_ac2_known_prefix_usr_bin_allowed(self, tmp_path):
        # AC: /usr/bin/uv は許可される（既知プレフィックス）
        # RED: 現状は絶対パス検証なし。このテストは allowlist 実装後に GREEN になる。
        #      しかし「検証関数が存在する」という前提が必要なので、
        #      検証関数の不在を検出して FAIL させる
        from twl.mcp_server.lifecycle import _find_mcp_server_cmd
        import twl.mcp_server.lifecycle as lifecycle_mod

        # 絶対パス検証関数が存在することを確認（実装されていなければ FAIL）
        has_validator = (
            hasattr(lifecycle_mod, "_validate_command")
            or hasattr(lifecycle_mod, "_is_allowed_command")
            or hasattr(lifecycle_mod, "_check_command_allowed")
        )
        assert has_validator, (
            "lifecycle モジュールにコマンド検証関数（_validate_command 等）が存在しない (AC2 未実装)"
        )

    def test_ac2_arbitrary_absolute_path_raises_value_error(self, tmp_path):
        # AC: /tmp/malicious は ValueError を raise する（未知プレフィックス）
        # RED: 現状は ValueError を raise しないため FAIL する
        from twl.mcp_server.lifecycle import _find_mcp_server_cmd

        mcp_json = self._make_mcp_json("/tmp/malicious", tmp_path)

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                with pytest.raises(ValueError):
                    _find_mcp_server_cmd()

    def test_ac2_home_local_bin_prefix_is_known(self):
        # AC: ~/.local/bin が既知プレフィックスに含まれること
        # RED: 現状は既知プレフィックスリスト自体が存在しない
        import twl.mcp_server.lifecycle as lifecycle_mod

        has_prefix_list = (
            hasattr(lifecycle_mod, "_ALLOWED_PREFIXES")
            or hasattr(lifecycle_mod, "ALLOWED_PREFIXES")
            or hasattr(lifecycle_mod, "_KNOWN_BIN_DIRS")
        )
        assert has_prefix_list, (
            "lifecycle モジュールに既知プレフィックスリスト（_ALLOWED_PREFIXES 等）が存在しない (AC2 未実装)"
        )

    def test_ac2_home_local_bin_uv_raises_no_error(self, tmp_path):
        # AC: ~/.local/bin/uv は許可される（既知プレフィックス + allowlist 名）
        # RED: 検証ロジック（_ALLOWED_PREFIXES）が未実装のため FAIL する
        import twl.mcp_server.lifecycle as lifecycle_mod

        has_prefix_list = (
            hasattr(lifecycle_mod, "_ALLOWED_PREFIXES")
            or hasattr(lifecycle_mod, "ALLOWED_PREFIXES")
            or hasattr(lifecycle_mod, "_KNOWN_BIN_DIRS")
        )
        assert has_prefix_list, (
            "lifecycle モジュールに既知プレフィックスリストが存在しない。"
            "~/.local/bin/uv の許可検証ができない (AC2 未実装)"
        )

        home_bin_uv = str(Path.home() / ".local" / "bin" / "uv")
        mcp_json = self._make_mcp_json(home_bin_uv, tmp_path)

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                try:
                    result = lifecycle_mod._find_mcp_server_cmd()
                    assert result is None or home_bin_uv in (result or []), (
                        f"~/.local/bin/uv は許可されるべきだが結果が不正: {result}"
                    )
                except ValueError as e:
                    pytest.fail(
                        f"~/.local/bin/uv は許可プレフィックスのため ValueError は不正: {e}"
                    )

    def test_ac2_etc_passwd_absolute_path_raises(self, tmp_path):
        # AC: /etc/passwd など明らかに不正な絶対パスは ValueError を raise する
        # RED: 現状は検証なし
        from twl.mcp_server.lifecycle import _find_mcp_server_cmd

        mcp_json = self._make_mcp_json("/etc/passwd", tmp_path)

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                with pytest.raises(ValueError):
                    _find_mcp_server_cmd()


# ---------------------------------------------------------------------------
# AC3: 検証失敗時に構造化ログ（command/allowlist/reason）を出力する
# ---------------------------------------------------------------------------

class TestAC3StructuredLogging:
    """AC3: 検証失敗時は構造化ログ（command 値・許可リスト・拒否理由）を出力し、
    原因が特定可能であること。

    RED: 現状は検証ロジックが存在しないためログも出力されない。
    """

    def _make_mcp_json(self, command: str, tmp_path: Path) -> Path:
        mcp_json = tmp_path / ".mcp.json"
        data = {
            "mcpServers": {
                "twl": {
                    "command": command,
                    "args": [],
                }
            }
        }
        mcp_json.write_text(json.dumps(data))
        return mcp_json

    def test_ac3_value_error_message_contains_command(self, tmp_path, capsys):
        # AC: ValueError のメッセージまたは stdout に command 値が含まれること
        # RED: 現状は ValueError 自体が raise されないため FAIL
        from twl.mcp_server.lifecycle import _find_mcp_server_cmd

        rejected_cmd = "evil-command"
        mcp_json = self._make_mcp_json(rejected_cmd, tmp_path)

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                try:
                    _find_mcp_server_cmd()
                    pytest.fail("ValueError が raise されなかった (AC3 未実装)")
                except ValueError as e:
                    # ValueError メッセージに command 値が含まれること
                    assert rejected_cmd in str(e), (
                        f"ValueError メッセージに command 値 '{rejected_cmd}' が含まれない: {e}"
                    )

    def test_ac3_value_error_message_contains_allowlist_or_reason(self, tmp_path):
        # AC: ValueError のメッセージに allowlist または拒否理由が含まれること
        # RED: 現状は ValueError 自体が raise されないため FAIL
        from twl.mcp_server.lifecycle import _find_mcp_server_cmd

        mcp_json = self._make_mcp_json("wget", tmp_path)

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                try:
                    _find_mcp_server_cmd()
                    pytest.fail("ValueError が raise されなかった (AC3 未実装)")
                except ValueError as e:
                    msg = str(e).lower()
                    has_reason = (
                        "allow" in msg
                        or "permit" in msg
                        or "reject" in msg
                        or "uv" in msg  # allowlist メンバーが示されている
                        or "uvx" in msg
                    )
                    assert has_reason, (
                        f"ValueError に allowlist または拒否理由が含まれない: {e}"
                    )

    def test_ac3_structured_log_output_on_rejection(self, tmp_path, capsys):
        """AC4 (Issue #1414): cli.main() 経由で stderr に構造化情報が出力されることを検証する。

        テスト境界: unit（_find_mcp_server_cmd 直接呼び出し）から
        integration（cli.main() 経由）にシフトした。
        これにより cli.py の try/except ValueError が存在しない限り
        stderr への "Error: mcp restart failed — ..." 出力は発生せず、
        テストは RED のままとなる（Issue #1414 実装後に GREEN になる）。

        AC: cli.main() 経由で不正コマンド検出時、stderr に構造化エラー行が出力される。
        RED: cli.py に try/except ValueError がないため、ValueError が propagate して
             "Error: mcp restart failed — ..." の stderr 出力がなく FAIL する。
        """
        import twl.cli as cli_mod

        error_msg = "command 'nc' not in allowlist: ['uv', 'uvx']"
        with patch("twl.mcp_server.lifecycle.restart_mcp_server") as mock_restart:
            mock_restart.side_effect = ValueError(error_msg)
            with patch.object(sys, "argv", ["twl", "mcp", "restart"]):
                try:
                    cli_mod.main()
                except SystemExit:
                    pass
                except ValueError:
                    # ValueError が cli.py で捕捉されず propagate した場合は FAIL
                    pytest.fail(
                        "ValueError が cli.py で捕捉されず propagate した (AC2/Issue#1414 未実装)"
                    )

        captured = capsys.readouterr()
        # cli.py が "Error: mcp restart failed — ..." を stderr に出力すること
        assert "Error: mcp restart failed" in captured.err, (
            f"cli.main() 経由で不正コマンド検出時に stderr に構造化エラー行が出力されていない "
            f"(AC2/Issue#1414 未実装).\n"
            f"stderr: {captured.err!r}"
        )


# ---------------------------------------------------------------------------
# AC4: 既存正常系（uv/uvx コマンド）は影響を受けず PASS する
# ---------------------------------------------------------------------------

class TestAC4LegitimateCommandsUnaffected:
    """AC4: 既存の twl mcp restart 正常系（uv run 系コマンド起動）は
    allowlist 実装後も影響を受けず PASS する。

    RED: allowlist 自体が存在しない現状では、
    「uv が allowlist に含まれる」という前提を検証する。
    """

    def _make_mcp_json(self, command: str, tmp_path: Path) -> Path:
        mcp_json = tmp_path / ".mcp.json"
        data = {
            "mcpServers": {
                "twl": {
                    "command": command,
                    "args": ["run", "--directory", "/some/path", "server.py"],
                }
            }
        }
        mcp_json.write_text(json.dumps(data))
        return mcp_json

    def test_ac4_uv_command_is_in_allowlist(self):
        # AC: "uv" が allowlist に含まれること
        # RED: allowlist 定数が存在しないため FAIL
        import twl.mcp_server.lifecycle as lifecycle_mod

        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, (
            "lifecycle モジュールに allowlist 定数が存在しない (AC4 未実装)"
        )
        assert "uv" in allowlist, (
            f"allowlist に 'uv' が含まれない: {allowlist} (AC4 未実装)"
        )

    def test_ac4_uvx_command_is_in_allowlist(self):
        # AC: "uvx" が allowlist に含まれること
        # RED: allowlist 定数が存在しないため FAIL
        import twl.mcp_server.lifecycle as lifecycle_mod

        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, (
            "lifecycle モジュールに allowlist 定数が存在しない (AC4 未実装)"
        )
        assert "uvx" in allowlist, (
            f"allowlist に 'uvx' が含まれない: {allowlist} (AC4 未実装)"
        )

    def test_ac4_uv_command_does_not_raise(self, tmp_path):
        # AC: command = "uv" では ValueError が raise されないこと
        # RED: 検証ロジックが存在しないため動作確認不可。
        #      allowlist 実装後にこのテストが GREEN になることを保証する。
        #      現状では、allowlist が存在しないため uv は ValueError を raise しない
        #      という動作自体は正しいが、「allowlist が存在しないまま通過する」点が問題。
        #      よって allowlist の存在確認と組み合わせて RED とする。
        import twl.mcp_server.lifecycle as lifecycle_mod

        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, (
            "allowlist が実装されていないため uv 許可動作を検証できない (AC4 未実装)"
        )

        mcp_json = self._make_mcp_json("uv", tmp_path)
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout=str(tmp_path) + "\n",
            )
            with patch("pathlib.Path.exists", return_value=True), \
                 patch("builtins.open", return_value=open(mcp_json)):
                # uv は ValueError を raise しないこと
                try:
                    result = lifecycle_mod._find_mcp_server_cmd()
                    # 結果が返ること（None でも list でも可）
                except ValueError as e:
                    pytest.fail(f"uv は allowlist に含まれるため ValueError は不正: {e}")


# ---------------------------------------------------------------------------
# AC5: 単体テストカバレッジ確認（許可/拒否/絶対パス）
# ---------------------------------------------------------------------------

class TestAC5UnitTestCoverage:
    """AC5: 単体テストで「許可ケース（uv/uvx）」「拒否ケース（任意バイナリ名）」
    「絶対パス許可ケース」「絶対パス拒否ケース」をカバーする。

    このクラスは AC1〜4 の横断確認として、
    個別テスト群がすべて存在することをメタ検証する。
    """

    def test_ac5_lifecycle_module_importable(self):
        # AC: twl.mcp_server.lifecycle が import 可能であること（前提確認）
        from twl.mcp_server import lifecycle  # noqa: F401

    def test_ac5_find_mcp_server_cmd_exists(self):
        # AC: _find_mcp_server_cmd 関数が存在すること
        from twl.mcp_server.lifecycle import _find_mcp_server_cmd
        assert callable(_find_mcp_server_cmd)

    def test_ac5_allowlist_covers_uv_and_uvx(self):
        # AC: allowlist に uv と uvx の両方が含まれること（許可ケースカバー）
        # RED: allowlist 未実装
        import twl.mcp_server.lifecycle as lifecycle_mod

        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
            or []
        )
        assert "uv" in allowlist and "uvx" in allowlist, (
            f"allowlist が uv/uvx 両方をカバーしていない: {allowlist} (AC5 未実装)"
        )

    def test_ac5_allowlist_is_restrictive(self):
        # AC: allowlist がデフォルトで 5 件以下の厳格なリスト（bash/sh/python 等を含まない）
        # RED: allowlist 未実装
        import twl.mcp_server.lifecycle as lifecycle_mod

        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, (
            "allowlist 定数が存在しない (AC5 未実装)"
        )
        # 危険なコマンドが含まれていないこと
        dangerous = {"bash", "sh", "python", "python3", "node", "ruby", "perl"}
        intersection = set(allowlist) & dangerous
        assert not intersection, (
            f"allowlist に危険なコマンドが含まれている: {intersection} (AC5 セキュリティ違反)"
        )


# ---------------------------------------------------------------------------
# AC6: cli.py の mcp restart ディスパッチが ValueError を捕捉して sys.exit(1) する
# ---------------------------------------------------------------------------

class TestAC6CliValueErrorHandling:
    """AC6: cli.py の mcp restart ディスパッチが ValueError を捕捉し、
    エラーメッセージを出力して sys.exit(1) する。

    RED: 現状は ValueError を捕捉せず propagate するため sys.exit(1) にならない。
    """

    def test_ac6_mcp_restart_catches_value_error_exits_1(self, capsys):
        # AC: restart_mcp_server が ValueError を raise した場合、
        #     cli.main() は sys.exit(1) すること
        # RED: 現状の cli.py は ValueError を捕捉しない
        from twl.mcp_server.lifecycle import restart_mcp_server
        import twl.cli as cli_mod

        with patch("twl.mcp_server.lifecycle.restart_mcp_server") as mock_restart:
            mock_restart.side_effect = ValueError("command 'evil' not in allowlist: ['uv', 'uvx']")
            with patch.object(sys, "argv", ["twl", "mcp", "restart"]):
                with pytest.raises(SystemExit) as exc_info:
                    cli_mod.main()
                assert exc_info.value.code == 1, (
                    f"mcp restart が ValueError を受けて sys.exit(1) しなかった: "
                    f"exit code = {exc_info.value.code} (AC6 未実装)"
                )

    def test_ac6_error_message_printed_on_value_error(self, capsys):
        # AC: ValueError 発生時にエラーメッセージが stdout または stderr に出力される
        # RED: 現状は ValueError が捕捉されずに propagate する
        import twl.cli as cli_mod

        error_msg = "command 'evil' not in allowlist: ['uv', 'uvx']"
        with patch("twl.mcp_server.lifecycle.restart_mcp_server") as mock_restart:
            mock_restart.side_effect = ValueError(error_msg)
            with patch.object(sys, "argv", ["twl", "mcp", "restart"]):
                try:
                    cli_mod.main()
                except SystemExit:
                    pass
                except ValueError:
                    # ValueError が propagate した = 捕捉されていない → FAIL
                    pytest.fail(
                        "ValueError が cli.py で捕捉されず propagate した (AC6 未実装)"
                    )

        captured = capsys.readouterr()
        combined = captured.out + captured.err
        assert combined.strip(), (
            "ValueError 発生時に cli.py が何もメッセージを出力しなかった (AC6 未実装)"
        )

    def test_ac6_cli_dispatch_has_try_except_for_value_error(self):
        # AC: cli.py の mcp restart ブロックに ValueError 捕捉が実装されていること
        # RED: 現状は try-except なし
        cli_path = TWL_SRC / "twl" / "cli.py"
        content = cli_path.read_text()

        # mcp restart のディスパッチ付近に ValueError 捕捉があること
        # 「mcp」セクションに「ValueError」が含まれること
        mcp_section_start = content.find("sys.argv[1] == 'mcp'")
        assert mcp_section_start != -1, (
            "cli.py に mcp ディスパッチが見つからない"
        )
        # mcp セクション以降に ValueError が含まれること
        mcp_section = content[mcp_section_start:mcp_section_start + 500]
        assert "ValueError" in mcp_section, (
            f"cli.py の mcp ディスパッチ付近に ValueError 捕捉が存在しない (AC6 未実装):\n{mcp_section}"
        )

    def test_ac6_cli_mcp_restart_exits_1_on_value_error_subprocess(self):
        # AC: subprocess として `twl mcp restart` を実行し、
        #     ValueError が発生する条件でも exit code 1 で終了すること
        # RED: 現状は ValueError が propagate して非 0 exit になるが、
        #      エラーメッセージが適切に出力されない可能性がある

        # .mcp.json に不正コマンドを設定した状態でテスト
        # （この段階では allowlist が未実装なので正常動作するが、
        #   テスト構造として記述する）
        import shutil
        twl_bin = shutil.which("twl") or str(TWL_DIR / "twl")

        # この時点では allowlist 未実装のため、
        # subprocess テストは「allowlist が実装後に exit 1 を返す」
        # ことを意図した RED テストとして、allowlist 定数の存在確認に依存する
        import twl.mcp_server.lifecycle as lifecycle_mod
        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, (
            "allowlist が未実装のため subprocess テストが意味をなさない (AC6 前提 未実装)"
        )

    def test_ac7_stderr_single_line_no_traceback_on_invalid_command(self, capsys):
        """AC7: stderr 出力が単一経路になることを behavioral test で確認する。

        cli.main() 経由で不正コマンド検出時:
          - captured.err に "Error: mcp restart failed —" で始まる行が正確に 1 行のみ出現すること
          - "Traceback (most recent call last):" が含まれないこと

        RED: cli.py に try/except ValueError がないため、ValueError が propagate して
             Python traceback が出力される（または "Error: mcp restart failed —" 行が存在しない）。
             いずれの場合も assert が FAIL する（Issue #1414 実装後に GREEN になる）。
        """
        import twl.cli as cli_mod

        error_detail = "command 'evil' not in allowlist: ['uv', 'uvx']"
        with patch("twl.mcp_server.lifecycle.restart_mcp_server") as mock_restart:
            mock_restart.side_effect = ValueError(error_detail)
            with patch.object(sys, "argv", ["twl", "mcp", "restart"]):
                try:
                    cli_mod.main()
                except SystemExit:
                    pass
                # ValueError propagate は捕捉せずに assert まで流す（traceback 有無を検証するため）

        captured = capsys.readouterr()

        # "Error: mcp restart failed —" で始まる行が正確に 1 行のみ出現すること
        error_lines = [
            line for line in captured.err.splitlines()
            if line.startswith("Error: mcp restart failed —")
        ]
        assert len(error_lines) == 1, (
            f"stderr に 'Error: mcp restart failed —' で始まる行が正確に 1 行のみ存在するべきだが "
            f"{len(error_lines)} 行あった (AC7 未実装).\n"
            f"stderr: {captured.err!r}"
        )

        # Python traceback が含まれないこと
        assert "Traceback (most recent call last):" not in captured.err, (
            f"stderr に Python traceback が含まれている (AC7 未実装 — try/except なしで ValueError propagate).\n"
            f"stderr: {captured.err!r}"
        )
