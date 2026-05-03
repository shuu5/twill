"""Tests for Issue #1111: 検証系 tool 5 個を tools.py に追加 (RED フェーズ).

TDD RED フェーズ用テストスタブ。
実装前は全テストが FAIL する（意図的 RED）。

AC 一覧:
- 共通-1: 5 tool が tools.py に定義されていること
- 共通-2: 各 tool に handler 関数が存在すること
- 共通-3: @mcp.tool() + try/except ImportError gate
- 共通-4: fastmcp 経由 + handler 直接呼出の 2 経路
- 共通-5: 既存 Bash hook が削除されず維持されていること
- 共通-6: pytest tests/ PASS、twl --validate deps drift なし
- 共通-7: MergeGate クラスを import しないこと
- 共通-8: SystemExit が発生しないこと
- 共通-9: action 系 tool が timeout_sec 引数を持つこと
- AC2-1a~e: 各 handler の signature
- AC2-3a: SystemExit 非発生（C1-codex 検証）
- AC2-3b: _check_running_guard / _check_phase_review_guard を呼ばないこと
- AC2-3c: flock 並列テスト
- AC2-3d: twl_check_specialist_handler stub envelope
- AC2-5a/b: timeout_sec=0 でタイムアウト応答
- AC-naming-2: docstring 1 行目に "validation module:" を含む
- AC-naming-3: twl_check の docstring に "plugin file integrity" を含む
"""

import inspect
import subprocess
import sys
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
WORKTREE_ROOT = TWL_DIR.parent.parent
HOOKS_DIR = WORKTREE_ROOT / "plugins" / "twl" / "scripts" / "hooks"


# ---------------------------------------------------------------------------
# 共通-1: 5 tool が tools.py に定義されていること
# ---------------------------------------------------------------------------

class TestCommon1FiveToolsDefined:
    """共通-1: 5 tool が tools.py に定義されていること."""

    def test_common1_five_tools_defined(self):
        # AC: twl_validate_deps / twl_validate_merge / twl_validate_commit /
        #     twl_check_completeness / twl_check_specialist が tools.py に定義されていること
        # RED: 未実装のため AttributeError
        from twl.mcp_server import tools

        expected_tools = [
            "twl_validate_deps",
            "twl_validate_merge",
            "twl_validate_commit",
            "twl_check_completeness",
            "twl_check_specialist",
        ]
        for name in expected_tools:
            assert hasattr(tools, name), (
                f"tools.py に {name} が未定義 (共通-1 未実装)"
            )


# ---------------------------------------------------------------------------
# 共通-2: handler 関数が存在すること（既存 5 tool の挙動は不変）
# ---------------------------------------------------------------------------

class TestCommon2HandlerFunctionsExist:
    """共通-2: 各 tool に handler 関数が存在すること."""

    def test_common2_new_handler_functions_exist(self):
        # AC: twl_<name>_handler suffix の pure Python 関数が存在すること
        # RED: 未実装のため AttributeError
        from twl.mcp_server import tools

        expected_handlers = [
            "twl_validate_deps_handler",
            "twl_validate_merge_handler",
            "twl_validate_commit_handler",
            "twl_check_completeness_handler",
            "twl_check_specialist_handler",
        ]
        for name in expected_handlers:
            assert hasattr(tools, name), (
                f"tools.py に {name} が未定義 (共通-2 未実装)"
            )
            fn = getattr(tools, name)
            assert callable(fn), f"{name} は callable でない (共通-2 未実装)"

    def test_common2_existing_handlers_intact(self):
        # AC: 既存 5 tool の handler 関数が引き続き存在・callable であること
        # RED: 既存が壊れた場合 AttributeError
        from twl.mcp_server import tools

        existing_handlers = [
            "twl_validate_handler",
            "twl_audit_handler",
            "twl_check_handler",
            "twl_state_read_handler",
            "twl_state_write_handler",
        ]
        for name in existing_handlers:
            assert hasattr(tools, name), (
                f"tools.py から既存 {name} が消滅している (共通-2 破壊)"
            )
            fn = getattr(tools, name)
            assert callable(fn), f"{name} は callable でない (共通-2 破壊)"


# ---------------------------------------------------------------------------
# 共通-3: @mcp.tool() + try/except ImportError gate
# ---------------------------------------------------------------------------

class TestCommon3McpToolRegistration:
    """共通-3: @mcp.tool() decorator + try/except ImportError gate."""

    def test_common3_mcp_tool_registration_pattern(self):
        # AC: @mcp.tool() decorator と try/except ImportError gate が実装されていること
        # RED: 未実装のため新 tool がまだ登録されていない
        tools_src = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
        content = tools_src.read_text(encoding="utf-8")

        # try/except ImportError gate が存在すること
        assert "try:" in content and "ImportError" in content, (
            "tools.py に try/except ImportError gate が存在しない (共通-3 未実装)"
        )

        # 5 新 tool のデコレータ登録が含まれること
        new_tools = [
            "twl_validate_deps",
            "twl_validate_merge",
            "twl_validate_commit",
            "twl_check_completeness",
            "twl_check_specialist",
        ]
        for name in new_tools:
            # @mcp.tool() + def name(...) の形で定義されているか確認
            assert f"def {name}(" in content, (
                f"tools.py に def {name}( が存在しない (共通-3 未実装)"
            )


# ---------------------------------------------------------------------------
# 共通-4: fastmcp 経由 + handler 直接呼出の 2 経路
# ---------------------------------------------------------------------------

class TestCommon4TwoCallPaths:
    """共通-4: fastmcp 経由 + handler 直接呼出の 2 経路でテスト可能であること."""

    def test_common4_handler_directly_callable(self):
        # AC: handler 関数を fastmcp なしで直接呼び出せること
        # RED: 未実装のため ImportError/AttributeError
        from twl.mcp_server.tools import twl_validate_deps_handler  # noqa: F401

        assert callable(twl_validate_deps_handler), (
            "twl_validate_deps_handler は callable でない (共通-4 未実装)"
        )

    def test_common4_mcp_tool_importable_via_module(self):
        # AC: tools モジュール経由で新 tool が import 可能であること
        # RED: 未実装のため AttributeError
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_validate_deps", None)
        assert fn is not None, (
            "tools.twl_validate_deps が存在しない (共通-4 未実装)"
        )


# ---------------------------------------------------------------------------
# 共通-5: 既存 Bash hook が削除されず維持されていること
# ---------------------------------------------------------------------------

class TestCommon5BashHooksPreserved:
    """共通-5: 既存 Bash hook が削除されず維持されていること."""

    def test_common5_pre_tool_use_deps_yaml_guard_exists(self):
        # AC: pre-tool-use-deps-yaml-guard.sh が存在すること
        # RED: ファイルが削除された場合 FAIL
        hook = HOOKS_DIR / "pre-tool-use-deps-yaml-guard.sh"
        assert hook.exists(), (
            f"pre-tool-use-deps-yaml-guard.sh が消滅している (共通-5 破壊): {hook}"
        )

    def test_common5_pre_bash_merge_guard_exists(self):
        # AC: pre-bash-merge-guard.sh が存在すること
        # RED: ファイルが削除された場合 FAIL
        hook = HOOKS_DIR / "pre-bash-merge-guard.sh"
        assert hook.exists(), (
            f"pre-bash-merge-guard.sh が消滅している (共通-5 破壊): {hook}"
        )

    def test_common5_pre_bash_commit_validate_exists(self):
        # AC: pre-bash-commit-validate.sh が存在すること
        # RED: ファイルが削除された場合 FAIL
        hook = HOOKS_DIR / "pre-bash-commit-validate.sh"
        assert hook.exists(), (
            f"pre-bash-commit-validate.sh が消滅している (共通-5 破壊): {hook}"
        )

    def test_common5_check_specialist_completeness_exists(self):
        # AC: check-specialist-completeness.sh が存在すること
        # RED: ファイルが削除された場合 FAIL
        hook = HOOKS_DIR / "check-specialist-completeness.sh"
        assert hook.exists(), (
            f"check-specialist-completeness.sh が消滅している (共通-5 破壊): {hook}"
        )


# ---------------------------------------------------------------------------
# 共通-7: tools.py が MergeGate クラスを import しないこと
# ---------------------------------------------------------------------------

class TestCommon7NoMergeGateImport:
    """共通-7: tools.py が MergeGate クラスを import しないこと."""

    def test_common7_no_mergegate_class_import(self):
        # AC: tools.py に MergeGate クラスの import が存在しないこと（sys.exit を含むため禁止）
        # RED: 実装時に誤って import した場合 FAIL
        tools_src = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"
        content = tools_src.read_text(encoding="utf-8")

        # "MergeGate" というクラス名が import 文に現れないこと
        # mergegate_guards.py の import は可（MergeGate クラスは sys.exit を含む mergegate.py 内）
        assert "from twl.autopilot.mergegate import MergeGate" not in content, (
            "tools.py が MergeGate クラスを import している (共通-7 違反)"
        )
        assert "import MergeGate" not in content, (
            "tools.py が MergeGate クラスを import している (共通-7 違反)"
        )


# ---------------------------------------------------------------------------
# 共通-8: SystemExit が発生しないこと
# ---------------------------------------------------------------------------

class TestCommon8NoSystemExit:
    """共通-8: twl_validate_merge_handler 呼出後に SystemExit が発生しないこと.

    Note: AC2-3a (TestAC23aNoSystemExit) も同一の SystemExit 検証を行う。
    共通-8 は「ADR-028 整合確認」の AC トレーサビリティ用、
    AC2-3a は「C1-codex MergeGate.execute import 禁止」の AC トレーサビリティ用。
    両者は別 AC に紐付くため、ac-test-mapping の 1:1 対応を維持するため分離している。
    """

    def test_common8_validate_merge_handler_no_system_exit(self):
        # AC: twl_validate_merge_handler 呼出後に SystemExit が発生しないこと
        # RED: 未実装のため ImportError
        from twl.mcp_server.tools import twl_validate_merge_handler

        # SystemExit が発生しないことを確認（正常/エラー問わず dict を返す）
        try:
            result = twl_validate_merge_handler(branch="test-branch-nonexistent-12345")
        except SystemExit as exc:
            pytest.fail(
                f"twl_validate_merge_handler が SystemExit を発生させた (共通-8 違反): {exc}"
            )
        except Exception:
            # SystemExit 以外の例外は許容（未実装 or 実行エラー）
            pass


# ---------------------------------------------------------------------------
# 共通-9: action 系 tool が timeout_sec 引数を持つこと
# ---------------------------------------------------------------------------

class TestCommon9TimeoutSecArgument:
    """共通-9: action 系 tool handler が timeout_sec: int | None = 300 引数を持つこと."""

    def test_common9_validate_merge_handler_has_timeout_sec(self):
        # AC: twl_validate_merge_handler が timeout_sec: int | None = 300 引数を持つこと
        # RED: 未実装のため ImportError または引数不在
        from twl.mcp_server.tools import twl_validate_merge_handler

        sig = inspect.signature(twl_validate_merge_handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_validate_merge_handler に timeout_sec 引数がない (共通-9 未実装)"
        )
        param = sig.parameters["timeout_sec"]
        assert param.default == 300, (
            f"twl_validate_merge_handler の timeout_sec のデフォルトが 300 でない: {param.default} (共通-9 未実装)"
        )

    def test_common9_validate_commit_handler_has_timeout_sec(self):
        # AC: twl_validate_commit_handler が timeout_sec: int | None = 300 引数を持つこと
        # RED: 未実装のため ImportError または引数不在
        from twl.mcp_server.tools import twl_validate_commit_handler

        sig = inspect.signature(twl_validate_commit_handler)
        assert "timeout_sec" in sig.parameters, (
            "twl_validate_commit_handler に timeout_sec 引数がない (共通-9 未実装)"
        )
        param = sig.parameters["timeout_sec"]
        assert param.default == 300, (
            f"twl_validate_commit_handler の timeout_sec のデフォルトが 300 でない: {param.default} (共通-9 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2-1a: twl_validate_deps_handler signature
# ---------------------------------------------------------------------------

class TestAC21aValidateDepsSignature:
    """AC2-1a: twl_validate_deps_handler(plugin_root: str) -> dict."""

    def test_ac2_1a_validate_deps_handler_signature(self):
        # AC: twl_validate_deps_handler(plugin_root: str) -> dict の signature が正しいこと
        # RED: 未実装のため ImportError
        from twl.mcp_server.tools import twl_validate_deps_handler

        sig = inspect.signature(twl_validate_deps_handler)
        params = sig.parameters

        assert "plugin_root" in params, (
            "twl_validate_deps_handler に plugin_root 引数がない (AC2-1a 未実装)"
        )
        assert len(params) == 1, (
            f"twl_validate_deps_handler の引数数が 1 でない: {list(params.keys())} (AC2-1a 未実装)"
        )

        # 戻り値アノテーションが dict であること
        ret = sig.return_annotation
        assert ret is dict or "dict" in str(ret), (
            f"twl_validate_deps_handler の戻り値アノテーションが dict でない: {ret} (AC2-1a 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2-1b: twl_validate_merge_handler signature
# ---------------------------------------------------------------------------

class TestAC21bValidateMergeSignature:
    """AC2-1b: twl_validate_merge_handler(branch: str, base: str = "main", timeout_sec: int | None = 300) -> dict."""

    def test_ac2_1b_validate_merge_handler_signature(self):
        # AC: twl_validate_merge_handler(branch: str, base: str = "main", timeout_sec: int | None = 300) -> dict
        # RED: 未実装のため ImportError
        from twl.mcp_server.tools import twl_validate_merge_handler

        sig = inspect.signature(twl_validate_merge_handler)
        params = sig.parameters

        assert "branch" in params, (
            "twl_validate_merge_handler に branch 引数がない (AC2-1b 未実装)"
        )
        assert "base" in params, (
            "twl_validate_merge_handler に base 引数がない (AC2-1b 未実装)"
        )
        assert params["base"].default == "main", (
            f"twl_validate_merge_handler の base デフォルトが 'main' でない: {params['base'].default} (AC2-1b 未実装)"
        )
        assert "timeout_sec" in params, (
            "twl_validate_merge_handler に timeout_sec 引数がない (AC2-1b 未実装)"
        )
        assert params["timeout_sec"].default == 300, (
            f"twl_validate_merge_handler の timeout_sec デフォルトが 300 でない (AC2-1b 未実装)"
        )

        ret = sig.return_annotation
        assert ret is dict or "dict" in str(ret), (
            f"twl_validate_merge_handler の戻り値アノテーションが dict でない: {ret} (AC2-1b 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2-1c: twl_validate_commit_handler signature
# ---------------------------------------------------------------------------

class TestAC21cValidateCommitSignature:
    """AC2-1c: twl_validate_commit_handler(command: str, files: list[str], timeout_sec: int | None = 300) -> dict.

    Updated in Issue #1334: message → command (handler now accepts full git command string).
    """

    def test_ac2_1c_validate_commit_handler_signature(self):
        # AC: twl_validate_commit_handler(command: str, files: list[str], timeout_sec: int | None = 300) -> dict
        # Updated by Issue #1334: message param renamed to command
        from twl.mcp_server.tools import twl_validate_commit_handler

        sig = inspect.signature(twl_validate_commit_handler)
        params = sig.parameters

        assert "command" in params, (
            "twl_validate_commit_handler に command 引数がない (Issue #1334 で message → command に変更)"
        )
        assert "files" in params, (
            "twl_validate_commit_handler に files 引数がない (AC2-1c 未実装)"
        )
        assert "timeout_sec" in params, (
            "twl_validate_commit_handler に timeout_sec 引数がない (AC2-1c 未実装)"
        )
        assert params["timeout_sec"].default == 300, (
            f"twl_validate_commit_handler の timeout_sec デフォルトが 300 でない (AC2-1c 未実装)"
        )

        ret = sig.return_annotation
        assert ret is dict or "dict" in str(ret), (
            f"twl_validate_commit_handler の戻り値アノテーションが dict でない: {ret} (AC2-1c 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2-1d: twl_check_completeness_handler signature
# ---------------------------------------------------------------------------

class TestAC21dCheckCompletenessSignature:
    """AC2-1d: twl_check_completeness_handler(manifest_context: str) -> dict."""

    def test_ac2_1d_check_completeness_handler_signature(self):
        # AC: twl_check_completeness_handler(manifest_context: str) -> dict の signature が正しいこと
        # RED: 未実装のため ImportError
        from twl.mcp_server.tools import twl_check_completeness_handler

        sig = inspect.signature(twl_check_completeness_handler)
        params = sig.parameters

        assert "manifest_context" in params, (
            "twl_check_completeness_handler に manifest_context 引数がない (AC2-1d 未実装)"
        )
        assert len(params) == 1, (
            f"twl_check_completeness_handler の引数数が 1 でない: {list(params.keys())} (AC2-1d 未実装)"
        )

        ret = sig.return_annotation
        assert ret is dict or "dict" in str(ret), (
            f"twl_check_completeness_handler の戻り値アノテーションが dict でない: {ret} (AC2-1d 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2-1e: twl_check_specialist_handler signature
# ---------------------------------------------------------------------------

class TestAC21eCheckSpecialistSignature:
    """AC2-1e: twl_check_specialist_handler(manifest_context: str) -> dict."""

    def test_ac2_1e_check_specialist_handler_signature(self):
        # AC: twl_check_specialist_handler(manifest_context: str) -> dict の signature が正しいこと
        # RED: 未実装のため ImportError
        from twl.mcp_server.tools import twl_check_specialist_handler

        sig = inspect.signature(twl_check_specialist_handler)
        params = sig.parameters

        assert "manifest_context" in params, (
            "twl_check_specialist_handler に manifest_context 引数がない (AC2-1e 未実装)"
        )
        assert len(params) == 1, (
            f"twl_check_specialist_handler の引数数が 1 でない: {list(params.keys())} (AC2-1e 未実装)"
        )

        ret = sig.return_annotation
        assert ret is dict or "dict" in str(ret), (
            f"twl_check_specialist_handler の戻り値アノテーションが dict でない: {ret} (AC2-1e 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2-3a: SystemExit 非発生（C1-codex 検証）
# ---------------------------------------------------------------------------

class TestAC23aNoSystemExit:
    """AC2-3a: twl_validate_merge_handler 呼出時に SystemExit が発生しないこと."""

    def test_ac2_3a_validate_merge_no_system_exit(self):
        # AC: twl_validate_merge_handler 呼出時に SystemExit が発生しないこと（C1-codex 検証）
        # RED: 未実装のため ImportError; 実装後も SystemExit が出ると FAIL
        from twl.mcp_server.tools import twl_validate_merge_handler

        try:
            result = twl_validate_merge_handler(branch="nonexistent-branch-ac2-3a")
        except SystemExit as exc:
            pytest.fail(
                f"twl_validate_merge_handler が SystemExit を発生させた (AC2-3a 違反): {exc}"
            )
        except Exception:
            # SystemExit 以外の例外（subprocess エラー等）は許容
            pass
        else:
            # 正常終了した場合は dict が返ること
            assert isinstance(result, dict), (
                f"twl_validate_merge_handler の戻り値が dict でない: {type(result)} (AC2-3a)"
            )


# ---------------------------------------------------------------------------
# AC2-3b: _check_running_guard / _check_phase_review_guard を呼ばないこと
# ---------------------------------------------------------------------------

class TestAC23bNoGuardCalls:
    """AC2-3b: twl_validate_merge_handler が scope 外 guard を呼ばないこと."""

    def test_ac2_3b_no_check_running_guard_call(self):
        # AC: twl_validate_merge_handler が _check_running_guard を呼ばないこと（Plan A' 2-guard scope 外）
        # RED: 未実装のため ImportError（handler が存在しないと import が失敗する）
        from unittest.mock import patch
        from twl.mcp_server.tools import twl_validate_merge_handler  # RED trigger: ImportError

        with patch("twl.autopilot.mergegate_guards._check_running_guard") as mock_guard:
            try:
                twl_validate_merge_handler(branch="test-branch-ac2-3b")
            except Exception:
                pass  # MergeGateError / subprocess エラー等は許容
            assert not mock_guard.called, (
                "_check_running_guard が呼ばれた (AC2-3b 違反: Plan A' 2-guard scope 外)"
            )

    def test_ac2_3b_no_check_phase_review_guard_call(self):
        # AC: twl_validate_merge_handler が _check_phase_review_guard を呼ばないこと（scope 外）
        # RED: 未実装のため ImportError（handler が存在しないと import が失敗する）
        from unittest.mock import patch
        from twl.mcp_server.tools import twl_validate_merge_handler  # RED trigger: ImportError

        with patch("twl.autopilot.mergegate_guards._check_phase_review_guard") as mock_guard:
            try:
                twl_validate_merge_handler(branch="test-branch-ac2-3b")
            except Exception:
                pass  # MergeGateError / subprocess エラー等は許容
            assert not mock_guard.called, (
                "_check_phase_review_guard が呼ばれた (AC2-3b 違反: Plan A' 2-guard scope 外)"
            )


# ---------------------------------------------------------------------------
# AC2-3c: flock 並列テスト（bash flock LOCK_EX 保持中に LOCK_SH で安全に読めること）
# ---------------------------------------------------------------------------

class TestAC23cFlockParallel:
    """AC2-3c: twl_check_completeness_handler が flock LOCK_EX 中に LOCK_SH で読めること."""

    def test_ac2_3c_completeness_handler_readable_under_flock(self, tmp_path):
        # AC: twl_check_completeness_handler が bash flock LOCK_EX 保持中に
        #     LOCK_SH で安全に読めること（R2-M3 flock 並列 test）
        # RED: 未実装のため ImportError
        import shutil
        import time
        if shutil.which("flock") is None:
            pytest.skip("flock command not available on this platform (Linux only)")

        from twl.mcp_server.tools import twl_check_completeness_handler

        lock_file = tmp_path / "test.lock"
        lock_file.touch()

        # bash flock LOCK_EX を 3 秒間保持するバックグラウンドプロセスを起動
        bg = subprocess.Popen(
            ["bash", "-c", f"flock -x {lock_file} sleep 3"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # flock プロセスが LOCK_EX を取得するまで確実に待つ（0.5 秒）
        time.sleep(0.5)

        # LOCK_EX 保持中に handler を呼び出す（LOCK_SH として安全に完了すること）
        try:
            result = twl_check_completeness_handler(manifest_context="test-context-flock")
        except SystemExit as exc:
            bg.terminate()
            bg.wait()
            pytest.fail(
                f"flock 中に twl_check_completeness_handler が SystemExit を発生させた (AC2-3c 違反): {exc}"
            )
        except Exception:
            # SystemExit 以外は許容（stub 実装等）
            pass
        finally:
            bg.terminate()
            bg.wait()


# ---------------------------------------------------------------------------
# AC2-3d: twl_check_specialist_handler stub envelope
# ---------------------------------------------------------------------------

class TestAC23dSpecialistStubEnvelope:
    """AC2-3d: twl_check_specialist_handler("test-ctx") の stub envelope 検証."""

    def test_ac2_3d_specialist_handler_stub_envelope(self):
        # AC: twl_check_specialist_handler("test-ctx") の結果が
        #     ok=True, items=[], "stub" in summary であること（R2-m2 stub envelope）
        # RED: 未実装のため ImportError
        from twl.mcp_server.tools import twl_check_specialist_handler

        result = twl_check_specialist_handler("test-ctx")

        assert isinstance(result, dict), (
            f"twl_check_specialist_handler の戻り値が dict でない: {type(result)} (AC2-3d 未実装)"
        )
        assert result.get("ok") is True, (
            f"twl_check_specialist_handler('test-ctx') の ok が True でない: {result} (AC2-3d 未実装)"
        )
        assert result.get("items") == [], (
            f"twl_check_specialist_handler('test-ctx') の items が [] でない: {result.get('items')} (AC2-3d 未実装)"
        )
        summary = result.get("summary", "")
        assert "stub" in str(summary), (
            f"twl_check_specialist_handler('test-ctx') の summary に 'stub' が含まれない: {summary} (AC2-3d 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2-5a: timeout_sec=0 で即時タイムアウト（validate_merge）
# ---------------------------------------------------------------------------

class TestAC25aValidateMergeTimeout:
    """AC2-5a: twl_validate_merge_handler(branch="test", timeout_sec=0) がタイムアウト応答を返すこと."""

    def test_ac2_5a_validate_merge_timeout_response(self):
        # AC: twl_validate_merge_handler(branch="test", timeout_sec=0) が
        #     {ok: False, error_type: "timeout", exit_code: 124} を返すこと
        # RED: 未実装のため ImportError
        from twl.mcp_server.tools import twl_validate_merge_handler

        result = twl_validate_merge_handler(branch="test", timeout_sec=0)

        assert isinstance(result, dict), (
            f"twl_validate_merge_handler の戻り値が dict でない: {type(result)} (AC2-5a 未実装)"
        )
        assert result.get("ok") is False, (
            f"timeout 時の ok が False でない: {result} (AC2-5a 未実装)"
        )
        assert result.get("error_type") == "timeout", (
            f"timeout 時の error_type が 'timeout' でない: {result.get('error_type')} (AC2-5a 未実装)"
        )
        assert result.get("exit_code") == 124, (
            f"timeout 時の exit_code が 124 でない: {result.get('exit_code')} (AC2-5a 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2-5b: timeout_sec=0 で即時タイムアウト（validate_commit）
# ---------------------------------------------------------------------------

class TestAC25bValidateCommitTimeout:
    """AC2-5b: twl_validate_commit_handler(command="git commit -m test", files=[], timeout_sec=0) がタイムアウト応答を返すこと.

    Updated in Issue #1334: message → command parameter.
    """

    def test_ac2_5b_validate_commit_timeout_response(self):
        # AC: twl_validate_commit_handler(command="...", files=[], timeout_sec=0) が
        #     {ok: False, error_type: "timeout", exit_code: 124} を返すこと
        # Updated by Issue #1334: message param renamed to command
        from twl.mcp_server.tools import twl_validate_commit_handler

        result = twl_validate_commit_handler(command='git commit -m "test"', files=[], timeout_sec=0)

        assert isinstance(result, dict), (
            f"twl_validate_commit_handler の戻り値が dict でない: {type(result)} (AC2-5b 未実装)"
        )
        assert result.get("ok") is False, (
            f"timeout 時の ok が False でない: {result} (AC2-5b 未実装)"
        )
        assert result.get("error_type") == "timeout", (
            f"timeout 時の error_type が 'timeout' でない: {result.get('error_type')} (AC2-5b 未実装)"
        )
        assert result.get("exit_code") == 124, (
            f"timeout 時の exit_code が 124 でない: {result.get('exit_code')} (AC2-5b 未実装)"
        )


# ---------------------------------------------------------------------------
# AC-naming-2: 各新 tool の docstring 1 行目に "validation module:" が含まれること
# ---------------------------------------------------------------------------

class TestACNaming2DocstringValidationModule:
    """AC-naming-2: 各新 tool の docstring 1 行目に 'validation module:' が含まれること."""

    def test_acnaming2_validate_deps_docstring(self):
        # AC: twl_validate_deps の docstring 1 行目に "validation module:" が含まれること
        # RED: 未実装のため AttributeError または docstring 不適切
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_validate_deps", None)
        assert fn is not None, "tools.twl_validate_deps が存在しない (AC-naming-2 未実装)"
        doc = fn.__doc__ or ""
        first_line = doc.strip().split("\n")[0]
        assert "validation module:" in first_line, (
            f"twl_validate_deps の docstring 1 行目に 'validation module:' が含まれない: '{first_line}' (AC-naming-2 未実装)"
        )

    def test_acnaming2_validate_merge_docstring(self):
        # AC: twl_validate_merge の docstring 1 行目に "validation module:" が含まれること
        # RED: 未実装のため AttributeError または docstring 不適切
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_validate_merge", None)
        assert fn is not None, "tools.twl_validate_merge が存在しない (AC-naming-2 未実装)"
        doc = fn.__doc__ or ""
        first_line = doc.strip().split("\n")[0]
        assert "validation module:" in first_line, (
            f"twl_validate_merge の docstring 1 行目に 'validation module:' が含まれない: '{first_line}' (AC-naming-2 未実装)"
        )

    def test_acnaming2_validate_commit_docstring(self):
        # AC: twl_validate_commit の docstring 1 行目に "validation module:" が含まれること
        # RED: 未実装のため AttributeError または docstring 不適切
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_validate_commit", None)
        assert fn is not None, "tools.twl_validate_commit が存在しない (AC-naming-2 未実装)"
        doc = fn.__doc__ or ""
        first_line = doc.strip().split("\n")[0]
        assert "validation module:" in first_line, (
            f"twl_validate_commit の docstring 1 行目に 'validation module:' が含まれない: '{first_line}' (AC-naming-2 未実装)"
        )

    def test_acnaming2_check_completeness_docstring(self):
        # AC: twl_check_completeness の docstring 1 行目に "validation module:" が含まれること
        # RED: 未実装のため AttributeError または docstring 不適切
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_check_completeness", None)
        assert fn is not None, "tools.twl_check_completeness が存在しない (AC-naming-2 未実装)"
        doc = fn.__doc__ or ""
        first_line = doc.strip().split("\n")[0]
        assert "validation module:" in first_line, (
            f"twl_check_completeness の docstring 1 行目に 'validation module:' が含まれない: '{first_line}' (AC-naming-2 未実装)"
        )

    def test_acnaming2_check_specialist_docstring(self):
        # AC: twl_check_specialist の docstring 1 行目に "validation module:" が含まれること
        # RED: 未実装のため AttributeError または docstring 不適切
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_check_specialist", None)
        assert fn is not None, "tools.twl_check_specialist が存在しない (AC-naming-2 未実装)"
        doc = fn.__doc__ or ""
        first_line = doc.strip().split("\n")[0]
        assert "validation module:" in first_line, (
            f"twl_check_specialist の docstring 1 行目に 'validation module:' が含まれない: '{first_line}' (AC-naming-2 未実装)"
        )


# ---------------------------------------------------------------------------
# AC-naming-3: 既存 twl_check の docstring に "plugin file integrity" が含まれること
# ---------------------------------------------------------------------------

class TestACNaming3CheckDocstring:
    """AC-naming-3: 既存 twl_check の docstring に 'plugin file integrity' が含まれること."""

    def test_acnaming3_twl_check_docstring_contains_plugin_file_integrity(self):
        # AC: 既存 twl_check の docstring に "plugin file integrity" が含まれること
        # RED: 現在の docstring は「Check file existence and chain integrity for a plugin.」
        #      であり "plugin file integrity" が含まれていないため FAIL（意図的 RED）
        from twl.mcp_server import tools

        fn = getattr(tools, "twl_check", None)
        assert fn is not None, "tools.twl_check が存在しない (AC-naming-3 未実装)"
        doc = fn.__doc__ or ""
        assert "plugin file integrity" in doc, (
            f"twl_check の docstring に 'plugin file integrity' が含まれない: '{doc}' (AC-naming-3 未実装)"
        )
