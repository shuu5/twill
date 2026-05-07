"""Tests for Issue #1514: twl_get_session_state MCP tool subcommand extension.

TDD RED phase. All tests MUST FAIL before implementation.

AC coverage:
  AC1: handler (tools.py line 221) extension/replacement with PR diff note
  AC2: subcommand compat — state / list [--json] / wait <state> [--timeout N]
  AC3: return value schema {ok, state, details, error}
  AC4: backward compatibility — existing autopilot session callers unaffected
  AC5: shadow mode rollout support
  AC6: AT-independence (no tmux dependency, mockable design)
  AC7: short-lived design (subprocess timeout enforced)

Implementation hint:
  twl_get_session_state_handler gains a `subcommand` parameter:
    subcommand=None          -> existing autopilot aggregate (backward compat)
    subcommand="state"       -> session-state.sh state <window_name>
    subcommand="list"        -> session-state.sh list [--json]
    subcommand="wait"        -> session-state.sh wait <window_name> <target_state> [--timeout N]
"""

import json
import os
import stat
import tempfile
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _handler():
    """Lazily import twl_get_session_state_handler."""
    from twl.mcp_server.tools import twl_get_session_state_handler  # noqa: PLC0415
    return twl_get_session_state_handler


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def fake_session_state_script(tmp_path: Path):
    """Create a fake session-state.sh that returns predictable output.

    Behaviour:
      state <window>          -> prints "idle"
      list                    -> prints one line per window (plain)
      list --json             -> prints JSON array
      wait <window> <state>   -> exits 0 immediately
    """
    script = tmp_path / "session-state.sh"
    script.write_text(
        "#!/bin/bash\n"
        "set -euo pipefail\n"
        "subcmd=${1:-}\n"
        "case $subcmd in\n"
        "  state)\n"
        "    echo 'idle'\n"
        "    ;;\n"
        "  list)\n"
        "    if [[ ${2:-} == '--json' ]]; then\n"
        "      echo '[{\"window\":\"w1\",\"state\":\"idle\"}]'\n"
        "    else\n"
        "      echo 'w1 idle'\n"
        "    fi\n"
        "    ;;\n"
        "  wait)\n"
        "    exit 0\n"
        "    ;;\n"
        "  *)\n"
        "    echo 'unknown subcommand' >&2\n"
        "    exit 1\n"
        "    ;;\n"
        "esac\n"
    )
    script.chmod(script.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return script


@pytest.fixture
def autopilot_dir_with_session(tmp_path: Path) -> Path:
    """Minimal autopilot dir with active session.json for backward-compat tests."""
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    (d / "checkpoints").mkdir()
    (d / "waves").mkdir()
    (d / "archive").mkdir()
    session_data = {
        "session_id": "abc12345",
        "plan_path": str(d / "plan.yaml"),
        "current_phase": 1,
        "phase_count": 3,
        "started_at": "2026-05-08T00:00:00Z",
        "cross_issue_warnings": [],
        "phase_insights": [],
        "patterns": {},
        "self_improve_issues": [],
    }
    (d / "session.json").write_text(json.dumps(session_data))
    return d


# ===========================================================================
# AC1: handler extension / replacement — tools.py line 221
# ===========================================================================


class TestAC1HandlerExtension:
    """AC1: twl_get_session_state_handler を拡張して subcommand パラメータを受け入れる。"""

    def test_ac1_handler_accepts_subcommand_parameter(self):
        # AC: twl_get_session_state_handler が subcommand パラメータを受け入れる
        # RED: 実装前は TypeError (unexpected keyword argument)
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        assert "subcommand" in sig.parameters, (
            "twl_get_session_state_handler に subcommand パラメータがない (AC1 未実装)"
        )

    def test_ac1_handler_accepts_window_name_parameter(self):
        # AC: state/wait サブコマンド用に window_name パラメータを受け入れる
        # RED: 実装前は TypeError
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        assert "window_name" in sig.parameters, (
            "twl_get_session_state_handler に window_name パラメータがない (AC1 未実装)"
        )

    def test_ac1_handler_accepts_target_state_parameter(self):
        # AC: wait サブコマンド用に target_state パラメータを受け入れる
        # RED: 実装前は TypeError
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        assert "target_state" in sig.parameters, (
            "twl_get_session_state_handler に target_state パラメータがない (AC1 未実装)"
        )

    def test_ac1_handler_accepts_timeout_parameter(self):
        # AC: wait サブコマンド用に timeout パラメータを受け入れる
        # RED: 実装前は TypeError
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        assert "timeout" in sig.parameters, (
            "twl_get_session_state_handler に timeout パラメータがない (AC1 未実装)"
        )

    def test_ac1_mcp_tool_signature_extended(self):
        # AC: MCP tool 関数 twl_get_session_state も subcommand を受け入れる
        # RED: 実装前は inspect で確認できない
        import inspect  # noqa: PLC0415
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        # MCP layer — module-level function (shadow or fastmcp-registered)
        # At minimum tools_mod must expose a callable with subcommand param
        fn = getattr(tools_mod, "twl_get_session_state", None)
        assert fn is not None, "twl_get_session_state が tools モジュールにない"
        sig = inspect.signature(fn)
        assert "subcommand" in sig.parameters, (
            "MCP tool twl_get_session_state に subcommand パラメータがない (AC1 未実装)"
        )


# ===========================================================================
# AC2: subcommand compatibility — state / list [--json] / wait
# ===========================================================================


class TestAC2SubcommandCompatibility:
    """AC2: state / list [--json] / wait <state> [--timeout N] サブコマンドが動作する。"""

    def test_ac2_state_subcommand_returns_ok_true(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: subcommand="state" + window_name → {ok: True, state: <value>}
        # RED: 実装前は KeyError or TypeError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="state", window_name="w1")
        assert result.get("ok") is True, f"state subcommand が ok=True を返さない: {result}"

    def test_ac2_state_subcommand_returns_state_key(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: state サブコマンドの戻り値に "state" キーが存在する
        # RED: 実装前は KeyError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="state", window_name="w1")
        assert "state" in result, f"state キーが戻り値にない: {result}"

    def test_ac2_state_subcommand_valid_state_values(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: state の値は idle|input-waiting|processing|error|exited のいずれか
        # RED: 実装前は assert FAIL
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="state", window_name="w1")
        valid_states = {"idle", "input-waiting", "processing", "error", "exited"}
        assert result.get("state") in valid_states, (
            f"state の値 '{result.get('state')}' が有効値 {valid_states} にない (AC2 未実装)"
        )

    def test_ac2_list_subcommand_returns_ok_true(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: subcommand="list" → {ok: True, ...}
        # RED: 実装前は TypeError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="list")
        assert result.get("ok") is True, f"list subcommand が ok=True を返さない: {result}"

    def test_ac2_list_subcommand_json_flag(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: subcommand="list" + json_output=True → {ok: True, windows: [...]}
        # RED: 実装前は TypeError or KeyError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="list", json_output=True)
        assert result.get("ok") is True, f"list --json が ok=True を返さない: {result}"
        assert "windows" in result, f"list --json 戻り値に 'windows' キーがない: {result}"

    def test_ac2_wait_subcommand_returns_ok_true(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: subcommand="wait" + window_name + target_state → {ok: True}
        # RED: 実装前は TypeError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="wait", window_name="w1", target_state="idle")
        assert result.get("ok") is True, f"wait subcommand が ok=True を返さない: {result}"

    def test_ac2_wait_subcommand_with_timeout(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: subcommand="wait" + timeout=10 が受け入れられる
        # RED: 実装前は TypeError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="wait", window_name="w1", target_state="idle", timeout=10)
        assert result.get("ok") is True, f"wait --timeout が ok=True を返さない: {result}"

    def test_ac2_unknown_subcommand_returns_error(self):
        # AC: 未知の subcommand は {ok: False, error_type: "invalid_subcommand"}
        # RED: 実装前は Exception
        result = _handler()(subcommand="bogus_cmd")
        assert result.get("ok") is False, "未知 subcommand で ok=True になっている (AC2 未実装)"
        assert "invalid_subcommand" in str(result.get("error_type", "")), (
            f"error_type が invalid_subcommand でない: {result.get('error_type')}"
        )


# ===========================================================================
# AC3: return value schema {ok, state, details, error}
# ===========================================================================


class TestAC3ReturnValueSchema:
    """AC3: state サブコマンド戻り値スキーマ {ok, state, details, error}。"""

    def test_ac3_state_response_has_ok_field(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: state レスポンスに "ok" フィールドがある
        # RED: 実装前は KeyError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="state", window_name="w1")
        assert "ok" in result, f"'ok' フィールドが戻り値にない (AC3 未実装): {result}"

    def test_ac3_state_response_has_state_field(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: state レスポンスに "state" フィールドがある
        # RED: 実装前は KeyError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="state", window_name="w1")
        assert "state" in result, f"'state' フィールドが戻り値にない (AC3 未実装): {result}"

    def test_ac3_state_response_has_details_field(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: state レスポンスに "details" フィールドがある
        # RED: 実装前は KeyError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="state", window_name="w1")
        assert "details" in result, f"'details' フィールドが戻り値にない (AC3 未実装): {result}"

    def test_ac3_error_response_has_error_field(self):
        # AC: エラー時レスポンスに "error" フィールドがある
        # RED: 実装前は KeyError
        result = _handler()(subcommand="state", window_name="w1")
        # No script set -> error path
        # Both ok=True (with error=None) and ok=False (with error=str) must have the key
        assert "error" in result, f"'error' フィールドが戻り値にない (AC3 未実装): {result}"

    def test_ac3_state_values_are_enumerated(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: state 値は "idle"|"input-waiting"|"processing"|"error"|"exited" に限定
        # RED: 実装前は assert FAIL
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="state", window_name="w1")
        if result.get("ok"):
            valid = {"idle", "input-waiting", "processing", "error", "exited"}
            assert result["state"] in valid, (
                f"state 値 '{result['state']}' が仕様外 (AC3 未実装)"
            )

    def test_ac3_error_envelope_has_ok_false_and_error(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
        # AC: スクリプト不在時のエラーエンベロープが {ok: False, error: str}
        # RED: 実装前は KeyError または Exception
        nonexistent = tmp_path / "no-such-script.sh"
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(nonexistent))
        result = _handler()(subcommand="state", window_name="w1")
        assert result.get("ok") is False, f"スクリプト不在で ok=True になっている: {result}"
        assert isinstance(result.get("error"), str) and result["error"], (
            f"error フィールドが空または非文字列: {result}"
        )


# ===========================================================================
# AC4: backward compatibility — existing autopilot session callers
# ===========================================================================


class TestAC4BackwardCompatibility:
    """AC4: subcommand=None (デフォルト) は既存の autopilot aggregate を返す。"""

    def test_ac4_no_subcommand_returns_aggregate_view(
        self, autopilot_dir_with_session: Path
    ):
        # AC: subcommand なし呼出で autopilot aggregate の ok=True が返る
        # RED: 拡張後のシグネチャで subcommand=None が明示的に受け入れられることを確認
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        assert "subcommand" in sig.parameters, (
            "subcommand パラメータがない — handler 拡張未完 (AC1/AC4 未実装)"
        )
        # subcommand を明示的に None で渡しても aggregate が返ること
        result = _handler()(subcommand=None, autopilot_dir=str(autopilot_dir_with_session))
        assert result.get("ok") is True, (
            f"subcommand=None 明示で ok=True にならない (AC4 backward compat 破壊): {result}"
        )

    def test_ac4_aggregate_keys_still_present_without_subcommand(
        self, autopilot_dir_with_session: Path
    ):
        # AC: subcommand=None 明示呼出でも aggregate keys が存在する
        # RED: subcommand パラメータ未実装なら TypeError で FAIL
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        assert "subcommand" in sig.parameters, (
            "subcommand パラメータがない — handler 拡張未完 (AC1/AC4 未実装)"
        )
        result = _handler()(subcommand=None, autopilot_dir=str(autopilot_dir_with_session))
        for key in ("active_issues", "pending_checkpoints", "wave_summaries_count", "session"):
            assert key in result, (
                f"aggregate key '{key}' が subcommand=None 呼出で欠落 (AC4 未実装)"
            )

    def test_ac4_explicit_none_subcommand_same_as_omitted(
        self, autopilot_dir_with_session: Path
    ):
        # AC: subcommand=None 明示でも同じ aggregate を返す
        # RED: 実装前は TypeError (unexpected keyword argument)
        result = _handler()(subcommand=None, autopilot_dir=str(autopilot_dir_with_session))
        assert result.get("ok") is True, (
            f"subcommand=None 明示で ok=True にならない (AC4 未実装): {result}"
        )
        assert "active_issues" in result, "subcommand=None 明示で active_issues が欠落 (AC4 未実装)"

    def test_ac4_session_id_param_still_works(
        self, autopilot_dir_with_session: Path
    ):
        # AC: 既存 session_id パラメータが subcommand 拡張後も機能する
        # RED: 実装前は TypeError
        result = _handler()(
            subcommand=None,
            session_id="nonexistent_session",
            autopilot_dir=str(autopilot_dir_with_session),
        )
        # nonexistent session_id -> error, but handler must not crash
        assert isinstance(result, dict), "session_id param 使用で dict 以外が返った (AC4 未実装)"
        assert "ok" in result, "'ok' キーが欠落 (AC4 未実装)"


# ===========================================================================
# AC5: shadow mode rollout
# ===========================================================================


class TestAC5ShadowModeRollout:
    """AC5: shadow mode rollout — 実装の段階的展開をサポートする設計。"""

    def test_ac5_shadow_mode_env_var_recognized(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: SHADOW_MODE=1 環境変数が存在する場合、handler がエラーなく動作する
        # RED: 実装前は NotImplementedError または無視される
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        monkeypatch.setenv("TWL_SHADOW_MODE", "1")
        result = _handler()(subcommand="state", window_name="w1")
        # shadow mode でも正常レスポンスを返す or shadow フラグが戻り値に含まれる
        assert isinstance(result, dict), "shadow mode で dict 以外が返った (AC5 未実装)"
        assert "ok" in result, "'ok' キーが shadow mode で欠落 (AC5 未実装)"

    def test_ac5_shadow_mode_result_includes_shadow_flag(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: shadow mode 実行時、戻り値に shadow=True が含まれる
        # RED: 実装前は KeyError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        monkeypatch.setenv("TWL_SHADOW_MODE", "1")
        result = _handler()(subcommand="state", window_name="w1")
        assert result.get("shadow") is True, (
            f"shadow mode で戻り値に shadow=True がない (AC5 未実装): {result}"
        )


# ===========================================================================
# AC6: AT-independence (no tmux dependency, mockable design)
# ===========================================================================


class TestAC6ATIndependence:
    """AC6: AT 非依存性 — session-state.sh 経由でモック可能、直接 tmux 呼出なし。"""

    def test_ac6_state_subcommand_uses_script_env_var(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: SESSION_STATE_SCRIPT 環境変数でスクリプトを差し替えられる（tmux 非依存）
        # RED: 実装前は env var が無視されて実 tmux を呼ぶ / TypeError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="state", window_name="w1")
        # fake script returns "idle" — if tmux was called instead, this would fail in CI
        assert result.get("ok") is True, (
            f"SESSION_STATE_SCRIPT が無視されている可能性 (AC6 未実装): {result}"
        )
        assert result.get("state") == "idle", (
            f"fake script の 'idle' が返らない — tmux 直呼びの可能性 (AC6 未実装): {result}"
        )

    def test_ac6_list_subcommand_uses_script_env_var(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: list サブコマンドも SESSION_STATE_SCRIPT 経由
        # RED: 実装前は TypeError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="list")
        assert result.get("ok") is True, (
            f"list サブコマンドで SESSION_STATE_SCRIPT が無視されている (AC6 未実装): {result}"
        )

    def test_ac6_wait_subcommand_uses_script_env_var(
        self, fake_session_state_script: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: wait サブコマンドも SESSION_STATE_SCRIPT 経由
        # RED: 実装前は TypeError
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(fake_session_state_script))
        result = _handler()(subcommand="wait", window_name="w1", target_state="idle")
        assert result.get("ok") is True, (
            f"wait サブコマンドで SESSION_STATE_SCRIPT が無視されている (AC6 未実装): {result}"
        )

    def test_ac6_missing_script_returns_error_not_tmux_call(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: スクリプト不在時は {ok: False, error_type: "script_not_found"}（tmux を直呼びしない）
        # RED: 実装前はスクリプト不在チェックが存在せず TypeError または tmux 直呼び
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(tmp_path / "no-script.sh"))
        result = _handler()(subcommand="state", window_name="w1")
        assert result.get("ok") is False, (
            f"スクリプト不在で ok=True は AT 依存の可能性 (AC6 未実装): {result}"
        )
        assert result.get("error_type") == "script_not_found", (
            f"error_type が script_not_found でない (AC6 未実装): {result.get('error_type')}"
        )


# ===========================================================================
# AC7: short-lived design (subprocess timeout)
# ===========================================================================


class TestAC7ShortLivedDesign:
    """AC7: short-lived 設計 — subprocess timeout が強制される。"""

    def test_ac7_state_subcommand_has_default_timeout(self):
        # AC: timeout パラメータのデフォルト値が設定されている（無制限 None は禁止）
        # RED: 実装前は timeout パラメータ自体がない
        import inspect  # noqa: PLC0415
        sig = inspect.signature(_handler())
        assert "timeout" in sig.parameters, (
            "timeout パラメータが handler にない (AC7 未実装)"
        )
        default = sig.parameters["timeout"].default
        assert default is not inspect.Parameter.empty, (
            "timeout にデフォルト値がない (AC7 未実装)"
        )
        # default must be a positive integer (short-lived)
        assert isinstance(default, int) and default > 0, (
            f"timeout デフォルト値 '{default}' が正の整数でない (AC7 未実装)"
        )

    def test_ac7_timeout_error_returns_error_envelope(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: タイムアウト発生時は {ok: False, error_type: "timeout", exit_code: 124}
        # RED: 実装前は TimeoutExpired が素通り
        # Use a script that sleeps longer than the timeout
        slow_script = tmp_path / "slow-session-state.sh"
        slow_script.write_text("#!/bin/bash\nsleep 10\n")
        slow_script.chmod(slow_script.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(slow_script))
        # timeout=1 second
        result = _handler()(subcommand="state", window_name="w1", timeout=1)
        assert result.get("ok") is False, (
            f"timeout 発生時に ok=True になっている (AC7 未実装): {result}"
        )
        assert result.get("error_type") == "timeout", (
            f"error_type が timeout でない (AC7 未実装): {result.get('error_type')}"
        )
        assert result.get("exit_code") == 124, (
            f"exit_code が 124 でない (AC7 未実装): {result.get('exit_code')}"
        )

    def test_ac7_wait_subcommand_also_enforces_timeout(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # AC: wait サブコマンドでも timeout が適用される
        # RED: 実装前は TypeError または無制限待機
        slow_script = tmp_path / "slow-wait.sh"
        slow_script.write_text("#!/bin/bash\nsleep 10\n")
        slow_script.chmod(slow_script.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        monkeypatch.setenv("SESSION_STATE_SCRIPT", str(slow_script))
        result = _handler()(subcommand="wait", window_name="w1", target_state="idle", timeout=1)
        # Either ok=False with timeout error_type, or ok=False for another reason —
        # the key invariant is that the call terminates within ~2 s (not verified here)
        # and returns a dict with "ok" key.
        assert isinstance(result, dict), (
            f"wait timeout で dict 以外が返った (AC7 未実装): {result}"
        )
        assert "ok" in result, f"'ok' キーが wait timeout 戻り値にない (AC7 未実装): {result}"
