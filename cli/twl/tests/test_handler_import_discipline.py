"""Tests for MCP handler import discipline — Issue #1113 AC3-9.

TDD RED フェーズ。実装前は全テストが FAIL する（意図的 RED）。

AC3-9: tools.py が CLI 入口関数 (sys.exit() を呼ぶ main / _parse_*) を
import していないことを AST で機械検証する。

sibling Issue #1111 の MergeGate.execute() sys.exit() 教訓と同型のリスクを予防。
"""

import ast
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"

# CLI 入口として sys.exit() を含む禁止 symbol 一覧
FORBIDDEN_NAMES = {
    "main",
    "_parse_read_args",
    "_parse_write_args",
    "_parse_create_args",
    "_parse_add_warning_args",
    "_parse_archive_args",
    "_print_read_usage",
    "_print_write_usage",
    "_print_usage",
}


def _load_ast() -> ast.Module:
    assert TOOLS_PY.exists(), f"tools.py が存在しない: {TOOLS_PY}"
    return ast.parse(TOOLS_PY.read_text())


# ===========================================================================
# AC3-9: 静的 import の AST 解析
# ===========================================================================


class TestAC39NoForbiddenStaticImports:
    """AC3-9: ast.ImportFrom / ast.Import で禁止 symbol を import していないこと。"""

    def test_ac9_no_import_from_forbidden_names(self):
        # AC: from twl.autopilot.X import <forbidden_name> がない
        # RED: 実装が誤って main 等を import していれば FAIL
        tree = _load_ast()
        violations = []
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom):
                for alias in node.names:
                    imported_name = alias.name
                    if imported_name in FORBIDDEN_NAMES:
                        violations.append(
                            f"line {node.lineno}: from {node.module} import {imported_name} "
                            f"(sys.exit() 経路の import — AC3-9 violation)"
                        )
        assert not violations, "\n".join(violations)

    def test_ac9_tools_py_exists(self):
        # AC: tools.py が存在し AST parse できる
        # RED: tools.py 未作成なら FAIL
        assert TOOLS_PY.exists(), f"tools.py が存在しない: {TOOLS_PY}"
        tree = _load_ast()
        assert isinstance(tree, ast.Module)


# ===========================================================================
# AC3-9: 動的 import の禁止
# ===========================================================================


class TestAC39NoDynamicImport:
    """AC3-9: handler 内で __import__ / importlib.import_module を呼ばない。"""

    FORBIDDEN_DYNAMIC = {"__import__", "import_module"}

    def test_ac9_no_dynamic_import_calls(self):
        # AC: ast.Call で __import__ / import_module が呼ばれていない
        # RED: 動的 import を使っていれば FAIL
        tree = _load_ast()
        violations = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                func_name = ""
                if isinstance(node.func, ast.Name):
                    func_name = node.func.id
                elif isinstance(node.func, ast.Attribute):
                    func_name = node.func.attr
                if func_name in self.FORBIDDEN_DYNAMIC:
                    violations.append(
                        f"line {node.lineno}: forbidden dynamic import: {ast.unparse(node)}"
                    )
        assert not violations, "\n".join(violations)


# ===========================================================================
# AC3-9: sys.exit() 含有モジュールからの class API 利用の正当性確認
# ===========================================================================


class TestAC39AllowedClassApiImports:
    """AC3-9: StateManager / CheckpointManager の class import は許可されている。

    禁止は main / _parse_* 等の CLI 入口のみ。class API は正規の利用経路。
    """

    ALLOWED_CLASS_NAMES = {"StateManager", "StateError", "StateArgError", "CheckpointManager"}

    def test_ac9_allowed_class_imports_present_or_absent(self):
        # AC: StateManager 等の import が tools.py にあれば from_node.names に FORBIDDEN_NAMES が含まれない
        # RED: 正当な class import を誤って禁止する実装があれば FAIL
        tree = _load_ast()
        # allowed class を import している場合、そのノードの names に forbidden が混入していないこと
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom):
                has_allowed = any(
                    alias.name in self.ALLOWED_CLASS_NAMES for alias in node.names
                )
                if has_allowed:
                    for alias in node.names:
                        assert alias.name not in FORBIDDEN_NAMES, (
                            f"line {node.lineno}: allowed import node に forbidden name '{alias.name}' が混在"
                        )


# ===========================================================================
# AC3-9: regression — 新 handler 追加後も discipline が維持されること
# ===========================================================================


class TestAC39RegressionGuard:
    """AC3-9: Issue #1113 で追加する 3 handler の import 規律 regression guard。"""

    NEW_HANDLER_NAMES = {
        "twl_get_session_state_handler",
        "twl_get_pane_state_handler",
        "twl_audit_session_handler",
    }

    def test_ac9_new_handlers_exist(self):
        # AC: 3 handler が tools.py に定義されている
        # RED: 実装前は FAIL
        tree = _load_ast()
        defined = {
            node.name
            for node in ast.walk(tree)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        }
        missing = self.NEW_HANDLER_NAMES - defined
        assert not missing, (
            f"3 handler が tools.py に未定義: {missing} (AC3-9 / AC3-1 未実装)"
        )

    def test_ac9_handler_suffix_convention(self):
        # AC: 新 handler は _handler suffix を持つ (AC3-3 / 共通-2)
        # このテストは new handlers の suffix を confirm するだけ (RED ではなく GREEN 前提)
        for name in self.NEW_HANDLER_NAMES:
            assert name.endswith("_handler"), (
                f"handler 命名規約違反: '{name}' は _handler suffix を持たない"
            )
