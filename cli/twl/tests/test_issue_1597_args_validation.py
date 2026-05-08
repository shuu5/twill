"""Tests for Issue #1597: _find_mcp_server_cmd() args validation (security).

TDD RED フェーズ用テスト。
実装前は全テストが FAIL する（意図的 RED）。

AC1: _find_mcp_server_cmd() が args[0] を検証し、"run" でない場合は ValueError を raise すること
AC2: _find_mcp_server_cmd() が --directory フラグの値を検証し、
     リポジトリルート外パス（例: /tmp/evil）の場合は ValueError を raise すること
AC3: args が空配列または args[0] が存在しない場合も適切に処理すること
     （ValueError または None 返却）
AC4: 正常な args では ValueError を raise しないこと（既存正常系の不変性）
"""

from pathlib import Path
from unittest.mock import MagicMock, mock_open, patch

import pytest

import twl.mcp_server.lifecycle as lifecycle_mod
from twl.mcp_server.lifecycle import _find_mcp_server_cmd

TWL_DIR = Path(__file__).resolve().parent.parent
TWL_SRC = TWL_DIR / "src"
LIFECYCLE_MODULE = "twl.mcp_server.lifecycle"


# ---------------------------------------------------------------------------
# AC1: args[0] が "run" でない場合は ValueError を raise すること
# ---------------------------------------------------------------------------

class TestAC1ArgsFirstElementValidation:
    """AC1: _find_mcp_server_cmd() が args[0] を検証し、
    "run" でない場合（例: "malicious-subcmd"）は ValueError を raise すること。

    RED: 現状は args 無検証のため ValueError は raise されない。
    """

    def test_ac1_args0_malicious_subcmd_raises_value_error(self, make_mcp_json, tmp_path):
        # AC: args[0] が "malicious-subcmd" の場合は ValueError を raise すること
        # RED: 現状は args 無検証のため FAIL する
        mcp_json = make_mcp_json(
            "uv",
            ["malicious-subcmd", "--directory", str(tmp_path), "mcp", "fastmcp", "run", "server.py"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError) as exc_info:
                _find_mcp_server_cmd()
            msg = str(exc_info.value).lower()
            assert "malicious-subcmd" in msg or "args" in msg or "run" in msg, (
                f"ValueError メッセージに args[0] 値や 'run' への言及がない: {exc_info.value}"
            )

    def test_ac1_args0_install_raises_value_error(self, make_mcp_json, tmp_path):
        # AC: args[0] が "install" の場合は ValueError を raise すること（uv install は危険）
        # RED: 現状は args 無検証のため FAIL する
        mcp_json = make_mcp_json(
            "uv",
            ["install", "malicious-package"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError):
                _find_mcp_server_cmd()

    def test_ac1_args0_shell_injection_raises_value_error(self, make_mcp_json, tmp_path):
        # AC: args[0] が "run; rm -rf /" のようなシェル注入文字列の場合は ValueError を raise すること
        # RED: 現状は args 無検証のため FAIL する
        mcp_json = make_mcp_json(
            "uv",
            ["run; rm -rf /", "--directory", str(tmp_path)],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError):
                _find_mcp_server_cmd()

    def test_ac1_validate_args_function_exists(self):
        # AC: lifecycle モジュールに _validate_args 関数（または args 検証ロジック）が存在すること
        # RED: 現状は存在しないため FAIL する
        has_validator = (
            hasattr(lifecycle_mod, "_validate_args")
            or hasattr(lifecycle_mod, "_validate_mcp_args")
            or hasattr(lifecycle_mod, "_check_args")
        )
        assert has_validator, (
            "lifecycle モジュールに args 検証関数（_validate_args 等）が存在しない (AC1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2: --directory フラグの値がリポジトリルート外の場合は ValueError を raise すること
# ---------------------------------------------------------------------------

class TestAC2DirectoryFlagValidation:
    """AC2: _find_mcp_server_cmd() が --directory フラグの値を検証し、
    リポジトリルート外パス（例: /tmp/evil）の場合は ValueError を raise すること。

    RED: 現状は args 無検証のため ValueError は raise されない。
    """

    def test_ac2_directory_outside_repo_root_raises_value_error(self, make_mcp_json, tmp_path):
        # AC: --directory の値が /tmp/evil（リポジトリルート外）の場合は ValueError を raise すること
        # RED: 現状は args 無検証のため FAIL する
        repo_root = str(tmp_path)
        mcp_json = make_mcp_json(
            "uv",
            ["run", "--directory", "/tmp/evil", "mcp", "fastmcp", "run", "server.py"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=repo_root + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError) as exc_info:
                _find_mcp_server_cmd()
            msg = str(exc_info.value)
            assert "/tmp/evil" in msg or "directory" in msg.lower() or "outside" in msg.lower(), (
                f"ValueError メッセージに --directory 値や境界外への言及がない: {exc_info.value}"
            )

    def test_ac2_directory_absolute_path_outside_repo_raises(self, make_mcp_json, tmp_path):
        # AC: --directory の値が /etc/passwd など絶対パスでリポジトリ外の場合は ValueError を raise する
        # RED: 現状は args 無検証のため FAIL する
        repo_root = str(tmp_path)
        mcp_json = make_mcp_json(
            "uv",
            ["run", "--directory", "/etc", "mcp"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=repo_root + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError):
                _find_mcp_server_cmd()

    def test_ac2_directory_path_traversal_raises(self, make_mcp_json, tmp_path):
        # AC: --directory の値にパストラバーサル（/../ 等）が含まれる場合は ValueError を raise する
        # RED: 現状は args 無検証のため FAIL する
        repo_root = str(tmp_path)
        traversal_path = str(tmp_path / ".." / ".." / "etc")
        mcp_json = make_mcp_json(
            "uv",
            ["run", "--directory", traversal_path, "mcp"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=repo_root + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError):
                _find_mcp_server_cmd()

    def test_ac2_missing_directory_flag_but_unsafe_path_raises(self, make_mcp_json, tmp_path):
        # AC: args に --directory の "値" として外部パスが埋め込まれた場合も検出する
        # （--directory /tmp/evil という連続するペア）
        # RED: 現状は args 無検証のため FAIL する
        repo_root = str(tmp_path)
        mcp_json = make_mcp_json(
            "uv",
            ["run", "--directory", "/home/attacker/evil", "--extra", "mcp", "fastmcp", "run", "server.py"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=repo_root + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            with pytest.raises(ValueError):
                _find_mcp_server_cmd()


# ---------------------------------------------------------------------------
# AC3: args が空配列または args[0] が存在しない場合の処理
# ---------------------------------------------------------------------------

class TestAC3EmptyArgsHandling:
    """AC3: args が空配列または args[0] が存在しない（空 args）の場合も
    適切に処理すること（ValueError または None 返却）。

    現在の実装: args が空でも `[command]` を返す（args 検証なし）。
    期待: 空 args は command のみで "run" subcmd がないため ValueError か None を返す。

    RED: 現状は空 args で正常に `["uv"]` を返してしまうため FAIL する。
    """

    def test_ac3_empty_args_raises_or_returns_none(self, make_mcp_json, tmp_path):
        # AC: args が空配列の場合は ValueError または None を返すこと
        # RED: 現状は ["uv"] を返してしまうため FAIL する
        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                result = _find_mcp_server_cmd()
                # None は許容、しかし ["uv"] のような不完全なコマンドリストは不正
                assert result is None, (
                    f"空 args の場合は None を返すべきだが {result!r} を返した (AC3 未実装)"
                )
            except ValueError:
                pass  # ValueError も許容

    def test_ac3_empty_args_does_not_return_bare_command(self, make_mcp_json, tmp_path):
        # AC: args が空配列の場合は `["uv"]` のような不完全なコマンドリストを返さないこと
        # RED: 現状は ["uv"] を返してしまうため FAIL する
        mcp_json = make_mcp_json("uv", [], tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                result = _find_mcp_server_cmd()
                # ["uv"] を返してはならない（subcmd なしの裸の uv 呼び出しは無効）
                assert result != ["uv"], (
                    "空 args の場合に ['uv'] のような不完全なコマンドを返してはならない (AC3 未実装)"
                )
            except ValueError:
                pass  # ValueError は OK

    def test_ac3_single_element_args_without_run_raises_or_returns_none(self, make_mcp_json, tmp_path):
        # AC: args が ["tool-name"] のように "run" なしの場合は ValueError または None を返すこと
        # RED: 現状は ["uv", "tool-name"] を返してしまうため FAIL する
        mcp_json = make_mcp_json("uv", ["tool-name"], tmp_path=tmp_path)
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(tmp_path) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                result = _find_mcp_server_cmd()
                assert result is None, (
                    f"args[0] が 'run' でない ['tool-name'] の場合は None を返すべきだが {result!r} を返した (AC3 未実装)"
                )
            except ValueError:
                pass  # ValueError も許容


# ---------------------------------------------------------------------------
# AC4: 正常な args では ValueError を raise しないこと（既存正常系の不変性）
# ---------------------------------------------------------------------------

class TestAC4LegitimateArgsUnaffected:
    """AC4: 正常な args（["run", "--directory", "<valid_repo_path>/cli/twl", ...]）では
    ValueError を raise しないこと。

    RED: _validate_args() が未実装のため、正常系でも誤って ValueError が出る
    可能性を先に確認する。実装後は GREEN になる必要がある。
    """

    def test_ac4_valid_args_run_with_directory_does_not_raise(self, make_mcp_json, tmp_path):
        # AC: args[0] が "run" かつ --directory が repo_root 配下のパスでは ValueError は raise しない
        # RED: _validate_args() 未実装のため、正常系が誤って reject される可能性あり
        repo_root = tmp_path
        valid_directory = str(repo_root / "cli" / "twl")
        mcp_json = make_mcp_json(
            "uv",
            ["run", "--directory", valid_directory, "--extra", "mcp", "fastmcp", "run", "server.py"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(repo_root) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                result = lifecycle_mod._find_mcp_server_cmd()
                # 正常系は list[str] を返すべき
                assert result is not None and isinstance(result, list), (
                    f"正常な args で None または非リストが返された: {result!r} (AC4 未実装)"
                )
            except ValueError as e:
                pytest.fail(
                    f"正常な args（run + valid --directory）で ValueError が raise された: {e} "
                    f"(AC4 未実装 — 正常系が誤って拒否されている)"
                )

    def test_ac4_valid_args_first_element_is_uv(self, make_mcp_json, tmp_path):
        # AC: 正常な args での戻り値の先頭要素が "uv" であること
        # RED: _validate_args() 未実装のため正常系の動作保証ができない
        repo_root = tmp_path
        valid_directory = str(repo_root / "cli" / "twl")
        mcp_json = make_mcp_json(
            "uv",
            ["run", "--directory", valid_directory, "mcp"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(repo_root) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                result = lifecycle_mod._find_mcp_server_cmd()
                assert result is not None and result[0] == "uv", (
                    f"正常系で戻り値の先頭が 'uv' でない: {result!r} (AC4 正常系確認失敗)"
                )
            except ValueError as e:
                pytest.fail(
                    f"正常な args で ValueError が raise された: {e} (AC4 未実装)"
                )

    def test_ac4_valid_args_no_directory_flag_does_not_raise(self, make_mcp_json, tmp_path):
        # AC: args に --directory フラグが存在しない場合は（検証スキップして）ValueError を raise しない
        # RED: _validate_args() が「--directory なし = 拒否」と誤実装した場合に FAIL する
        repo_root = tmp_path
        mcp_json = make_mcp_json(
            "uv",
            ["run", "mcp", "fastmcp", "run", "server.py"],
            tmp_path=tmp_path,
        )
        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout=str(repo_root) + "\n")), \
             patch("twl.mcp_server.lifecycle.open", mock_open(read_data=mcp_json.read_text())):
            try:
                result = lifecycle_mod._find_mcp_server_cmd()
                # --directory なしでも None 以外の正常値を返す、または None
                # いずれにせよ ValueError は出てはならない
            except ValueError as e:
                pytest.fail(
                    f"--directory フラグなしの正常な args で ValueError が raise された: {e} "
                    f"(AC4 正常系が誤って拒否されている)"
                )
