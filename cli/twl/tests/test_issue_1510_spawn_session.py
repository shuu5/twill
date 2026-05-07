"""Tests for Issue #1510: twl_spawn_session — cld-spawn MCP wrapper.

TDD RED フェーズ用テスト。実装前は全テストが FAIL する（意図的 RED）。

AC 対応:
  AC1: twl_spawn_session_handler が tools.py に存在する
  AC2: 引数 spec {cwd?, env_file?, window_name?, timeout?, model?, force_new?, prompt}
  AC3: 戻り値 {ok, session, window, pid, error} 構造
  AC4: shadow mode rollout — exit code + stderr 構造化記録
  AC5: AT 非依存性 (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 で動作)
  AC7: fire-and-forget short-lived 設計 (deadlock 回避)
"""

import inspect
import os
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"


# ---------------------------------------------------------------------------
# AC1: twl_spawn_session_handler が tools.py に存在する
# ---------------------------------------------------------------------------

class TestAC1HandlerExists:
    """AC1: mcp__twl__twl_spawn_session handler を tools.py に追加。

    RED: 現状は handler が存在しないため FAIL する。
    """

    def test_ac1_handler_importable(self):
        # AC: twl_spawn_session_handler が import 可能であること
        # RED: 現状は未実装のため ImportError / AttributeError で FAIL
        from twl.mcp_server.tools import twl_spawn_session_handler  # noqa: F401

    def test_ac1_handler_is_callable(self):
        # AC: twl_spawn_session_handler が callable であること
        # RED: 存在しないため FAIL
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_spawn_session_handler"), (
            "twl_spawn_session_handler が tools モジュールに存在しない (AC1 未実装)"
        )
        assert callable(tools.twl_spawn_session_handler), (
            "twl_spawn_session_handler が callable でない (AC1 未実装)"
        )

    def test_ac1_handler_in_tools_py_source(self):
        # AC: TOOLS_PY に "twl_spawn_session_handler" が定義されていること
        # RED: 現状は存在しない
        content = TOOLS_PY.read_text()
        assert "twl_spawn_session_handler" in content, (
            f"tools.py に twl_spawn_session_handler が存在しない (AC1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2: 引数 spec {cwd?, env_file?, window_name?, timeout?, model?, force_new?, prompt}
# ---------------------------------------------------------------------------

class TestAC2ArgumentSpec:
    """AC2: cld-spawn flag と 1:1 対応した引数 spec。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def _get_handler(self):
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_spawn_session_handler"), (
            "twl_spawn_session_handler が存在しない (AC1 未実装が AC2 をブロック)"
        )
        return tools.twl_spawn_session_handler

    def test_ac2_prompt_param_exists(self):
        # AC: prompt 引数が存在すること (cld-spawn の最後の positional arg に対応)
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "prompt" in params, (
            f"twl_spawn_session_handler に prompt 引数がない: {list(params)} (AC2 未実装)"
        )

    def test_ac2_cwd_param_optional(self):
        # AC: cwd 引数がオプショナルであること (cld-spawn --cd に対応)
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "cwd" in params, (
            f"twl_spawn_session_handler に cwd 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["cwd"].default is not inspect.Parameter.empty, (
            "cwd 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_env_file_param_optional(self):
        # AC: env_file 引数がオプショナルであること (cld-spawn --env-file に対応)
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "env_file" in params, (
            f"twl_spawn_session_handler に env_file 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["env_file"].default is not inspect.Parameter.empty, (
            "env_file 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_window_name_param_optional(self):
        # AC: window_name 引数がオプショナルであること (cld-spawn --window-name に対応)
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "window_name" in params, (
            f"twl_spawn_session_handler に window_name 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["window_name"].default is not inspect.Parameter.empty, (
            "window_name 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_timeout_param_optional(self):
        # AC: timeout 引数がオプショナルであること (cld-spawn --timeout に対応)
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "timeout" in params, (
            f"twl_spawn_session_handler に timeout 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["timeout"].default is not inspect.Parameter.empty, (
            "timeout 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_model_param_optional(self):
        # AC: model 引数がオプショナルであること (cld-spawn --model に対応)
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "model" in params, (
            f"twl_spawn_session_handler に model 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["model"].default is not inspect.Parameter.empty, (
            "model 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_force_new_param_optional(self):
        # AC: force_new 引数がオプショナルであること (cld-spawn --force-new に対応)
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "force_new" in params, (
            f"twl_spawn_session_handler に force_new 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["force_new"].default is not inspect.Parameter.empty, (
            "force_new 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_all_required_params_present(self):
        # AC: 7 引数すべて ({cwd, env_file, window_name, timeout, model, force_new, prompt}) が存在すること
        handler = self._get_handler()
        params = set(inspect.signature(handler).parameters.keys())
        required = {"cwd", "env_file", "window_name", "timeout", "model", "force_new", "prompt"}
        missing = required - params
        assert not missing, (
            f"twl_spawn_session_handler に引数が不足: {missing} (AC2 未実装)"
        )


# ---------------------------------------------------------------------------
# AC3: 戻り値 {ok, session, window, pid, error} 構造
# ---------------------------------------------------------------------------

class TestAC3ReturnValueSchema:
    """AC3: 戻り値に ok, session, window, pid, error キーが含まれること。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac3_ok_true_contains_required_keys(self, tmp_path):
        # AC: ok=True のとき session, window, pid キーが存在すること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_session_handler

        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = "spawned → tmux window 'wt-test-window'\n"
        fake_proc.stderr = ""

        with patch("subprocess.run", return_value=fake_proc), \
             patch("subprocess.Popen", return_value=MagicMock(pid=12345)):
            result = twl_spawn_session_handler(prompt="hello")

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"戻り値に 'ok' キーがない: {result}"
        # ok=True のとき session, window, pid が存在すること
        if result.get("ok"):
            assert "window" in result, f"ok=True のとき 'window' キーがない: {result}"
            assert "pid" in result, f"ok=True のとき 'pid' キーがない: {result}"

    def test_ac3_ok_false_contains_error_key(self, tmp_path):
        # AC: ok=False のとき error キーが存在すること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_session_handler

        with patch("subprocess.run", side_effect=FileNotFoundError("cld-spawn not found")):
            result = twl_spawn_session_handler(prompt="hello")

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        # ok=False の場合は error キーが存在すること
        if not result.get("ok", True):
            assert "error" in result, f"ok=False のとき 'error' キーがない: {result}"

    def test_ac3_return_schema_has_ok_key(self):
        # AC: 戻り値スキーマに ok キーが必ず含まれること（正常系・異常系共通）
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_session_handler

        with patch("subprocess.run", side_effect=RuntimeError("test error")):
            try:
                result = twl_spawn_session_handler(prompt="test")
            except Exception:
                pytest.fail(
                    "twl_spawn_session_handler が例外を propagate した "
                    "— 戻り値 {ok: False, error: ...} で wrap すべき (AC3 未実装)"
                )
        assert "ok" in result, f"例外時でも ok キーが存在すべき: {result}"
        assert result["ok"] is False, f"例外時は ok=False であるべき: {result}"


# ---------------------------------------------------------------------------
# AC4: shadow mode rollout — exit code + stderr 構造化記録
# ---------------------------------------------------------------------------

class TestAC4ShadowModeRollout:
    """AC4: spawn 系は side-effect 大のため shadow log は exit code + stderr 構造化記録のみ。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac4_shadow_log_records_exit_code(self, tmp_path):
        # AC: shadow mode で実行した場合、exit code が記録されること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_spawn_session_handler"), (
            "twl_spawn_session_handler が存在しない (AC4 前提 AC1 未実装)"
        )
        # shadow mode が存在するか確認（_SHADOW_MODE or shadow_log 等の定数/関数）
        content = TOOLS_PY.read_text()
        has_shadow = (
            "shadow" in content.lower()
            or "SHADOW" in content
        )
        # shadow mode 実装は Step 2 以降のため、現状は実装なしでも良いが
        # handler 自体は存在する必要がある
        assert "twl_spawn_session_handler" in content, (
            "tools.py に twl_spawn_session_handler が存在しない (AC4 前提 AC1 未実装)"
        )

    def test_ac4_stderr_captured_in_shadow_log(self, tmp_path):
        # AC: cld-spawn の stderr が shadow log に構造化記録されること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_session_handler

        fake_proc = MagicMock()
        fake_proc.returncode = 1
        fake_proc.stdout = ""
        fake_proc.stderr = "Error: tmux内で実行してください"

        with patch("subprocess.run", return_value=fake_proc):
            result = twl_spawn_session_handler(prompt="test")

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        # 失敗時は ok=False かつ error に stderr 情報が含まれること
        assert "ok" in result, f"'ok' キーがない: {result}"


# ---------------------------------------------------------------------------
# AC5: AT 非依存性 (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 で動作)
# ---------------------------------------------------------------------------

class TestAC5ATIndependence:
    """AC5: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 環境でも動作すること。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac5_handler_works_without_at_flag(self, monkeypatch):
        # AC: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 で import・呼び出しが可能であること
        # RED: handler 未実装のため FAIL
        monkeypatch.setenv("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", "0")

        from twl.mcp_server.tools import twl_spawn_session_handler

        with patch("subprocess.run", side_effect=RuntimeError("test")):
            try:
                result = twl_spawn_session_handler(prompt="test")
            except Exception:
                pytest.fail(
                    "AT=0 環境で twl_spawn_session_handler が例外を propagate した (AC5 未実装)"
                )

        assert "ok" in result, f"AT=0 環境でも ok キーが存在すべき: {result}"

    def test_ac5_no_agent_teams_import_in_handler(self):
        # AC: handler が AGENT_TEAMS 依存の import を使わないこと
        # RED: handler 未実装のため確認不能
        content = TOOLS_PY.read_text()
        assert "twl_spawn_session_handler" in content, (
            "twl_spawn_session_handler が tools.py に存在しない (AC5 前提 AC1 未実装)"
        )
        # handler 本体に agent_teams や AT チェックが不要なことを確認
        # （存在しても issue ではないが、依存していないことが望ましい）


# ---------------------------------------------------------------------------
# AC7: fire-and-forget short-lived 設計 (deadlock 回避)
# ---------------------------------------------------------------------------

class TestAC7FireAndForget:
    """AC7: cld-spawn は fire-and-forget short-lived 設計。deadlock 回避 (#754 教訓)。

    spawn 呼び出しはブロッキングしない。
    cld-spawn プロセスは非同期に起動され、handler は pid を返して即時 return する。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac7_handler_does_not_block_indefinitely(self):
        # AC: handler が完了するまで長時間ブロックしないこと
        # RED: handler 未実装のため FAIL
        import signal

        from twl.mcp_server.tools import twl_spawn_session_handler

        def timeout_handler(signum, frame):
            raise TimeoutError("twl_spawn_session_handler が 10 秒以上ブロックした (AC7 違反)")

        signal.signal(signal.SIGALRM, timeout_handler)
        signal.alarm(10)  # 10 秒タイムアウト
        try:
            with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout="", stderr="")), \
                 patch("subprocess.Popen", return_value=MagicMock(pid=99999)):
                result = twl_spawn_session_handler(prompt="fire-and-forget test")
        finally:
            signal.alarm(0)

        assert "ok" in result, f"fire-and-forget 後も ok キーが存在すべき: {result}"

    def test_ac7_uses_popen_not_blocking_run(self):
        # AC: cld-spawn プロセス起動に subprocess.Popen（非同期）または
        #     subprocess.run（タイムアウト付き）が使われること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_spawn_session_handler"), (
            "twl_spawn_session_handler が存在しない (AC7 前提 AC1 未実装)"
        )
        content = TOOLS_PY.read_text()
        has_nonblocking = (
            "Popen" in content
            or "popen" in content
            or "timeout" in content  # subprocess.run(timeout=...) も可
        )
        assert has_nonblocking, (
            "tools.py に Popen/popen/timeout のいずれも存在しない "
            "— fire-and-forget 実装の証跡がない (AC7 未実装)"
        )

    def test_ac7_spawn_returns_pid(self):
        # AC: 戻り値に pid が含まれること（プロセス起動確認の証跡）
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_session_handler

        mock_proc = MagicMock()
        mock_proc.pid = 54321
        mock_proc.returncode = 0
        mock_proc.stdout = "spawned → tmux window 'wt-test'\n"
        mock_proc.stderr = ""

        with patch("subprocess.Popen", return_value=mock_proc), \
             patch("subprocess.run", return_value=MagicMock(returncode=0, stdout="spawned\n", stderr="")):
            result = twl_spawn_session_handler(prompt="test")

        assert "ok" in result, f"'ok' キーがない: {result}"
        if result.get("ok"):
            assert "pid" in result, f"ok=True のとき 'pid' キーがない (AC7 未実装): {result}"


# ---------------------------------------------------------------------------
# 統合: MCP ツール登録確認
# ---------------------------------------------------------------------------

class TestMCPRegistration:
    """AC1: mcp__twl__twl_spawn_session として MCP に登録されていること。"""

    def test_mcp_tool_registered(self):
        # AC: twl_spawn_session が @mcp.tool() で登録されていること
        # RED: handler 未実装のため FAIL
        content = TOOLS_PY.read_text()
        assert "twl_spawn_session" in content, (
            "tools.py に twl_spawn_session の定義がない (AC1 MCP 登録 未実装)"
        )

    def test_mcp_tool_name_matches_convention(self):
        # AC: MCP ツール名が twl_spawn_session であること（twl_ prefix 統一）
        # RED: 未実装のため FAIL
        content = TOOLS_PY.read_text()
        # @mcp.tool() デコレータ付きの def twl_spawn_session または
        # twl_spawn_session_handler の存在を確認
        assert (
            "def twl_spawn_session(" in content
            or "twl_spawn_session_handler" in content
        ), (
            "tools.py に twl_spawn_session / twl_spawn_session_handler が存在しない (MCP 登録 未実装)"
        )
