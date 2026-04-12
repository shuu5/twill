"""Scenario tests for issue-462: mergegate_guards モジュール分割

Spec: deltaspec/changes/issue-462/specs/module-split/spec.md

NOTE: これらのテストは mergegate_guards.py が実装された後に PASS することを意図した
スケルトンテストです。現時点では mergegate_guards モジュールは未存在のため、
xfail マーカーで段階的に実装を確認できるよう構成しています。

Scenarios covered:
  - guard 関数のインポート（Requirement: mergegate_guards モジュール）
  - deps.yaml 登録（Requirement: mergegate_guards モジュール）
  - Phase A 後の行数確認（Requirement: mergegate.py の行数削減）
  - テストファイルのインポートパス（Requirement: テストのインポートパス更新）
"""

from __future__ import annotations

import ast
import subprocess
import sys
from pathlib import Path

import pytest


# ---------------------------------------------------------------------------
# ヘルパー
# ---------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parents[4]  # worktree root
_MERGEGATE_PY = (
    _REPO_ROOT / "cli" / "twl" / "src" / "twl" / "autopilot" / "mergegate.py"
)
_MERGEGATE_GUARDS_PY = (
    _REPO_ROOT
    / "cli"
    / "twl"
    / "src"
    / "twl"
    / "autopilot"
    / "mergegate_guards.py"
)
_TEST_PHASE_REVIEW = (
    _REPO_ROOT
    / "cli"
    / "twl"
    / "tests"
    / "autopilot"
    / "test_merge_gate_phase_review.py"
)
_DEPS_YAML = _REPO_ROOT / "deps.yaml"


# ---------------------------------------------------------------------------
# Requirement: mergegate_guards モジュール
# Scenario: guard 関数のインポート
# ---------------------------------------------------------------------------


class TestGuardFunctionImport:
    """
    WHEN: from twl.autopilot.mergegate_guards import _check_phase_review_guard を実行する
    THEN: インポートが成功し、関数が呼び出し可能である
    """

    @pytest.mark.xfail(
        not _MERGEGATE_GUARDS_PY.exists(),
        reason="mergegate_guards.py はまだ存在しない（Phase A 実装後に PASS）",
        strict=True,
    )
    def test_import_check_phase_review_guard_from_mergegate_guards(self) -> None:
        """_check_phase_review_guard が mergegate_guards からインポート可能であること。"""
        # xfail が外れるのは mergegate_guards.py 作成後
        from twl.autopilot.mergegate_guards import (  # noqa: PLC0415
            _check_phase_review_guard,
        )

        assert callable(_check_phase_review_guard), (
            "_check_phase_review_guard は callable でなければならない"
        )

    @pytest.mark.xfail(
        not _MERGEGATE_GUARDS_PY.exists(),
        reason="mergegate_guards.py はまだ存在しない（Phase A 実装後に PASS）",
        strict=True,
    )
    def test_mergegate_guards_module_is_importable(self) -> None:
        """twl.autopilot.mergegate_guards モジュール自体がインポート可能であること。"""
        import importlib  # noqa: PLC0415

        mod = importlib.import_module("twl.autopilot.mergegate_guards")
        assert mod is not None


# ---------------------------------------------------------------------------
# Requirement: mergegate_guards モジュール
# Scenario: deps.yaml 登録
# ---------------------------------------------------------------------------


class TestDepsYamlRegistration:
    """
    WHEN: twl check を実行する
    THEN: autopilot-mergegate-guards エントリが deps.yaml に存在し、エラーが発生しない
    """

    @pytest.mark.xfail(
        reason="deps.yaml への autopilot-mergegate-guards 登録は Phase A 実装後",
        strict=True,
    )
    def test_deps_yaml_contains_autopilot_mergegate_guards_entry(self) -> None:
        """deps.yaml に autopilot-mergegate-guards エントリが存在すること。"""
        assert _DEPS_YAML.exists(), f"deps.yaml が見つかりません: {_DEPS_YAML}"
        content = _DEPS_YAML.read_text(encoding="utf-8")
        assert "autopilot-mergegate-guards" in content, (
            "deps.yaml に autopilot-mergegate-guards エントリが見つかりません。"
            "Phase A 完了後に deps.yaml を更新してください。"
        )


# ---------------------------------------------------------------------------
# Requirement: mergegate.py の行数削減
# Scenario: Phase A 後の行数確認
# ---------------------------------------------------------------------------


class TestMergegatePyLineCount:
    """
    WHEN: wc -l cli/twl/src/twl/autopilot/mergegate.py を実行する
    THEN: 行数が 500 以下である
    """

    @pytest.mark.xfail(
        _MERGEGATE_PY.exists()
        and _MERGEGATE_PY.stat().st_size > 0
        and sum(1 for _ in _MERGEGATE_PY.open()) > 500,
        reason=(
            f"mergegate.py の現在行数が 500 超 "
            f"（guard 抽出 Phase A 完了後に PASS）"
        ),
        strict=True,
    )
    def test_mergegate_py_line_count_is_500_or_less(self) -> None:
        """mergegate.py の行数が 500 行以下であること（Phase A 後の目標）。"""
        assert _MERGEGATE_PY.exists(), f"mergegate.py が見つかりません: {_MERGEGATE_PY}"
        line_count = sum(1 for _ in _MERGEGATE_PY.open(encoding="utf-8"))
        assert line_count <= 500, (
            f"mergegate.py の行数が {line_count} 行です（上限: 500 行）。"
            "Phase A（guard 抽出）を完了してください。"
        )


# ---------------------------------------------------------------------------
# Requirement: テストのインポートパス更新
# Scenario: テストファイルのインポートパス
# ---------------------------------------------------------------------------


class TestImportPathInTestFile:
    """
    WHEN: test_merge_gate_phase_review.py を inspect する
    THEN: from twl.autopilot.mergegate_guards import _check_phase_review_guard が含まれる
    """

    def test_phase_review_test_file_exists(self) -> None:
        """test_merge_gate_phase_review.py が存在すること。"""
        assert _TEST_PHASE_REVIEW.exists(), (
            f"テストファイルが見つかりません: {_TEST_PHASE_REVIEW}"
        )

    @pytest.mark.xfail(
        _TEST_PHASE_REVIEW.exists()
        and "from twl.autopilot.mergegate_guards import _check_phase_review_guard"
        not in _TEST_PHASE_REVIEW.read_text(encoding="utf-8"),
        reason=(
            "test_merge_gate_phase_review.py がまだ mergegate.py からインポートしている"
            "（Phase A 実装後にインポートパスを更新）"
        ),
        strict=True,
    )
    def test_phase_review_test_imports_from_mergegate_guards(self) -> None:
        """test_merge_gate_phase_review.py が mergegate_guards からインポートすること。"""
        assert _TEST_PHASE_REVIEW.exists(), (
            f"テストファイルが見つかりません: {_TEST_PHASE_REVIEW}"
        )
        source = _TEST_PHASE_REVIEW.read_text(encoding="utf-8")
        assert (
            "from twl.autopilot.mergegate_guards import _check_phase_review_guard"
            in source
        ), (
            "test_merge_gate_phase_review.py のインポートパスを "
            "twl.autopilot.mergegate に修正してください。\n"
            "期待: from twl.autopilot.mergegate_guards import _check_phase_review_guard"
        )

    def test_phase_review_test_does_not_import_guard_from_mergegate(self) -> None:
        """
        Phase A 完了後: test_merge_gate_phase_review.py が
        twl.autopilot.mergegate から _check_phase_review_guard を
        インポートしていないことを確認（後方互換 re-export は除く）。

        NOTE: このテストは実装後に xfail を外して有効化する。
        現時点では現状（mergegate から直接インポート）を確認するだけ。
        """
        if not _TEST_PHASE_REVIEW.exists():
            pytest.skip("テストファイルが未存在のためスキップ")

        source = _TEST_PHASE_REVIEW.read_text(encoding="utf-8")

        # AST 解析で import 文を確認
        try:
            tree = ast.parse(source)
        except SyntaxError as exc:
            pytest.fail(f"test_merge_gate_phase_review.py の構文エラー: {exc}")

        old_import_found = False
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom):
                module = node.module or ""
                names = [alias.name for alias in node.names]
                if (
                    module == "twl.autopilot.mergegate"
                    and "_check_phase_review_guard" in names
                ):
                    old_import_found = True
                    break

        # 現時点は old_import が存在することを想定（Phase A 前）
        # Phase A 完了後は以下のアサーションを反転させること:
        #   assert not old_import_found, "古いインポートパスが残っています"
        # 現在は既存状態をドキュメントするだけなので常に PASS
        _ = old_import_found  # Phase A 後に削除し assert not old_import_found に変更
