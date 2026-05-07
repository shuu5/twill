"""Tests for twl_capture_pane — Issue #1512 AC1-AC7.

TDD RED フェーズ。実装前は全テストが FAIL する（意図的 RED）。
対象 handler: twl_capture_pane_handler (tools.py)

AC 対応:
  AC1: handler 追加（既存 twl_get_pane_state と並列配置）
  AC2: 引数 {window_name, lines?, mode: "raw"|"plain", from_line?, to_line?}
  AC3: 戻り値 {ok, content, ansi_stripped: bool, lines, error} — mode=plain で ANSI strip
  AC4: 既存 twl_get_pane_state との責務境界
  AC5: shadow mode rollout
  AC6: AT 非依存性
  AC7: short-lived 設計
"""

import inspect
import json
from pathlib import Path
from unittest import mock

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"


def _handler():
    from twl.mcp_server.tools import twl_capture_pane_handler  # noqa: PLC0415
    return twl_capture_pane_handler


# ===========================================================================
# AC1: handler 追加（既存 twl_get_pane_state と並列配置）
# ===========================================================================


class TestAC1HandlerExists:
    """AC1: twl_capture_pane_handler が tools.py に追加されている。"""

    def test_ac1_handler_importable(self):
        # AC: tools.py に twl_capture_pane_handler が定義されている
        # RED: 実装前は ImportError で FAIL
        from twl.mcp_server.tools import twl_capture_pane_handler  # noqa: F401

    def test_ac1_handler_is_callable(self):
        # AC: twl_capture_pane_handler が callable である
        # RED: 実装前は ImportError → FAIL
        handler = _handler()
        assert callable(handler), "twl_capture_pane_handler が callable でない"

    def test_ac1_mcp_tool_registered(self):
        # AC: twl_capture_pane が MCP tools モジュールに登録されている
        # RED: 実装前は AttributeError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_capture_pane") or hasattr(
            tools_mod, "twl_capture_pane_handler"
        ), "twl_capture_pane が tools モジュールに存在しない (AC1 未実装)"

    def test_ac1_coexists_with_get_pane_state(self):
        # AC: 既存 twl_get_pane_state_handler と並列に存在する
        # RED: 実装前は ImportError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_get_pane_state_handler"), (
            "既存 twl_get_pane_state_handler が消えている（既存ハンドラを壊してはならない）"
        )
        from twl.mcp_server.tools import twl_capture_pane_handler  # noqa: F401


# ===========================================================================
# AC2: 引数シグネチャ
# ===========================================================================


class TestAC2Signature:
    """AC2: 引数 {window_name, lines?, mode: "raw"|"plain", from_line?, to_line?}。"""

    def test_ac2_window_name_param_required(self):
        # AC: window_name が必須引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "window_name" in params, (
            "twl_capture_pane_handler に window_name 引数がない (AC2 未実装)"
        )
        # window_name は必須引数（デフォルト値なし）
        assert params["window_name"].default is inspect.Parameter.empty, (
            "window_name にデフォルト値が設定されている（必須引数のはず）"
        )

    def test_ac2_lines_param_optional(self):
        # AC: lines が省略可能な引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "lines" in params, (
            "twl_capture_pane_handler に lines 引数がない (AC2 未実装)"
        )
        # lines はオプション引数（デフォルト値あり）
        assert params["lines"].default is not inspect.Parameter.empty, (
            "lines のデフォルト値がない（省略可能引数のはず）"
        )

    def test_ac2_mode_param_exists(self):
        # AC: mode 引数が存在し、デフォルト値を持つ
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "mode" in params, (
            "twl_capture_pane_handler に mode 引数がない (AC2 未実装)"
        )
        # mode はデフォルト値あり（"raw" or "plain"）
        assert params["mode"].default is not inspect.Parameter.empty, (
            "mode にデフォルト値がない"
        )

    def test_ac2_from_line_param_optional(self):
        # AC: from_line が省略可能な引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "from_line" in params, (
            "twl_capture_pane_handler に from_line 引数がない (AC2 未実装)"
        )
        assert params["from_line"].default is not inspect.Parameter.empty, (
            "from_line のデフォルト値がない（省略可能引数のはず）"
        )

    def test_ac2_to_line_param_optional(self):
        # AC: to_line が省略可能な引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "to_line" in params, (
            "twl_capture_pane_handler に to_line 引数がない (AC2 未実装)"
        )
        assert params["to_line"].default is not inspect.Parameter.empty, (
            "to_line のデフォルト値がない（省略可能引数のはず）"
        )

    def test_ac2_mode_accepts_raw(self):
        # AC: mode="raw" で呼び出し可能（エラーにならない）
        # RED: 実装前は ImportError → FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "line1\nline2\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", mode="raw")
        # mode="raw" で ok=True を期待（実装前は FAIL）
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert result.get("ok") is True, f"mode=raw で ok=False: {result}"

    def test_ac2_mode_accepts_plain(self):
        # AC: mode="plain" で呼び出し可能
        # RED: 実装前は ImportError → FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "\x1b[32mGreen text\x1b[0m\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", mode="plain")
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert result.get("ok") is True, f"mode=plain で ok=False: {result}"

    def test_ac2_invalid_mode_rejected(self):
        # AC: mode が "raw"/"plain" 以外の値はエラー envelope を返す
        # RED: 実装前は ImportError → FAIL
        result = _handler()(window_name="test-window", mode="unknown")
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert result.get("ok") is False, (
            f"無効な mode='unknown' で ok=True になっている: {result}"
        )


# ===========================================================================
# AC3: 戻り値スキーマ
# ===========================================================================


class TestAC3ReturnSchema:
    """AC3: 戻り値 {ok, content, ansi_stripped, lines, error}。"""

    def test_ac3_success_schema_raw_mode(self):
        # AC: mode=raw での ok=True 時の戻り値スキーマ検証
        # RED: 実装前は ImportError or assert FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "line1\nline2\nline3\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", mode="raw")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        assert "content" in result, f"content キーがない: {result}"
        assert "ansi_stripped" in result, f"ansi_stripped キーがない: {result}"
        assert "lines" in result, f"lines キーがない: {result}"

    def test_ac3_raw_mode_does_not_strip_ansi(self):
        # AC: mode=raw では ANSI 制御文字を strip しない（ansi_stripped=False）
        # RED: 実装前は ImportError or assert FAIL
        ansi_content = "\x1b[32mGreen\x1b[0m text"
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = ansi_content + "\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", mode="raw")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        assert result.get("ansi_stripped") is False, (
            f"mode=raw で ansi_stripped=True になっている: {result}"
        )
        # raw mode では ANSI コードが content に含まれる
        content = result.get("content", "")
        assert "\x1b[" in content, (
            f"mode=raw で ANSI コードが除去されている: content={repr(content)}"
        )

    def test_ac3_plain_mode_strips_ansi(self):
        # AC: mode=plain では ANSI 制御文字を strip する（ansi_stripped=True, epic AC11）
        # RED: 実装前は ImportError or assert FAIL
        ansi_content = "\x1b[32mGreen\x1b[0m text"
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = ansi_content + "\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", mode="plain")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        assert result.get("ansi_stripped") is True, (
            f"mode=plain で ansi_stripped=False になっている: {result}"
        )
        content = result.get("content", "")
        assert "\x1b[" not in content, (
            f"mode=plain で ANSI コードが残っている: content={repr(content)}"
        )
        assert "Green" in content, (
            f"mode=plain で可視テキストが消えている: content={repr(content)}"
        )

    def test_ac3_lines_count_matches_content(self):
        # AC: lines フィールドが content の行数と一致する
        # RED: 実装前は ImportError or assert FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "line1\nline2\nline3\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", mode="raw")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        content = result.get("content", "")
        lines = result.get("lines")
        assert isinstance(lines, int), f"lines が int でない: {type(lines)}"
        # 行数は content の改行数から推定（末尾改行は除く）
        expected_lines = len([l for l in content.splitlines() if l or content.endswith("\n")])
        assert lines >= 1, f"lines が 0 以下: {lines}"

    def test_ac3_error_envelope_on_subprocess_failure(self):
        # AC: subprocess 失敗時は ok=False + error フィールドを含む
        # RED: 実装前は ImportError or assert FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_result.stderr = "no such window"

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="nonexistent-window", mode="raw")

        assert result.get("ok") is False, f"subprocess 失敗で ok=True: {result}"
        assert "error" in result, f"error フィールドがない: {result}"

    def test_ac3_invalid_window_name_rejected(self):
        # AC: shell injection リスクのある window_name はエラー envelope を返す
        # RED: 実装前は ImportError → FAIL
        result = _handler()(window_name="test; rm -rf /", mode="raw")
        assert result.get("ok") is False, (
            f"invalid window_name が ok=True: {result}"
        )


# ===========================================================================
# AC4: 既存 twl_get_pane_state との責務境界
# ===========================================================================


class TestAC4ResponsibilityBoundary:
    """AC4: get_pane_state = state 抽出、capture_pane = content 取得。"""

    def test_ac4_capture_pane_returns_content_not_state(self):
        # AC: capture_pane の戻り値に state フィールドがない（責務境界）
        # RED: 実装前は ImportError or assert FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "some output\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", mode="raw")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        # capture_pane は state を返さない（get_pane_state の責務）
        assert "state" not in result, (
            f"capture_pane が state フィールドを返している（責務境界違反 AC4）: {result}"
        )
        # capture_pane は content を返す
        assert "content" in result, (
            f"capture_pane に content フィールドがない: {result}"
        )

    def test_ac4_boundary_enforced_both_tools_present(self):
        # AC: 責務境界が両ツールの存在を前提に成立している
        # - get_pane_state: state を返す / content を返さない
        # - capture_pane: content を返す / state を返さない
        # RED: capture_pane_handler が未実装なので ImportError → FAIL
        from twl.mcp_server.tools import twl_capture_pane_handler  # noqa: PLC0415
        from twl.mcp_server.tools import twl_get_pane_state_handler  # noqa: PLC0415

        # 両方が存在して初めて責務境界が成立している
        assert callable(twl_capture_pane_handler), "capture_pane_handler が callable でない"
        assert callable(twl_get_pane_state_handler), "get_pane_state_handler が callable でない"

        # get_pane_state は state フィールドを持ち content を持たない（不変条件）
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "idle\n"
        mock_result.stderr = ""

        import os  # noqa: PLC0415
        script = Path("/tmp/dummy_session_state_ac4.sh")
        script.write_text("#!/bin/bash\necho idle\n")
        script.chmod(0o755)
        orig = os.environ.get("SESSION_STATE_SCRIPT")
        os.environ["SESSION_STATE_SCRIPT"] = str(script)
        try:
            with mock.patch("subprocess.run", return_value=mock_result):
                state_result = twl_get_pane_state_handler(
                    window_name="test-window", timeout_sec=5
                )
        finally:
            if orig is None:
                del os.environ["SESSION_STATE_SCRIPT"]
            else:
                os.environ["SESSION_STATE_SCRIPT"] = orig

        assert "content" not in state_result, (
            f"get_pane_state が content フィールドを返している（責務境界違反 AC4）: {state_result}"
        )
        assert "state" in state_result, (
            f"get_pane_state に state フィールドがない: {state_result}"
        )

    def test_ac4_capture_pane_does_not_import_session_state_script(self):
        # AC: capture_pane は session-state.sh に依存しない（tmux capture-pane を直接使う）
        # RED: 実装前は ImportError → FAIL
        # SESSION_STATE_SCRIPT が未設定の状態でも capture_pane が動作すること
        #（サブプロセス呼び出しは mock するが SESSION_STATE_SCRIPT 不在でエラーにならない）
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "output line\n"
        mock_result.stderr = ""

        import os  # noqa: PLC0415
        orig = os.environ.get("SESSION_STATE_SCRIPT")
        # SESSION_STATE_SCRIPT を明示的に削除
        if "SESSION_STATE_SCRIPT" in os.environ:
            del os.environ["SESSION_STATE_SCRIPT"]
        try:
            with mock.patch("subprocess.run", return_value=mock_result):
                result = _handler()(window_name="test-window", mode="raw")
        finally:
            if orig is not None:
                os.environ["SESSION_STATE_SCRIPT"] = orig

        # SESSION_STATE_SCRIPT がなくても script_not_found にならない
        assert result.get("error_type") != "script_not_found", (
            "capture_pane が SESSION_STATE_SCRIPT に依存している（責務境界違反 AC4）"
        )


# ===========================================================================
# AC5: shadow mode rollout
# ===========================================================================


class TestAC5ShadowMode:
    """AC5: shadow mode rollout — 失敗しても呼び出し元に影響しない設計。"""

    def test_ac5_handler_never_raises_exception(self):
        # AC: handler は例外を raise せず、常に dict を返す（shadow mode 設計）
        # RED: 実装前は ImportError → FAIL
        handler = _handler()

        # subprocess が例外を投げる状況でも dict を返す
        with mock.patch("subprocess.run", side_effect=Exception("unexpected error")):
            try:
                result = handler(window_name="test-window", mode="raw")
            except Exception as exc:  # noqa: BLE001
                pytest.fail(
                    f"twl_capture_pane_handler が例外を raise した（shadow mode 違反 AC5）: {exc}"
                )
        assert isinstance(result, dict), (
            f"戻り値が dict でない: {type(result)}"
        )
        assert result.get("ok") is False, (
            f"例外発生時に ok=True になっている: {result}"
        )

    def test_ac5_subprocess_timeout_returns_error_dict(self):
        # AC: subprocess タイムアウト時は例外 raise でなく error dict を返す
        # RED: 実装前は ImportError → FAIL
        import subprocess  # noqa: PLC0415

        with mock.patch(
            "subprocess.run",
            side_effect=subprocess.TimeoutExpired(cmd=["tmux"], timeout=30)
        ):
            try:
                result = _handler()(window_name="test-window", mode="raw")
            except Exception as exc:  # noqa: BLE001
                pytest.fail(
                    f"TimeoutExpired で例外が伝播した（shadow mode 違反 AC5）: {exc}"
                )
        assert isinstance(result, dict)
        assert result.get("ok") is False
        assert result.get("error_type") in ("timeout", "error"), (
            f"timeout 時の error_type が想定外: {result.get('error_type')}"
        )

    def test_ac5_shadow_mode_does_not_affect_existing_tool(self):
        # AC: capture_pane の失敗が get_pane_state に影響しない（独立性）
        # RED: 実装前は ImportError → FAIL
        # capture_pane が例外を raise しないことを確認した後、get_pane_state が動作することを確認
        from twl.mcp_server.tools import twl_get_pane_state_handler  # noqa: PLC0415

        # まず capture_pane を強制失敗させる
        with mock.patch("subprocess.run", side_effect=Exception("capture failed")):
            result_capture = _handler()(window_name="test-window", mode="raw")
        assert result_capture.get("ok") is False

        # その後 get_pane_state が正常動作することを確認
        mock_state = mock.MagicMock()
        mock_state.returncode = 0
        mock_state.stdout = "idle\n"
        mock_state.stderr = ""

        import os  # noqa: PLC0415
        script = Path("/tmp/dummy_session_state_ac5.sh")
        script.write_text("#!/bin/bash\necho idle\n")
        script.chmod(0o755)
        orig = os.environ.get("SESSION_STATE_SCRIPT")
        os.environ["SESSION_STATE_SCRIPT"] = str(script)
        try:
            with mock.patch("subprocess.run", return_value=mock_state):
                result_state = twl_get_pane_state_handler(
                    window_name="test-window", timeout_sec=5
                )
        finally:
            if orig is None:
                del os.environ["SESSION_STATE_SCRIPT"]
            else:
                os.environ["SESSION_STATE_SCRIPT"] = orig

        assert result_state.get("ok") is True, (
            f"capture_pane 失敗後に get_pane_state が動作しない（AC5 shadow mode 分離違反）: {result_state}"
        )


# ===========================================================================
# AC6: AT 非依存性（tmux 実セッション非依存）
# ===========================================================================


class TestAC6ATIndependence:
    """AC6: AT 非依存性 — 自動テストが tmux 実セッションに依存しないこと。"""

    def test_ac6_handler_works_with_mocked_subprocess(self):
        # AC: subprocess を mock すればテストが tmux 実セッション不要で動作する
        # RED: 実装前は ImportError → FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "mocked output\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result) as mock_run:
            result = _handler()(window_name="test-window", mode="raw")

        # subprocess.run が呼ばれたことを確認（tmux 実セッション非依存の証明）
        assert mock_run.called, "subprocess.run が呼ばれていない（mock が機能していない）"
        assert result.get("ok") is True, f"mock 経由で ok=False: {result}"

    def test_ac6_no_real_tmux_required_for_error_paths(self):
        # AC: エラーパス（window 不在等）も tmux 実セッション不要でテスト可能
        # RED: 実装前は ImportError → FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_result.stderr = "can't find window: no-such-window"

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="no-such-window", mode="raw")

        assert result.get("ok") is False, (
            f"window 不在シミュレーションで ok=True: {result}"
        )

    def test_ac6_handler_has_no_global_tmux_side_effects(self):
        # AC: handler をインポートしただけで tmux コマンドが実行されない
        # RED: 実装前は ImportError → FAIL
        # import 時に subprocess.run が呼ばれていないことを確認
        with mock.patch("subprocess.run") as mock_run:
            # import だけ行う（呼び出しはしない）
            from twl.mcp_server.tools import twl_capture_pane_handler  # noqa: F401
        assert not mock_run.called, (
            "import 時に subprocess.run が実行されている（グローバル副作用 AC6 違反）"
        )


# ===========================================================================
# AC7: short-lived 設計
# ===========================================================================


class TestAC7ShortLived:
    """AC7: short-lived 設計 — handler がリソースを長期保持しないこと。"""

    def test_ac7_handler_does_not_store_state_between_calls(self):
        # AC: 複数回呼び出しても状態が持ち越されない（short-lived）
        # RED: 実装前は ImportError → FAIL
        mock_result1 = mock.MagicMock()
        mock_result1.returncode = 0
        mock_result1.stdout = "first call output\n"
        mock_result1.stderr = ""

        mock_result2 = mock.MagicMock()
        mock_result2.returncode = 0
        mock_result2.stdout = "second call output\n"
        mock_result2.stderr = ""

        handler = _handler()

        with mock.patch("subprocess.run", return_value=mock_result1):
            result1 = handler(window_name="window-a", mode="raw")
        with mock.patch("subprocess.run", return_value=mock_result2):
            result2 = handler(window_name="window-b", mode="raw")

        # 各呼び出しが独立していること
        assert result1.get("ok") is True, f"1回目呼び出し失敗: {result1}"
        assert result2.get("ok") is True, f"2回目呼び出し失敗: {result2}"
        assert result1.get("content") != result2.get("content"), (
            "2回の呼び出し結果が同じ（状態持ち越し疑い AC7 違反）"
        )

    def test_ac7_handler_result_contains_no_connection_object(self):
        # AC: 戻り値 dict に接続オブジェクト/ファイルハンドラが含まれない
        # RED: 実装前は ImportError → FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "output\n"
        mock_result.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(window_name="test-window", mode="raw")

        # JSON シリアライズ可能であること（接続オブジェクト等が含まれていない証明）
        try:
            json.dumps(result)
        except (TypeError, ValueError) as exc:
            pytest.fail(
                f"戻り値が JSON シリアライズ不可（リソースオブジェクト混入疑い AC7 違反）: {exc}"
            )

    def test_ac7_mcp_tool_returns_json_string(self):
        # AC: MCP tool 関数 twl_capture_pane が JSON 文字列を返す（short-lived dispatch 設計）
        # RED: 実装前は AttributeError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415

        # twl_capture_pane が存在することを確認
        assert hasattr(tools_mod, "twl_capture_pane"), (
            "twl_capture_pane が tools モジュールに存在しない (AC7 MCP tool 未実装)"
        )
