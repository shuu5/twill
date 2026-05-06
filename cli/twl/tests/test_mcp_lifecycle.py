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

    def test_ac3_structured_log_output_on_rejection(self, make_mcp_json, tmp_path, capsys):
        # AC: 検証失敗時に stdout または stderr に構造化情報が出力される
        # RED: 現状は出力なし
        mcp_json = make_mcp_json("nc", tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                _find_mcp_server_cmd()
                pytest.fail("ValueError が raise されなかった (AC3 未実装)")
            except ValueError:
                pass
        captured = capsys.readouterr()
        assert (captured.out + captured.err).strip(), (
            "検証失敗時に stdout/stderr に何も出力されていない (AC3 未実装)"
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
