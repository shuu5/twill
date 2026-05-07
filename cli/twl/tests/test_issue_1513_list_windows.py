"""Tests for twl_list_windows — Issue #1513 AC1-AC7.

TDD RED フェーズ。実装前は全テストが FAIL する（意図的 RED）。
対象 handler: twl_list_windows_handler (tools.py)

AC 対応:
  AC1: handler 追加（twl_capture_pane_handler と並列配置）
  AC2: 引数 {session?, format?: "minimal"|"detailed"}
  AC3: 戻り値 {ok, windows: [{name, index, session, active, panes_count, ...}], error}
  AC4: tmux list-sessions と list-windows -F 両方サポート
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
    from twl.mcp_server.tools import twl_list_windows_handler  # noqa: PLC0415
    return twl_list_windows_handler


# ===========================================================================
# AC1: handler 追加（既存 twl_capture_pane_handler と並列配置）
# ===========================================================================


class TestAC1HandlerExists:
    """AC1: twl_list_windows_handler が tools.py に追加されている。"""

    def test_ac1_handler_importable(self):
        # AC: tools.py に twl_list_windows_handler が定義されている
        # RED: 実装前は ImportError で FAIL
        from twl.mcp_server.tools import twl_list_windows_handler  # noqa: F401

    def test_ac1_handler_is_callable(self):
        # AC: twl_list_windows_handler が callable である
        # RED: 実装前は ImportError → FAIL
        handler = _handler()
        assert callable(handler), "twl_list_windows_handler が callable でない"

    def test_ac1_mcp_tool_registered(self):
        # AC: twl_list_windows が MCP tools モジュールに登録されている
        # RED: 実装前は AttributeError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_list_windows") or hasattr(
            tools_mod, "twl_list_windows_handler"
        ), "twl_list_windows が tools モジュールに存在しない (AC1 未実装)"

    def test_ac1_coexists_with_capture_pane(self):
        # AC: 既存 twl_capture_pane_handler と並列に存在する
        # RED: 実装前は ImportError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_capture_pane_handler"), (
            "既存 twl_capture_pane_handler が消えている（既存ハンドラを壊してはならない）"
        )
        from twl.mcp_server.tools import twl_list_windows_handler  # noqa: F401


# ===========================================================================
# AC2: 引数シグネチャ
# ===========================================================================


class TestAC2Signature:
    """AC2: 引数 {session?, format?: "minimal"|"detailed"}。"""

    def test_ac2_session_param_optional(self):
        # AC: session が省略可能な引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "session" in params, (
            "twl_list_windows_handler に session 引数がない (AC2 未実装)"
        )
        # session はオプション引数（デフォルト値あり、省略時は全セッション）
        assert params["session"].default is not inspect.Parameter.empty, (
            "session にデフォルト値がない（省略可能引数のはず）"
        )

    def test_ac2_format_param_optional(self):
        # AC: format が省略可能な引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "format" in params, (
            "twl_list_windows_handler に format 引数がない (AC2 未実装)"
        )
        # format はオプション引数（デフォルト値あり）
        assert params["format"].default is not inspect.Parameter.empty, (
            "format にデフォルト値がない（省略可能引数のはず）"
        )

    def test_ac2_format_default_is_minimal(self):
        # AC: format のデフォルト値は "minimal"
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "format" in params, (
            "twl_list_windows_handler に format 引数がない (AC2 未実装)"
        )
        assert params["format"].default == "minimal", (
            f"format のデフォルト値が 'minimal' でない: {params['format'].default}"
        )

    def test_ac2_format_accepts_minimal(self):
        # AC: format="minimal" で呼び出し可能
        # RED: 実装前は ImportError → FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\ndev\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        with mock.patch("subprocess.run", side_effect=[mock_sessions, mock_windows]):
            result = _handler()(format="minimal")
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"

    def test_ac2_format_accepts_detailed(self):
        # AC: format="detailed" で呼び出し可能
        # RED: 実装前は ImportError → FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        with mock.patch("subprocess.run", side_effect=[mock_sessions, mock_windows]):
            result = _handler()(format="detailed")
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"

    def test_ac2_invalid_format_rejected(self):
        # AC: format が "minimal"/"detailed" 以外の値はエラー envelope を返す
        # RED: 実装前は ImportError → FAIL
        result = _handler()(format="unknown")
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert result.get("ok") is False, (
            f"無効な format='unknown' で ok=True になっている: {result}"
        )

    def test_ac2_session_param_filters_by_session(self):
        # AC: session 指定時は指定セッションのウィンドウのみ取得する
        # RED: 実装前は ImportError → FAIL
        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_windows) as mock_run:
            result = _handler()(session="main", format="minimal")

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        # session 指定時は list-sessions を呼ばない（list-windows -t <session> のみ）
        # subprocess.run の呼び出し引数に "main" が含まれていること
        assert mock_run.called, "subprocess.run が呼ばれていない"


# ===========================================================================
# AC3: 戻り値スキーマ
# ===========================================================================


class TestAC3ReturnSchema:
    """AC3: 戻り値 {ok, windows: [{name, index, session, active, panes_count, ...}], error}。"""

    def test_ac3_success_schema_top_level_keys(self):
        # AC: ok=True 時の戻り値スキーマ検証
        # RED: 実装前は ImportError or assert FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        with mock.patch("subprocess.run", side_effect=[mock_sessions, mock_windows]):
            result = _handler()(format="minimal")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        assert "windows" in result, f"windows キーがない: {result}"
        assert isinstance(result["windows"], list), (
            f"windows が list でない: {type(result['windows'])}"
        )

    def test_ac3_window_entry_has_required_fields(self):
        # AC: windows リスト内の各エントリに必須フィールドが存在する
        # RED: 実装前は ImportError or assert FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        # format: name:index:active:panes_count
        mock_windows.stdout = "editor:0:1:2\n"
        mock_windows.stderr = ""

        with mock.patch("subprocess.run", side_effect=[mock_sessions, mock_windows]):
            result = _handler()(format="minimal")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        windows = result.get("windows", [])
        assert len(windows) >= 1, f"windows リストが空: {result}"

        entry = windows[0]
        assert "name" in entry, f"name フィールドがない: {entry}"
        assert "index" in entry, f"index フィールドがない: {entry}"
        assert "session" in entry, f"session フィールドがない: {entry}"
        assert "active" in entry, f"active フィールドがない: {entry}"

    def test_ac3_window_entry_types(self):
        # AC: windows エントリのフィールド型が正しい
        # RED: 実装前は ImportError or assert FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:3\n"
        mock_windows.stderr = ""

        with mock.patch("subprocess.run", side_effect=[mock_sessions, mock_windows]):
            result = _handler()(format="minimal")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        windows = result.get("windows", [])
        assert len(windows) >= 1, f"windows リストが空: {result}"

        entry = windows[0]
        assert isinstance(entry.get("name"), str), (
            f"name が str でない: {type(entry.get('name'))}"
        )
        assert isinstance(entry.get("index"), int), (
            f"index が int でない: {type(entry.get('index'))}"
        )
        assert isinstance(entry.get("session"), str), (
            f"session が str でない: {type(entry.get('session'))}"
        )
        assert isinstance(entry.get("active"), bool), (
            f"active が bool でない: {type(entry.get('active'))}"
        )

    def test_ac3_detailed_format_includes_panes_count(self):
        # AC: format="detailed" 時は panes_count フィールドが存在する
        # RED: 実装前は ImportError or assert FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:4\n"
        mock_windows.stderr = ""

        with mock.patch("subprocess.run", side_effect=[mock_sessions, mock_windows]):
            result = _handler()(format="detailed")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        windows = result.get("windows", [])
        assert len(windows) >= 1, f"windows リストが空: {result}"

        entry = windows[0]
        assert "panes_count" in entry, (
            f"detailed format で panes_count フィールドがない: {entry}"
        )
        assert isinstance(entry.get("panes_count"), int), (
            f"panes_count が int でない: {type(entry.get('panes_count'))}"
        )

    def test_ac3_error_envelope_on_subprocess_failure(self):
        # AC: subprocess 失敗時は ok=False + error フィールドを含む
        # RED: 実装前は ImportError or assert FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_result.stderr = "no server running"

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(format="minimal")

        assert result.get("ok") is False, f"subprocess 失敗で ok=True: {result}"
        assert "error" in result, f"error フィールドがない: {result}"

    def test_ac3_empty_session_returns_empty_windows_list(self):
        # AC: セッションが存在しない場合は windows=[] を返す
        # RED: 実装前は ImportError or assert FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = ""
        mock_sessions.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_sessions):
            result = _handler()(format="minimal")

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert result.get("ok") is True, f"空セッションで ok=False: {result}"
        assert result.get("windows") == [], (
            f"空セッションで windows が空リストでない: {result.get('windows')}"
        )

    def test_ac3_multiple_sessions_aggregate_windows(self):
        # AC: 複数セッション時は全ウィンドウを集約する
        # RED: 実装前は ImportError or assert FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\ndev\n"
        mock_sessions.stderr = ""

        mock_windows_main = mock.MagicMock()
        mock_windows_main.returncode = 0
        mock_windows_main.stdout = "editor:0:1:1\n"
        mock_windows_main.stderr = ""

        mock_windows_dev = mock.MagicMock()
        mock_windows_dev.returncode = 0
        mock_windows_dev.stdout = "tests:0:0:2\n"
        mock_windows_dev.stderr = ""

        with mock.patch(
            "subprocess.run",
            side_effect=[mock_sessions, mock_windows_main, mock_windows_dev]
        ):
            result = _handler()(format="minimal")

        assert result.get("ok") is True, f"ok が True でない: {result}"
        windows = result.get("windows", [])
        assert len(windows) >= 2, (
            f"複数セッションのウィンドウが集約されていない: windows={windows}"
        )


# ===========================================================================
# AC4: tmux list-sessions と list-windows -F 両方サポート
# ===========================================================================


class TestAC4TmuxCommands:
    """AC4: tmux list-sessions でセッション一覧、list-windows -F でウィンドウ取得。"""

    def test_ac4_calls_list_sessions_when_no_session_specified(self):
        # AC: session 省略時は list-sessions を呼ぶ
        # RED: 実装前は ImportError → FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = ""
        mock_windows.stderr = ""

        calls = []
        def fake_run(cmd, **kwargs):
            calls.append(cmd)
            if "list-sessions" in cmd:
                return mock_sessions
            return mock_windows

        with mock.patch("subprocess.run", side_effect=fake_run):
            _handler()(format="minimal")

        list_sessions_calls = [c for c in calls if "list-sessions" in c]
        assert len(list_sessions_calls) >= 1, (
            "session 省略時に list-sessions が呼ばれていない (AC4 未実装)"
        )

    def test_ac4_calls_list_windows_with_format_flag(self):
        # AC: list-windows -F フォーマット指定で呼ぶ
        # RED: 実装前は ImportError → FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        calls = []
        def fake_run(cmd, **kwargs):
            calls.append(cmd)
            if "list-sessions" in cmd:
                return mock_sessions
            return mock_windows

        with mock.patch("subprocess.run", side_effect=fake_run):
            _handler()(format="minimal")

        list_windows_calls = [c for c in calls if "list-windows" in c]
        assert len(list_windows_calls) >= 1, (
            "list-windows が呼ばれていない (AC4 未実装)"
        )
        # -F フラグが含まれていること
        lw_cmd = list_windows_calls[0]
        assert "-F" in lw_cmd, (
            f"list-windows に -F フラグがない: {lw_cmd}"
        )

    def test_ac4_session_specified_skips_list_sessions(self):
        # AC: session 指定時は list-sessions を呼ばず、直接 list-windows -t <session> を呼ぶ
        # RED: 実装前は ImportError → FAIL
        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        calls = []
        def fake_run(cmd, **kwargs):
            calls.append(cmd)
            return mock_windows

        with mock.patch("subprocess.run", side_effect=fake_run):
            _handler()(session="main", format="minimal")

        list_sessions_calls = [c for c in calls if "list-sessions" in c]
        assert len(list_sessions_calls) == 0, (
            f"session 指定時に list-sessions が呼ばれている（不要）: {list_sessions_calls}"
        )

    def test_ac4_list_windows_includes_session_target(self):
        # AC: session 指定時の list-windows に -t <session> が含まれる
        # RED: 実装前は ImportError → FAIL
        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        calls = []
        def fake_run(cmd, **kwargs):
            calls.append(cmd)
            return mock_windows

        with mock.patch("subprocess.run", side_effect=fake_run):
            _handler()(session="main", format="minimal")

        assert len(calls) >= 1, "subprocess.run が呼ばれていない"
        lw_cmd = calls[0]
        assert "list-windows" in lw_cmd, f"list-windows が呼ばれていない: {lw_cmd}"
        assert "main" in lw_cmd, (
            f"list-windows コマンドにセッション名 'main' が含まれていない: {lw_cmd}"
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

        with mock.patch("subprocess.run", side_effect=Exception("unexpected error")):
            try:
                result = handler(format="minimal")
            except Exception as exc:  # noqa: BLE001
                pytest.fail(
                    f"twl_list_windows_handler が例外を raise した（shadow mode 違反 AC5）: {exc}"
                )
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
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
                result = _handler()(format="minimal")
            except Exception as exc:  # noqa: BLE001
                pytest.fail(
                    f"TimeoutExpired で例外が伝播した（shadow mode 違反 AC5）: {exc}"
                )
        assert isinstance(result, dict)
        assert result.get("ok") is False

    def test_ac5_shadow_mode_does_not_affect_existing_tool(self):
        # AC: list_windows の失敗が capture_pane に影響しない（独立性）
        # RED: 実装前は ImportError → FAIL
        from twl.mcp_server.tools import twl_capture_pane_handler  # noqa: PLC0415

        # まず list_windows を強制失敗させる
        with mock.patch("subprocess.run", side_effect=Exception("list_windows failed")):
            result_list = _handler()(format="minimal")
        assert result_list.get("ok") is False

        # その後 capture_pane が正常動作することを確認
        mock_pane = mock.MagicMock()
        mock_pane.returncode = 0
        mock_pane.stdout = "some output\n"
        mock_pane.stderr = ""

        with mock.patch("subprocess.run", return_value=mock_pane):
            result_pane = twl_capture_pane_handler(window_name="test-window", mode="raw")

        assert result_pane.get("ok") is True, (
            f"list_windows 失敗後に capture_pane が動作しない（AC5 shadow mode 分離違反）: {result_pane}"
        )


# ===========================================================================
# AC6: AT 非依存性（tmux 実セッション非依存）
# ===========================================================================


class TestAC6ATIndependence:
    """AC6: AT 非依存性 — 自動テストが tmux 実セッションに依存しないこと。"""

    def test_ac6_handler_works_with_mocked_subprocess(self):
        # AC: subprocess を mock すればテストが tmux 実セッション不要で動作する
        # RED: 実装前は ImportError → FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        with mock.patch(
            "subprocess.run",
            side_effect=[mock_sessions, mock_windows]
        ) as mock_run:
            result = _handler()(format="minimal")

        assert mock_run.called, "subprocess.run が呼ばれていない（mock が機能していない）"
        assert result.get("ok") is True, f"mock 経由で ok=False: {result}"

    def test_ac6_no_real_tmux_required_for_error_paths(self):
        # AC: エラーパス（セッション不在等）も tmux 実セッション不要でテスト可能
        # RED: 実装前は ImportError → FAIL
        mock_result = mock.MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_result.stderr = "no server running on /tmp/tmux-1000/default"

        with mock.patch("subprocess.run", return_value=mock_result):
            result = _handler()(format="minimal")

        assert result.get("ok") is False, (
            f"サーバー不在シミュレーションで ok=True: {result}"
        )

    def test_ac6_handler_has_no_global_tmux_side_effects(self):
        # AC: handler をインポートしただけで tmux コマンドが実行されない
        # RED: 実装前は ImportError → FAIL
        with mock.patch("subprocess.run") as mock_run:
            # import だけ行う（呼び出しはしない）
            from twl.mcp_server.tools import twl_list_windows_handler  # noqa: F401
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
        mock_sessions1 = mock.MagicMock()
        mock_sessions1.returncode = 0
        mock_sessions1.stdout = "sessionA\n"
        mock_sessions1.stderr = ""

        mock_windows1 = mock.MagicMock()
        mock_windows1.returncode = 0
        mock_windows1.stdout = "winA:0:1:1\n"
        mock_windows1.stderr = ""

        mock_sessions2 = mock.MagicMock()
        mock_sessions2.returncode = 0
        mock_sessions2.stdout = "sessionB\n"
        mock_sessions2.stderr = ""

        mock_windows2 = mock.MagicMock()
        mock_windows2.returncode = 0
        mock_windows2.stdout = "winB:0:0:2\n"
        mock_windows2.stderr = ""

        handler = _handler()

        with mock.patch(
            "subprocess.run",
            side_effect=[mock_sessions1, mock_windows1]
        ):
            result1 = handler(format="minimal")

        with mock.patch(
            "subprocess.run",
            side_effect=[mock_sessions2, mock_windows2]
        ):
            result2 = handler(format="minimal")

        assert result1.get("ok") is True, f"1回目呼び出し失敗: {result1}"
        assert result2.get("ok") is True, f"2回目呼び出し失敗: {result2}"
        # 各呼び出しが独立していること（状態持ち越しなし）
        windows1 = result1.get("windows", [])
        windows2 = result2.get("windows", [])
        assert windows1 != windows2, (
            "2回の呼び出し結果が同じ（状態持ち越し疑い AC7 違反）"
        )

    def test_ac7_handler_result_contains_no_connection_object(self):
        # AC: 戻り値 dict に接続オブジェクト/ファイルハンドラが含まれない
        # RED: 実装前は ImportError → FAIL
        mock_sessions = mock.MagicMock()
        mock_sessions.returncode = 0
        mock_sessions.stdout = "main\n"
        mock_sessions.stderr = ""

        mock_windows = mock.MagicMock()
        mock_windows.returncode = 0
        mock_windows.stdout = "editor:0:1:1\n"
        mock_windows.stderr = ""

        with mock.patch(
            "subprocess.run",
            side_effect=[mock_sessions, mock_windows]
        ):
            result = _handler()(format="minimal")

        # JSON シリアライズ可能であること（接続オブジェクト等が含まれていない証明）
        try:
            json.dumps(result)
        except (TypeError, ValueError) as exc:
            pytest.fail(
                f"戻り値が JSON シリアライズ不可（リソースオブジェクト混入疑い AC7 違反）: {exc}"
            )

    def test_ac7_mcp_tool_registered_returns_json_string(self):
        # AC: MCP tool 関数 twl_list_windows が存在する（short-lived dispatch 設計）
        # RED: 実装前は AttributeError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415

        assert hasattr(tools_mod, "twl_list_windows"), (
            "twl_list_windows が tools モジュールに存在しない (AC7 MCP tool 未実装)"
        )
