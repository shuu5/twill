"""Tests for Issue #1114: feat(mcp): autopilot tool 12 本追加 (tools.py EPI).

TDD RED フェーズ用テストスタブ。
実装前は全テストが FAIL する（意図的 RED）。

AC 一覧:
  共通-1: 12 tool が tools.py に存在すること
  共通-2: 12 handler 関数が tools.py に存在すること
  共通-3: MCP tool 登録 (@mcp.tool() + try/except ImportError gate)
  共通-6: pytest 全テスト PASS（既存テスト含む）
  共通-9: action 系 tool に timeout_sec: int 引数が存在すること
  AC4-1: mergegate 系 3 tool のハンドラ動作
  AC4-2: orchestrator 系 4 tool のハンドラ動作
  AC4-3: worktree 系 5 tool のハンドラ動作
  AC4-5: 不変条件 B CWD-based role check
  AC4-6: critical assertion 群
  AC4-12: plan_file check
  AC4-13: docstring に timeout 注記
  AC-naming-1: tool 名が snake_case で twl_<module>_<action> 規則に準拠
  AC-naming-2: 12 tool それぞれの docstring 1 行目が非空
"""

from __future__ import annotations

import inspect
import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# ターゲットモジュール
TWL_DIR = Path(__file__).resolve().parent.parent

# 期待する 12 tool 名
EXPECTED_TOOL_NAMES = [
    "twl_mergegate_run",
    "twl_mergegate_reject",
    "twl_mergegate_reject_final",
    "twl_orchestrator_phase_review",
    "twl_orchestrator_get_phase_issues",
    "twl_orchestrator_summary",
    "twl_orchestrator_resolve_repos",
    "twl_worktree_create",
    "twl_worktree_delete",
    "twl_worktree_list",
    "twl_worktree_generate_branch_name",
    "twl_worktree_validate_branch_name",
]

# action 系 tool（timeout_sec 引数が必要）
ACTION_TOOL_HANDLER_NAMES = [
    "twl_mergegate_run_handler",
    "twl_mergegate_reject_handler",
    "twl_mergegate_reject_final_handler",
    "twl_orchestrator_phase_review_handler",
    "twl_worktree_create_handler",
    "twl_worktree_delete_handler",
]


# ---------------------------------------------------------------------------
# 共通-1: 12 tool が tools.py に存在すること
# ---------------------------------------------------------------------------


class TestCommon1TwelveToolsExist:
    """共通-1: 12 tool が tools.py に存在すること.

    実装前は各 tool 名が tools モジュールに存在しないため
    AttributeError で FAIL する（意図的 RED）。
    """

    def test_common1_all_12_tools_present_in_module(self):
        # AC: 12 tool が tools.py に定義されていること
        # RED: 実装前は各 tool 関数が存在しないため FAIL する
        from twl.mcp_server import tools
        missing = [name for name in EXPECTED_TOOL_NAMES if not hasattr(tools, name)]
        assert not missing, (
            f"tools.py に以下の tool が存在しない (共通-1 未実装): {missing}"
        )

    def test_common1_twl_mergegate_run_exists(self):
        # AC: twl_mergegate_run が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_mergegate_run"), (
            "tools.py に twl_mergegate_run が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_mergegate_reject_exists(self):
        # AC: twl_mergegate_reject が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_mergegate_reject"), (
            "tools.py に twl_mergegate_reject が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_mergegate_reject_final_exists(self):
        # AC: twl_mergegate_reject_final が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_mergegate_reject_final"), (
            "tools.py に twl_mergegate_reject_final が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_orchestrator_phase_review_exists(self):
        # AC: twl_orchestrator_phase_review が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_orchestrator_phase_review"), (
            "tools.py に twl_orchestrator_phase_review が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_orchestrator_get_phase_issues_exists(self):
        # AC: twl_orchestrator_get_phase_issues が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_orchestrator_get_phase_issues"), (
            "tools.py に twl_orchestrator_get_phase_issues が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_orchestrator_summary_exists(self):
        # AC: twl_orchestrator_summary が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_orchestrator_summary"), (
            "tools.py に twl_orchestrator_summary が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_orchestrator_resolve_repos_exists(self):
        # AC: twl_orchestrator_resolve_repos が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_orchestrator_resolve_repos"), (
            "tools.py に twl_orchestrator_resolve_repos が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_worktree_create_exists(self):
        # AC: twl_worktree_create が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_create"), (
            "tools.py に twl_worktree_create が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_worktree_delete_exists(self):
        # AC: twl_worktree_delete が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_delete"), (
            "tools.py に twl_worktree_delete が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_worktree_list_exists(self):
        # AC: twl_worktree_list が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_list"), (
            "tools.py に twl_worktree_list が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_worktree_generate_branch_name_exists(self):
        # AC: twl_worktree_generate_branch_name が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_generate_branch_name"), (
            "tools.py に twl_worktree_generate_branch_name が存在しない (共通-1 未実装)"
        )

    def test_common1_twl_worktree_validate_branch_name_exists(self):
        # AC: twl_worktree_validate_branch_name が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_validate_branch_name"), (
            "tools.py に twl_worktree_validate_branch_name が存在しない (共通-1 未実装)"
        )


# ---------------------------------------------------------------------------
# 共通-2: 12 handler 関数が tools.py に存在すること
# ---------------------------------------------------------------------------


class TestCommon2TwelveHandlersExist:
    """共通-2: 12 個の handler 関数が tools.py に存在すること（twl_<name>_handler 命名）.

    実装前は handler 関数が存在しないため AttributeError で FAIL する（意図的 RED）。
    """

    def test_common2_all_12_handlers_present(self):
        # AC: 12 handler 関数が tools.py に twl_<name>_handler 命名で存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        expected_handlers = [name + "_handler" for name in EXPECTED_TOOL_NAMES]
        missing = [h for h in expected_handlers if not hasattr(tools, h)]
        assert not missing, (
            f"tools.py に以下の handler が存在しない (共通-2 未実装): {missing}"
        )

    def test_common2_twl_mergegate_run_handler_exists(self):
        # AC: twl_mergegate_run_handler が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_mergegate_run_handler"), (
            "tools.py に twl_mergegate_run_handler が存在しない (共通-2 未実装)"
        )

    def test_common2_twl_orchestrator_phase_review_handler_exists(self):
        # AC: twl_orchestrator_phase_review_handler が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_orchestrator_phase_review_handler"), (
            "tools.py に twl_orchestrator_phase_review_handler が存在しない (共通-2 未実装)"
        )

    def test_common2_twl_worktree_create_handler_exists(self):
        # AC: twl_worktree_create_handler が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_create_handler"), (
            "tools.py に twl_worktree_create_handler が存在しない (共通-2 未実装)"
        )

    def test_common2_twl_worktree_delete_handler_exists(self):
        # AC: twl_worktree_delete_handler が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_delete_handler"), (
            "tools.py に twl_worktree_delete_handler が存在しない (共通-2 未実装)"
        )

    def test_common2_twl_worktree_list_handler_exists(self):
        # AC: twl_worktree_list_handler が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_list_handler"), (
            "tools.py に twl_worktree_list_handler が存在しない (共通-2 未実装)"
        )

    def test_common2_twl_worktree_validate_branch_name_handler_exists(self):
        # AC: twl_worktree_validate_branch_name_handler が tools.py に存在すること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        assert hasattr(tools, "twl_worktree_validate_branch_name_handler"), (
            "tools.py に twl_worktree_validate_branch_name_handler が存在しない (共通-2 未実装)"
        )


# ---------------------------------------------------------------------------
# 共通-3: MCP tool 登録 (@mcp.tool() + try/except ImportError gate)
# ---------------------------------------------------------------------------


class TestCommon3McpToolRegistration:
    """共通-3: @mcp.tool() + try/except ImportError gate 実装済み.

    実装前は 12 tool がモジュールに存在しないため FAIL する（意図的 RED）。
    """

    def test_common3_tools_module_importable(self):
        # AC: tools.py が import 可能であること
        # RED: 12 tool 未実装のため import に失敗する可能性あり
        from twl.mcp_server import tools  # noqa: F401

    def test_common3_12_tools_importable_from_tools_module(self):
        # AC: 12 tool が tools モジュールから直接 import 可能であること
        # RED: 実装前は存在しないため FAIL する
        from twl.mcp_server import tools
        for name in EXPECTED_TOOL_NAMES:
            assert hasattr(tools, name), (
                f"tools.twl.{name} が存在しない (共通-3 未実装)"
            )


# ---------------------------------------------------------------------------
# 共通-9: action 系 tool に timeout_sec: int 引数が存在すること
# ---------------------------------------------------------------------------


class TestCommon9TimeoutSecArgument:
    """共通-9: action 系 tool handler に timeout_sec: int 引数が存在すること.

    実装前は handler 関数が存在しないため AttributeError で FAIL する（意図的 RED）。
    """

    def test_common9_twl_mergegate_run_handler_has_timeout_sec(self):
        # AC: twl_mergegate_run_handler の引数に timeout_sec: int が存在すること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_mergegate_run_handler", None)
        assert handler is not None, "twl_mergegate_run_handler が存在しない (共通-9 未実装)"
        sig = inspect.signature(handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_mergegate_run_handler に timeout_sec 引数が存在しない (共通-9 未実装)"
        )
        param = sig.parameters["timeout_sec"]
        assert param.annotation == int or str(param.annotation) == "int", (
            "twl_mergegate_run_handler の timeout_sec が int 型でない (共通-9 未実装)"
        )

    def test_common9_twl_mergegate_reject_handler_has_timeout_sec(self):
        # AC: twl_mergegate_reject_handler の引数に timeout_sec: int が存在すること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_mergegate_reject_handler", None)
        assert handler is not None, "twl_mergegate_reject_handler が存在しない (共通-9 未実装)"
        sig = inspect.signature(handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_mergegate_reject_handler に timeout_sec 引数が存在しない (共通-9 未実装)"
        )

    def test_common9_twl_mergegate_reject_final_handler_has_timeout_sec(self):
        # AC: twl_mergegate_reject_final_handler の引数に timeout_sec: int が存在すること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_mergegate_reject_final_handler", None)
        assert handler is not None, "twl_mergegate_reject_final_handler が存在しない (共通-9 未実装)"
        sig = inspect.signature(handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_mergegate_reject_final_handler に timeout_sec 引数が存在しない (共通-9 未実装)"
        )

    def test_common9_twl_orchestrator_phase_review_handler_has_timeout_sec(self):
        # AC: twl_orchestrator_phase_review_handler の引数に timeout_sec: int が存在すること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_orchestrator_phase_review_handler", None)
        assert handler is not None, (
            "twl_orchestrator_phase_review_handler が存在しない (共通-9 未実装)"
        )
        sig = inspect.signature(handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_orchestrator_phase_review_handler に timeout_sec 引数が存在しない (共通-9 未実装)"
        )

    def test_common9_twl_worktree_create_handler_has_timeout_sec(self):
        # AC: twl_worktree_create_handler の引数に timeout_sec: int が存在すること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_worktree_create_handler", None)
        assert handler is not None, "twl_worktree_create_handler が存在しない (共通-9 未実装)"
        sig = inspect.signature(handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_worktree_create_handler に timeout_sec 引数が存在しない (共通-9 未実装)"
        )

    def test_common9_twl_worktree_delete_handler_has_timeout_sec(self):
        # AC: twl_worktree_delete_handler の引数に timeout_sec: int が存在すること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_worktree_delete_handler", None)
        assert handler is not None, "twl_worktree_delete_handler が存在しない (共通-9 未実装)"
        sig = inspect.signature(handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_worktree_delete_handler に timeout_sec 引数が存在しない (共通-9 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4-1: mergegate 系 3 tool のハンドラ動作
# ---------------------------------------------------------------------------


class TestAC41MergegateHandlers:
    """AC4-1: mergegate 系 3 tool のハンドラ動作.

    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac41_twl_mergegate_run_handler_returns_dict(self):
        # AC: twl_mergegate_run_handler が dict を返すこと
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_mergegate_run_handler
        result = twl_mergegate_run_handler.__call__  # type: ignore
        assert callable(twl_mergegate_run_handler), (
            "twl_mergegate_run_handler が callable でない (AC4-1 未実装)"
        )

    def test_ac41_twl_mergegate_run_handler_system_exit_catch(self):
        # AC: MergeGate.execute() が sys.exit(1) を raise する mock で
        #     handler が {"ok": False, "error_type": "merge_exit_1", "exit_code": 1} を返すこと
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_mergegate_run_handler

        mock_gh_output = json.dumps({
            "number": 1,
            "headRefName": "feat/1-test",
            "labels": [{"name": "issue-1"}],
        })
        mock_run_result = MagicMock()
        mock_run_result.returncode = 0
        mock_run_result.stdout = mock_gh_output

        with patch("subprocess.run", return_value=mock_run_result):
            with patch(
                "twl.autopilot.mergegate.MergeGate.execute",
                side_effect=SystemExit(1),
            ):
                result = twl_mergegate_run_handler(
                    pr_number=1,
                    timeout_sec=60,
                )
        assert isinstance(result, dict), "handler が dict を返さない (AC4-1 未実装)"
        assert result.get("ok") is False, "ok が False でない (AC4-1 未実装)"
        assert result.get("error_type") == "merge_exit_1", (
            f"error_type が 'merge_exit_1' でない: {result.get('error_type')} (AC4-1 未実装)"
        )
        assert result.get("exit_code") == 1, (
            f"exit_code が 1 でない: {result.get('exit_code')} (AC4-1 未実装)"
        )

    def test_ac41_twl_mergegate_run_handler_pr_resolve_error(self):
        # AC: pr_number resolve 失敗 (gh API mock fail) で
        #     {"ok": False, "error_type": "pr_resolve_error", "exit_code": 2} 返却
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_mergegate_run_handler

        with patch(
            "subprocess.run",
            side_effect=Exception("gh API failure mock"),
        ):
            result = twl_mergegate_run_handler(
                pr_number=1,
                timeout_sec=60,
            )
        assert isinstance(result, dict), "handler が dict を返さない (AC4-1 未実装)"
        assert result.get("ok") is False, "ok が False でない (AC4-1 未実装)"
        assert result.get("error_type") == "pr_resolve_error", (
            f"error_type が 'pr_resolve_error' でない: {result.get('error_type')} (AC4-1 未実装)"
        )
        assert result.get("exit_code") == 2, (
            f"exit_code が 2 でない: {result.get('exit_code')} (AC4-1 未実装)"
        )

    def test_ac41_twl_mergegate_run_handler_timeout(self):
        # AC: timeout_sec=1 の long-running mock で
        #     {"ok": False, "error_type": "timeout", "exit_code": 124} 返却
        # RED: handler が存在しないため FAIL する
        import time
        from twl.mcp_server.tools import twl_mergegate_run_handler

        mock_gh_output = json.dumps({
            "number": 1,
            "headRefName": "feat/1-test",
            "labels": [{"name": "issue-1"}],
        })
        mock_run_result = MagicMock()
        mock_run_result.returncode = 0
        mock_run_result.stdout = mock_gh_output

        def _slow_execute(*args, **kwargs):
            time.sleep(5)

        with patch("subprocess.run", return_value=mock_run_result):
            with patch("twl.autopilot.mergegate.MergeGate.execute", side_effect=_slow_execute):
                result = twl_mergegate_run_handler(
                    pr_number=1,
                    timeout_sec=1,
                )
        assert isinstance(result, dict), "handler が dict を返さない (AC4-1 未実装)"
        assert result.get("ok") is False, "ok が False でない (AC4-1 未実装)"
        assert result.get("error_type") == "timeout", (
            f"error_type が 'timeout' でない: {result.get('error_type')} (AC4-1 未実装)"
        )
        assert result.get("exit_code") == 124, (
            f"exit_code が 124 でない: {result.get('exit_code')} (AC4-1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4-2: orchestrator 系 4 tool のハンドラ動作
# ---------------------------------------------------------------------------


class TestAC42OrchestratorHandlers:
    """AC4-2: orchestrator 系 4 tool のハンドラ動作.

    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac42_twl_orchestrator_phase_review_handler_returns_dict(self):
        # AC: twl_orchestrator_phase_review_handler が存在し dict を返すこと
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_orchestrator_phase_review_handler
        assert callable(twl_orchestrator_phase_review_handler), (
            "twl_orchestrator_phase_review_handler が callable でない (AC4-2 未実装)"
        )

    def test_ac42_twl_orchestrator_phase_review_handler_plan_file_missing(self):
        # AC: plan_file 不在で {"ok": False, "error_type": "arg_error", "exit_code": 2} 返却
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_orchestrator_phase_review_handler

        result = twl_orchestrator_phase_review_handler(
            phase=1,
            plan_file="/nonexistent/plan.yaml",
            session_file="/tmp/session.json",
            project_dir="/tmp/proj",
            autopilot_dir="/tmp/.autopilot",
            cwd="/tmp/main",
            timeout_sec=60,
        )
        assert isinstance(result, dict), "handler が dict を返さない (AC4-2 未実装)"
        assert result.get("ok") is False, "ok が False でない (AC4-2 未実装)"
        assert result.get("error_type") == "arg_error", (
            f"error_type が 'arg_error' でない: {result.get('error_type')} (AC4-2 未実装)"
        )
        assert result.get("exit_code") == 2, (
            f"exit_code が 2 でない: {result.get('exit_code')} (AC4-2 未実装)"
        )

    def test_ac42_twl_orchestrator_phase_review_handler_tmux_not_found(self):
        # AC: tmux 不在環境 mock (FileNotFoundError raise) で
        #     {"ok": False, "error_type": "subprocess_error", "exit_code": 127} 返却
        # RED: handler が存在しないため FAIL する
        import tempfile, os
        from twl.mcp_server.tools import twl_orchestrator_phase_review_handler

        # plan_file を実際に作成してから tmux 不在をテスト
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write("phases:\n  - phase: 1\n    issues:\n      - 1\n")
            tmp_plan = f.name
        try:
            with patch(
                "twl.autopilot.orchestrator.PhaseOrchestrator.run",
                side_effect=FileNotFoundError("tmux not found"),
            ):
                result = twl_orchestrator_phase_review_handler(
                    phase=1,
                    plan_file=tmp_plan,
                    session_file="/tmp/session.json",
                    project_dir="/tmp/proj",
                    autopilot_dir="/tmp/.autopilot",
                    cwd="/tmp/main",
                    timeout_sec=60,
                )
        finally:
            os.unlink(tmp_plan)
        assert isinstance(result, dict), "handler が dict を返さない (AC4-2 未実装)"
        assert result.get("ok") is False, "ok が False でない (AC4-2 未実装)"
        assert result.get("error_type") == "subprocess_error", (
            f"error_type が 'subprocess_error' でない: {result.get('error_type')} (AC4-2 未実装)"
        )
        assert result.get("exit_code") == 127, (
            f"exit_code が 127 でない: {result.get('exit_code')} (AC4-2 未実装)"
        )

    def test_ac42_orchestrator_run_result_json_serializable(self):
        # AC: PhaseOrchestrator.run() が dict 返却 → tool 登録側 json.dumps で str 化される
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_orchestrator_phase_review_handler", None)
        assert handler is not None, (
            "twl_orchestrator_phase_review_handler が存在しない (AC4-2 未実装)"
        )
        # handler の戻り値が json.dumps 可能であることを確認する
        # ここでは plan_file 不在ケースで確認
        result = handler(phase=1, plan_file="/nonexistent/plan.yaml", session_file="/tmp/s.json", project_dir="/tmp/proj", autopilot_dir="/tmp/.ap", timeout_sec=60)
        # json.dumps で例外が出ないこと
        json_str = json.dumps(result, ensure_ascii=False)
        assert isinstance(json_str, str), (
            "handler の戻り値が json.dumps できない (AC4-2 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4-3: worktree 系 5 tool のハンドラ動作
# ---------------------------------------------------------------------------


class TestAC43WorktreeHandlers:
    """AC4-3: worktree 系 5 tool のハンドラ動作.

    実装前は WorktreeManager に delete/list_porcelain が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac43_workTreeManager_delete_method_exists(self):
        # AC: WorktreeManager.delete method が worktree.py に存在すること
        # RED: delete が未実装のため FAIL する
        from twl.autopilot.worktree import WorktreeManager
        assert hasattr(WorktreeManager, "delete"), (
            "WorktreeManager に delete method が存在しない (AC4-3 未実装)"
        )
        assert callable(getattr(WorktreeManager, "delete")), (
            "WorktreeManager.delete が callable でない (AC4-3 未実装)"
        )

    def test_ac43_workTreeManager_list_porcelain_method_exists(self):
        # AC: WorktreeManager.list_porcelain method が worktree.py に存在すること
        # RED: list_porcelain が未実装のため FAIL する
        from twl.autopilot.worktree import WorktreeManager
        assert hasattr(WorktreeManager, "list_porcelain"), (
            "WorktreeManager に list_porcelain method が存在しない (AC4-3 未実装)"
        )
        assert callable(getattr(WorktreeManager, "list_porcelain")), (
            "WorktreeManager.list_porcelain が callable でない (AC4-3 未実装)"
        )

    def test_ac43_workTreeManager_list_porcelain_returns_list_of_dict(self):
        # AC: WorktreeManager.list_porcelain が list[dict] を返すこと
        # RED: list_porcelain が未実装のため FAIL する
        from twl.autopilot.worktree import WorktreeManager

        mock_porcelain = (
            "worktree /tmp/proj/main\n"
            "HEAD abc123\n"
            "branch refs/heads/main\n\n"
            "worktree /tmp/proj/worktrees/feat/123-test\n"
            "HEAD def456\n"
            "branch refs/heads/feat/123-test\n\n"
        )
        with patch("subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.returncode = 0
            mock_result.stdout = mock_porcelain
            mock_run.return_value = mock_result
            mgr = WorktreeManager()
            result = mgr.list_porcelain()

        assert isinstance(result, list), (
            f"list_porcelain が list を返さない: {type(result)} (AC4-3 未実装)"
        )
        if result:
            assert isinstance(result[0], dict), (
                f"list_porcelain の要素が dict でない: {type(result[0])} (AC4-3 未実装)"
            )

    def test_ac43_twl_worktree_generate_branch_name_handler_issue_number_is_str(self):
        # AC: twl_worktree_generate_branch_name_handler の引数 issue_number が str 型であること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server import tools
        handler = getattr(tools, "twl_worktree_generate_branch_name_handler", None)
        assert handler is not None, (
            "twl_worktree_generate_branch_name_handler が存在しない (AC4-3 未実装)"
        )
        sig = inspect.signature(handler)
        assert "issue_number" in sig.parameters, (
            "twl_worktree_generate_branch_name_handler に issue_number 引数がない (AC4-3 未実装)"
        )
        param = sig.parameters["issue_number"]
        assert param.annotation == str or str(param.annotation) == "str", (
            f"issue_number の型が str でない: {param.annotation} (AC4-3 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4-5: 不変条件 B CWD-based role check
# ---------------------------------------------------------------------------


class TestAC45InvariantBCwdCheck:
    """AC4-5: 不変条件 B CWD-based role check.

    CWD が worktrees/ 配下の場合 twl_worktree_create/delete_handler は
    invariant_b_violation で拒否すること。
    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac45_worktree_create_from_worktrees_cwd_rejected(self):
        # AC: CWD が /tmp/xxx/worktrees/feat-test/ (realpath 後も /worktrees/ 含む) 状態で
        #     twl_worktree_create_handler 呼出 → {"ok": False, "error_type": "invariant_b_violation", "exit_code": 1}
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_worktree_create_handler

        with patch("os.getcwd", return_value="/tmp/proj/worktrees/feat-test"):
            with patch("os.path.realpath", return_value="/tmp/proj/worktrees/feat-test"):
                result = twl_worktree_create_handler(
                    branch="feat/999-test",
                    timeout_sec=60,
                )
        assert isinstance(result, dict), "handler が dict を返さない (AC4-5 未実装)"
        assert result.get("ok") is False, "ok が False でない (AC4-5 未実装)"
        assert result.get("error_type") == "invariant_b_violation", (
            f"error_type が 'invariant_b_violation' でない: {result.get('error_type')} (AC4-5 未実装)"
        )
        assert result.get("exit_code") == 1, (
            f"exit_code が 1 でない: {result.get('exit_code')} (AC4-5 未実装)"
        )

    def test_ac45_worktree_delete_from_worktrees_cwd_rejected(self):
        # AC: CWD が /tmp/xxx/worktrees/feat-test/ 状態で twl_worktree_delete_handler 呼出
        #     → {"ok": False, "error_type": "invariant_b_violation", "exit_code": 1}
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_worktree_delete_handler

        with patch("os.getcwd", return_value="/tmp/proj/worktrees/feat-test"):
            with patch("os.path.realpath", return_value="/tmp/proj/worktrees/feat-test"):
                result = twl_worktree_delete_handler(
                    branch="feat/999-test",
                    timeout_sec=60,
                )
        assert isinstance(result, dict), "handler が dict を返さない (AC4-5 未実装)"
        assert result.get("ok") is False, "ok が False でない (AC4-5 未実装)"
        assert result.get("error_type") == "invariant_b_violation", (
            f"error_type が 'invariant_b_violation' でない: {result.get('error_type')} (AC4-5 未実装)"
        )
        assert result.get("exit_code") == 1, (
            f"exit_code が 1 でない: {result.get('exit_code')} (AC4-5 未実装)"
        )

    def test_ac45_worktree_create_from_main_cwd_not_rejected(self):
        # AC: CWD が /tmp/xxx/main/ 状態で twl_worktree_create_handler 呼出
        #     → invariant_b_violation ではない（通常実行パスに入る）
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_worktree_create_handler

        with patch("os.getcwd", return_value="/tmp/proj/main"):
            with patch("os.path.realpath", return_value="/tmp/proj/main"):
                # 通常実行パスで WorktreeManager.create が呼ばれる想定
                # 実際の git コマンドは mock して create 自体はエラーになってよい
                with patch(
                    "twl.autopilot.worktree.WorktreeManager.create",
                    side_effect=Exception("mock create failure"),
                ):
                    result = twl_worktree_create_handler(
                        branch="feat/999-test",
                        timeout_sec=60,
                    )
        assert isinstance(result, dict), "handler が dict を返さない (AC4-5 未実装)"
        # invariant_b_violation ではないこと
        assert result.get("error_type") != "invariant_b_violation", (
            "main/ CWD でも invariant_b_violation が返された (AC4-5 実装誤り)"
        )


# ---------------------------------------------------------------------------
# AC4-6: critical assertion 群
# ---------------------------------------------------------------------------


class TestAC46CriticalAssertions:
    """AC4-6: critical assertion 群.

    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac46_twl_worktree_list_handler_returns_list_dict_structure(self):
        # AC: twl_worktree_list_handler が list[dict] 構造を含む dict を返すこと
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_worktree_list_handler

        mock_porcelain = (
            "worktree /tmp/proj/main\n"
            "HEAD abc123\n"
            "branch refs/heads/main\n\n"
        )
        with patch("subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.returncode = 0
            mock_result.stdout = mock_porcelain
            mock_run.return_value = mock_result

            result = twl_worktree_list_handler()

        assert isinstance(result, dict), (
            f"twl_worktree_list_handler が dict を返さない: {type(result)} (AC4-6 未実装)"
        )
        assert "ok" in result, (
            f"dict に ok キーがない: {list(result.keys())} (AC4-6 未実装)"
        )
        # ok=True の場合 "result" フィールドが list[dict] であること
        if result.get("ok"):
            entries = result.get("result", [])
            assert isinstance(entries, list), (
                f"result フィールドが list でない: {type(entries)} (AC4-6 未実装)"
            )

    def test_ac46_twl_worktree_validate_branch_name_handler_catches_worktree_arg_error(self):
        # AC: twl_worktree_validate_branch_name_handler が WorktreeArgError を catch して
        #     envelope 返却すること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_worktree_validate_branch_name_handler
        from twl.autopilot.worktree import WorktreeArgError

        # 不正なブランチ名でも handler が例外を上に投げず envelope を返すこと
        result = twl_worktree_validate_branch_name_handler(branch="main")
        assert isinstance(result, dict), (
            f"handler が dict を返さない: {type(result)} (AC4-6 未実装)"
        )
        # "main" は予約語なので ok=False が期待される
        assert result.get("ok") is False, (
            "'main' ブランチで ok が False でない (AC4-6 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4-12: plan_file check
# ---------------------------------------------------------------------------


class TestAC412PlanFileCheck:
    """AC4-12: plan_file check.

    実装前は handler が存在しないため FAIL する（意図的 RED）。
    """

    def test_ac412_twl_orchestrator_get_phase_issues_handler_plan_file_missing(self):
        # AC: twl_orchestrator_get_phase_issues_handler も plan_file 不在で graceful return すること
        # RED: handler が存在しないため FAIL する
        from twl.mcp_server.tools import twl_orchestrator_get_phase_issues_handler

        result = twl_orchestrator_get_phase_issues_handler(
            phase=1,
            plan_file="/nonexistent/plan.yaml",
        )
        assert isinstance(result, dict), (
            f"handler が dict を返さない: {type(result)} (AC4-12 未実装)"
        )
        assert result.get("ok") is False, "ok が False でない (AC4-12 未実装)"
        # graceful return: 例外が上に漏れず dict が返ること自体が AC を満たす
        assert "error_type" in result, (
            f"error_type キーが result に存在しない: {list(result.keys())} (AC4-12 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4-13: docstring に timeout 注記
# ---------------------------------------------------------------------------


class TestAC413DocstringTimeoutNote:
    """AC4-13: docstring に timeout 注記.

    実装前は tool 関数が存在しないため AttributeError で FAIL する（意図的 RED）。
    """

    def test_ac413_twl_mergegate_run_docstring_has_mcp_client_timeout(self):
        # AC: twl_mergegate_run の docstring に "MCP_CLIENT_TIMEOUT" が含まれること
        # RED: tool が存在しないため FAIL する
        from twl.mcp_server import tools
        tool_fn = getattr(tools, "twl_mergegate_run", None)
        assert tool_fn is not None, "twl_mergegate_run が存在しない (AC4-13 未実装)"
        doc = tool_fn.__doc__ or ""
        assert "MCP_CLIENT_TIMEOUT" in doc, (
            "twl_mergegate_run の docstring に 'MCP_CLIENT_TIMEOUT' が含まれない (AC4-13 未実装)\n"
            f"docstring: {doc!r}"
        )

    def test_ac413_twl_orchestrator_phase_review_docstring_has_mcp_client_timeout(self):
        # AC: twl_orchestrator_phase_review の docstring に "MCP_CLIENT_TIMEOUT" が含まれること
        # RED: tool が存在しないため FAIL する
        from twl.mcp_server import tools
        tool_fn = getattr(tools, "twl_orchestrator_phase_review", None)
        assert tool_fn is not None, (
            "twl_orchestrator_phase_review が存在しない (AC4-13 未実装)"
        )
        doc = tool_fn.__doc__ or ""
        assert "MCP_CLIENT_TIMEOUT" in doc, (
            "twl_orchestrator_phase_review の docstring に 'MCP_CLIENT_TIMEOUT' が含まれない (AC4-13 未実装)\n"
            f"docstring: {doc!r}"
        )


# ---------------------------------------------------------------------------
# AC-naming-1: tool 名が snake_case で twl_<module>_<action> 規則に準拠
# ---------------------------------------------------------------------------


class TestACNaming1ToolNameConvention:
    """AC-naming-1: tool 名が snake_case で twl_<module>_<action> 規則に準拠していること.

    実装前は tool が存在しないため FAIL する（意図的 RED）。
    """

    def test_naming1_all_tools_follow_snake_case_convention(self):
        # AC: 12 tool 名が全て snake_case かつ twl_<module>_<action> 形式であること
        # RED: tool が存在しないため FAIL する
        import re
        from twl.mcp_server import tools

        snake_case_re = re.compile(r"^twl_[a-z][a-z0-9]*(_[a-z][a-z0-9]*)+$")
        invalid = []
        for name in EXPECTED_TOOL_NAMES:
            if not snake_case_re.match(name):
                invalid.append(name)

        assert not invalid, (
            f"以下の tool 名が snake_case/twl_<module>_<action> 規則に準拠していない: {invalid} (AC-naming-1 未実装)"
        )

        # tool が実際に存在することも確認
        missing = [name for name in EXPECTED_TOOL_NAMES if not hasattr(tools, name)]
        assert not missing, (
            f"tools.py に以下の tool が存在しない (AC-naming-1 未実装): {missing}"
        )


# ---------------------------------------------------------------------------
# AC-naming-2: 12 tool それぞれの docstring 1 行目が非空
# ---------------------------------------------------------------------------


class TestACNaming2DocstringNonEmpty:
    """AC-naming-2: 12 tool それぞれの docstring 1 行目が非空であること.

    実装前は tool が存在しないため FAIL する（意図的 RED）。
    """

    def test_naming2_all_tools_have_non_empty_docstring_first_line(self):
        # AC: 12 tool それぞれの docstring 1 行目が非空であること
        # RED: tool が存在しないため FAIL する
        from twl.mcp_server import tools

        empty_doc_tools = []
        missing_tools = []
        for name in EXPECTED_TOOL_NAMES:
            tool_fn = getattr(tools, name, None)
            if tool_fn is None:
                missing_tools.append(name)
                continue
            doc = tool_fn.__doc__ or ""
            first_line = doc.strip().split("\n")[0].strip() if doc.strip() else ""
            if not first_line:
                empty_doc_tools.append(name)

        assert not missing_tools, (
            f"tools.py に以下の tool が存在しない (AC-naming-2 未実装): {missing_tools}"
        )
        assert not empty_doc_tools, (
            f"以下の tool の docstring 1 行目が空: {empty_doc_tools} (AC-naming-2 未実装)"
        )
