"""Tests for twl_get_budget — Issue #1515 AC1-AC8.

TDD RED フェーズ。実装前は全テストが FAIL する（意図的 RED）。
対象 handler: twl_get_budget_handler (tools.py)

AC 対応:
  AC1: handler 追加
  AC2: 引数 {window_name, threshold_remaining_minutes?, threshold_cycle_minutes?, config_path?}
  AC3: 戻り値 {ok, budget_pct, budget_min, cycle_reset_min, low: bool, error}
       budget-detect.sh の 5h:%(Ym) regex pattern を踏襲
  AC4: plugins/twl/refs/ref-budget-format.md 作成（epic AC10）
  AC5: format mismatch 検出時に low=true, error="format-mismatch" で安全側 fallback
  AC6: shadow mode rollout
  AC7: AT 非依存性
  AC8: short-lived 設計
"""

import inspect
from pathlib import Path
from unittest import mock

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
REFS_DIR = TWL_DIR.parent.parent / "plugins" / "twl" / "refs"


def _handler():
    from twl.mcp_server.tools import twl_get_budget_handler  # noqa: PLC0415
    return twl_get_budget_handler


# ===========================================================================
# AC1: handler 追加
# ===========================================================================


class TestAC1HandlerExists:
    """AC1: twl_get_budget_handler が tools.py に追加されている。"""

    def test_ac1_handler_importable(self):
        # AC: tools.py に twl_get_budget_handler が定義されている
        # RED: 実装前は ImportError で FAIL
        from twl.mcp_server.tools import twl_get_budget_handler  # noqa: F401

    def test_ac1_handler_is_callable(self):
        # AC: twl_get_budget_handler が callable である
        # RED: 実装前は ImportError → FAIL
        handler = _handler()
        assert callable(handler), "twl_get_budget_handler が callable でない"

    def test_ac1_mcp_tool_registered(self):
        # AC: twl_get_budget が MCP tools モジュールに登録されている
        # RED: 実装前は AttributeError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_get_budget") or hasattr(
            tools_mod, "twl_get_budget_handler"
        ), "twl_get_budget が tools モジュールに存在しない (AC1 未実装)"

    def test_ac1_coexists_with_list_windows(self):
        # AC: 既存 twl_list_windows_handler と並列に存在する
        # RED: 実装前は ImportError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_list_windows_handler"), (
            "既存 twl_list_windows_handler が消えている（既存ハンドラを壊してはならない）"
        )
        from twl.mcp_server.tools import twl_get_budget_handler  # noqa: F401


# ===========================================================================
# AC2: 引数シグネチャ
# ===========================================================================


class TestAC2Signature:
    """AC2: 引数 {window_name, threshold_remaining_minutes?, threshold_cycle_minutes?, config_path?}。"""

    def test_ac2_window_name_param_required(self):
        # AC: window_name が必須引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "window_name" in params, (
            "twl_get_budget_handler に window_name 引数がない (AC2 未実装)"
        )

    def test_ac2_threshold_remaining_minutes_optional(self):
        # AC: threshold_remaining_minutes が省略可能な引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "threshold_remaining_minutes" in params, (
            "twl_get_budget_handler に threshold_remaining_minutes 引数がない (AC2 未実装)"
        )
        assert params["threshold_remaining_minutes"].default is not inspect.Parameter.empty, (
            "threshold_remaining_minutes にデフォルト値がない（省略可能引数のはず）"
        )

    def test_ac2_threshold_cycle_minutes_optional(self):
        # AC: threshold_cycle_minutes が省略可能な引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "threshold_cycle_minutes" in params, (
            "twl_get_budget_handler に threshold_cycle_minutes 引数がない (AC2 未実装)"
        )
        assert params["threshold_cycle_minutes"].default is not inspect.Parameter.empty, (
            "threshold_cycle_minutes にデフォルト値がない（省略可能引数のはず）"
        )

    def test_ac2_config_path_optional(self):
        # AC: config_path が省略可能な引数として存在する
        # RED: 実装前は ImportError → FAIL
        sig = inspect.signature(_handler())
        params = sig.parameters
        assert "config_path" in params, (
            "twl_get_budget_handler に config_path 引数がない (AC2 未実装)"
        )
        assert params["config_path"].default is not inspect.Parameter.empty, (
            "config_path にデフォルト値がない（省略可能引数のはず）"
        )


# ===========================================================================
# AC3: 戻り値スキーマ（5h:%(Ym) regex pattern を踏襲）
# ===========================================================================


class TestAC3ReturnSchema:
    """AC3: 戻り値 {ok, budget_pct, budget_min, cycle_reset_min, low: bool, error}。"""

    NORMAL_PANE = "5h:72%(83m) some status line text"

    def test_ac3_success_schema_required_keys(self):
        # AC: ok=True 時の戻り値スキーマに必須キーが存在する
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = self.NORMAL_PANE
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"ok キーがない: {result}"
        assert "budget_pct" in result, f"budget_pct キーがない: {result}"
        assert "budget_min" in result, f"budget_min キーがない: {result}"
        assert "cycle_reset_min" in result, f"cycle_reset_min キーがない: {result}"
        assert "low" in result, f"low キーがない: {result}"
        assert "error" in result, f"error キーがない: {result}"

    def test_ac3_success_ok_true(self):
        # AC: 正常取得時は ok=True
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = self.NORMAL_PANE
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert result.get("ok") is True, f"ok が True でない: {result}"

    def test_ac3_budget_pct_parsed(self):
        # AC: 5h:72%(83m) から budget_pct=72 が抽出される
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = self.NORMAL_PANE
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert result.get("budget_pct") == 72, (
            f"budget_pct が 72 でない: {result.get('budget_pct')}"
        )

    def test_ac3_cycle_reset_min_parsed(self):
        # AC: 5h:72%(83m) から cycle_reset_min=83 が抽出される
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = self.NORMAL_PANE
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert result.get("cycle_reset_min") == 83, (
            f"cycle_reset_min が 83 でない: {result.get('cycle_reset_min')}"
        )

    def test_ac3_budget_min_derived(self):
        # AC: budget_pct=72 から budget_min が計算される（300 × (100-72) / 100 = 84）
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = self.NORMAL_PANE
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert result.get("budget_min") == 84, (
            f"budget_min が 84 でない: {result.get('budget_min')}"
        )

    def test_ac3_low_false_above_threshold(self):
        # AC: budget_min > threshold（デフォルト40） の場合 low=False
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = self.NORMAL_PANE  # budget_min=84, threshold=40
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert result.get("low") is False, (
            f"threshold 上回り時 low が False でない: {result.get('low')}"
        )

    def test_ac3_low_true_below_threshold(self):
        # AC: budget_min <= threshold_remaining_minutes で low=True
        # 5h:95%(3m) → budget_min=15, デフォルト threshold=40 → low=True
        # RED: 実装前は ImportError or assert FAIL
        low_budget_pane = "5h:95%(3m) some status line text"
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = low_budget_pane
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert result.get("low") is True, (
            f"threshold 下回り時 low が True でない: {result.get('low')}"
        )

    def test_ac3_low_type_is_bool(self):
        # AC: low フィールドの型は bool
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = self.NORMAL_PANE
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert isinstance(result.get("low"), bool), (
            f"low の型が bool でない: {type(result.get('low'))}"
        )


# ===========================================================================
# AC4: plugins/twl/refs/ref-budget-format.md 作成
# ===========================================================================


class TestAC4RefBudgetFormatMd:
    """AC4: plugins/twl/refs/ref-budget-format.md が作成されている（epic AC10）。"""

    def test_ac4_ref_file_exists(self):
        # AC: ref-budget-format.md が存在する
        # RED: 未作成の場合 FAIL
        ref_path = REFS_DIR / "ref-budget-format.md"
        assert ref_path.exists(), (
            f"ref-budget-format.md が存在しない: {ref_path} (AC4 未実装)"
        )

    def test_ac4_ref_file_not_empty(self):
        # AC: ref-budget-format.md が空でない
        # RED: 未作成または空の場合 FAIL
        ref_path = REFS_DIR / "ref-budget-format.md"
        if ref_path.exists():
            content = ref_path.read_text(encoding="utf-8")
            assert len(content.strip()) > 0, "ref-budget-format.md が空 (AC4 未実装)"
        else:
            pytest.fail(f"ref-budget-format.md が存在しない: {ref_path}")

    def test_ac4_ref_file_contains_regex_pattern(self):
        # AC: ref-budget-format.md が 5h:%(Ym) regex pattern を記載している
        # RED: 未作成または pattern 未記載の場合 FAIL
        ref_path = REFS_DIR / "ref-budget-format.md"
        if ref_path.exists():
            content = ref_path.read_text(encoding="utf-8")
            assert "5h:" in content, (
                "ref-budget-format.md に '5h:' フォーマット仕様が記載されていない (AC4 未実装)"
            )
        else:
            pytest.fail(f"ref-budget-format.md が存在しない: {ref_path}")


# ===========================================================================
# AC5: format mismatch 検出時に low=true, error="format-mismatch" で安全側 fallback
# ===========================================================================


class TestAC5FormatMismatchFallback:
    """AC5: format mismatch 検出時は low=true, error="format-mismatch"。"""

    def test_ac5_no_budget_pattern_returns_format_mismatch(self):
        # AC: status line に 5h:%(Ym) パターンがない場合 error="format-mismatch"
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = "some unrelated status line without budget info"
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert result.get("error") == "format-mismatch", (
            f"format mismatch 時 error が 'format-mismatch' でない: {result.get('error')}"
        )

    def test_ac5_format_mismatch_low_is_true(self):
        # AC: format mismatch 時は安全側 fallback として low=True
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = "no_budget_pattern_here"
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert result.get("low") is True, (
            f"format mismatch 時 low が True でない（安全側 fallback 必須）: {result.get('low')}"
        )

    def test_ac5_empty_pane_returns_format_mismatch(self):
        # AC: pane が空の場合も error="format-mismatch"
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = ""
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        assert result.get("error") == "format-mismatch", (
            f"空 pane 時 error が 'format-mismatch' でない: {result.get('error')}"
        )
        assert result.get("low") is True, (
            f"空 pane 時 low が True でない: {result.get('low')}"
        )


# ===========================================================================
# AC6: shadow mode rollout
# ===========================================================================


class TestAC6ShadowMode:
    """AC6: shadow mode rollout 対応。"""

    def test_ac6_handler_defined_in_tools_py(self):
        # AC: handler が tools.py に定義されている（shadow mode 対応の前提）
        # RED: 実装前は ImportError → FAIL
        assert TOOLS_PY.exists(), f"tools.py が存在しない: {TOOLS_PY}"
        content = TOOLS_PY.read_text(encoding="utf-8")
        assert "twl_get_budget_handler" in content, (
            "tools.py に twl_get_budget_handler が定義されていない (AC6 未実装)"
        )

    def test_ac6_shadow_mode_env_respected(self):
        # AC: MCP_SHADOW_MODE 環境変数設定時でも handler が動作する
        # RED: 実装前は ImportError → FAIL
        import os
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = "5h:72%(83m) status"
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            with mock.patch.dict(os.environ, {"MCP_SHADOW_MODE": "1"}):
                result = _handler()(window_name="pilot")
        assert isinstance(result, dict), f"shadow mode 時 戻り値が dict でない: {type(result)}"


# ===========================================================================
# AC7: AT 非依存性（tmux 以外のテスト環境でも動作可能）
# ===========================================================================


class TestAC7ATIndependence:
    """AC7: AT 非依存性 — subprocess は mock 可能、テスト時に実 tmux 不要。"""

    def test_ac7_handler_uses_subprocess_mockable(self):
        # AC: handler が subprocess.run をモック可能な形で使用している
        # RED: 実装前は ImportError → FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = "5h:50%(120m) status"
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc) as mock_run:
            result = _handler()(window_name="test-window")
        assert mock_run.called, "subprocess.run がモックされていない（AT 非依存性を保証できない）"
        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"

    def test_ac7_no_real_tmux_required(self):
        # AC: subprocess.run を mock すれば実 tmux なしで動作する
        # RED: 実装前は ImportError → FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = "5h:30%(200m) pilot window text"
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot")
        # 実 tmux がなくても戻り値が返ること
        assert isinstance(result, dict), f"mock 環境で戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"ok キーがない: {result}"


# ===========================================================================
# AC8: short-lived 設計（subprocess timeout 強制）
# ===========================================================================


class TestAC8ShortLived:
    """AC8: short-lived 設計 — subprocess.run に timeout を設定している。"""

    def test_ac8_timeout_set_on_subprocess(self):
        # AC: subprocess.run が timeout 引数付きで呼ばれている
        # RED: 実装前は ImportError or timeout 未設定で FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = "5h:72%(83m) status"
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc) as mock_run:
            _handler()(window_name="pilot")
        assert mock_run.called, "subprocess.run が呼ばれていない"
        call_kwargs = mock_run.call_args
        # timeout が kwargs または positional args に含まれている
        has_timeout = (
            call_kwargs.kwargs.get("timeout") is not None
            if call_kwargs.kwargs
            else False
        )
        assert has_timeout, (
            f"subprocess.run に timeout が設定されていない (AC8 short-lived 設計違反): kwargs={call_kwargs.kwargs}"
        )

    def test_ac8_timeout_expired_handled(self):
        # AC: subprocess.TimeoutExpired 時はエラー envelope を返す（クラッシュしない）
        # RED: 実装前は ImportError or exception 未処理で FAIL
        import subprocess
        with mock.patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="tmux", timeout=10)):
            result = _handler()(window_name="pilot")
        assert isinstance(result, dict), f"TimeoutExpired 時 戻り値が dict でない: {type(result)}"
        assert result.get("ok") is False, (
            f"TimeoutExpired 時 ok が False でない: {result}"
        )

    def test_ac8_tmux_error_handled(self):
        # AC: tmux コマンド失敗時はエラー envelope を返す（ok=False）
        # RED: 実装前は ImportError or exception 未処理で FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 1
        mock_proc.stdout = ""
        mock_proc.stderr = "no server running"
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="nonexistent")
        assert isinstance(result, dict), f"tmux エラー時 戻り値が dict でない: {type(result)}"
        # tmux 失敗時は ok=False またはエラーフォールバック（低予算側）
        assert "ok" in result or "error" in result, (
            f"tmux エラー時に ok/error キーがない: {result}"
        )


# ===========================================================================
# 追加: threshold カスタマイズ
# ===========================================================================


class TestThresholdCustomization:
    """threshold_remaining_minutes / threshold_cycle_minutes のカスタマイズ動作。"""

    def test_custom_threshold_remaining_respected(self):
        # 5h:72%(83m) → budget_min=84。threshold=90 なら low=True
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = "5h:72%(83m) status"
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot", threshold_remaining_minutes=90)
        assert result.get("low") is True, (
            f"threshold=90, budget_min=84 のとき low が True でない: {result.get('low')}"
        )

    def test_custom_threshold_cycle_respected(self):
        # 5h:72%(83m) → cycle_reset_min=83。threshold_cycle=90 なら low=True
        # RED: 実装前は ImportError or assert FAIL
        mock_proc = mock.MagicMock()
        mock_proc.returncode = 0
        mock_proc.stdout = "5h:72%(83m) status"
        mock_proc.stderr = ""
        with mock.patch("subprocess.run", return_value=mock_proc):
            result = _handler()(window_name="pilot", threshold_cycle_minutes=90)
        assert result.get("low") is True, (
            f"threshold_cycle=90, cycle_reset_min=83 のとき low が True でない: {result.get('low')}"
        )
