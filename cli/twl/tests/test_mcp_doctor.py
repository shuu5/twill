"""Tests for Issue #1589: twl mcp doctor command.

TDD RED フェーズ用テスト。
実装前は全テストが FAIL する（意図的 RED）。

AC1: cli.py に doctor サブパーサーと --probe / --format 引数を追加
AC2: doctor.py 新規モジュール（mcp.json 読み込み → _validate_command → binary 確認 → probe）
AC3: 出力フォーマット human-readable / --format json
AC4: exit code 規約（0=OK / 1=warning / 2=critical）
"""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, mock_open, patch

import pytest

TWL_SRC = Path(__file__).resolve().parent.parent / "src"
if str(TWL_SRC) not in sys.path:
    sys.path.insert(0, str(TWL_SRC))


# ---------------------------------------------------------------------------
# AC1: cli.py に doctor サブパーサーが追加されていること
# ---------------------------------------------------------------------------

class TestAC1CliDoctorSubparser:
    """AC1: cli.py の mcp_subparsers に 'doctor' が追加され、
    --probe と --format 引数を持つこと。

    RED: doctor サブパーサーが未実装のため、parse_args が fail する。
    """

    def test_ac1_doctor_module_importable(self):
        # AC: twl.mcp_server.doctor が import 可能であること
        # RED: doctor.py が存在しないため ImportError で FAIL する
        try:
            import twl.mcp_server.doctor  # noqa: F401
        except ImportError as e:
            pytest.fail(
                f"twl.mcp_server.doctor が import できない (AC1/AC2 未実装): {e}"
            )

    def test_ac1_mcp_doctor_subparser_registered(self):
        # AC: 'twl mcp doctor' が parse_args で認識されること
        # RED: cli.py に doctor サブパーサーがないため parse_args が error で終了する
        import twl.cli as cli_mod
        import argparse

        # cli.main() を parse_args 部分だけ再現するため、
        # argparse の parser を再構築して doctor が登録されているかを検証する
        cli_path = TWL_SRC / "twl" / "cli.py"
        content = cli_path.read_text()
        assert "doctor" in content, (
            "cli.py に 'doctor' という文字列が存在しない (AC1 未実装 — doctor サブパーサー追加が必要)"
        )

    def test_ac1_doctor_subparser_has_probe_argument(self):
        # AC: doctor サブパーサーに --probe 引数が定義されていること
        # RED: doctor サブパーサーが未実装のため FAIL する
        cli_path = TWL_SRC / "twl" / "cli.py"
        content = cli_path.read_text()

        # cli.py の doctor 周辺に --probe が定義されていること
        doctor_idx = content.find("'doctor'")
        if doctor_idx == -1:
            pytest.fail("cli.py に 'doctor' サブパーサーが存在しない (AC1 未実装)")
        # doctor 定義付近（前後500文字）に --probe があること
        nearby = content[max(0, doctor_idx - 50):doctor_idx + 500]
        assert "--probe" in nearby, (
            f"cli.py の doctor サブパーサー付近に '--probe' 引数が定義されていない (AC1 未実装):\n{nearby}"
        )

    def test_ac1_doctor_subparser_has_format_argument(self):
        # AC: doctor サブパーサーに --format 引数が定義されていること
        # RED: doctor サブパーサーが未実装のため FAIL する
        cli_path = TWL_SRC / "twl" / "cli.py"
        content = cli_path.read_text()

        doctor_idx = content.find("'doctor'")
        if doctor_idx == -1:
            pytest.fail("cli.py に 'doctor' サブパーサーが存在しない (AC1 未実装)")
        nearby = content[max(0, doctor_idx - 50):doctor_idx + 600]
        assert "--format" in nearby, (
            f"cli.py の doctor サブパーサー付近に '--format' 引数が定義されていない (AC1 未実装):\n{nearby}"
        )

    def test_ac1_cli_dispatches_to_doctor_run_doctor(self):
        # AC: cli.py の mcp_subcommand == 'doctor' ブロックで
        #     doctor.run_doctor(args) が呼ばれること
        # RED: dispatch ブロックが未実装のため FAIL する
        cli_path = TWL_SRC / "twl" / "cli.py"
        content = cli_path.read_text()
        assert "run_doctor" in content, (
            "cli.py に 'run_doctor' 呼び出しが存在しない (AC1 未実装)"
        )
        assert "mcp_subcommand == 'doctor'" in content or "mcp_subcommand==\"doctor\"" in content or \
               "args.mcp_subcommand == 'doctor'" in content, (
            "cli.py に doctor ディスパッチブロックが存在しない (AC1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2: doctor.py モジュール — 各 check 関数の存在と動作
# ---------------------------------------------------------------------------

class TestAC2DoctorModule:
    """AC2: twl.mcp_server.doctor モジュールが存在し、run_doctor() が実装されていること。

    RED: doctor.py が存在しないため ImportError で FAIL する。
    """

    def test_ac2_run_doctor_function_exists(self):
        # AC: doctor.run_doctor 関数が存在すること
        # RED: doctor.py が存在しないため ImportError で FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2 未実装): {e}")
        assert hasattr(doctor, "run_doctor") and callable(doctor.run_doctor), (
            "doctor.run_doctor 関数が存在しない (AC2 未実装)"
        )

    def test_ac2_doctor_reads_mcp_json_directly(self):
        # AC: doctor は .mcp.json を独自に読み込み、_find_mcp_server_cmd() を使わないこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2 未実装): {e}")
        import inspect
        source = inspect.getsource(doctor)
        # doctor は _find_mcp_server_cmd() を呼ばない
        assert "_find_mcp_server_cmd" not in source, (
            "doctor.py が _find_mcp_server_cmd() を呼んでいる (AC2 違反 — doctor は独自に .mcp.json を読む)"
        )
        # .mcp.json を読む処理が存在すること
        assert ".mcp.json" in source or "mcp_json" in source, (
            "doctor.py に .mcp.json 読み込み処理が存在しない (AC2 未実装)"
        )

    def test_ac2_doctor_calls_validate_command(self):
        # AC: doctor が lifecycle._validate_command() を呼ぶこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2 未実装): {e}")
        import inspect
        source = inspect.getsource(doctor)
        assert "_validate_command" in source, (
            "doctor.py で _validate_command() の呼び出しが見当たらない (AC2 未実装)"
        )

    def test_ac2_doctor_checks_binary_exists(self):
        # AC: doctor が shutil.which または os.access でバイナリ存在確認すること
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2 未実装): {e}")
        import inspect
        source = inspect.getsource(doctor)
        has_which = "shutil.which" in source or "which(" in source
        has_access = "os.access" in source
        assert has_which or has_access, (
            "doctor.py に shutil.which / os.access によるバイナリ確認がない (AC2 未実装)"
        )

    def test_ac2_ok_case_all_checks_pass(self, make_mcp_json, tmp_path):
        # AC: 正常な .mcp.json（command="uv"）で run_doctor() が 0 を返すこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2 未実装): {e}")

        mcp_json = make_mcp_json("uv", ["run", "--directory", str(tmp_path), "server.py"], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "human"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"):
            result = doctor.run_doctor(args)

        assert result == 0, (
            f"正常ケースで run_doctor() が 0 を返さなかった: {result} (AC2/AC4 未実装)"
        )

    def test_ac2_critical_case_mcp_json_unreadable(self, tmp_path):
        # AC: .mcp.json が読み取れない場合は run_doctor() が 2 を返すこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2 未実装): {e}")

        args = MagicMock()
        args.probe = False
        args.format = "human"

        # _find_mcp_json が None を返す → .mcp.json が見つからない
        with patch("twl.mcp_server.doctor._find_mcp_json", return_value=None):
            result = doctor.run_doctor(args)

        assert result == 2, (
            f".mcp.json 読み取り失敗時に run_doctor() が 2 を返さなかった: {result} (AC2/AC4 未実装)"
        )

    def test_ac2_critical_case_validate_command_fails(self, make_mcp_json, tmp_path):
        # AC: _validate_command() が ValueError を raise した場合は 2 を返すこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2 未実装): {e}")

        mcp_json = make_mcp_json("bash", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "human"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")):
            result = doctor.run_doctor(args)

        assert result == 2, (
            f"_validate_command 失敗時に run_doctor() が 2 を返さなかった: {result} (AC2/AC4 未実装)"
        )

    def test_ac2_warning_case_binary_not_found(self, make_mcp_json, tmp_path):
        # AC: バイナリが見つからない場合は 1 を返すこと（warning）
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "human"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value=None):
            result = doctor.run_doctor(args)

        assert result == 1, (
            f"binary_not_found 時に run_doctor() が 1 を返さなかった: {result} (AC2/AC4 未実装)"
        )


# ---------------------------------------------------------------------------
# AC3: 出力フォーマット — human と JSON
# ---------------------------------------------------------------------------

class TestAC3OutputFormats:
    """AC3: --format json で機械可読 JSON を出力し、human（default）で色付き出力すること。

    RED: doctor.py が存在しないため FAIL する。
    """

    def test_ac3_json_format_output_is_valid_json(self, make_mcp_json, tmp_path, capsys):
        # AC: --format json 時に stdout に有効な JSON が出力されること
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC3 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "json"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"):
            doctor.run_doctor(args)

        captured = capsys.readouterr()
        try:
            output = json.loads(captured.out)
        except json.JSONDecodeError as e:
            pytest.fail(
                f"--format json 時の stdout が有効な JSON でない (AC3 未実装): {e}\n"
                f"stdout: {captured.out!r}"
            )

    def test_ac3_json_schema_has_required_keys(self, make_mcp_json, tmp_path, capsys):
        # AC: JSON 出力が status / summary / checks キーを持つこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC3 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "json"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"):
            doctor.run_doctor(args)

        captured = capsys.readouterr()
        try:
            output = json.loads(captured.out)
        except json.JSONDecodeError:
            pytest.fail("--format json の stdout が JSON でない (AC3 未実装)")

        for key in ("status", "summary", "checks"):
            assert key in output, (
                f"JSON 出力に '{key}' キーが存在しない (AC3 未実装). keys={list(output.keys())}"
            )

    def test_ac3_json_checks_has_expected_names(self, make_mcp_json, tmp_path, capsys):
        # AC: checks 配列に mcp_json_readable / validate_command / binary_exists / stdio_probe が含まれること
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC3 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "json"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"):
            doctor.run_doctor(args)

        captured = capsys.readouterr()
        try:
            output = json.loads(captured.out)
        except json.JSONDecodeError:
            pytest.fail("--format json の stdout が JSON でない (AC3 未実装)")

        check_names = {c["name"] for c in output.get("checks", [])}
        expected_names = {"mcp_json_readable", "validate_command", "binary_exists", "stdio_probe"}
        assert expected_names <= check_names, (
            f"checks に期待されるエントリが不足 (AC3 未実装). "
            f"不足: {expected_names - check_names}"
        )

    def test_ac3_json_status_values_are_valid(self, make_mcp_json, tmp_path, capsys):
        # AC: status は "ok" / "warning" / "critical" のいずれかであること
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC3 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "json"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"):
            doctor.run_doctor(args)

        captured = capsys.readouterr()
        try:
            output = json.loads(captured.out)
        except json.JSONDecodeError:
            pytest.fail("--format json の stdout が JSON でない (AC3 未実装)")

        assert output.get("status") in ("ok", "warning", "critical"), (
            f"status が有効値でない: {output.get('status')!r} (AC3 未実装)"
        )

    def test_ac3_json_check_result_values_are_valid(self, make_mcp_json, tmp_path, capsys):
        # AC: 各 check の result は "pass" / "fail" / "skipped" のいずれかであること
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC3 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "json"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"):
            doctor.run_doctor(args)

        captured = capsys.readouterr()
        try:
            output = json.loads(captured.out)
        except json.JSONDecodeError:
            pytest.fail("--format json の stdout が JSON でない (AC3 未実装)")

        valid_results = {"pass", "fail", "skipped"}
        for check in output.get("checks", []):
            assert check.get("result") in valid_results, (
                f"check '{check.get('name')}' の result が無効値: {check.get('result')!r} "
                f"(AC3 未実装)"
            )

    def test_ac3_stdio_probe_skipped_without_flag(self, make_mcp_json, tmp_path, capsys):
        # AC: --probe なしの場合 stdio_probe の result は "skipped" であること
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC3 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "json"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"):
            doctor.run_doctor(args)

        captured = capsys.readouterr()
        try:
            output = json.loads(captured.out)
        except json.JSONDecodeError:
            pytest.fail("--format json の stdout が JSON でない (AC3 未実装)")

        probe_checks = [c for c in output.get("checks", []) if c.get("name") == "stdio_probe"]
        assert probe_checks, "checks に stdio_probe エントリが存在しない (AC3 未実装)"
        assert probe_checks[0].get("result") == "skipped", (
            f"--probe なし時に stdio_probe が skipped でない: {probe_checks[0].get('result')!r} "
            f"(AC3 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4: exit code 規約（0=OK / 1=warning / 2=critical）
# ---------------------------------------------------------------------------

class TestAC4ExitCodes:
    """AC4: run_doctor() の exit code が規約通りであること。

    RED: doctor.py が存在しないため FAIL する。
    """

    def test_ac4_exit_0_all_checks_pass(self, make_mcp_json, tmp_path):
        # AC: 全 check pass で 0 を返すこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC4 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "human"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"):
            result = doctor.run_doctor(args)

        assert result == 0, (
            f"全 check pass 時に 0 を返さなかった: {result} (AC4 未実装)"
        )

    def test_ac4_exit_1_binary_not_found_warning(self, make_mcp_json, tmp_path):
        # AC: binary_exists が fail（warning）の場合は 1 を返すこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC4 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "human"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value=None):
            result = doctor.run_doctor(args)

        assert result == 1, (
            f"binary_not_found 時に 1 を返さなかった: {result} (AC4 未実装)"
        )

    def test_ac4_exit_2_mcp_json_unreadable_critical(self, tmp_path):
        # AC: mcp_json_readable が fail（critical）の場合は 2 を返すこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC4 未実装): {e}")

        args = MagicMock()
        args.probe = False
        args.format = "human"

        with patch("twl.mcp_server.doctor._find_mcp_json", return_value=None):
            result = doctor.run_doctor(args)

        assert result == 2, (
            f".mcp.json 読み取り失敗時に 2 を返さなかった: {result} (AC4 未実装)"
        )

    def test_ac4_exit_2_validate_command_critical(self, make_mcp_json, tmp_path):
        # AC: validate_command が fail（critical）の場合は 2 を返すこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC4 未実装): {e}")

        # allowlist 外コマンド
        mcp_json = make_mcp_json("bash", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = False
        args.format = "human"

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")):
            result = doctor.run_doctor(args)

        assert result == 2, (
            f"validate_command 失敗（critical）時に 2 を返さなかった: {result} (AC4 未実装)"
        )

    def test_ac4_exit_1_probe_fail_warning(self, make_mcp_json, tmp_path):
        # AC: stdio_probe が fail（warning）の場合は 1 を返すこと
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC4 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = True  # --probe 有効
        args.format = "human"

        # subprocess.Popen が即座に終了してしまう（probe 失敗）
        mock_proc = MagicMock()
        mock_proc.stdout.readline.return_value = b""  # 空 = JSON-RPC 応答なし
        mock_proc.wait.return_value = 1
        mock_proc.poll.return_value = 1

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"), \
             patch("subprocess.Popen", return_value=mock_proc):
            result = doctor.run_doctor(args)

        assert result == 1, (
            f"stdio_probe 失敗（warning）時に 1 を返さなかった: {result} (AC4 未実装)"
        )

    def test_ac4_cli_doctor_exits_with_correct_code(self, make_mcp_json, tmp_path):
        # AC: cli.main() 経由で 'twl mcp doctor' が適切な exit code で終了すること
        # RED: cli.py に doctor dispatch がないため SystemExit(2) ではなく
        #     argparse error または KeyError で終了する
        import twl.cli as cli_mod

        try:
            from twl.mcp_server import doctor as doctor_mod
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC4 未実装): {e}")

        with patch("twl.mcp_server.doctor.run_doctor", return_value=0) as mock_run, \
             patch.object(sys, "argv", ["twl", "mcp", "doctor"]):
            with pytest.raises(SystemExit) as exc_info:
                cli_mod.main()
            assert exc_info.value.code == 0, (
                f"twl mcp doctor (OK) の exit code が 0 でない: {exc_info.value.code} (AC4 未実装)"
            )


# ---------------------------------------------------------------------------
# AC2(b): --probe フラグが実際の stdio handshake を実施すること
# ---------------------------------------------------------------------------

class TestAC2ProbeFlag:
    """AC2(d): --probe フラグ時に 5 秒 timeout で stdio handshake を実施すること。

    RED: doctor.py が存在しないため FAIL する。
    """

    def test_ac2d_probe_succeeds_on_valid_jsonrpc_response(self, make_mcp_json, tmp_path):
        # AC: プロセスが 5 秒以内に JSON-RPC 応答を返した場合は probe が pass であること
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2d 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = True
        args.format = "json"

        # JSON-RPC 応答を返す mock プロセス（communicate ベース実装に合わせる）
        mock_proc = MagicMock()
        mock_proc.communicate.return_value = (b'{"jsonrpc": "2.0", "id": 1, "result": {}}\n', b'')
        mock_proc.poll.return_value = None  # まだ実行中

        with patch("twl.mcp_server.doctor._find_mcp_json", return_value=mcp_json), \
             patch("shutil.which", return_value="/usr/bin/uv"), \
             patch("subprocess.Popen", return_value=mock_proc):
            result = doctor.run_doctor(args)

        assert result == 0, (
            f"有効な JSON-RPC 応答時に run_doctor() が 0 を返さなかった: {result} (AC2d 未実装)"
        )

    def test_ac2d_probe_sends_sigterm_on_failure(self, make_mcp_json, tmp_path):
        # AC: probe 失敗時にプロセスを SIGTERM で後始末すること
        # RED: doctor.py が存在しないため FAIL する
        try:
            from twl.mcp_server import doctor
        except ImportError as e:
            pytest.fail(f"twl.mcp_server.doctor が import できない (AC2d 未実装): {e}")

        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)

        args = MagicMock()
        args.probe = True
        args.format = "human"

        mock_proc = MagicMock()
        mock_proc.stdout.readline.return_value = b""  # 空 = 応答なし
        mock_proc.poll.return_value = None  # まだ実行中

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("shutil.which", return_value="/usr/bin/uv"), \
             patch("subprocess.Popen", return_value=mock_proc):
            doctor.run_doctor(args)

        # SIGTERM または terminate() が呼ばれていること
        assert mock_proc.terminate.called or mock_proc.send_signal.called, (
            "probe 失敗時にプロセスの terminate が呼ばれなかった (AC2d 未実装)"
        )


import contextlib

@contextlib.contextmanager
def capsys_workaround():
    """capsys を使わないテストケースでの stdout キャプチャ回避用 no-op コンテキスト。"""
    yield
