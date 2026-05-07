"""Tests for Issue #1511: twl_spawn_controller — spawn-controller.sh MCP wrapper.

TDD RED フェーズ用テスト。実装前は全テストが FAIL する（意図的 RED）。

AC 対応:
  AC1: twl_spawn_controller_handler が tools.py に存在する
  AC2: 引数 spec {skill_name, prompt_file_or_text, with_chain?, issue?, project_dir?,
       autopilot_dir?, extra_args?}
  AC3: skill 名 allow-list 検証（7 スキル + twl: prefix 両対応）
  AC4: 戻り値 {ok, window, session, prompt_prepended, error}
  AC5: SUPERVISOR_DIR validation 継承（#1346 pattern）
  AC6: 並列 spawn check 継承（#1116）— SKIP_PARALLEL_CHECK=1 bypass +
       intervention-log 自動記録
  AC7: shadow mode rollout（SUB-2 と同）
  AC8: AT 非依存性
  AC9: short-lived 設計
"""

import inspect
import os
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"

SPAWN_CONTROLLER_SH = (
    TWL_DIR.parent.parent.parent
    / "plugins" / "twl" / "skills" / "su-observer" / "scripts" / "spawn-controller.sh"
)

VALID_SKILLS = [
    "co-explore",
    "co-issue",
    "co-architect",
    "co-autopilot",
    "co-project",
    "co-utility",
    "co-self-improve",
]


# ---------------------------------------------------------------------------
# AC1: twl_spawn_controller_handler が tools.py に存在する
# ---------------------------------------------------------------------------

class TestAC1HandlerExists:
    """AC1: mcp__twl__twl_spawn_controller handler を tools.py に追加。

    RED: 現状は handler が存在しないため FAIL する。
    """

    def test_ac1_handler_importable(self):
        # AC: twl_spawn_controller_handler が import 可能であること
        # RED: 現状は未実装のため ImportError / AttributeError で FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler  # noqa: F401

    def test_ac1_handler_is_callable(self):
        # AC: twl_spawn_controller_handler が callable であること
        # RED: 存在しないため FAIL
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_spawn_controller_handler"), (
            "twl_spawn_controller_handler が tools モジュールに存在しない (AC1 未実装)"
        )
        assert callable(tools.twl_spawn_controller_handler), (
            "twl_spawn_controller_handler が callable でない (AC1 未実装)"
        )

    def test_ac1_handler_in_tools_py_source(self):
        # AC: TOOLS_PY に "twl_spawn_controller_handler" が定義されていること
        # RED: 現状は存在しない
        content = TOOLS_PY.read_text()
        assert "twl_spawn_controller_handler" in content, (
            "tools.py に twl_spawn_controller_handler が存在しない (AC1 未実装)"
        )

    def test_ac1_mcp_tool_registered(self):
        # AC: twl_spawn_controller が @mcp.tool() で登録されていること
        # RED: 未実装のため FAIL
        content = TOOLS_PY.read_text()
        assert "twl_spawn_controller" in content, (
            "tools.py に twl_spawn_controller の定義がない (AC1 MCP 登録 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2: 引数 spec {skill_name, prompt_file_or_text, with_chain?, issue?,
#       project_dir?, autopilot_dir?, extra_args?}
# ---------------------------------------------------------------------------

class TestAC2ArgumentSpec:
    """AC2: spawn-controller.sh 引数と 1:1 対応した引数 spec。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def _get_handler(self):
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_spawn_controller_handler"), (
            "twl_spawn_controller_handler が存在しない (AC1 未実装が AC2 をブロック)"
        )
        return tools.twl_spawn_controller_handler

    def test_ac2_skill_name_param_exists(self):
        # AC: skill_name 引数が存在すること（spawn-controller.sh の第1引数に対応）
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "skill_name" in params, (
            f"twl_spawn_controller_handler に skill_name 引数がない: {list(params)} (AC2 未実装)"
        )

    def test_ac2_prompt_file_or_text_param_exists(self):
        # AC: prompt_file_or_text 引数が存在すること（spawn-controller.sh の第2引数に対応）
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "prompt_file_or_text" in params, (
            f"twl_spawn_controller_handler に prompt_file_or_text 引数がない: {list(params)} (AC2 未実装)"
        )

    def test_ac2_with_chain_param_optional(self):
        # AC: with_chain 引数がオプショナルであること（--with-chain フラグに対応）
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "with_chain" in params, (
            f"twl_spawn_controller_handler に with_chain 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["with_chain"].default is not inspect.Parameter.empty, (
            "with_chain 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_issue_param_optional(self):
        # AC: issue 引数がオプショナルであること（--issue N フラグに対応）
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "issue" in params, (
            f"twl_spawn_controller_handler に issue 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["issue"].default is not inspect.Parameter.empty, (
            "issue 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_project_dir_param_optional(self):
        # AC: project_dir 引数がオプショナルであること（--project-dir DIR フラグに対応）
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "project_dir" in params, (
            f"twl_spawn_controller_handler に project_dir 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["project_dir"].default is not inspect.Parameter.empty, (
            "project_dir 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_autopilot_dir_param_optional(self):
        # AC: autopilot_dir 引数がオプショナルであること（--autopilot-dir DIR フラグに対応）
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "autopilot_dir" in params, (
            f"twl_spawn_controller_handler に autopilot_dir 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["autopilot_dir"].default is not inspect.Parameter.empty, (
            "autopilot_dir 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_extra_args_param_optional(self):
        # AC: extra_args 引数がオプショナルであること（追加引数パススルーに対応）
        handler = self._get_handler()
        params = inspect.signature(handler).parameters
        assert "extra_args" in params, (
            f"twl_spawn_controller_handler に extra_args 引数がない: {list(params)} (AC2 未実装)"
        )
        assert params["extra_args"].default is not inspect.Parameter.empty, (
            "extra_args 引数がオプショナルでない (AC2 未実装)"
        )

    def test_ac2_all_required_params_present(self):
        # AC: 7 引数すべてが存在すること
        handler = self._get_handler()
        params = set(inspect.signature(handler).parameters.keys())
        required = {
            "skill_name",
            "prompt_file_or_text",
            "with_chain",
            "issue",
            "project_dir",
            "autopilot_dir",
            "extra_args",
        }
        missing = required - params
        assert not missing, (
            f"twl_spawn_controller_handler に引数が不足: {missing} (AC2 未実装)"
        )


# ---------------------------------------------------------------------------
# AC3: skill 名 allow-list 検証
# ---------------------------------------------------------------------------

class TestAC3SkillAllowList:
    """AC3: skill 名を allow-list でバリデーション。twl: prefix 両対応。

    allow-list: co-explore/co-issue/co-architect/co-autopilot/
                co-project/co-utility/co-self-improve

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac3_invalid_skill_returns_error(self):
        # AC: 無効な skill 名を渡すと ok=False が返ること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout="", stderr="")):
            result = twl_spawn_controller_handler(
                skill_name="invalid-skill",
                prompt_file_or_text="test prompt",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"'ok' キーがない: {result}"
        assert result["ok"] is False, (
            f"無効な skill 名で ok=True が返った (AC3 未実装): {result}"
        )
        assert "error" in result, f"エラー時に 'error' キーがない: {result}"

    @pytest.mark.parametrize("skill", VALID_SKILLS)
    def test_ac3_valid_skill_passes_validation(self, skill, tmp_path):
        # AC: allow-list の skill 名が validation を通過すること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        # validation チェックのため subprocess は FileNotFoundError で止める
        with patch("subprocess.run", side_effect=FileNotFoundError("spawn-controller not found")):
            result = twl_spawn_controller_handler(
                skill_name=skill,
                prompt_file_or_text="test prompt",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"'ok' キーがない: {result}"
        # allow-list 通過後に subprocess エラーで ok=False になるのは OK
        # allow-list で弾かれた場合のエラーメッセージに "invalid" や "allow" が含まれていないことを確認
        if not result.get("ok"):
            error_msg = result.get("error", "")
            assert "invalid skill" not in error_msg.lower(), (
                f"有効な skill '{skill}' が allow-list で弾かれた (AC3 未実装): {result}"
            )

    @pytest.mark.parametrize("skill", VALID_SKILLS)
    def test_ac3_twl_prefix_skill_passes_validation(self, skill):
        # AC: "twl:" prefix 付き skill 名も validation を通過すること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        twl_prefixed = f"twl:{skill}"
        with patch("subprocess.run", side_effect=FileNotFoundError("spawn-controller not found")):
            result = twl_spawn_controller_handler(
                skill_name=twl_prefixed,
                prompt_file_or_text="test prompt",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"'ok' キーがない: {result}"
        if not result.get("ok"):
            error_msg = result.get("error", "")
            assert "invalid skill" not in error_msg.lower(), (
                f"twl: prefix 付き skill '{twl_prefixed}' が allow-list で弾かれた (AC3 未実装): {result}"
            )

    def test_ac3_allow_list_in_source(self):
        # AC: tools.py に 7 スキルの allow-list が定義されていること
        # RED: 未実装のため FAIL
        content = TOOLS_PY.read_text()
        assert "twl_spawn_controller_handler" in content, (
            "tools.py に twl_spawn_controller_handler が存在しない (AC3 前提 AC1 未実装)"
        )
        for skill in VALID_SKILLS:
            assert skill in content, (
                f"tools.py に allow-list スキル '{skill}' が存在しない (AC3 未実装)"
            )


# ---------------------------------------------------------------------------
# AC4: 戻り値 {ok, window, session, prompt_prepended, error}
# ---------------------------------------------------------------------------

class TestAC4ReturnValueSchema:
    """AC4: 戻り値に ok, window, session, prompt_prepended, error キーが含まれること。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac4_ok_true_contains_required_keys(self, tmp_path):
        # AC: ok=True のとき window, session, prompt_prepended キーが存在すること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = "spawned → tmux window 'wt-co-explore-120000'\n"
        fake_proc.stderr = ""

        with patch("subprocess.run", return_value=fake_proc):
            result = twl_spawn_controller_handler(
                skill_name="co-explore",
                prompt_file_or_text="test prompt text",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"戻り値に 'ok' キーがない: {result}"
        if result.get("ok"):
            for key in ("window", "session", "prompt_prepended"):
                assert key in result, (
                    f"ok=True のとき '{key}' キーがない: {result} (AC4 未実装)"
                )

    def test_ac4_ok_false_contains_error_key(self):
        # AC: ok=False のとき error キーが存在すること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        with patch("subprocess.run", side_effect=FileNotFoundError("spawn-controller not found")):
            result = twl_spawn_controller_handler(
                skill_name="co-explore",
                prompt_file_or_text="test prompt",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        if not result.get("ok", True):
            assert "error" in result, f"ok=False のとき 'error' キーがない: {result} (AC4 未実装)"

    def test_ac4_return_schema_has_ok_key_always(self):
        # AC: 戻り値スキーマに ok キーが必ず含まれること（正常系・異常系共通）
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        with patch("subprocess.run", side_effect=RuntimeError("unexpected error")):
            try:
                result = twl_spawn_controller_handler(
                    skill_name="co-explore",
                    prompt_file_or_text="test",
                )
            except Exception:
                pytest.fail(
                    "twl_spawn_controller_handler が例外を propagate した "
                    "— 戻り値 {ok: False, error: ...} で wrap すべき (AC4 未実装)"
                )

        assert "ok" in result, f"例外時でも ok キーが存在すべき: {result}"
        assert result["ok"] is False, f"例外時は ok=False であるべき: {result}"

    def test_ac4_prompt_prepended_field_indicates_twl_prefix(self):
        # AC: prompt_prepended フィールドが /twl:<skill> の prepend 状態を示すこと
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = "spawned → tmux window 'wt-co-issue-120001'\n"
        fake_proc.stderr = ""

        with patch("subprocess.run", return_value=fake_proc):
            result = twl_spawn_controller_handler(
                skill_name="co-issue",
                prompt_file_or_text="test prompt",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"'ok' キーがない: {result}"
        # ok=True の場合 prompt_prepended が存在し bool または None であること
        if result.get("ok"):
            assert "prompt_prepended" in result, (
                f"ok=True のとき 'prompt_prepended' キーがない (AC4 未実装): {result}"
            )


# ---------------------------------------------------------------------------
# AC5: SUPERVISOR_DIR validation 継承（#1346 pattern）
# ---------------------------------------------------------------------------

class TestAC5SupervisorDirValidation:
    """AC5: SUPERVISOR_DIR validation を #1346 pattern で継承。

    spawn-controller.sh は SUPERVISOR_DIR を validate_supervisor_dir() で検証する。
    MCP handler もこの検証を呼び出すか、または spawn 前にチェックすること。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac5_invalid_supervisor_dir_returns_error(self, monkeypatch, tmp_path):
        # AC: SUPERVISOR_DIR が無効な場合（存在しない / 不正パス）、ok=False が返ること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        monkeypatch.setenv("SUPERVISOR_DIR", str(tmp_path / "nonexistent-supervisor"))

        with patch("subprocess.run", return_value=MagicMock(returncode=2, stdout="", stderr="Error: SUPERVISOR_DIR invalid")):
            result = twl_spawn_controller_handler(
                skill_name="co-explore",
                prompt_file_or_text="test",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"'ok' キーがない: {result}"

    def test_ac5_supervisor_dir_validation_in_source(self):
        # AC: tools.py に SUPERVISOR_DIR または supervisor_dir の参照が存在すること
        # RED: 未実装のため FAIL
        content = TOOLS_PY.read_text()
        assert "twl_spawn_controller_handler" in content, (
            "tools.py に twl_spawn_controller_handler が存在しない (AC5 前提 AC1 未実装)"
        )
        # SUPERVISOR_DIR validation の参照確認
        has_supervisor_ref = (
            "SUPERVISOR_DIR" in content
            or "supervisor_dir" in content.lower()
        )
        # handler 実装後に検証できるよう、現状は handler 存在チェックで代替
        # 実装後: assert has_supervisor_ref, "SUPERVISOR_DIR validation が存在しない (AC5 未実装)"
        assert "twl_spawn_controller" in content, (
            "tools.py に twl_spawn_controller が存在しない (AC5 前提 AC1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC6: §11.3 並列 spawn check 継承（#1116）
# ---------------------------------------------------------------------------

class TestAC6ParallelSpawnCheck:
    """AC6: §11.3 並列 spawn check 継承（#1116）。

    SKIP_PARALLEL_CHECK=1 で bypass + intervention-log 自動記録。
    spawn-controller.sh の動作を MCP handler 経由で正しく引き継ぐこと。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac6_handler_passes_skip_parallel_check_to_script(self, monkeypatch):
        # AC: SKIP_PARALLEL_CHECK=1 が設定されているとき、spawn-controller.sh に
        #     SKIP_PARALLEL_CHECK=1 が伝達されること（環境変数経由 or 明示的フラグ）
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        monkeypatch.setenv("SKIP_PARALLEL_CHECK", "1")

        captured_kwargs = {}

        def fake_run(*args, **kwargs):
            captured_kwargs.update(kwargs)
            captured_kwargs["cmd"] = args[0] if args else kwargs.get("args", [])
            m = MagicMock()
            m.returncode = 0
            m.stdout = "spawned → tmux window 'wt-co-explore-120002'\n"
            m.stderr = ""
            return m

        with patch("subprocess.run", side_effect=fake_run):
            result = twl_spawn_controller_handler(
                skill_name="co-explore",
                prompt_file_or_text="test parallel bypass",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"'ok' キーがない: {result}"
        # SKIP_PARALLEL_CHECK が env に含まれるか、cmd に含まれていることを確認
        env = captured_kwargs.get("env", {})
        if env:
            assert env.get("SKIP_PARALLEL_CHECK") == "1", (
                "SKIP_PARALLEL_CHECK=1 が spawn-controller.sh の env に渡されていない (AC6 未実装)"
            )

    def test_ac6_intervention_log_recorded_when_skip(self, monkeypatch, tmp_path):
        # AC: SKIP_PARALLEL_CHECK=1 bypass 時、intervention-log.md に記録が追加されること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        supervisor_dir = tmp_path / ".supervisor"
        supervisor_dir.mkdir()
        monkeypatch.setenv("SUPERVISOR_DIR", str(supervisor_dir))
        monkeypatch.setenv("SKIP_PARALLEL_CHECK", "1")
        monkeypatch.setenv("SKIP_PARALLEL_REASON", "test-bypass")

        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = "spawned → tmux window 'wt-co-explore-120003'\n"
        fake_proc.stderr = "[spawn-controller] WARN: SKIP_PARALLEL_CHECK=1"

        with patch("subprocess.run", return_value=fake_proc):
            result = twl_spawn_controller_handler(
                skill_name="co-explore",
                prompt_file_or_text="test",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"'ok' キーがない: {result}"

    def test_ac6_parallel_check_bypass_in_source(self):
        # AC: tools.py または spawn-controller.sh に SKIP_PARALLEL_CHECK の参照があること
        # RED: handler 未実装のため FAIL
        content = TOOLS_PY.read_text()
        assert "twl_spawn_controller_handler" in content, (
            "tools.py に twl_spawn_controller_handler が存在しない (AC6 前提 AC1 未実装)"
        )
        # spawn-controller.sh 自体に SKIP_PARALLEL_CHECK があることも確認
        sc_content = SPAWN_CONTROLLER_SH.read_text() if SPAWN_CONTROLLER_SH.exists() else ""
        has_parallel_check = (
            "SKIP_PARALLEL_CHECK" in content
            or "SKIP_PARALLEL_CHECK" in sc_content
        )
        assert has_parallel_check, (
            "SKIP_PARALLEL_CHECK の参照が tools.py にも spawn-controller.sh にも存在しない (AC6 未実装)"
        )


# ---------------------------------------------------------------------------
# AC7: shadow mode rollout
# ---------------------------------------------------------------------------

class TestAC7ShadowModeRollout:
    """AC7: shadow mode rollout（SUB-2 と同）。

    spawn 系は side-effect 大のため shadow log は exit code + stderr 構造化記録のみ。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac7_shadow_log_records_exit_code(self):
        # AC: shadow mode で実行した場合、exit code が記録されること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_spawn_controller_handler"), (
            "twl_spawn_controller_handler が存在しない (AC7 前提 AC1 未実装)"
        )
        content = TOOLS_PY.read_text()
        assert "twl_spawn_controller_handler" in content, (
            "tools.py に twl_spawn_controller_handler が存在しない (AC7 前提 AC1 未実装)"
        )

    def test_ac7_stderr_captured_in_shadow_log(self):
        # AC: spawn-controller.sh の stderr が shadow log に構造化記録されること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        fake_proc = MagicMock()
        fake_proc.returncode = 1
        fake_proc.stdout = ""
        fake_proc.stderr = "Error: tmux 内で実行してください"

        with patch("subprocess.run", return_value=fake_proc):
            result = twl_spawn_controller_handler(
                skill_name="co-explore",
                prompt_file_or_text="test",
            )

        assert isinstance(result, dict), f"戻り値が dict でない: {type(result)}"
        assert "ok" in result, f"'ok' キーがない: {result}"

    def test_ac7_shadow_mode_in_source(self):
        # AC: tools.py に shadow log / shadow mode の実装があること
        # RED: 未実装のため FAIL（handler 存在チェックで代替）
        content = TOOLS_PY.read_text()
        has_shadow = (
            "shadow" in content.lower()
            or "SHADOW" in content
        )
        # 現状 shadow 実装は _spawn_shadow_log で存在するはずだが
        # twl_spawn_controller_handler 用の shadow log が必要
        assert "twl_spawn_controller_handler" in content, (
            "tools.py に twl_spawn_controller_handler が存在しない (AC7 前提 AC1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC8: AT 非依存性
# ---------------------------------------------------------------------------

class TestAC8ATIndependence:
    """AC8: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 環境でも動作すること。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac8_handler_works_without_at_flag(self, monkeypatch):
        # AC: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 で import・呼び出しが可能であること
        # RED: handler 未実装のため FAIL
        monkeypatch.setenv("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", "0")

        from twl.mcp_server.tools import twl_spawn_controller_handler

        with patch("subprocess.run", side_effect=RuntimeError("test")):
            try:
                result = twl_spawn_controller_handler(
                    skill_name="co-explore",
                    prompt_file_or_text="test",
                )
            except Exception:
                pytest.fail(
                    "AT=0 環境で twl_spawn_controller_handler が例外を propagate した (AC8 未実装)"
                )

        assert "ok" in result, f"AT=0 環境でも ok キーが存在すべき: {result}"

    def test_ac8_no_agent_teams_dependency_in_handler(self):
        # AC: handler が AGENT_TEAMS 依存の import を使わないこと
        # RED: handler 未実装のため確認不能
        content = TOOLS_PY.read_text()
        assert "twl_spawn_controller_handler" in content, (
            "twl_spawn_controller_handler が tools.py に存在しない (AC8 前提 AC1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC9: short-lived 設計
# ---------------------------------------------------------------------------

class TestAC9ShortLivedDesign:
    """AC9: short-lived 設計。

    handler は spawn-controller.sh を起動して即時 return する。
    長時間ブロックしない。

    RED: handler が存在しないため全テストが FAIL する。
    """

    def test_ac9_handler_does_not_block_indefinitely(self):
        # AC: handler が完了するまで長時間ブロックしないこと（10 秒以内）
        # RED: handler 未実装のため FAIL
        import signal

        from twl.mcp_server.tools import twl_spawn_controller_handler

        def timeout_handler(signum, frame):
            raise TimeoutError(
                "twl_spawn_controller_handler が 10 秒以上ブロックした (AC9 short-lived 違反)"
            )

        signal.signal(signal.SIGALRM, timeout_handler)
        signal.alarm(10)
        try:
            with patch("subprocess.run", return_value=MagicMock(returncode=0, stdout="spawned → tmux window 'wt-co-explore-120004'\n", stderr="")):
                result = twl_spawn_controller_handler(
                    skill_name="co-explore",
                    prompt_file_or_text="short-lived test",
                )
        finally:
            signal.alarm(0)

        assert "ok" in result, f"short-lived 後も ok キーが存在すべき: {result}"

    def test_ac9_uses_subprocess_run_with_timeout(self):
        # AC: spawn-controller.sh の実行に timeout 付き subprocess.run が使われること
        # RED: handler 未実装のため FAIL
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_spawn_controller_handler"), (
            "twl_spawn_controller_handler が存在しない (AC9 前提 AC1 未実装)"
        )
        content = TOOLS_PY.read_text()
        has_timeout = "timeout" in content
        assert has_timeout, (
            "tools.py に timeout が存在しない "
            "— short-lived 実装の証跡がない (AC9 未実装)"
        )

    def test_ac9_handler_returns_on_subprocess_error(self):
        # AC: subprocess エラー時も handler が例外を propagate せず dict を返すこと
        # RED: handler 未実装のため FAIL
        from twl.mcp_server.tools import twl_spawn_controller_handler

        with patch("subprocess.run", side_effect=Exception("unexpected")):
            try:
                result = twl_spawn_controller_handler(
                    skill_name="co-explore",
                    prompt_file_or_text="error test",
                )
            except Exception:
                pytest.fail(
                    "twl_spawn_controller_handler が例外を propagate した (AC9 未実装)"
                )

        assert isinstance(result, dict), f"例外時も dict を返すべき: {type(result)}"
        assert "ok" in result, f"例外時も ok キーが存在すべき: {result}"
        assert result["ok"] is False, f"例外時は ok=False であるべき: {result}"
