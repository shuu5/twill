"""Tests for Issue #1118: workflow.can_spawn に reference を追加する tech-debt 修正。

TDD RED phase -- すべてのテストは実装前に FAIL する。
実装完了後に GREEN になることを期待する。
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest
import yaml

# ---------------------------------------------------------------------------
# パス定数
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).parents[3]
CLI_TWL = REPO_ROOT / "cli" / "twl"
PLUGINS_TWL = REPO_ROOT / "plugins" / "twl"

TYPES_YAML = CLI_TWL / "types.yaml"
DEPS_YAML = PLUGINS_TWL / "deps.yaml"
PITFALLS_CATALOG = PLUGINS_TWL / "skills" / "su-observer" / "refs" / "pitfalls-catalog.md"


# ---------------------------------------------------------------------------
# AC-1: types.yaml の workflow.can_spawn に reference が存在すること
# ---------------------------------------------------------------------------


def test_ac1_types_yaml_workflow_can_spawn_includes_reference():
    """AC-1: cli/twl/types.yaml の workflow.can_spawn に 'reference' が含まれること。

    RED: 現在は can_spawn: [atomic, composite, specialist, script] で reference が欠落。
    """
    assert TYPES_YAML.exists(), f"types.yaml が存在しない: {TYPES_YAML}"
    data = yaml.safe_load(TYPES_YAML.read_text(encoding="utf-8"))
    can_spawn = data["types"]["workflow"]["can_spawn"]
    assert "reference" in can_spawn, (
        f"workflow.can_spawn に 'reference' が存在しない。現在の値: {can_spawn}"
    )


def test_ac1_types_yaml_workflow_can_spawn_order():
    """AC-1 補足: can_spawn の順序が [atomic, composite, specialist, reference, script] であること。

    RED: reference が欠落しているため順序検証も fail する。
    """
    assert TYPES_YAML.exists(), f"types.yaml が存在しない: {TYPES_YAML}"
    data = yaml.safe_load(TYPES_YAML.read_text(encoding="utf-8"))
    can_spawn = data["types"]["workflow"]["can_spawn"]
    expected = ["atomic", "composite", "specialist", "reference", "script"]
    assert can_spawn == expected, (
        f"workflow.can_spawn の順序が期待と異なる。期待: {expected}, 実際: {can_spawn}"
    )


def test_ac1_fallback_type_rules_workflow_includes_reference():
    """AC-1 補足: types.py の _FALLBACK_TYPE_RULES['workflow']['can_spawn'] に 'reference' が含まれること。

    RED: 現在 {'atomic', 'composite', 'specialist'} で reference も script も欠落。
    """
    import sys
    src_path = CLI_TWL / "src"
    sys.path.insert(0, str(src_path))
    try:
        # モジュールキャッシュをリセットして最新の状態を読み込む
        for mod_name in list(sys.modules.keys()):
            if mod_name.startswith("twl"):
                del sys.modules[mod_name]
        from twl.core.types import _FALLBACK_TYPE_RULES
        can_spawn = _FALLBACK_TYPE_RULES["workflow"]["can_spawn"]
        assert "reference" in can_spawn, (
            f"_FALLBACK_TYPE_RULES['workflow']['can_spawn'] に 'reference' が存在しない。現在の値: {can_spawn}"
        )
    finally:
        sys.path.remove(str(src_path))


# ---------------------------------------------------------------------------
# AC-2: plugins/twl/ で twl --validate を実行すると violations が 0 になること
# ---------------------------------------------------------------------------


def test_ac2_validate_violations_zero():
    """AC-2: plugins/twl/ ディレクトリで twl --validate を実行したとき Violations: 0 が出力されること。

    RED: 現在 4 violations が検出されている状態（workflow が reference を spawn できないとして違反）。
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


def test_ac2_validate_no_new_violations_in_other_categories():
    """AC-2 補足: twl --validate で workflow.can_spawn 関連以外の新規違反が発生していないこと。

    RED: AC-1 実装後の回帰を検出するテスト。現時点では violations > 0 のため fail。
    """
    result = subprocess.run(
        ["python3", "-m", "twl", "--validate"],
        cwd=PLUGINS_TWL,
        capture_output=True,
        text=True,
        env={**__import__("os").environ, "TWL_LOOM_ROOT": str(CLI_TWL)},
    )
    output = result.stdout + result.stderr
    # Violations: 0 であれば新規違反なし
    assert "Violations: 0" in output, (
        f"twl --validate に violations が残っている。\n出力:\n{output}"
    )
    # ERROR レベルの非 violation メッセージが含まれていないこと
    error_lines = [line for line in output.splitlines() if "ERROR" in line and "Violations" not in line]
    assert not error_lines, (
        f"validate 出力に予期しない ERROR が含まれている:\n" + "\n".join(error_lines)
    )


# ---------------------------------------------------------------------------
# AC-3: types.yaml 変更が既存テストを破壊しないこと（smoke test）
# ---------------------------------------------------------------------------


def test_ac3_existing_pytest_suite_passes():
    """AC-3: 既存の pytest スイート (test_v3_schema.py, test_promote.py, test_supervisor_type.py) が pass すること。

    RED: AC-1 実装前の状態では types.yaml が不整合のため、これらのテストが参照する
    load_type_rules() が旧 can_spawn を返し、間接的に fail するケースがある。
    実装後に GREEN になることを期待する。

    注意: このテストは subprocess で既存テストを実行する smoke runner。
    既存テスト自体は変更しない。
    """
    target_tests = [
        "tests/test_v3_schema.py",
        "tests/test_promote.py",
        "tests/test_supervisor_type.py",
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


# ---------------------------------------------------------------------------
# AC-4: pitfalls-catalog.md に §16 が存在すること
# ---------------------------------------------------------------------------


def test_ac4_pitfalls_catalog_has_section_16():
    """AC-4: plugins/twl/skills/su-observer/refs/pitfalls-catalog.md に §16 セクションが存在すること。

    RED: 現在最後のセクションは §15 であり、§16 は存在しない。
    """
    assert PITFALLS_CATALOG.exists(), f"pitfalls-catalog.md が存在しない: {PITFALLS_CATALOG}"
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    # "## 16." または "## §16" の形式を許容
    pattern = re.compile(r"^## (?:§?16[.\s])", re.MULTILINE)
    assert pattern.search(content), (
        "pitfalls-catalog.md に §16 セクション (## 16. ... または ## §16 ...) が存在しない。"
    )


# ---------------------------------------------------------------------------
# AC-7: workflow-pr-merge / workflow-issue-lifecycle / workflow-issue-refine の
#        deps.yaml can_spawn が types.yaml 変更後と矛盾しないこと
# ---------------------------------------------------------------------------


def _load_deps_yaml() -> dict:
    assert DEPS_YAML.exists(), f"deps.yaml が存在しない: {DEPS_YAML}"
    return yaml.safe_load(DEPS_YAML.read_text(encoding="utf-8"))


def _load_types_yaml_workflow_can_spawn() -> list:
    assert TYPES_YAML.exists(), f"types.yaml が存在しない: {TYPES_YAML}"
    data = yaml.safe_load(TYPES_YAML.read_text(encoding="utf-8"))
    return data["types"]["workflow"]["can_spawn"]


def test_ac7_workflow_pr_merge_can_spawn_consistent_with_types():
    """AC-7: workflow-pr-merge の deps.yaml can_spawn が types.yaml の workflow.can_spawn のサブセットであること。

    RED: workflow-pr-merge.can_spawn = [composite, atomic, script] で reference を呼んでいる
    (calls に reference: pr-merge-domain-rules / pr-merge-chain-steps) にもかかわらず
    can_spawn に reference がない矛盾がある。types.yaml 修正後は can_spawn を
    [composite, atomic, script, reference] または [composite, atomic, reference, script] に
    更新すれば整合する。現時点では types.yaml が reference を許可していないため fail。
    """
    deps = _load_deps_yaml()
    allowed_by_types = set(_load_types_yaml_workflow_can_spawn())

    workflow_entry = deps["skills"]["workflow-pr-merge"]
    entry_can_spawn = set(workflow_entry.get("can_spawn", []))

    # deps.yaml の can_spawn が types.yaml で許可された型のみを含むこと
    disallowed = entry_can_spawn - allowed_by_types
    assert not disallowed, (
        f"workflow-pr-merge.can_spawn に types.yaml で許可されていない型が含まれている: {disallowed}"
    )

    # calls に reference を含む場合、can_spawn に reference が含まれていること
    calls = workflow_entry.get("calls", [])
    has_reference_call = any("reference" in call for call in calls)
    if has_reference_call:
        assert "reference" in entry_can_spawn, (
            "workflow-pr-merge は calls に reference を持つが、can_spawn に reference が含まれていない。"
        )


def test_ac7_workflow_issue_lifecycle_can_spawn_consistent_with_types():
    """AC-7: workflow-issue-lifecycle の deps.yaml can_spawn が types.yaml の workflow.can_spawn のサブセットであること。

    RED: 現在 types.yaml が reference を許可していないため、整合性検証で fail する可能性がある。
    実装後（types.yaml に reference 追加）に GREEN になることを期待する。
    """
    deps = _load_deps_yaml()
    allowed_by_types = set(_load_types_yaml_workflow_can_spawn())

    workflow_entry = deps["skills"]["workflow-issue-lifecycle"]
    entry_can_spawn = set(workflow_entry.get("can_spawn", []))

    disallowed = entry_can_spawn - allowed_by_types
    assert not disallowed, (
        f"workflow-issue-lifecycle.can_spawn に types.yaml で許可されていない型が含まれている: {disallowed}"
    )

    calls = workflow_entry.get("calls", [])
    has_reference_call = any("reference" in call for call in calls)
    if has_reference_call:
        assert "reference" in entry_can_spawn, (
            "workflow-issue-lifecycle は calls に reference を持つが、can_spawn に reference が含まれていない。"
        )


def test_ac7_workflow_issue_refine_can_spawn_consistent_with_types():
    """AC-7: workflow-issue-refine の deps.yaml can_spawn が types.yaml の workflow.can_spawn のサブセットであること。

    RED: 現在 types.yaml が reference を許可していないため、整合性検証で fail する可能性がある。
    実装後（types.yaml に reference 追加）に GREEN になることを期待する。
    """
    deps = _load_deps_yaml()
    allowed_by_types = set(_load_types_yaml_workflow_can_spawn())

    workflow_entry = deps["skills"]["workflow-issue-refine"]
    entry_can_spawn = set(workflow_entry.get("can_spawn", []))

    disallowed = entry_can_spawn - allowed_by_types
    assert not disallowed, (
        f"workflow-issue-refine.can_spawn に types.yaml で許可されていない型が含まれている: {disallowed}"
    )

    calls = workflow_entry.get("calls", [])
    has_reference_call = any("reference" in call for call in calls)
    if has_reference_call:
        assert "reference" in entry_can_spawn, (
            "workflow-issue-refine は calls に reference を持つが、can_spawn に reference が含まれていない。"
        )


def test_ac7_workflow_pr_merge_can_spawn_includes_reference_when_calls_reference():
    """AC-7 補足: workflow-pr-merge が calls で reference を呼ぶなら can_spawn に reference が必要。

    RED: 現在 workflow-pr-merge.can_spawn = [composite, atomic, script] で
    reference が calls に含まれているにもかかわらず can_spawn に reference がない。
    types.yaml に reference を追加し、deps.yaml の workflow-pr-merge.can_spawn も
    更新すれば GREEN になる。
    """
    deps = _load_deps_yaml()
    workflow_entry = deps["skills"]["workflow-pr-merge"]
    calls = workflow_entry.get("calls", [])
    entry_can_spawn = set(workflow_entry.get("can_spawn", []))

    reference_calls = [call for call in calls if "reference" in call]
    assert reference_calls, (
        "テスト前提: workflow-pr-merge の calls に reference エントリが存在すること（前提確認用）"
    )
    assert "reference" in entry_can_spawn, (
        f"workflow-pr-merge は {reference_calls} を calls するが can_spawn に reference がない。"
    )
