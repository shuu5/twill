"""Scenario tests for issue-598: Done アイテム自動 archive 廃止.

Generated from: deltaspec/changes/issue-598/specs/archive-removal.md
Coverage level: edge-cases

Verifies:
- orchestrator.py から _archive_done_issues / _archive_deltaspec_changes が削除されている
- run() メソッド内でこれらが呼び出されていないこと
- skipped_archives フィールドがレポートから除去されていること
- test_autopilot_orchestrator.py から archive 関連テストが削除されていること
"""

from __future__ import annotations

import ast
import inspect
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Project paths
# ---------------------------------------------------------------------------

_HERE = Path(__file__).parent
_CLI_ROOT = _HERE.parent.parent  # cli/twl/
_SRC_ROOT = _CLI_ROOT / "src" / "twl"
_ORCHESTRATOR_PY = _SRC_ROOT / "autopilot" / "orchestrator.py"
_TEST_ORCHESTRATOR_PY = _CLI_ROOT / "tests" / "test_autopilot_orchestrator.py"


# ---------------------------------------------------------------------------
# Helper: parse orchestrator source without importing
# ---------------------------------------------------------------------------


def _read_source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _source_contains(path: Path, pattern: str) -> bool:
    import re
    return bool(re.search(pattern, _read_source(path)))


def _source_not_contains(path: Path, pattern: str) -> bool:
    return not _source_contains(path, pattern)


# ---------------------------------------------------------------------------
# Requirement: 自動 archive 処理の除去（Python）
# ---------------------------------------------------------------------------


class TestPythonArchiveRemoval:
    """orchestrator.py から archive メソッドが削除されていること。

    Scenario: Python orchestrator からの archive メソッド除去 (spec line 19)
    WHEN: orchestrator.py の run() メソッドが実行される
    THEN: _archive_done_issues() は呼び出されないこと
    """

    def test_orchestrator_file_exists(self) -> None:
        """前提: orchestrator.py が存在すること。"""
        assert _ORCHESTRATOR_PY.exists(), (
            f"orchestrator.py が見つかりません: {_ORCHESTRATOR_PY}"
        )

    def test_archive_done_issues_method_removed(self) -> None:
        """_archive_done_issues メソッド定義が削除されていること。"""
        assert _source_not_contains(_ORCHESTRATOR_PY, r"def _archive_done_issues"), (
            "orchestrator.py に _archive_done_issues メソッド定義が残っています。"
            "このメソッドは issue-598 で削除対象です。"
        )

    def test_archive_deltaspec_changes_method_removed(self) -> None:
        """_archive_deltaspec_changes メソッド定義が削除されていること。"""
        assert _source_not_contains(_ORCHESTRATOR_PY, r"def _archive_deltaspec_changes"), (
            "orchestrator.py に _archive_deltaspec_changes メソッド定義が残っています。"
            "このメソッドは issue-598 で削除対象です。"
        )

    def test_archive_done_issues_not_called_in_run(self) -> None:
        """run() メソッド内で _archive_done_issues が呼び出されていないこと。

        Edge case: run() 本体のスコープ内の呼び出しをチェック。
        """
        source = _read_source(_ORCHESTRATOR_PY)
        # メソッド名への参照自体がないことを確認（呼び出し + 属性アクセス両方）
        assert "_archive_done_issues" not in source, (
            "orchestrator.py に _archive_done_issues の参照が残っています（呼び出し箇所）。"
        )

    def test_archive_deltaspec_changes_not_called(self) -> None:
        """_archive_deltaspec_changes の呼び出し箇所が全て削除されていること。

        Edge case: self._archive_deltaspec_changes(issue) 形式の呼び出しを含む。
        """
        source = _read_source(_ORCHESTRATOR_PY)
        assert "_archive_deltaspec_changes" not in source, (
            "orchestrator.py に _archive_deltaspec_changes の参照が残っています。"
        )

    def test_skipped_archives_field_removed_from_class(self) -> None:
        """_skipped_archives インスタンス変数が削除されていること。

        Edge case: __init__ 内の self._skipped_archives: list[int] = []
        """
        assert _source_not_contains(_ORCHESTRATOR_PY, r"_skipped_archives"), (
            "orchestrator.py に _skipped_archives フィールドが残っています。"
            "このフィールドは issue-598 で削除対象です。"
        )

    def test_skipped_archives_not_in_phase_report(self) -> None:
        """_generate_phase_report の出力に skipped_archives が含まれないこと。

        Scenario: phase report から skipped_archives フィールドの除去 (spec line 11)
        WHEN: フェーズレポートが生成される
        THEN: skipped_archives フィールドが JSON 出力に含まれないこと
        """
        assert _source_not_contains(_ORCHESTRATOR_PY, r'"skipped_archives"'), (
            "orchestrator.py に \"skipped_archives\" キーが残っています（レポート生成部分）。"
        )
        assert _source_not_contains(_ORCHESTRATOR_PY, r"skipped_archives"), (
            "orchestrator.py に skipped_archives への参照が残っています。"
        )

    def test_twl_spec_archive_calls_removed(self) -> None:
        """'twl spec archive' コマンド呼び出しが削除されていること。

        Edge case: _archive_deltaspec_changes 内の subprocess.run(["twl", "spec", "archive", ...])
        """
        assert _source_not_contains(_ORCHESTRATOR_PY, r"spec.*archive|archive.*spec"), (
            "orchestrator.py に 'twl spec archive' 呼び出しが残っています。"
        )


# ---------------------------------------------------------------------------
# Requirement: 関連テストの除去
# ---------------------------------------------------------------------------


class TestArchiveTestsRemoved:
    """test_autopilot_orchestrator.py から archive 関連テストが削除されていること。

    Scenario: 関連テストの除去 (spec line 23)
    WHEN: test_autopilot_orchestrator.py のテストスイートが実行される
    THEN: archive 関連のテスト（test_archive_done_issues 等）が存在しないこと
    """

    def test_test_file_exists(self) -> None:
        """前提: test_autopilot_orchestrator.py が存在すること。"""
        assert _TEST_ORCHESTRATOR_PY.exists(), (
            f"test_autopilot_orchestrator.py が見つかりません: {_TEST_ORCHESTRATOR_PY}"
        )

    def test_archive_test_class_removed(self) -> None:
        """TestArchiveDoneIssuesFailClosed クラスが削除されていること。

        Edge case: クラスとして定義されたテストグループ全体が対象。
        """
        assert _source_not_contains(_TEST_ORCHESTRATOR_PY, r"class TestArchiveDoneIssuesFailClosed"), (
            "test_autopilot_orchestrator.py に TestArchiveDoneIssuesFailClosed クラスが残っています。"
            "issue-598 ではこのクラス全体を削除してください。"
        )

    def test_archive_done_issues_tests_removed(self) -> None:
        """test_archive_done_issues / test_closed_issue_is_archived 等が削除されていること。"""
        assert _source_not_contains(_TEST_ORCHESTRATOR_PY, r"def test_closed_issue_is_archived"), (
            "test_closed_issue_is_archived テストが残っています。"
        )
        assert _source_not_contains(_TEST_ORCHESTRATOR_PY, r"def test_open_issue_is_skipped"), (
            "test_open_issue_is_skipped テストが残っています。"
        )
        assert _source_not_contains(_TEST_ORCHESTRATOR_PY, r"def test_empty_state_is_skipped"), (
            "test_empty_state_is_skipped テストが残っています。"
        )

    def test_archive_related_imports_cleaned(self) -> None:
        """archive 専用に追加された import が除去されていること（もし存在すれば）。

        Edge case: _archive_done_issues のために追加されたモック patch が残っていないこと。
        """
        assert _source_not_contains(
            _TEST_ORCHESTRATOR_PY,
            r"patch\.object\(orch,\s*['\"]_archive_done_issues"
        ), (
            "test_autopilot_orchestrator.py に _archive_done_issues の patch.object が残っています。"
        )

    def test_skipped_archives_assertion_removed(self) -> None:
        """skipped_archives を検証するアサーションが全て削除されていること。

        Edge case: orch._skipped_archives への参照が残っていないこと。
        """
        assert _source_not_contains(_TEST_ORCHESTRATOR_PY, r"_skipped_archives"), (
            "test_autopilot_orchestrator.py に _skipped_archives への参照が残っています。"
        )

    def test_generate_phase_report_no_skipped_archives_test(self) -> None:
        """_generate_phase_report で skipped_archives を検証するテストが削除されていること。

        Edge case: test_generate_phase_report_includes_skipped_archives 等の関数。
        """
        assert _source_not_contains(
            _TEST_ORCHESTRATOR_PY,
            r"def test_generate_phase_report_includes_skipped_archives"
        ), (
            "test_generate_phase_report_includes_skipped_archives が残っています。"
        )
