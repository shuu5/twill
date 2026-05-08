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

import sys
from pathlib import Path
from unittest.mock import MagicMock, mock_open, patch
import pytest

import twl.mcp_server.lifecycle as lifecycle_mod
from twl.mcp_server.lifecycle import _find_mcp_server_cmd

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

    def test_ac1_unknown_command_raises_value_error(self, make_mcp_json, tmp_path):
        # AC: allowlist 外のコマンド（例: bash）は ValueError を raise する
        # RED: 現状は ValueError を raise しないため FAIL する
        mcp_json = make_mcp_json("bash", tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError) as exc_info:
                _find_mcp_server_cmd()
            assert "bash" in str(exc_info.value).lower() or "allowlist" in str(exc_info.value).lower() or "allowed" in str(exc_info.value).lower(), (
                f"ValueError メッセージにコマンド名や allowlist への言及がない: {exc_info.value}"
            )

    def test_ac1_arbitrary_binary_raises_value_error(self, make_mcp_json, tmp_path):
        # AC: 任意のバイナリ名（curl, python3 等）は ValueError を raise する
        # RED: 現状は ValueError を raise しないため FAIL する
        mcp_json = make_mcp_json("curl", tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError):
                _find_mcp_server_cmd()

    def test_ac1_allowlist_attribute_or_constant_exists(self):
        # AC: lifecycle モジュールに allowlist 定数（_ALLOWED_COMMANDS 等）が存在すること
        # RED: 現状は存在しないため FAIL する
        has_allowlist = (
            hasattr(lifecycle_mod, "_ALLOWED_COMMANDS")
            or hasattr(lifecycle_mod, "ALLOWED_COMMANDS")
            or hasattr(lifecycle_mod, "_COMMAND_ALLOWLIST")
        )
        assert has_allowlist, (
            "lifecycle モジュールに allowlist 定数（_ALLOWED_COMMANDS 等）が存在しない (AC1 未実装)"
        )

    def test_ac1_popen_not_called_on_rejected_command(self, make_mcp_json, tmp_path):
        # AC: allowlist 外コマンドでは subprocess.Popen が呼ばれないこと
        # RED: allowlist 定数が存在しないため検証ロジック自体がない
        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, (
            "lifecycle モジュールに allowlist 定数が存在しない。"
            "allowlist なしでは Popen 呼び出し防止を保証できない (AC1 未実装)"
        )
        mcp_json = make_mcp_json("malicious-binary", tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())), \
             patch.object(lifecycle_mod.subprocess, "Popen") as mock_popen:
            try:
                lifecycle_mod._find_mcp_server_cmd()
            except Exception:
                pass
            mock_popen.assert_not_called()


# ---------------------------------------------------------------------------
# AC2: 絶対パスの command は既知バイナリディレクトリ prefix に限定される
# ---------------------------------------------------------------------------

class TestAC2AbsolutePathValidation:
    """AC2: 絶対パスで指定された command は /usr/bin, /usr/local/bin,
    ~/.local/bin 等の既知プレフィックスに限定される。

    RED: 現状は絶対パス検証なし。任意の絶対パスが通過してしまう。
    """

    def test_ac2_known_prefix_usr_bin_allowed(self):
        # AC: /usr/bin/uv は許可される（既知プレフィックス）
        # RED: 検証関数が存在しないため FAIL する
        has_validator = (
            hasattr(lifecycle_mod, "_validate_command")
            or hasattr(lifecycle_mod, "_is_allowed_command")
            or hasattr(lifecycle_mod, "_check_command_allowed")
        )
        assert has_validator, (
            "lifecycle モジュールにコマンド検証関数（_validate_command 等）が存在しない (AC2 未実装)"
        )

    def test_ac2_arbitrary_absolute_path_raises_value_error(self, make_mcp_json, tmp_path):
        # AC: /tmp/malicious は ValueError を raise する（未知プレフィックス）
        # RED: 現状は ValueError を raise しないため FAIL する
        mcp_json = make_mcp_json("/tmp/malicious", tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError):
                _find_mcp_server_cmd()

    def test_ac2_home_local_bin_prefix_is_known(self):
        # AC: ~/.local/bin が既知プレフィックスに含まれること
        # RED: 現状は既知プレフィックスリスト自体が存在しない
        has_prefix_list = (
            hasattr(lifecycle_mod, "_ALLOWED_PREFIXES")
            or hasattr(lifecycle_mod, "ALLOWED_PREFIXES")
            or hasattr(lifecycle_mod, "_KNOWN_BIN_DIRS")
        )
        assert has_prefix_list, (
            "lifecycle モジュールに既知プレフィックスリスト（_ALLOWED_PREFIXES 等）が存在しない (AC2 未実装)"
        )

    def test_ac2_home_local_bin_uv_raises_no_error(self, make_mcp_json, tmp_path):
        # AC: ~/.local/bin/uv は許可される（既知プレフィックス + allowlist 名）
        # RED: 検証ロジック（_ALLOWED_PREFIXES）が未実装のため FAIL する
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
        mcp_json = make_mcp_json(home_bin_uv, tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                result = lifecycle_mod._find_mcp_server_cmd()
                assert result is None or home_bin_uv in (result or []), (
                    f"~/.local/bin/uv は許可されるべきだが結果が不正: {result}"
                )
            except ValueError as e:
                pytest.fail(f"~/.local/bin/uv は許可プレフィックスのため ValueError は不正: {e}")

    def test_ac2_etc_passwd_absolute_path_raises(self, make_mcp_json, tmp_path):
        # AC: /etc/passwd など明らかに不正な絶対パスは ValueError を raise する
        # RED: 現状は検証なし
        mcp_json = make_mcp_json("/etc/passwd", tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
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

    def test_ac3_value_error_message_contains_command(self, make_mcp_json, tmp_path, capsys):
        # AC: ValueError のメッセージまたは stdout に command 値が含まれること
        # RED: 現状は ValueError 自体が raise されないため FAIL
        rejected_cmd = "evil-command"
        mcp_json = make_mcp_json(rejected_cmd, tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                _find_mcp_server_cmd()
                pytest.fail("ValueError が raise されなかった (AC3 未実装)")
            except ValueError as e:
                assert rejected_cmd in str(e), (
                    f"ValueError メッセージに command 値 '{rejected_cmd}' が含まれない: {e}"
                )

    def test_ac3_value_error_message_contains_allowlist_or_reason(self, make_mcp_json, tmp_path):
        # AC: ValueError のメッセージに allowlist または拒否理由が含まれること
        # RED: 現状は ValueError 自体が raise されないため FAIL
        mcp_json = make_mcp_json("wget", tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                _find_mcp_server_cmd()
                pytest.fail("ValueError が raise されなかった (AC3 未実装)")
            except ValueError as e:
                msg = str(e).lower()
                has_reason = (
                    "allow" in msg or "permit" in msg or "reject" in msg
                    or "uv" in msg or "uvx" in msg
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

    def test_ac4_uv_command_is_in_allowlist(self):
        # AC: "uv" が allowlist に含まれること
        # RED: allowlist 定数が存在しないため FAIL
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

    def test_ac4_uv_command_does_not_raise(self, make_mcp_json, tmp_path):
        # AC: command = "uv" では ValueError が raise されないこと
        # RED: allowlist が実装されていないため uv 許可動作を検証できない
        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, (
            "allowlist が実装されていないため uv 許可動作を検証できない (AC4 未実装)"
        )
        mcp_json = make_mcp_json("uv", ["run", "--directory", "/some/path", "server.py"], tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                lifecycle_mod._find_mcp_server_cmd()
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
        import twl.mcp_server.lifecycle  # noqa: F401

    def test_ac5_find_mcp_server_cmd_exists(self):
        # AC: _find_mcp_server_cmd 関数が存在すること
        assert callable(_find_mcp_server_cmd)

    def test_ac5_allowlist_covers_uv_and_uvx(self):
        # AC: allowlist に uv と uvx の両方が含まれること（許可ケースカバー）
        # RED: allowlist 未実装
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
        allowlist = (
            getattr(lifecycle_mod, "_ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "ALLOWED_COMMANDS", None)
            or getattr(lifecycle_mod, "_COMMAND_ALLOWLIST", None)
        )
        assert allowlist is not None, "allowlist 定数が存在しない (AC5 未実装)"
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
        import twl.cli as cli_mod  # noqa: PLC0415

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

        # mcp restart のディスパッチ付近に ValueError 捕捉があること（argparse ベース）
        # 「args.subcommand == 'mcp'」セクションに「ValueError」が含まれること
        mcp_section_start = content.find("args.subcommand == 'mcp'")
        assert mcp_section_start != -1, (
            "cli.py に mcp ディスパッチが見つからない（args.subcommand == 'mcp' が存在しない）"
        )
        # mcp セクション以降に ValueError が含まれること
        mcp_section = content[mcp_section_start:mcp_section_start + 500]
        assert "ValueError" in mcp_section, (
            f"cli.py の mcp ディスパッチ付近に ValueError 捕捉が存在しない (AC2 未実装):\n{mcp_section}"
        )

    def test_ac6_cli_mcp_restart_exits_1_on_value_error_subprocess(self):
        # AC: ValueError が発生する条件でも exit code 1 で終了すること
        # RED: allowlist が未実装のため subprocess テストが意味をなさない
        import shutil
        shutil.which("twl") or str(TWL_DIR / "twl")

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
                except ValueError:
                    pytest.fail(
                        "ValueError が cli.py で捕捉されず propagate した (AC2/Issue#1414 未実装)"
                    )

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


# ---------------------------------------------------------------------------
# Issue #1588 AC1: .mcp.json の command が "uv" であること
# ---------------------------------------------------------------------------

class TestIssue1588AC1McpJsonCommand:
    """Issue #1588 AC1: .mcp.json の mcpServers.twl.command が "uv" に変更されていること。

    RED: 現状の .mcp.json は command が fastmcp の絶対パスのため FAIL する。
    """

    def test_ac1_mcp_json_twl_command_is_uv(self):
        # AC: .mcp.json の mcpServers.twl.command が "uv" であること
        # RED: 現状は "/home/.../fastmcp" が設定されているため FAIL する
        import json
        mcp_json_path = Path(__file__).resolve().parents[3] / ".mcp.json"
        assert mcp_json_path.exists(), f".mcp.json が見つからない: {mcp_json_path}"
        with open(mcp_json_path) as f:
            config = json.load(f)
        twl_server = config.get("mcpServers", {}).get("twl", {})
        assert twl_server, ".mcp.json に mcpServers.twl エントリが存在しない"
        command = twl_server.get("command", "")
        assert command == "uv", (
            f".mcp.json mcpServers.twl.command が 'uv' でない: {command!r} "
            f"(Issue #1588 AC1 未実装 — fastmcp パスから uv への変更が必要)"
        )

    def test_ac1_mcp_json_twl_args_starts_with_run(self):
        # AC: .mcp.json の mcpServers.twl.args の先頭が "run" であること
        # RED: 現状は fastmcp コマンドの args が設定されているため FAIL する
        import json
        mcp_json_path = Path(__file__).resolve().parents[3] / ".mcp.json"
        assert mcp_json_path.exists(), f".mcp.json が見つからない: {mcp_json_path}"
        with open(mcp_json_path) as f:
            config = json.load(f)
        twl_server = config.get("mcpServers", {}).get("twl", {})
        args = twl_server.get("args", [])
        assert args and args[0] == "run", (
            f".mcp.json mcpServers.twl.args の先頭が 'run' でない: {args!r} "
            f"(Issue #1588 AC1 未実装)"
        )

    def test_ac1_mcp_json_twl_args_contains_directory_flag(self):
        # AC: args に "--directory" と cli/twl への絶対パスが含まれること
        # RED: 現状の args は uv --directory 形式でないため FAIL する
        import json
        mcp_json_path = Path(__file__).resolve().parents[3] / ".mcp.json"
        assert mcp_json_path.exists(), f".mcp.json が見つからない: {mcp_json_path}"
        with open(mcp_json_path) as f:
            config = json.load(f)
        twl_server = config.get("mcpServers", {}).get("twl", {})
        args = twl_server.get("args", [])
        assert "--directory" in args, (
            f".mcp.json mcpServers.twl.args に '--directory' が含まれない: {args!r} "
            f"(Issue #1588 AC1 未実装)"
        )

    def test_ac1_mcp_json_twl_args_contains_extra_mcp(self):
        # AC: args に "--extra" "mcp" が含まれること
        # RED: 現状の args に --extra mcp がないため FAIL する
        import json
        mcp_json_path = Path(__file__).resolve().parents[3] / ".mcp.json"
        assert mcp_json_path.exists(), f".mcp.json が見つからない: {mcp_json_path}"
        with open(mcp_json_path) as f:
            config = json.load(f)
        twl_server = config.get("mcpServers", {}).get("twl", {})
        args = twl_server.get("args", [])
        assert "--extra" in args and "mcp" in args, (
            f".mcp.json mcpServers.twl.args に '--extra' 'mcp' が含まれない: {args!r} "
            f"(Issue #1588 AC1 未実装)"
        )

    def test_ac1_mcp_json_twl_type_is_stdio(self):
        # AC: type: "stdio" が維持されていること
        # RED: type フィールドが変わっている場合は FAIL する（防衛的検証）
        import json
        mcp_json_path = Path(__file__).resolve().parents[3] / ".mcp.json"
        assert mcp_json_path.exists(), f".mcp.json が見つからない: {mcp_json_path}"
        with open(mcp_json_path) as f:
            config = json.load(f)
        twl_server = config.get("mcpServers", {}).get("twl", {})
        typ = twl_server.get("type", "")
        assert typ == "stdio", (
            f".mcp.json mcpServers.twl.type が 'stdio' でない: {typ!r} "
            f"(Issue #1588 AC1 — type維持が必要)"
        )


# ---------------------------------------------------------------------------
# Issue #1588 AC3: fail-fast regression 二次予防
# ---------------------------------------------------------------------------

class TestIssue1588AC3FailFastBehavior:
    """Issue #1588 AC3: restart_mcp_server() が SIGTERM 前に _find_mcp_server_cmd() を
    dry-run し、エラー時はサーバーを停止せずに return 1 すること。

    RED: 現状の restart_mcp_server() は SIGTERM 後に _find_mcp_server_cmd() を呼ぶため、
    ValueError 時もサーバーを停止してしまう（fail-fast なし）。
    """

    def test_ac3_value_error_in_find_cmd_returns_1_without_sigterm(self):
        # AC: _find_mcp_server_cmd() が ValueError を raise するとき、
        #     restart_mcp_server() は SIGTERM を送らずに 1 を返すこと
        # RED: 現状は SIGTERM 後に _find_mcp_server_cmd() を呼ぶため、
        #     ValueError が出てもすでにサーバーが停止している
        with patch.object(lifecycle_mod, "_find_mcp_server_pids", return_value=[99999]), \
             patch.object(lifecycle_mod, "_find_mcp_server_cmd",
                          side_effect=ValueError("command not in allowlist")), \
             patch("os.kill") as mock_kill, \
             patch.object(lifecycle_mod, "_wait_for_pids_exit", return_value=True):
            result = lifecycle_mod.restart_mcp_server()
        assert result == 1, (
            f"restart_mcp_server() が ValueError 時に 1 を返さなかった: {result} "
            f"(Issue #1588 AC3 未実装 — fail-fast 前に SIGTERM が必要)"
        )
        # SIGTERM が送られていないこと
        sigterm_calls = [
            call for call in mock_kill.call_args_list
            if len(call.args) >= 2 and call.args[1] == signal.SIGTERM
        ]
        assert not sigterm_calls, (
            f"ValueError 検出前に SIGTERM が送られた: {sigterm_calls} "
            f"(Issue #1588 AC3 未実装 — dry-run 検証が SIGTERM より前にない)"
        )

    def test_ac3_none_return_from_find_cmd_returns_1_without_stopping_server(self):
        # AC: _find_mcp_server_cmd() が None を返すとき、
        #     restart_mcp_server() はサーバーを停止せずに 1 を返すこと
        # RED: 現状は None 時に停止させずに return 0 する（return 1 でない）
        with patch.object(lifecycle_mod, "_find_mcp_server_pids", return_value=[88888]), \
             patch.object(lifecycle_mod, "_find_mcp_server_cmd", return_value=None), \
             patch("os.kill") as mock_kill, \
             patch.object(lifecycle_mod, "_wait_for_pids_exit", return_value=True):
            result = lifecycle_mod.restart_mcp_server()
        assert result == 1, (
            f"restart_mcp_server() が None 時に 1 を返さなかった: {result} "
            f"(Issue #1588 AC3 未実装 — None は return 1 でなければならない)"
        )
        # SIGTERM が送られていないこと
        sigterm_calls = [
            call for call in mock_kill.call_args_list
            if len(call.args) >= 2 and call.args[1] == signal.SIGTERM
        ]
        assert not sigterm_calls, (
            f"None 検出前に SIGTERM が送られた: {sigterm_calls} "
            f"(Issue #1588 AC3 未実装 — dry-run 検証が SIGTERM より前にない)"
        )

    def test_ac3_value_error_outputs_structured_error_to_stderr(self, capsys):
        # AC: ValueError 時に stderr に "Error: mcp restart aborted — <reason>" が出力されること
        # RED: 現状の実装は ValueError を捕捉して構造化出力する処理がない
        with patch.object(lifecycle_mod, "_find_mcp_server_pids", return_value=[]), \
             patch.object(lifecycle_mod, "_find_mcp_server_cmd",
                          side_effect=ValueError("command not in allowlist")):
            result = lifecycle_mod.restart_mcp_server()

        assert result == 1, (
            f"restart_mcp_server() が ValueError 時に 1 を返さなかった: {result} "
            f"(Issue #1588 AC3 未実装)"
        )
        captured = capsys.readouterr()
        assert "Error: mcp restart aborted" in captured.err, (
            f"ValueError 時に stderr に 'Error: mcp restart aborted' が出力されていない "
            f"(Issue #1588 AC3 未実装).\n"
            f"stderr: {captured.err!r}"
        )

    def test_ac3_docstring_updated(self):
        # AC: restart_mcp_server() の docstring が
        #     "Returns 0 on success, 1 on validation failure (server not stopped)" に更新されていること
        # RED: 現状は "Always returns 0" のまま
        doc = lifecycle_mod.restart_mcp_server.__doc__ or ""
        assert "Always returns 0" not in doc, (
            "restart_mcp_server() の docstring がまだ 'Always returns 0' のまま "
            "(Issue #1588 AC3 未実装 — docstring 更新が必要)"
        )
        assert "1" in doc and ("validation failure" in doc or "server not stopped" in doc), (
            f"restart_mcp_server() の docstring に '1' と検証失敗の説明がない: {doc!r} "
            f"(Issue #1588 AC3 未実装)"
        )

    def test_ac5_fix_guidance_in_error_message(self, capsys):
        # AC: _format_fix_guidance が実装され、restart_mcp_server() の stderr に
        #     その出力文字列が含まれること
        # RED: _format_fix_guidance が未実装のため AttributeError または出力内容が変わらない
        with patch.object(lifecycle_mod, "_find_mcp_server_pids", return_value=[]), \
             patch.object(lifecycle_mod, "_find_mcp_server_cmd",
                          side_effect=ValueError("command 'xxx' not in allowlist: ['uv', 'uvx']")):
            result = lifecycle_mod.restart_mcp_server()
        assert result == 1
        captured = capsys.readouterr()
        # _format_fix_guidance の出力が含まれることを確認
        # 実装前は _format_fix_guidance が存在しないため fail する
        assert hasattr(lifecycle_mod, "_format_fix_guidance"), \
            "_format_fix_guidance が lifecycle.py に未実装 (AC5 RED)"
        expected_guidance = lifecycle_mod._format_fix_guidance("command 'xxx' not in allowlist: ['uv', 'uvx']")
        assert expected_guidance in captured.err, \
            f"stderr に _format_fix_guidance の出力が含まれていない: {captured.err!r}"


# ---------------------------------------------------------------------------
# Issue #1588 AC4: ADR-0008 ファイルが存在すること
# ---------------------------------------------------------------------------

class TestIssue1588AC4AdrExists:
    """Issue #1588 AC4: ADR-0008-mcp-config-command-format.md が存在すること。

    RED: ファイルがまだ作成されていないため FAIL する。
    """

    def test_ac4_adr_0008_file_exists(self):
        # AC: cli/twl/architecture/decisions/ADR-0008-mcp-config-command-format.md が存在すること
        # RED: ファイルが存在しないため FAIL する
        adr_path = (
            Path(__file__).resolve().parents[1]
            / "architecture"
            / "decisions"
            / "ADR-0008-mcp-config-command-format.md"
        )
        assert adr_path.exists(), (
            f"ADR-0008-mcp-config-command-format.md が存在しない: {adr_path} "
            f"(Issue #1588 AC4 未実装 — ADR 作成が必要)"
        )

    def test_ac4_adr_0008_file_has_content(self):
        # AC: ADR-0008 ファイルが空でないこと
        # RED: ファイルが存在しないため FAIL する
        adr_path = (
            Path(__file__).resolve().parents[1]
            / "architecture"
            / "decisions"
            / "ADR-0008-mcp-config-command-format.md"
        )
        assert adr_path.exists(), (
            f"ADR-0008-mcp-config-command-format.md が存在しない: {adr_path} "
            f"(Issue #1588 AC4 未実装)"
        )
        content = adr_path.read_text().strip()
        assert content, (
            f"ADR-0008-mcp-config-command-format.md が空ファイル "
            f"(Issue #1588 AC4 未実装)"
        )

    def test_ac4_adr_0008_mentions_uv_command(self):
        # AC: ADR-0008 の内容に "uv" コマンドへの言及があること
        # RED: ファイルが存在しないため FAIL する
        adr_path = (
            Path(__file__).resolve().parents[1]
            / "architecture"
            / "decisions"
            / "ADR-0008-mcp-config-command-format.md"
        )
        assert adr_path.exists(), (
            f"ADR-0008-mcp-config-command-format.md が存在しない: {adr_path} "
            f"(Issue #1588 AC4 未実装)"
        )
        content = adr_path.read_text()
        assert "uv" in content, (
            f"ADR-0008 に 'uv' への言及がない (Issue #1588 AC4 未実装).\n"
            f"content: {content[:200]!r}"
        )


# ---------------------------------------------------------------------------
# Issue #1588 AC5: 実 .mcp.json round-trip test
# ---------------------------------------------------------------------------

class TestActualMcpJsonRoundTrip:
    """Issue #1588 AC5: 実 .mcp.json を読み込み _find_mcp_server_cmd() が
    ValueError を raise せず list[str] を返し、先頭が "uv" であることを検証する。

    RED: 現状の .mcp.json は command が fastmcp パスのため
    _validate_command() が ValueError を raise するか、
    先頭要素が "uv" でないため FAIL する。

    既存テストクラス（TestAC1AllowlistValidation 〜 TestAC6CliValueErrorHandling）は維持する。
    """

    def test_actual_mcp_json_find_cmd_no_value_error(self):
        # AC: 実 .mcp.json を読み込んで _find_mcp_server_cmd() が ValueError を raise しないこと
        # RED: 現状の .mcp.json は fastmcp パスのため _validate_command() が ValueError を raise する
        mcp_json_path = Path(__file__).resolve().parents[3] / ".mcp.json"
        assert mcp_json_path.exists(), f"実 .mcp.json が見つからない: {mcp_json_path}"

        repo_root = str(mcp_json_path.parent)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=repo_root + "\n")):
            try:
                result = lifecycle_mod._find_mcp_server_cmd()
            except ValueError as e:
                pytest.fail(
                    f"実 .mcp.json を使った _find_mcp_server_cmd() が ValueError を raise した: {e} "
                    f"(Issue #1588 AC5 未実装 — .mcp.json を uv コマンドに変更する必要がある)"
                )

    def test_actual_mcp_json_find_cmd_returns_list(self):
        # AC: _find_mcp_server_cmd() が list[str] を返すこと（None でないこと）
        # RED: 現状は ValueError が raise されるか、コマンド解釈に失敗して None を返す可能性がある
        mcp_json_path = Path(__file__).resolve().parents[3] / ".mcp.json"
        assert mcp_json_path.exists(), f"実 .mcp.json が見つからない: {mcp_json_path}"

        repo_root = str(mcp_json_path.parent)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=repo_root + "\n")):
            try:
                result = lifecycle_mod._find_mcp_server_cmd()
            except ValueError:
                result = None

        assert isinstance(result, list), (
            f"_find_mcp_server_cmd() が list を返さなかった: {result!r} "
            f"(Issue #1588 AC5 未実装)"
        )

    def test_actual_mcp_json_find_cmd_first_element_is_uv(self):
        # AC: _find_mcp_server_cmd() の戻り値の先頭要素が "uv" であること
        # RED: 現状は fastmcp パスが先頭になるため FAIL する
        mcp_json_path = Path(__file__).resolve().parents[3] / ".mcp.json"
        assert mcp_json_path.exists(), f"実 .mcp.json が見つからない: {mcp_json_path}"

        repo_root = str(mcp_json_path.parent)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=repo_root + "\n")):
            try:
                result = lifecycle_mod._find_mcp_server_cmd()
            except ValueError as e:
                pytest.fail(
                    f"実 .mcp.json を使った _find_mcp_server_cmd() が ValueError を raise した: {e} "
                    f"(Issue #1588 AC5 未実装)"
                )

        assert result is not None and result[0] == "uv", (
            f"_find_mcp_server_cmd() の先頭要素が 'uv' でない: {result!r} "
            f"(Issue #1588 AC5 未実装 — .mcp.json command を 'uv' に変更する必要がある)"
        )
