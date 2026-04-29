"""Tests for twl_get_pane_state — Issue #1113 AC3-1, AC3-4, 共通-9.

TDD RED フェーズ。実装前は全テストが FAIL する（意図的 RED）。
対象 handler: twl_get_pane_state_handler (tools.py)

AC 対応:
  AC3-1: tool シグネチャ・戻り値 schema (window_name + timeout_sec, state enum)
  AC3-4: pytest 2 経路 (handler 直接 + fastmcp 経由)
  共通-9: timeout_sec 引数の必須化 (subprocess 起動ツール)
"""

import json
import os
from pathlib import Path
from unittest import mock

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"

VALID_STATES = {"exited", "idle", "processing", "input-waiting", "error"}


def _handler():
    from twl.mcp_server.tools import twl_get_pane_state_handler  # noqa: PLC0415
    return twl_get_pane_state_handler


@pytest.fixture(autouse=False)
def dummy_script(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """テスト用ダミー session-state.sh を作成し SESSION_STATE_SCRIPT 環境変数を設定する。"""
    script = tmp_path / "session-state.sh"
    script.write_text("#!/bin/bash\n")
    script.chmod(0o755)
    monkeypatch.setenv("SESSION_STATE_SCRIPT", str(script))
    return script


# ===========================================================================
# AC3-1: tool シグネチャ
# ===========================================================================


class TestAC31Signature:
    """AC3-1: twl_get_pane_state のシグネチャと基本 schema。"""

    def test_ac1_handler_importable(self):
        # AC: tools.py に twl_get_pane_state_handler が定義されている
        # RED: 実装前は ImportError で FAIL
        from twl.mcp_server.tools import twl_get_pane_state_handler  # noqa: F401

    def test_ac1_timeout_sec_param_exists(self):
        # AC: handler が timeout_sec 引数を持つ (default=30)
        # RED: 実装前は ImportError → FAIL
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "timeout_sec" in params, (
            "twl_get_pane_state_handler に timeout_sec 引数がない (共通-9 未実装)"
        )
        assert params["timeout_sec"].default == 30, (
            f"timeout_sec のデフォルトが 30 でない: {params['timeout_sec'].default}"
        )

    def test_ac1_window_name_param_exists(self):
        # AC: handler が window_name 引数を持つ
        # RED: 実装前は ImportError → FAIL
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        assert "window_name" in sig.parameters, (
            "twl_get_pane_state_handler に window_name 引数がない (AC3-1 未実装)"
        )


# ===========================================================================
# AC3-1: 戻り値 schema — ok=True path
# ===========================================================================


class TestAC31SuccessSchema:
    """AC3-1: ok=True 時の戻り値は {"ok": True, "state": <enum>, "exit_code": 0}。"""

    def test_ac1_success_envelope_structure(self, dummy_script: Path):
        # AC: subprocess が exit 0 で valid state を返すと ok=True envelope
        # RED: 実装前は ImportError or mock 未対応 → FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "idle\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", timeout_sec=5)

        assert result.get("ok") is True, f"ok が True でない: {result}"
        assert result.get("state") == "idle", f"state が 'idle' でない: {result.get('state')}"
        assert result.get("exit_code") == 0, f"exit_code が 0 でない: {result.get('exit_code')}"

    def test_ac1_all_valid_states_accepted(self, dummy_script: Path):
        # AC: exited/idle/processing/input-waiting/error の各 state を返す
        # RED: 実装前は assert FAIL
        for state_val in VALID_STATES:
            mock_result = mock.MagicMock()
            mock_result.returncode = 0
            mock_result.stdout = state_val + "\n"
            mock_result.stderr = ""

            with mock.patch("subprocess.run", return_value=mock_result):
                result = _handler()(window_name="test-window", timeout_sec=5)

            assert result.get("ok") is True, (
                f"state='{state_val}' で ok=False になっている: {result}"
            )
            assert result.get("state") == state_val, (
                f"state が '{state_val}' でない: {result.get('state')}"
            )


# ===========================================================================
# AC3-1: 戻り値 schema — ok=False paths
# ===========================================================================


class TestAC31ErrorSchemas:
    """AC3-1: 各 error path の error envelope 構造。"""

    def test_ac1_shell_error_on_nonzero_returncode(self, dummy_script: Path):
        # AC: subprocess returncode != 0 は shell_error envelope
        # RED: 実装前は assert FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_result.stderr = "no such window: test-window"

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", timeout_sec=5)

        assert result.get("ok") is False, f"returncode=1 で ok=True になっている: {result}"
        assert result.get("error_type") == "shell_error", (
            f"error_type が shell_error でない: {result.get('error_type')}"
        )
        assert result.get("exit_code") == 1

    def test_ac1_unknown_state_envelope(self, dummy_script: Path):
        # AC: stdout が enum 外の値のとき unknown_state envelope
        # RED: 実装前は assert FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "running\n"  # 不正値
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", timeout_sec=5)

        assert result.get("ok") is False, f"unknown state で ok=True になっている: {result}"
        assert result.get("error_type") == "unknown_state", (
            f"error_type が unknown_state でない: {result.get('error_type')}"
        )
        assert result.get("exit_code") == 3

    def test_ac1_script_not_found_envelope(self, tmp_path: Path):
        # AC: SESSION_STATE_SCRIPT 不在時は script_not_found envelope
        # RED: 実装前は assert FAIL
        nonexistent = str(tmp_path / "nonexistent.sh")
        original = os.environ.get("SESSION_STATE_SCRIPT")
        os.environ["SESSION_STATE_SCRIPT"] = nonexistent
        try:
            result = _handler()(window_name="test-window", timeout_sec=5)
        finally:
            if original is None:
                del os.environ["SESSION_STATE_SCRIPT"]
            else:
                os.environ["SESSION_STATE_SCRIPT"] = original

        assert result.get("ok") is False, "script_not_found で ok=True になっている"
        assert result.get("error_type") == "script_not_found", (
            f"error_type が script_not_found でない: {result.get('error_type')}"
        )
        assert result.get("exit_code") == 2


# ===========================================================================
# AC3-1: shell injection 安全性 — window_name の入力検証
# ===========================================================================


class TestAC31InputValidation:
    """AC3-1 (設計確定事項): window_name の不正文字を defense in depth で ArgError reject。"""

    def test_ac1_invalid_window_name_rejected(self):
        # AC: window_name に ';' '$()' 等が含まれる場合は ArgError/ValueError
        # RED: 実装前は subprocess 直撃 or assert FAIL
        with pytest.raises((ValueError, Exception)):
            _handler()(window_name="test; rm -rf /", timeout_sec=5)

    def test_ac1_valid_window_name_accepted(self, dummy_script: Path):
        # AC: 英数字/アンダースコア/ハイフン/ドット/コロン/スラッシュは許可
        # RED: 実装前は ImportError → FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "idle\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="wt-twill-main-h8", timeout_sec=5)
        assert result.get("ok") is True


# ===========================================================================
# AC3-4: MCP tool 関数の JSON 文字列経路
# ===========================================================================


class TestAC34McpToolPath:
    """AC3-4: MCP tool 関数 twl_get_pane_state が JSON 文字列を返す。"""

    def test_ac4_mcp_tool_exists(self):
        # AC: tools モジュールに twl_get_pane_state が存在する
        # RED: 実装前は AttributeError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_get_pane_state"), (
            "twl_get_pane_state が tools モジュールに存在しない (AC3-4 未実装)"
        )

    def test_ac4_mcp_tool_returns_json_string(self, dummy_script: Path):
        # AC: mcp tool が JSON 文字列を返す
        # RED: 実装前は assert FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415

        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "idle\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result_str = tools_mod.twl_get_pane_state(
                window_name="test-window", timeout_sec=5
            )
        result = json.loads(result_str)
        assert isinstance(result, dict)
        assert result.get("ok") is True
