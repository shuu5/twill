"""Tests for Issue #1173: fix(mcp): twl_mergegate_reject / reject_final に invariant B check を追加.

TDD RED phase test stubs.
All tests FAIL before implementation (intentional RED).

AC list:
  AC1: twl_mergegate_reject_handler の本体先頭で violation = _check_invariant_b(cwd) を呼び、
       violation が非 None の場合は即座に violation を return する
  AC2: twl_mergegate_reject_final_handler の本体先頭で同一処理を行う
  AC3: worktrees/ 配下を cwd に渡したケースで両 handler が
       {"ok": false, "error_type": "invariant_b_violation", "exit_code": 1, ...} を返す
       (reject / reject_final それぞれ最低 1 ケース)
  AC4: main/ 配下 (もしくは cwd=None) を渡したケースで violation 判定が None となり
       MergeGate.reject() / reject_final() の subprocess 呼び出しに到達する
       (subprocess は monkeypatch でモック可)
  AC5: tool 登録 (L956 / L961 / L1081 / L1085) の signature を変更しない
       (cwd: str | None = None をそのまま handler に pass する後方互換)
  AC6: 修正後 pytest cli/twl/tests/test_issue_1173_mergegate_invariant_b.py 全 PASS
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

WORKTREE_ROOT = Path(__file__).resolve().parent.parent
TOOLS_PY = WORKTREE_ROOT / "src" / "twl" / "mcp_server" / "tools.py"


# ---------------------------------------------------------------------------
# AC1: twl_mergegate_reject_handler の本体先頭で
#       violation = _check_invariant_b(cwd) を呼び出している
# ---------------------------------------------------------------------------


class TestAC1RejectHandlerCallsCheckInvariantB:
    """AC1: twl_mergegate_reject_handler 本体先頭に _check_invariant_b(cwd) 呼び出しが存在すること."""

    def test_ac1_reject_handler_source_has_check_invariant_b(self):
        # AC: ソースコードの twl_mergegate_reject_handler 本体に
        #     _check_invariant_b(cwd) の呼び出しが存在すること
        # RED: 現在の実装には _check_invariant_b(cwd) 呼び出しが存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_mergegate_reject_handler(")
        assert handler_start != -1, "twl_mergegate_reject_handler が tools.py に存在しない"
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        assert "_check_invariant_b(cwd)" in handler_source, (
            "AC1 未実装: twl_mergegate_reject_handler 本体に "
            "'_check_invariant_b(cwd)' 呼び出しが存在しない"
        )

    def test_ac1_reject_handler_source_has_violation_early_return(self):
        # AC: violation が非 None の場合に violation を return するパターンが存在すること
        # RED: 現在の実装には violation return が存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_mergegate_reject_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        # _check_invariant_b の呼び出し + violation の early return パターン確認
        # パターン: violation = _check_invariant_b(cwd) の直後に if violation: return violation
        assert "_check_invariant_b(cwd)" in handler_source, (
            "AC1 未実装: twl_mergegate_reject_handler に _check_invariant_b(cwd) がない"
        )
        assert "return violation" in handler_source, (
            "AC1 未実装: twl_mergegate_reject_handler に 'return violation' がない"
        )


# ---------------------------------------------------------------------------
# AC2: twl_mergegate_reject_final_handler の本体先頭で同一処理を行う
# ---------------------------------------------------------------------------


class TestAC2RejectFinalHandlerCallsCheckInvariantB:
    """AC2: twl_mergegate_reject_final_handler 本体先頭に _check_invariant_b(cwd) 呼び出しが存在すること."""

    def test_ac2_reject_final_handler_source_has_check_invariant_b(self):
        # AC: ソースコードの twl_mergegate_reject_final_handler 本体に
        #     _check_invariant_b(cwd) の呼び出しが存在すること
        # RED: 現在の実装には _check_invariant_b(cwd) 呼び出しが存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_mergegate_reject_final_handler(")
        assert handler_start != -1, "twl_mergegate_reject_final_handler が tools.py に存在しない"
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        assert "_check_invariant_b(cwd)" in handler_source, (
            "AC2 未実装: twl_mergegate_reject_final_handler 本体に "
            "'_check_invariant_b(cwd)' 呼び出しが存在しない"
        )

    def test_ac2_reject_final_handler_source_has_violation_early_return(self):
        # AC: violation が非 None の場合に violation を return するパターンが存在すること
        # RED: 現在の実装には violation return が存在しないため FAIL する
        source = TOOLS_PY.read_text(encoding="utf-8")
        handler_start = source.find("def twl_mergegate_reject_final_handler(")
        handler_end = source.find("\ndef ", handler_start + 1)
        handler_source = source[handler_start:handler_end]

        assert "_check_invariant_b(cwd)" in handler_source, (
            "AC2 未実装: twl_mergegate_reject_final_handler に _check_invariant_b(cwd) がない"
        )
        assert "return violation" in handler_source, (
            "AC2 未実装: twl_mergegate_reject_final_handler に 'return violation' がない"
        )


# ---------------------------------------------------------------------------
# AC3: worktrees/ 配下を cwd に渡したケースで両 handler が
#       {"ok": false, "error_type": "invariant_b_violation", "exit_code": 1} を返す
# ---------------------------------------------------------------------------


class TestAC3RejectHandlerWorktreesCwdViolation:
    """AC3 (reject): worktrees/ 配下 cwd で twl_mergegate_reject_handler が invariant_b_violation を返すこと."""

    def test_ac3_reject_handler_worktrees_cwd_returns_violation(self):
        # AC: cwd="/tmp/worktrees/feat/1173-test" で呼び出すと
        #     {"ok": False, "error_type": "invariant_b_violation", "exit_code": 1} が返ること
        # RED: handler に _check_invariant_b(cwd) が存在しないため FAIL する
        from twl.mcp_server.tools import twl_mergegate_reject_handler

        result = twl_mergegate_reject_handler(
            pr_number=1173,
            reason="test violation check",
            cwd="/tmp/worktrees/feat/1173-test",
            timeout_sec=None,
        )

        assert result.get("ok") is False, (
            f"AC3 未実装: worktrees/ cwd で ok:False が返らない。got={result}"
        )
        assert result.get("error_type") == "invariant_b_violation", (
            f"AC3 未実装: error_type が 'invariant_b_violation' でない。"
            f"got={result.get('error_type')}"
        )
        assert result.get("exit_code") == 1, (
            f"AC3 未実装: exit_code が 1 でない。got={result.get('exit_code')}"
        )


class TestAC3RejectFinalHandlerWorktreesCwdViolation:
    """AC3 (reject_final): worktrees/ 配下 cwd で twl_mergegate_reject_final_handler が invariant_b_violation を返すこと."""

    def test_ac3_reject_final_handler_worktrees_cwd_returns_violation(self):
        # AC: cwd="/home/user/worktrees/feat/1173-test" で呼び出すと
        #     {"ok": False, "error_type": "invariant_b_violation", "exit_code": 1} が返ること
        # RED: handler に _check_invariant_b(cwd) が存在しないため FAIL する
        from twl.mcp_server.tools import twl_mergegate_reject_final_handler

        result = twl_mergegate_reject_final_handler(
            pr_number=1173,
            reason="test violation check",
            cwd="/home/user/worktrees/feat/1173-test",
            timeout_sec=None,
        )

        assert result.get("ok") is False, (
            f"AC3 未実装: worktrees/ cwd で ok:False が返らない。got={result}"
        )
        assert result.get("error_type") == "invariant_b_violation", (
            f"AC3 未実装: error_type が 'invariant_b_violation' でない。"
            f"got={result.get('error_type')}"
        )
        assert result.get("exit_code") == 1, (
            f"AC3 未実装: exit_code が 1 でない。got={result.get('exit_code')}"
        )


# ---------------------------------------------------------------------------
# AC4: main/ 配下 (もしくは cwd=None) を渡したケースで violation 判定が None となり
#       MergeGate.reject() / reject_final() の subprocess 呼び出しに到達する
#       (regression、subprocess は monkeypatch でモック可)
# ---------------------------------------------------------------------------


class TestAC4RejectHandlerMainCwdReachesSubprocess:
    """AC4 (reject): main/ cwd または cwd=None で twl_mergegate_reject_handler が subprocess に到達すること."""

    def test_ac4_reject_handler_main_cwd_reaches_subprocess(self):
        # AC: cwd="/home/user/main" で呼び出すと invariant_b_violation にならず
        #     subprocess.run (gh pr view) が呼ばれること
        # RED: handler に _check_invariant_b が実装されても、cwd=None/main の場合は
        #     subprocess に到達するはず。この regression テストは現在 FAIL しない可能性があるが、
        #     実装後も PASS し続けることを保証するために含める。
        #     現在は _check_invariant_b(cwd) がないので subprocess.run が必ず呼ばれるため、
        #     mock が呼ばれることは確認できる。
        from twl.mcp_server.tools import twl_mergegate_reject_handler

        mock_run = MagicMock()
        mock_run.returncode = 1
        mock_run.stderr = "not found"
        mock_run.stdout = ""

        with patch("subprocess.run", return_value=mock_run) as mock_subprocess:
            result = twl_mergegate_reject_handler(
                pr_number=1173,
                reason="test main cwd",
                cwd="/home/user/main",
                timeout_sec=None,
            )

        # subprocess.run が呼ばれていること（violation による early return ではない）
        assert mock_subprocess.called, (
            "AC4 未実装: cwd=main/ で subprocess.run が呼ばれていない "
            "（invariant_b_violation による早期 return が誤って発火している可能性）"
        )
        # 戻り値は pr_resolve_error（gh pr view が returncode=1 なので）
        assert result.get("error_type") != "invariant_b_violation", (
            f"AC4 未実装: main/ cwd で invariant_b_violation が返された。got={result}"
        )

    def test_ac4_reject_handler_none_cwd_reaches_subprocess(self):
        # AC: cwd=None (デフォルト) で呼び出すと subprocess.run が呼ばれること
        # RED: cwd=None での _check_invariant_b は実際の CWD を使う。テスト実行環境が
        #     worktrees/ 配下でない限り PASS するはずだが、明示的に確認する。
        from twl.mcp_server.tools import twl_mergegate_reject_handler

        mock_run = MagicMock()
        mock_run.returncode = 1
        mock_run.stderr = "not found"
        mock_run.stdout = ""

        with patch("subprocess.run", return_value=mock_run) as mock_subprocess:
            result = twl_mergegate_reject_handler(
                pr_number=1173,
                reason="test none cwd",
                cwd=None,
                timeout_sec=None,
            )

        assert mock_subprocess.called, (
            "AC4 未実装: cwd=None で subprocess.run が呼ばれていない"
        )
        assert result.get("error_type") != "invariant_b_violation", (
            f"AC4: cwd=None で invariant_b_violation が返された（テスト実行環境が worktrees/ 配下の可能性）。got={result}"
        )


class TestAC4RejectFinalHandlerMainCwdReachesSubprocess:
    """AC4 (reject_final): main/ cwd で twl_mergegate_reject_final_handler が subprocess に到達すること."""

    def test_ac4_reject_final_handler_main_cwd_reaches_subprocess(self):
        # AC: cwd="/home/user/main" で呼び出すと invariant_b_violation にならず
        #     subprocess.run (gh pr view) が呼ばれること
        from twl.mcp_server.tools import twl_mergegate_reject_final_handler

        mock_run = MagicMock()
        mock_run.returncode = 1
        mock_run.stderr = "not found"
        mock_run.stdout = ""

        with patch("subprocess.run", return_value=mock_run) as mock_subprocess:
            result = twl_mergegate_reject_final_handler(
                pr_number=1173,
                reason="test main cwd",
                cwd="/home/user/main",
                timeout_sec=None,
            )

        assert mock_subprocess.called, (
            "AC4 未実装: cwd=main/ で subprocess.run が呼ばれていない "
            "（invariant_b_violation による早期 return が誤って発火している可能性）"
        )
        assert result.get("error_type") != "invariant_b_violation", (
            f"AC4 未実装: main/ cwd で invariant_b_violation が返された。got={result}"
        )

    def test_ac4_reject_final_handler_none_cwd_reaches_subprocess(self):
        # AC: cwd=None (デフォルト) で呼び出すと subprocess.run が呼ばれること
        from twl.mcp_server.tools import twl_mergegate_reject_final_handler

        mock_run = MagicMock()
        mock_run.returncode = 1
        mock_run.stderr = "not found"
        mock_run.stdout = ""

        with patch("subprocess.run", return_value=mock_run) as mock_subprocess:
            result = twl_mergegate_reject_final_handler(
                pr_number=1173,
                reason="test none cwd",
                cwd=None,
                timeout_sec=None,
            )

        assert mock_subprocess.called, (
            "AC4 未実装: cwd=None で subprocess.run が呼ばれていない"
        )
        assert result.get("error_type") != "invariant_b_violation", (
            f"AC4: cwd=None で invariant_b_violation が返された（テスト実行環境が worktrees/ 配下の可能性）。got={result}"
        )


# ---------------------------------------------------------------------------
# AC5: tool 登録 (L956 / L961 / L1081 / L1085) の signature を変更しない
#       (cwd: str | None = None をそのまま handler に pass する後方互換)
# ---------------------------------------------------------------------------


class TestAC5ToolRegistrationSignatureBackwardCompat:
    """AC5: tools.py の MCP tool 登録箇所が cwd: str | None = None を handler に pass していること."""

    def test_ac5_try_branch_reject_signature_has_cwd(self):
        # AC: try branch (L956 周辺) の twl_mergegate_reject シグネチャに
        #     cwd: str | None = None が存在すること
        # PASS: 現在の実装では既に存在する（回帰防止テスト）
        source = TOOLS_PY.read_text(encoding="utf-8")

        # except ImportError: より前の部分が try branch
        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        # twl_mergegate_reject の定義行を探す（@mcp.tool() デコレート版）
        reject_def_pos = try_branch_source.rfind("def twl_mergegate_reject(")
        assert reject_def_pos != -1, (
            "AC5: try branch に twl_mergegate_reject 定義が見つからない"
        )
        def_line_end = try_branch_source.find("\n", reject_def_pos)
        def_line = try_branch_source[reject_def_pos:def_line_end]

        assert "cwd" in def_line, (
            f"AC5 破壊: try branch の twl_mergegate_reject シグネチャに 'cwd' が存在しない。"
            f"got={def_line}"
        )

    def test_ac5_try_branch_reject_final_signature_has_cwd(self):
        # AC: try branch (L961 周辺) の twl_mergegate_reject_final シグネチャに
        #     cwd: str | None = None が存在すること
        # PASS: 現在の実装では既に存在する（回帰防止テスト）
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        reject_final_def_pos = try_branch_source.rfind("def twl_mergegate_reject_final(")
        assert reject_final_def_pos != -1, (
            "AC5: try branch に twl_mergegate_reject_final 定義が見つからない"
        )
        def_line_end = try_branch_source.find("\n", reject_final_def_pos)
        def_line = try_branch_source[reject_final_def_pos:def_line_end]

        assert "cwd" in def_line, (
            f"AC5 破壊: try branch の twl_mergegate_reject_final シグネチャに 'cwd' が存在しない。"
            f"got={def_line}"
        )

    def test_ac5_except_importerror_branch_reject_signature_has_cwd(self):
        # AC: except-ImportError branch (L1081 周辺) の twl_mergegate_reject シグネチャに
        #     cwd: str | None = None が存在すること
        # PASS: 現在の実装では既に存在する（回帰防止テスト）
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        except_branch_source = source[except_import_pos:]

        reject_def_pos = except_branch_source.find("def twl_mergegate_reject(")
        assert reject_def_pos != -1, (
            "AC5: except-ImportError branch に twl_mergegate_reject 定義が見つからない"
        )
        def_line_end = except_branch_source.find("\n", reject_def_pos)
        def_line = except_branch_source[reject_def_pos:def_line_end]

        assert "cwd" in def_line, (
            f"AC5 破壊: except-ImportError branch の twl_mergegate_reject シグネチャに 'cwd' が存在しない。"
            f"got={def_line}"
        )

    def test_ac5_except_importerror_branch_reject_final_signature_has_cwd(self):
        # AC: except-ImportError branch (L1085 周辺) の twl_mergegate_reject_final シグネチャに
        #     cwd: str | None = None が存在すること
        # PASS: 現在の実装では既に存在する（回帰防止テスト）
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        except_branch_source = source[except_import_pos:]

        reject_final_def_pos = except_branch_source.find("def twl_mergegate_reject_final(")
        assert reject_final_def_pos != -1, (
            "AC5: except-ImportError branch に twl_mergegate_reject_final 定義が見つからない"
        )
        def_line_end = except_branch_source.find("\n", reject_final_def_pos)
        def_line = except_branch_source[reject_final_def_pos:def_line_end]

        assert "cwd" in def_line, (
            f"AC5 破壊: except-ImportError branch の twl_mergegate_reject_final シグネチャに 'cwd' が存在しない。"
            f"got={def_line}"
        )

    def test_ac5_try_branch_reject_passes_cwd_to_handler(self):
        # AC: try branch の twl_mergegate_reject の handler 呼び出しに cwd=cwd が含まれること
        # PASS: 現在の実装では既に存在する（回帰防止テスト）
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        reject_def_pos = try_branch_source.rfind("def twl_mergegate_reject(")
        next_def_pos = try_branch_source.find("\n    @mcp.tool()", reject_def_pos + 1)
        if next_def_pos == -1:
            next_def_pos = len(try_branch_source)
        body_source = try_branch_source[reject_def_pos:next_def_pos]

        assert "cwd=cwd" in body_source, (
            "AC5 破壊: try branch の twl_mergegate_reject_handler 呼び出しに 'cwd=cwd' がない"
        )

    def test_ac5_try_branch_reject_final_passes_cwd_to_handler(self):
        # AC: try branch の twl_mergegate_reject_final の handler 呼び出しに cwd=cwd が含まれること
        # PASS: 現在の実装では既に存在する（回帰防止テスト）
        source = TOOLS_PY.read_text(encoding="utf-8")

        except_import_pos = source.find("except ImportError:")
        try_branch_source = source[:except_import_pos]

        reject_final_def_pos = try_branch_source.rfind("def twl_mergegate_reject_final(")
        next_def_pos = try_branch_source.find("\n    @mcp.tool()", reject_final_def_pos + 1)
        if next_def_pos == -1:
            next_def_pos = len(try_branch_source)
        body_source = try_branch_source[reject_final_def_pos:next_def_pos]

        assert "cwd=cwd" in body_source, (
            "AC5 破壊: try branch の twl_mergegate_reject_final_handler 呼び出しに 'cwd=cwd' がない"
        )
