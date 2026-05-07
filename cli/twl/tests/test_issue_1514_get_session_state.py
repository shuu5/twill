"""Tests for twl_get_session_state -- Issue #1514 AC1-AC7.

TDD RED フェーズ。実装前は全テストが FAIL する（意図的 RED）。
対象: twl_get_session_state_handler (tools.py line 221) の拡張

AC 対応:
  AC1: 既存 handler を拡張または置換（差分・置換方針を PR で明記） -- プロセス AC
  AC2: subcommand 互換 state / list [--json] / wait <state> [--timeout N]
  AC3: 戻り値 {ok, state: "idle"|"input-waiting"|"processing"|"error"|"exited", details, error}
  AC4: 既存 caller の backward compatibility
  AC5: shadow mode rollout
  AC6: AT 非依存性
  AC7: short-lived 設計
"""

import inspect
from pathlib import Path
from unittest import mock

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
SESSION_STATE_SH = (
    Path(__file__).resolve().parent.parent.parent.parent.parent
    / "plugins" / "session" / "scripts" / "session-state.sh"
)


def _handler():
    from twl.mcp_server.tools import twl_get_session_state_handler  # noqa: PLC0415
    return twl_get_session_state_handler


# ===========================================================================
# AC1: 既存 handler を拡張または置換 -- プロセス AC（PR 明記が本質）
# ===========================================================================


class TestAC1ProcessCheck:
    """AC1: 既存 handler の拡張・置換方針を確認するプロセスチェック。

    本 AC の本質は「PR で差分・置換方針を明記」というプロセス要件のため、
    テストは実装側の事前条件（handler が存在すること）を確認するにとどめる。
    """

    def test_ac1_existing_handler_still_importable(self):
        # AC: 既存 twl_get_session_state_handler が tools.py に存在し import できる
        # RED: 実装前は既存実装のままであり、拡張後の signature チェックで FAIL する想定
        # （本テストは現在の実装でも PASS するが、AC2/AC3 テストが RED になることで
        #  拡張実装の必要性を示す）
        raise NotImplementedError("AC#1 未実装 -- PR に差分・置換方針を明記してください")


# ===========================================================================
# AC2: subcommand 互換 state / list [--json] / wait <state> [--timeout N]
# ===========================================================================


class TestAC2SubcommandCompat:
    """AC2: session-state.sh の subcommand (state/list/wait) と互換性のある引数を持つ。"""

    def test_ac2_subcommand_param_exists(self):
        # AC: handler に subcommand 引数（"state" / "list" / "wait"）が存在する
        # RED: 現行 handler は session_id/autopilot_dir のみで subcommand を持たない
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "subcommand" in params, (
            "twl_get_session_state_handler に subcommand 引数がない (AC2 未実装)"
        )

    def test_ac2_window_name_param_exists(self):
        # AC: state/wait subcommand に必要な window_name 引数が存在する
        # RED: 現行 handler は window_name を持たない
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "window_name" in params, (
            "twl_get_session_state_handler に window_name 引数がない (AC2 未実装)"
        )

    def test_ac2_json_flag_param_exists(self):
        # AC: list subcommand の --json フラグに相当する json_output 引数が存在する
        # RED: 現行 handler は json_output / as_json を持たない
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "json_output" in params or "as_json" in params, (
            "twl_get_session_state_handler に json_output / as_json 引数がない (AC2 未実装)"
        )

    def test_ac2_timeout_param_exists(self):
        # AC: wait subcommand の --timeout N に相当する timeout 引数が存在する
        # RED: 現行 handler は timeout を持たない
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "timeout" in params, (
            "twl_get_session_state_handler に timeout 引数がない (AC2 未実装)"
        )

    def test_ac2_state_subcommand_calls_session_state_sh(self):
        # AC: subcommand="state" 呼び出しが session-state.sh state <window> を実行する
        # RED: 現行実装は subprocess で session-state.sh を呼ばない
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="idle\n", stderr=""
            )
            result = _handler()(subcommand="state", window_name="test-window")
        # session-state.sh が呼ばれていることを確認
        assert mock_run.called, (
            "subcommand='state' で subprocess.run が呼ばれなかった (AC2 未実装)"
        )
        call_args = mock_run.call_args
        cmd = call_args[0][0] if call_args[0] else call_args[1].get("args", [])
        cmd_str = " ".join(str(c) for c in cmd)
        assert "session-state.sh" in cmd_str or "state" in cmd_str, (
            f"session-state.sh state が呼ばれていない: {cmd_str}"
        )

    def test_ac2_list_subcommand_calls_session_state_sh(self):
        # AC: subcommand="list" 呼び出しが session-state.sh list を実行する
        # RED: 現行実装は list subcommand を持たない
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="window1\tidle\n", stderr=""
            )
            result = _handler()(subcommand="list")
        assert mock_run.called, (
            "subcommand='list' で subprocess.run が呼ばれなかった (AC2 未実装)"
        )

    def test_ac2_wait_subcommand_calls_session_state_sh(self):
        # AC: subcommand="wait" 呼び出しが session-state.sh wait <window> <state> を実行する
        # RED: 現行実装は wait subcommand を持たない
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="idle\n", stderr=""
            )
            result = _handler()(
                subcommand="wait",
                window_name="test-window",
                target_state="idle",
                timeout=10,
            )
        assert mock_run.called, (
            "subcommand='wait' で subprocess.run が呼ばれなかった (AC2 未実装)"
        )


# ===========================================================================
# AC3: 戻り値 {ok, state: "idle"|..., details, error}
# ===========================================================================


class TestAC3ReturnValueSchema:
    """AC3: 戻り値が {ok, state, details, error} スキーマに準拠する。"""

    VALID_STATES = {"idle", "input-waiting", "processing", "error", "exited"}

    def test_ac3_ok_key_exists_on_success(self):
        # AC: 成功時の戻り値に ok キーが存在する
        # RED: 現行の state subcommand は存在しないため TypeError/KeyError で FAIL
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="idle\n", stderr=""
            )
            try:
                result = _handler()(subcommand="state", window_name="test-window")
            except TypeError:
                pytest.fail("subcommand 引数が存在しない (AC3 未実装): TypeError raised")
        assert "ok" in result, (
            f"戻り値に 'ok' キーがない: {result}"
        )

    def test_ac3_state_key_exists_on_success(self):
        # AC: 成功時の戻り値に state キーが存在する
        # RED: 現行 handler は state キーを返さない（session_data を返す）
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="idle\n", stderr=""
            )
            try:
                result = _handler()(subcommand="state", window_name="test-window")
            except TypeError:
                pytest.fail("subcommand 引数が存在しない (AC3 未実装): TypeError raised")
        assert "state" in result, (
            f"戻り値に 'state' キーがない: {result}"
        )

    def test_ac3_state_value_is_valid_enum(self):
        # AC: state の値が有効な enum 値 (idle/input-waiting/processing/error/exited)
        # RED: subcommand が未実装のため FAIL
        import subprocess  # noqa: PLC0415

        for valid_state in self.VALID_STATES:
            with mock.patch("subprocess.run") as mock_run:
                mock_run.return_value = mock.Mock(
                    returncode=0, stdout=f"{valid_state}\n", stderr=""
                )
                try:
                    result = _handler()(subcommand="state", window_name="test-window")
                except TypeError:
                    pytest.fail(f"AC3 未実装 (TypeError): subcommand 引数なし")

            if result.get("ok"):
                assert result["state"] in self.VALID_STATES, (
                    f"state 値 '{result['state']}' が有効な enum 外 (AC3 未実装)"
                )

    def test_ac3_details_key_exists_on_success(self):
        # AC: 成功時の戻り値に details キーが存在する
        # RED: 現行 handler は details を返さない
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="idle\n", stderr=""
            )
            try:
                result = _handler()(subcommand="state", window_name="test-window")
            except TypeError:
                pytest.fail("subcommand 引数が存在しない (AC3 未実装): TypeError raised")
        assert "details" in result, (
            f"成功時の戻り値に 'details' キーがない: {result}"
        )

    def test_ac3_error_key_exists_on_failure(self):
        # AC: 失敗時の戻り値に error キーが存在する
        # RED: subcommand が未実装のため FAIL
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=1, stdout="", stderr="Error: window not found"
            )
            try:
                result = _handler()(subcommand="state", window_name="nonexistent-window")
            except TypeError:
                pytest.fail("subcommand 引数が存在しない (AC3 未実装): TypeError raised")
        assert result.get("ok") is False, (
            f"失敗時に ok=False でない: {result}"
        )
        assert "error" in result, (
            f"失敗時の戻り値に 'error' キーがない: {result}"
        )

    def test_ac3_invalid_state_from_script_returns_error(self):
        # AC: session-state.sh が不正な state 文字列を返した場合 ok=False にする
        # RED: subcommand が未実装のため FAIL
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="unknown-invalid-state\n", stderr=""
            )
            try:
                result = _handler()(subcommand="state", window_name="test-window")
            except TypeError:
                pytest.fail("subcommand 引数が存在しない (AC3 未実装): TypeError raised")
        assert result.get("ok") is False, (
            f"不正 state に対して ok=False でない: {result}"
        )


# ===========================================================================
# AC4: 既存 caller の backward compatibility
# ===========================================================================


class TestAC4BackwardCompat:
    """AC4: 既存 caller への破壊的変更を回避する。"""

    def test_ac4_existing_params_and_new_subcommand_coexist(self):
        # AC: session_id / autopilot_dir (既存) と subcommand (新規) が共存する
        # RED: 現行 handler は subcommand を持たないため FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        # 両方が揃っていることを確認（拡張実装でなければ FAIL）
        has_legacy = "session_id" in params or "autopilot_dir" in params
        has_new = "subcommand" in params
        assert has_legacy and has_new, (
            f"backward compat 拡張未完了: legacy={has_legacy}, new_subcommand={has_new} "
            "(AC4 未実装: session_id/autopilot_dir と subcommand が共存していない)"
        )

    def test_ac4_no_subcommand_returns_legacy_format_and_new_subcommand_works(self):
        # AC: subcommand なし（デフォルト）は legacy 形式を返し、かつ subcommand 引数も使える
        # RED: subcommand が実装されていないため、後半の subcommand 呼び出しで FAIL する
        from pathlib import Path  # noqa: PLC0415
        import tempfile  # noqa: PLC0415
        import json  # noqa: PLC0415
        import subprocess  # noqa: PLC0415

        # 前半: legacy 動作の確認
        with tempfile.TemporaryDirectory() as tmpdir:
            ap_dir = Path(tmpdir)
            session_data = {
                "session_id": "test123",
                "current_phase": 1,
                "phase_count": 3,
                "cross_issue_warnings": [],
            }
            (ap_dir / "session.json").write_text(
                json.dumps(session_data), encoding="utf-8"
            )
            legacy_result = _handler()(autopilot_dir=str(ap_dir))

        assert legacy_result.get("ok") is True, (
            f"既存の autopilot_dir 引数での呼び出しが失敗: {legacy_result}"
        )
        assert "session" in legacy_result, (
            "backward compat 破壊: 'session' キーが消えた (AC4 未実装)"
        )

        # 後半: 新規 subcommand も同一 handler で動作することの確認
        # RED: subcommand が未実装のため TypeError で FAIL する
        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0, stdout="idle\n", stderr="")
            try:
                new_result = _handler()(subcommand="state", window_name="test-window")
            except TypeError:
                pytest.fail(
                    "subcommand 引数が存在しない -- backward compat + new feature が同一 handler "
                    "で共存していない (AC4 未実装)"
                )
        assert new_result.get("ok") is True or "state" in new_result, (
            f"subcommand='state' の結果が不正: {new_result} (AC4 未実装)"
        )


# ===========================================================================
# AC5: shadow mode rollout
# ===========================================================================


class TestAC5ShadowMode:
    """AC5: shadow mode rollout の仕組みが存在する。"""

    def test_ac5_shadow_mode_env_var_or_param_exists(self):
        # AC: SHADOW_MODE 環境変数またはパラメータが参照される仕組みが実装されている
        # RED: shadow mode の実装が存在しない場合 FAIL
        import os  # noqa: PLC0415
        import subprocess  # noqa: PLC0415

        # shadow mode では実際の実行をスキップしてログのみ出す
        with mock.patch.dict(os.environ, {"TWL_SESSION_STATE_SHADOW": "1"}):
            with mock.patch("subprocess.run") as mock_run:
                mock_run.return_value = mock.Mock(
                    returncode=0, stdout="idle\n", stderr=""
                )
                try:
                    result = _handler()(subcommand="state", window_name="test-window")
                except TypeError:
                    pytest.fail("subcommand 引数が存在しない (AC5 のテスト前提条件未実装)")

        # shadow mode の結果には ok または shadow_mode フラグが含まれる
        assert "ok" in result or "shadow_mode" in result, (
            f"shadow mode 戻り値に期待するキーがない: {result} (AC5 未実装)"
        )

    def test_ac5_shadow_mode_does_not_raise(self):
        # AC: shadow mode 設定下での呼び出しが例外を投げない
        # RED: shadow mode 未実装のため TypeError 等で FAIL
        import os  # noqa: PLC0415

        with mock.patch.dict(os.environ, {"TWL_SESSION_STATE_SHADOW": "1"}):
            with mock.patch("subprocess.run") as mock_run:
                mock_run.return_value = mock.Mock(
                    returncode=0, stdout="processing\n", stderr=""
                )
                try:
                    result = _handler()(subcommand="state", window_name="test-window")
                except TypeError as e:
                    pytest.fail(f"shadow mode 呼び出しで TypeError: {e} (AC5 未実装)")
                except Exception as e:
                    pytest.fail(f"shadow mode 呼び出しで予期しない例外: {e} (AC5 未実装)")


# ===========================================================================
# AC6: AT 非依存性
# ===========================================================================


class TestAC6ATIndependence:
    """AC6: AutoPilot (AT) に非依存で動作する。"""

    def test_ac6_session_state_sh_exists_as_impl_target(self):
        # AC: session-state.sh が実装の依存先として存在する（AT 経由ではなく直接呼ぶ）
        # RED: session-state.sh が存在しない場合 FAIL（前提確認）
        assert SESSION_STATE_SH.exists(), (
            f"session-state.sh が存在しない: {SESSION_STATE_SH} "
            "(実装対象スクリプトが削除/移動された?)"
        )

    def test_ac6_no_autopilot_dir_needed_for_state_subcommand(self):
        # AC: subcommand="state" は autopilot_dir なしで動作する（AT 非依存）
        # RED: 現行実装は subcommand を持たず AT 依存のため FAIL
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="idle\n", stderr=""
            )
            try:
                # autopilot_dir を渡さない（AT 非依存）
                result = _handler()(subcommand="state", window_name="test-window")
            except TypeError as e:
                pytest.fail(
                    f"subcommand='state' 呼び出しで TypeError: {e} "
                    "(AT 非依存を意図しているが AC6 未実装)"
                )
        assert result.get("ok") is True or "state" in result, (
            f"AT 非依存の state subcommand が失敗: {result} (AC6 未実装)"
        )

    def test_ac6_no_session_json_dependency_for_state_subcommand(self):
        # AC: subcommand="state" は session.json を読まずに動作する
        # RED: 現行実装は autopilot_dir/session.json に依存するため FAIL
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout="idle\n", stderr=""
            )
            with mock.patch("pathlib.Path.read_text") as mock_read:
                try:
                    result = _handler()(subcommand="state", window_name="test-window")
                except TypeError:
                    pytest.fail("subcommand 引数が存在しない (AC6 のテスト前提条件未実装)")
            # state subcommand では session.json の read_text を呼ぶべきでない
            # (AT 非依存)
            assert not mock_read.called, (
                "subcommand='state' が session.json を読んでいる (AT 依存 -- AC6 未実装)"
            )


# ===========================================================================
# AC7: short-lived 設計
# ===========================================================================


class TestAC7ShortLivedDesign:
    """AC7: short-lived 設計（呼び出し毎にプロセスを起動して即終了する設計）。"""

    def test_ac7_subprocess_called_per_invocation(self):
        # AC: 呼び出しごとに subprocess（session-state.sh）を起動して即終了する
        # RED: daemon/長期プロセスを使う実装では fail する（subcommand 未実装でも FAIL）
        import subprocess  # noqa: PLC0415

        call_count = 0

        def counting_run(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            return mock.Mock(returncode=0, stdout="idle\n", stderr="")

        with mock.patch("subprocess.run", side_effect=counting_run):
            for _ in range(3):
                try:
                    _handler()(subcommand="state", window_name="test-window")
                except TypeError:
                    pytest.fail("subcommand 引数が存在しない (AC7 のテスト前提条件未実装)")

        assert call_count == 3, (
            f"3回呼び出しで subprocess.run が {call_count} 回しか呼ばれなかった "
            "-- short-lived 設計（呼び出し毎に新規プロセス）でない (AC7 未実装)"
        )

    def test_ac7_no_persistent_connection(self):
        # AC: クラス変数・モジュールレベルのプロセス/ソケット等の永続接続を持たない
        # RED: subcommand 実装後、永続接続が追加されていないことを確認するテスト
        # 実装前は subcommand 未実装で呼び出しが TypeError になるため FAIL させる
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0, stdout="idle\n", stderr="")
            try:
                result = _handler()(subcommand="state", window_name="test-window")
            except TypeError:
                pytest.fail(
                    "subcommand 引数が存在しない (AC7 前提条件未実装) "
                    "-- short-lived 設計検証のために subcommand が必要"
                )

        # 呼び出し後にモジュールレベルに永続接続オブジェクトが存在しない
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        persistent_attrs = [
            attr for attr in dir(tools_mod)
            if any(kw in attr.lower() for kw in ("daemon", "socket", "connection", "process"))
            and not attr.startswith("_")
        ]
        assert len(persistent_attrs) == 0, (
            f"モジュールレベルに永続接続オブジェクトが存在する: {persistent_attrs} (AC7 違反)"
        )

    def test_ac7_handler_is_stateless_function(self):
        # AC: handler が pure function として実装され、subcommand 拡張後も stateless を維持
        # RED: subcommand 未実装のため呼び出しが TypeError になり FAIL
        import subprocess  # noqa: PLC0415

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0, stdout="idle\n", stderr="")
            try:
                # subcommand 実装後に stateless であることを確認するために呼び出す
                result = _handler()(subcommand="state", window_name="test-window")
            except TypeError:
                pytest.fail(
                    "subcommand 引数が存在しない (AC7 stateless 検証のための前提条件未実装)"
                )

        # handler 自体が pure function であること
        handler = _handler()
        import types  # noqa: PLC0415
        assert isinstance(handler, (types.FunctionType, types.MethodType)), (
            f"handler が pure function でない: {type(handler)} (AC7 未実装の可能性)"
        )
