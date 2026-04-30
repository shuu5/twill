"""Tests for Issue #1129: fix(mcp): merge-gate specialist tools.py fixes.

TDD RED phase test stubs.
All tests FAIL before implementation (intentional RED).

AC list:
  AC1: twl_mergegate_reject_handler の except SystemExit 節に if code == 0: early-return が存在する
  AC2: twl_mergegate_reject_final_handler の except SystemExit 節にも対称な if code == 0: early-return が存在する
  AC3a: twl_orchestrator_phase_review_handler シグネチャに cwd: str | None = None 引数が存在し
        本体冒頭で _check_invariant_b(cwd) を呼び出している
  AC3b: cwd を /worktrees/ 配下にして handler を直接呼び出すと
        {ok: False, error_type: "invariant_b_violation", exit_code: 1} になる
  AC4: MCP wrapper の try branch (L954 周辺) と except-ImportError branch (L1077 周辺) の
       両方の twl_orchestrator_phase_review シグネチャに cwd が存在し、
       handler 呼び出しに cwd=cwd が渡されている
  AC5: twl_orchestrator_summary_handler の最後の except 節として except Exception が存在する
  AC6: twl_worktree_delete_handler._inner() の最後の except 節として except Exception が存在する
  AC7: cli/twl/tests/test_issue_1114_autopilot_tools.py の TestAC42OrchestratorHandlers 内
       phase_review_handler 呼び出し 2 箇所に cwd="/tmp/main" 引数が含まれている
"""

from __future__ import annotations

import ast
import inspect
import sys
from pathlib import Path

import pytest

WORKTREE_ROOT = Path(__file__).resolve().parent.parent
TOOLS_PY = WORKTREE_ROOT / "src" / "twl" / "mcp_server" / "tools.py"
TEST_1114_PY = WORKTREE_ROOT / "tests" / "test_issue_1114_autopilot_tools.py"


# ---------------------------------------------------------------------------
# AC1: twl_mergegate_reject_handler の except SystemExit 節に
#       if code == 0: early-return (ok:True, message:"rejected (exit 0)") が存在する
# ---------------------------------------------------------------------------


class TestAC1MergeGateRejectHandlerEarlyReturn:
    """AC1: twl_mergegate_reject_handler が SystemExit(0) を ok:True で返すこと."""

    def test_ac1_reject_handler_systemexit0_returns_ok_true(self):
        # AC: SystemExit(0) の場合 ok:True, message:"rejected (exit 0)" が返ること
        # RED: 現在の実装では exit 0 でも ok:False を返すため FAIL する
        from unittest.mock import MagicMock, patch

        from twl.mcp_server.tools import twl_mergegate_reject_handler

        # gh pr view を成功させ、MergeGate.reject() が SystemExit(0) を発生させる mock
        # label は "issue-N" 形式 (_resolve_issue_from_labels の規則)
        mock_pr_data = '{"number": 1, "headRefName": "feat/1-test", "labels": [{"name": "issue-1"}]}'
        mock_run = MagicMock()
        mock_run.returncode = 0
        mock_run.stdout = mock_pr_data

        with (
            patch("subprocess.run", return_value=mock_run),
            patch("twl.autopilot.mergegate.MergeGate.reject", side_effect=SystemExit(0)),
        ):
            result = twl_mergegate_reject_handler(
                pr_number=1,
                reason="test reason",
                timeout_sec=None,
            )

        assert result.get("ok") is True, (
            f"AC1 未実装: SystemExit(0) 時に ok:True が返らない。got={result}"
        )
        assert result.get("message") == "rejected (exit 0)", (
            f"AC1 未実装: message が 'rejected (exit 0)' でない。got={result.get('message')}"
        )

    def test_ac1_reject_handler_systemexit0_source_check(self):
        # AC: ソースコードに if code == 0: early-return パターンが存在すること
        # RED: 現在の except SystemExit 節には if code == 0: が存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        # twl_mergegate_reject_handler の定義箇所を抽出して確認
        handler_start = source.find("def twl_mergegate_reject_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        assert "if code == 0:" in handler_source, (
            "AC1 未実装: twl_mergegate_reject_handler の except SystemExit 節に "
            "'if code == 0:' early-return が存在しない"
        )
        assert '"rejected (exit 0)"' in handler_source, (
            "AC1 未実装: twl_mergegate_reject_handler に "
            "message='rejected (exit 0)' の early-return が存在しない"
        )


# ---------------------------------------------------------------------------
# AC2: twl_mergegate_reject_final_handler の except SystemExit 節にも
#       対称な if code == 0: early-return が存在する
# ---------------------------------------------------------------------------


class TestAC2MergeGateRejectFinalHandlerEarlyReturn:
    """AC2: twl_mergegate_reject_final_handler が SystemExit(0) を ok:True で返すこと."""

    def test_ac2_reject_final_handler_systemexit0_returns_ok_true(self):
        # AC: SystemExit(0) の場合 ok:True, message:"reject_final completed (exit 0)" が返ること
        # RED: 現在の実装では exit 0 でも ok:False を返すため FAIL する
        from unittest.mock import MagicMock, patch

        from twl.mcp_server.tools import twl_mergegate_reject_final_handler

        # label は "issue-N" 形式 (_resolve_issue_from_labels の規則)
        mock_pr_data = '{"number": 1, "headRefName": "feat/1-test", "labels": [{"name": "issue-1"}]}'
        mock_run = MagicMock()
        mock_run.returncode = 0
        mock_run.stdout = mock_pr_data

        with (
            patch("subprocess.run", return_value=mock_run),
            patch("twl.autopilot.mergegate.MergeGate.reject_final", side_effect=SystemExit(0)),
        ):
            result = twl_mergegate_reject_final_handler(
                pr_number=1,
                reason="test reason",
                timeout_sec=None,
            )

        assert result.get("ok") is True, (
            f"AC2 未実装: SystemExit(0) 時に ok:True が返らない。got={result}"
        )
        assert result.get("message") == "reject_final completed (exit 0)", (
            f"AC2 未実装: message が 'reject_final completed (exit 0)' でない。"
            f"got={result.get('message')}"
        )

    def test_ac2_reject_final_handler_systemexit0_source_check(self):
        # AC: ソースコードに if code == 0: early-return パターンが存在すること
        # RED: 現在の except SystemExit 節には if code == 0: が存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_mergegate_reject_final_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        assert "if code == 0:" in handler_source, (
            "AC2 未実装: twl_mergegate_reject_final_handler の except SystemExit 節に "
            "'if code == 0:' early-return が存在しない"
        )
        assert '"reject_final completed (exit 0)"' in handler_source, (
            "AC2 未実装: twl_mergegate_reject_final_handler に "
            "message='reject_final completed (exit 0)' の early-return が存在しない"
        )


# ---------------------------------------------------------------------------
# AC3a: twl_orchestrator_phase_review_handler シグネチャに cwd: str | None = None 引数が
#        存在し、本体冒頭で _check_invariant_b(cwd) を呼び出している
# ---------------------------------------------------------------------------


class TestAC3aOrchestratorPhaseReviewHandlerCwdArg:
    """AC3a: twl_orchestrator_phase_review_handler に cwd 引数と invariant_b check が存在すること."""

    def test_ac3a_phase_review_handler_has_cwd_param(self):
        # AC: シグネチャに cwd: str | None = None が存在すること
        # RED: 現在の handler シグネチャに cwd 引数が存在しないため FAIL する
        from twl.mcp_server.tools import twl_orchestrator_phase_review_handler

        sig = inspect.signature(twl_orchestrator_phase_review_handler)
        assert "cwd" in sig.parameters, (
            "AC3a 未実装: twl_orchestrator_phase_review_handler シグネチャに 'cwd' 引数が存在しない"
        )
        param = sig.parameters["cwd"]
        assert param.default is None, (
            f"AC3a 未実装: 'cwd' 引数のデフォルト値が None でない。got={param.default}"
        )

    def test_ac3a_phase_review_handler_calls_check_invariant_b(self):
        # AC: handler 本体冒頭で _check_invariant_b(cwd) を呼び出していること
        # RED: 現在の handler に _check_invariant_b 呼び出しが存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_orchestrator_phase_review_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        assert "_check_invariant_b(cwd)" in handler_source, (
            "AC3a 未実装: twl_orchestrator_phase_review_handler 本体に "
            "'_check_invariant_b(cwd)' 呼び出しが存在しない"
        )


# ---------------------------------------------------------------------------
# AC3b: cwd を /worktrees/ 配下にして handler を直接呼び出すと
#         {ok: False, error_type: "invariant_b_violation", exit_code: 1} になる
# ---------------------------------------------------------------------------


class TestAC3bOrchestratorPhaseReviewInvariantBViolation:
    """AC3b: worktrees/ 配下 cwd で phase_review_handler が invariant_b_violation を返すこと."""

    def test_ac3b_phase_review_handler_worktrees_cwd_returns_invariant_b_violation(self):
        # AC: cwd=/tmp/worktrees/test で呼び出すと ok:False, error_type:"invariant_b_violation"
        # RED: handler に cwd 引数と invariant_b check が存在しないため FAIL する
        from twl.mcp_server.tools import twl_orchestrator_phase_review_handler

        result = twl_orchestrator_phase_review_handler(
            phase=1,
            plan_file="/nonexistent/plan.yaml",
            session_file="/tmp/session.json",
            project_dir="/tmp/proj",
            autopilot_dir="/tmp/.autopilot",
            cwd="/tmp/worktrees/test",
            timeout_sec=60,
        )

        assert result.get("ok") is False, (
            f"AC3b 未実装: worktrees/ 配下 cwd で ok:False が返らない。got={result}"
        )
        assert result.get("error_type") == "invariant_b_violation", (
            f"AC3b 未実装: error_type が 'invariant_b_violation' でない。"
            f"got={result.get('error_type')}"
        )
        assert result.get("exit_code") == 1, (
            f"AC3b 未実装: exit_code が 1 でない。got={result.get('exit_code')}"
        )


# ---------------------------------------------------------------------------
# AC4: MCP wrapper の try branch と except-ImportError branch 両方の
#       twl_orchestrator_phase_review シグネチャに cwd が存在し、
#       handler 呼び出しに cwd=cwd が渡されている
# ---------------------------------------------------------------------------


class TestAC4MergeGatePhaseReviewWrapperCwd:
    """AC4: MCP wrapper 両 branch の twl_orchestrator_phase_review に cwd 引数が存在すること."""

    def test_ac4_try_branch_phase_review_has_cwd_param(self):
        # AC: try branch (L954 周辺) の twl_orchestrator_phase_review シグネチャに cwd が存在すること
        # RED: 現在の try branch シグネチャに cwd が含まれていないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")

        # try branch 内の twl_orchestrator_phase_review 定義を検索
        # "except ImportError:" より前の定義が try branch
        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        # try branch の twl_orchestrator_phase_review 定義行を探す
        phase_review_def_pos = try_branch_source.rfind("def twl_orchestrator_phase_review(")
        assert phase_review_def_pos != -1, (
            "AC4 未実装: try branch に twl_orchestrator_phase_review 定義が見つからない"
        )

        # 定義行の終わり（次の改行まで）を取得
        def_line_end = try_branch_source.find("\n", phase_review_def_pos)
        def_line = try_branch_source[phase_review_def_pos:def_line_end]

        assert "cwd" in def_line, (
            f"AC4 未実装: try branch の twl_orchestrator_phase_review シグネチャに 'cwd' が存在しない。"
            f"got={def_line}"
        )

    def test_ac4_except_importerror_branch_phase_review_has_cwd_param(self):
        # AC: except-ImportError branch (L1077 周辺) の twl_orchestrator_phase_review シグネチャに cwd が存在すること
        # RED: 現在の except-ImportError branch シグネチャに cwd が含まれていないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")

        # except ImportError: より後の定義が except-ImportError branch
        except_import_pos = source.find("except ImportError:")
        except_branch_source = source[except_import_pos:]

        phase_review_def_pos = except_branch_source.find("def twl_orchestrator_phase_review(")
        assert phase_review_def_pos != -1, (
            "AC4 未実装: except-ImportError branch に twl_orchestrator_phase_review 定義が見つからない"
        )

        def_line_end = except_branch_source.find("\n", phase_review_def_pos)
        def_line = except_branch_source[phase_review_def_pos:def_line_end]

        assert "cwd" in def_line, (
            f"AC4 未実装: except-ImportError branch の twl_orchestrator_phase_review シグネチャに "
            f"'cwd' が存在しない。got={def_line}"
        )

    def test_ac4_try_branch_phase_review_passes_cwd_to_handler(self):
        # AC: try branch の handler 呼び出しに cwd=cwd が渡されていること
        # RED: 現在の handler 呼び出しに cwd=cwd が含まれていないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        phase_review_def_pos = try_branch_source.rfind("def twl_orchestrator_phase_review(")
        # 定義から次の @mcp.tool() または def まで
        next_def_pos = try_branch_source.find("\n    @mcp.tool()", phase_review_def_pos + 1)
        if next_def_pos == -1:
            next_def_pos = len(try_branch_source)
        body_source = try_branch_source[phase_review_def_pos:next_def_pos]

        assert "cwd=cwd" in body_source, (
            "AC4 未実装: try branch の twl_orchestrator_phase_review_handler 呼び出しに "
            "'cwd=cwd' が含まれていない"
        )

    def test_ac4_except_importerror_branch_phase_review_passes_cwd_to_handler(self):
        # AC: except-ImportError branch の handler 呼び出しに cwd=cwd が渡されていること
        # RED: 現在の handler 呼び出しに cwd=cwd が含まれていないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        except_branch_source = source[except_import_pos:]

        phase_review_def_pos = except_branch_source.find("def twl_orchestrator_phase_review(")
        next_def_pos = except_branch_source.find("\n    def ", phase_review_def_pos + 1)
        if next_def_pos == -1:
            next_def_pos = len(except_branch_source)
        body_source = except_branch_source[phase_review_def_pos:next_def_pos]

        assert "cwd=cwd" in body_source, (
            "AC4 未実装: except-ImportError branch の twl_orchestrator_phase_review_handler 呼び出しに "
            "'cwd=cwd' が含まれていない"
        )


# ---------------------------------------------------------------------------
# AC5: twl_orchestrator_summary_handler の最後の except 節として
#       except Exception が存在する
# ---------------------------------------------------------------------------


class TestAC5OrchestratorSummaryHandlerExceptException:
    """AC5: twl_orchestrator_summary_handler の最後の except 節が except Exception であること."""

    def test_ac5_summary_handler_has_except_exception(self):
        # AC: handler 本体の最後の except 節として except Exception が存在すること
        # RED: 現在の handler には except OrchestratorError のみで except Exception が存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_orchestrator_summary_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        assert "except Exception" in handler_source, (
            "AC5 未実装: twl_orchestrator_summary_handler に "
            "'except Exception' 節が存在しない"
        )

    def test_ac5_summary_handler_except_exception_is_last(self):
        # AC: except Exception が最後の except 節（OrchestratorError より後）であること
        # RED: except Exception が存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_orchestrator_summary_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        orchestrator_error_pos = handler_source.find("except OrchestratorError")
        except_exception_pos = handler_source.find("except Exception")

        assert except_exception_pos != -1, (
            "AC5 未実装: twl_orchestrator_summary_handler に 'except Exception' が存在しない"
        )
        assert orchestrator_error_pos == -1 or except_exception_pos > orchestrator_error_pos, (
            "AC5 未実装: 'except Exception' が 'except OrchestratorError' より前に存在する"
        )


# ---------------------------------------------------------------------------
# AC6: twl_worktree_delete_handler._inner() の最後の except 節として
#       except Exception が存在する
# ---------------------------------------------------------------------------


class TestAC6WorktreeDeleteHandlerExceptException:
    """AC6: twl_worktree_delete_handler._inner() の最後の except 節が except Exception であること."""

    def test_ac6_worktree_delete_handler_inner_has_except_exception(self):
        # AC: _inner() の最後の except 節として except Exception が存在すること
        # RED: 現在の _inner() には WorktreeArgError と WorktreeError のみで
        #       except Exception が存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_worktree_delete_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        assert "except Exception" in handler_source, (
            "AC6 未実装: twl_worktree_delete_handler._inner() に "
            "'except Exception' 節が存在しない"
        )

    def test_ac6_worktree_delete_handler_inner_except_exception_is_last(self):
        # AC: except Exception が _inner() 内の最後の except 節であること
        # RED: except Exception が存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_worktree_delete_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        worktree_error_pos = handler_source.rfind("except WorktreeError")
        except_exception_pos = handler_source.find("except Exception")

        assert except_exception_pos != -1, (
            "AC6 未実装: twl_worktree_delete_handler に 'except Exception' が存在しない"
        )
        assert worktree_error_pos == -1 or except_exception_pos > worktree_error_pos, (
            "AC6 未実装: 'except Exception' が 'except WorktreeError' より前に存在する"
        )


# ---------------------------------------------------------------------------
# AC7: test_issue_1114_autopilot_tools.py の TestAC42OrchestratorHandlers 内
#       phase_review_handler 呼び出し 2 箇所に cwd="/tmp/main" 引数が含まれている
# ---------------------------------------------------------------------------


class TestAC7Test1114PhaseReviewHandlerCwdArgument:
    """AC7: test_issue_1114_autopilot_tools.py の phase_review_handler 呼び出しに cwd="/tmp/main" が 2 箇所存在すること."""

    def test_ac7_test_1114_exists(self):
        # 前提: test_issue_1114_autopilot_tools.py が存在すること
        assert TEST_1114_PY.exists(), (
            f"test_issue_1114_autopilot_tools.py が存在しない: {TEST_1114_PY}"
        )

    def test_ac7_phase_review_handler_calls_have_cwd_main(self):
        # AC: TestAC42OrchestratorHandlers 内の phase_review_handler 呼び出し 2 箇所に
        #     cwd="/tmp/main" が含まれていること
        # RED: 現在の test_issue_1114_autopilot_tools.py の phase_review_handler 呼び出しに
        #      cwd="/tmp/main" が存在しないため FAIL する
        source = TEST_1114_PY.read_text(encoding="utf-8")

        # TestAC42OrchestratorHandlers クラスの範囲を特定
        class_start = source.find("class TestAC42OrchestratorHandlers")
        assert class_start != -1, (
            "AC7 未実装: TestAC42OrchestratorHandlers クラスが test_issue_1114 に存在しない"
        )

        # クラス終端を特定（次のクラス定義まで）
        next_class_pos = source.find("\nclass ", class_start + 1)
        class_source = source[class_start:next_class_pos] if next_class_pos != -1 else source[class_start:]

        # cwd="/tmp/main" の出現回数をカウント
        count = class_source.count('cwd="/tmp/main"')
        assert count >= 2, (
            f"AC7 未実装: TestAC42OrchestratorHandlers 内の phase_review_handler 呼び出しに "
            f'cwd="/tmp/main" が {count} 箇所しかない（2 箇所必要）'
        )

    def test_ac7_phase_review_handler_specific_calls_have_cwd(self):
        # AC: plan_file_missing テストと tmux_not_found テストの両方に cwd="/tmp/main" があること
        # RED: 現在のテストに cwd="/tmp/main" が存在しないため FAIL する
        source = TEST_1114_PY.read_text(encoding="utf-8")

        # plan_file_missing テストに cwd="/tmp/main" があること
        missing_test_start = source.find("def test_ac42_twl_orchestrator_phase_review_handler_plan_file_missing")
        missing_test_end = source.find("\n    def ", missing_test_start + 1)
        missing_source = source[missing_test_start:missing_test_end] if missing_test_end != -1 else source[missing_test_start:]

        assert 'cwd="/tmp/main"' in missing_source, (
            "AC7 未実装: test_ac42_twl_orchestrator_phase_review_handler_plan_file_missing に "
            'cwd="/tmp/main" が存在しない'
        )

        # tmux_not_found テストに cwd="/tmp/main" があること
        tmux_test_start = source.find("def test_ac42_twl_orchestrator_phase_review_handler_tmux_not_found")
        tmux_test_end = source.find("\n    def ", tmux_test_start + 1)
        tmux_source = source[tmux_test_start:tmux_test_end] if tmux_test_end != -1 else source[tmux_test_start:]

        assert 'cwd="/tmp/main"' in tmux_source, (
            "AC7 未実装: test_ac42_twl_orchestrator_phase_review_handler_tmux_not_found に "
            'cwd="/tmp/main" が存在しない'
        )
