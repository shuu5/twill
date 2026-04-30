"""Tests for Issue #1123: workflow-observe-loop の can_spawn に script を追加する tech-debt 修正。

TDD RED phase -- AC-1 / AC-3 のテストは実装前に FAIL する。
AC-2 / AC-4 は回帰ガード（現時点で PASS、実装後も PASS を維持すること）。
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import yaml

# ---------------------------------------------------------------------------
# パス定数
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).parents[3]
CLI_TWL = REPO_ROOT / "cli" / "twl"
PLUGINS_TWL = REPO_ROOT / "plugins" / "twl"

DEPS_YAML = PLUGINS_TWL / "deps.yaml"


# ---------------------------------------------------------------------------
# ヘルパー
# ---------------------------------------------------------------------------


def _load_deps_yaml() -> dict:
    assert DEPS_YAML.exists(), f"deps.yaml が存在しない: {DEPS_YAML}"
    return yaml.safe_load(DEPS_YAML.read_text(encoding="utf-8"))


def _get_observe_loop_entry(deps: dict) -> dict:
    entry = deps["skills"].get("workflow-observe-loop")
    assert entry is not None, "deps.yaml に workflow-observe-loop エントリが存在しない"
    return entry


# ---------------------------------------------------------------------------
# AC-1: deps.yaml の workflow-observe-loop.can_spawn に script が含まれること
# ---------------------------------------------------------------------------


def test_ac1_workflow_observe_loop_can_spawn_includes_script():
    """AC-1: plugins/twl/deps.yaml の workflow-observe-loop.can_spawn に 'script' が含まれること。

    RED: 現在は can_spawn: [composite, atomic, specialist] で script が欠落。
    """
    deps = _load_deps_yaml()
    entry = _get_observe_loop_entry(deps)
    can_spawn = entry.get("can_spawn", [])
    assert "script" in can_spawn, (
        f"workflow-observe-loop.can_spawn に 'script' が存在しない。現在の値: {can_spawn}"
    )


def test_ac1_workflow_observe_loop_can_spawn_final_value():
    """AC-1 補足: can_spawn の最終値が [composite, atomic, specialist, script] であること。

    RED: script が欠落しているため現在の値は [composite, atomic, specialist]。
    """
    deps = _load_deps_yaml()
    entry = _get_observe_loop_entry(deps)
    can_spawn = entry.get("can_spawn", [])
    expected = ["composite", "atomic", "specialist", "script"]
    assert can_spawn == expected, (
        f"workflow-observe-loop.can_spawn の値が期待と異なる。期待: {expected}, 実際: {can_spawn}"
    )


# ---------------------------------------------------------------------------
# AC-2: twl --validate で Violations: 0 が維持されること（回帰ガード）
# ---------------------------------------------------------------------------


def test_ac2_validate_violations_zero():
    """AC-2: plugins/twl/ で twl --validate を実行したとき Violations: 0 が出力されること。

    回帰ガード: 現状すでに Violations: 0 (runtime 違反なし)。修正後も維持すること。
    """
    result = subprocess.run(
        ["python3", "-m", "twl", "--validate"],
        cwd=PLUGINS_TWL,
        capture_output=True,
        text=True,
        env={**__import__("os").environ, "TWL_LOOM_ROOT": str(CLI_TWL)},
    )
    output = result.stdout + result.stderr
    assert "Violations: 0" in output, (
        f"twl --validate が Violations: 0 を出力しなかった。\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


# ---------------------------------------------------------------------------
# AC-3: 命名規約準拠の consistency test（Issue #1123 指定の exact 名称）
# ---------------------------------------------------------------------------


def test_workflow_observe_loop_can_spawn_includes_script():
    """AC-3: deps.yaml の workflow-observe-loop.can_spawn に 'script' が含まれること。

    RED: 現在 can_spawn = [composite, atomic, specialist] で script が欠落。
    AC-1 修正後に GREEN になることを期待する。
    """
    deps = _load_deps_yaml()
    entry = _get_observe_loop_entry(deps)
    can_spawn = entry.get("can_spawn", [])
    assert "script" in can_spawn, (
        f"workflow-observe-loop.can_spawn に 'script' が存在しない。現在の値: {can_spawn}"
    )


def test_workflow_observe_loop_calls_script_implies_can_spawn_script():
    """AC-3: workflow-observe-loop の calls に script エントリがある場合、can_spawn に script が含まれること。

    RED: 現在 calls に script が 2 件 (observe-wrapper, session-state-wrapper) 存在するが
    can_spawn に script が含まれていない。AC-1 修正後に GREEN になることを期待する。

    スコープ: workflow-observe-loop 単体エントリのみ。他 workflow エントリは Out of scope。
    trivially-pass note: calls に script が常に 2 件あるため前提条件は常に true となり、
    このテストは現状の整合性を継続的に保証する。
    """
    deps = _load_deps_yaml()
    entry = _get_observe_loop_entry(deps)
    calls = entry.get("calls", [])
    can_spawn = entry.get("can_spawn", [])

    script_calls = [call for call in calls if "script" in call]
    # 前提確認: calls に script エントリが存在すること（Issue 時点で observe-wrapper, session-state-wrapper）
    assert script_calls, (
        "テスト前提: workflow-observe-loop の calls に script エントリが存在すること。"
        f"現在の calls: {calls}"
    )
    # 本体アサーション: script を呼ぶなら can_spawn に script が必要
    assert "script" in can_spawn, (
        f"workflow-observe-loop は {script_calls} を calls するが can_spawn に script がない。"
        f"現在の can_spawn: {can_spawn}"
    )


# ---------------------------------------------------------------------------
# AC-4: 既存 pytest スイートが引き続き pass すること（回帰ガード）
# ---------------------------------------------------------------------------


def test_ac4_existing_pytest_suite_passes():
    """AC-4: 既存テストスイートが pass すること（回帰ガード）。

    回帰ガード: deps.yaml 修正による既存テストへの影響がないことを確認する。
    """
    target_tests = [
        "tests/test_v3_schema.py",
        "tests/test_promote.py",
        "tests/test_supervisor_type.py",
        "tests/test_issue_1118_workflow_can_spawn.py",
    ]
    result = subprocess.run(
        ["python3", "-m", "pytest", "--tb=short", "-q"] + target_tests,
        cwd=CLI_TWL,
        capture_output=True,
        text=True,
        env={**__import__("os").environ, "TWL_LOOM_ROOT": str(CLI_TWL)},
    )
    assert result.returncode == 0, (
        f"既存テストが fail した。\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
