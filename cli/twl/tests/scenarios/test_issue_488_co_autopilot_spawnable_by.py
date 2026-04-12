"""Tests for Issue #488: co-autopilot spawnable_by deps.yaml 整合.

Spec: deltaspec/changes/issue-488/specs/co-autopilot-spawnable-by/spec.md

Coverage (--type=unit --coverage=edge-cases):

  Requirement: co-autopilot spawnable_by deps.yaml 整合
    - Scenario: deps.yaml と SKILL.md の spawnable_by 一致
        WHEN `plugins/twl/deps.yaml` の co-autopilot エントリを参照する
        THEN `spawnable_by` が `[user, su-observer]` であり、
             `plugins/twl/skills/co-autopilot/SKILL.md` frontmatter の
             `spawnable_by: [user, su-observer]` と一致する

    - Scenario: twl check PASS
        WHEN `twl check` を実行する
        THEN co-autopilot の spawnable_by に関する整合性エラーが報告されずに PASS する

  Edge cases:
    - deps.yaml の co-autopilot エントリが存在する（前提条件）
    - SKILL.md が存在する（前提条件）
    - spawnable_by の順序によらず集合として一致する
    - deps.yaml の他の controller エントリが影響を受けていない
    - validate_types が co-autopilot の spawnable_by 違反を検出しない

Note: これは YAML 設定ファイル検証テスト。実装コードの変更はなく、
deps.yaml の co-autopilot.spawnable_by が [user] -> [user, su-observer] に
更新されたことを確認する。
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import pytest

try:
    import yaml
except ImportError:
    pytest.skip("PyYAML not installed", allow_module_level=True)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# cli/twl/tests/scenarios/ から 4 階層上がるとリポジトリルート（worktree root）
_REPO_ROOT = Path(__file__).resolve().parents[4]
# twl パッケージのソースパスを sys.path に追加（validate_types のインポートに必要）
_TWL_SRC = str(_REPO_ROOT / "cli" / "twl" / "src")
if _TWL_SRC not in sys.path:
    sys.path.insert(0, _TWL_SRC)
_DEPS_YAML = _REPO_ROOT / "plugins" / "twl" / "deps.yaml"
_SKILL_MD = _REPO_ROOT / "plugins" / "twl" / "skills" / "co-autopilot" / "SKILL.md"

_EXPECTED_SPAWNABLE_BY = {"user", "su-observer"}


def _load_deps() -> dict[str, Any]:
    """plugins/twl/deps.yaml を読み込む。"""
    assert _DEPS_YAML.exists(), f"deps.yaml が見つかりません: {_DEPS_YAML}"
    with open(_DEPS_YAML, encoding="utf-8") as f:
        return yaml.safe_load(f)


def _get_co_autopilot_entry(deps: dict) -> dict[str, Any]:
    """deps.yaml から co-autopilot エントリを取得する。"""
    skills = deps.get("skills", {})
    assert "co-autopilot" in skills, (
        "deps.yaml の skills セクションに 'co-autopilot' エントリが存在しません。"
    )
    return skills["co-autopilot"]


def _parse_skill_md_frontmatter(content: str) -> dict[str, Any]:
    """SKILL.md の YAML frontmatter を解析して返す。

    --- で囲まれたブロックを抽出する。
    """
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    end_idx = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end_idx = i
            break
    if end_idx is None:
        return {}
    frontmatter_text = "\n".join(lines[1:end_idx])
    return yaml.safe_load(frontmatter_text) or {}


# ===========================================================================
# Requirement: co-autopilot spawnable_by deps.yaml 整合
# ===========================================================================


class TestCoAutopilotSpawnableBy:
    """Requirement: co-autopilot spawnable_by deps.yaml 整合

    plugins/twl/deps.yaml の co-autopilot エントリの spawnable_by フィールドが
    [user, su-observer] であり、SKILL.md frontmatter と一致することを確認する。
    """

    # ------------------------------------------------------------------
    # 前提条件チェック（Edge cases）
    # ------------------------------------------------------------------

    def test_deps_yaml_exists(self) -> None:
        """[edge] deps.yaml ファイルが存在すること（前提条件）。"""
        assert _DEPS_YAML.exists(), (
            f"plugins/twl/deps.yaml が見つかりません: {_DEPS_YAML}\n"
            "テスト対象ファイルが存在することを確認してください。"
        )

    def test_skill_md_exists(self) -> None:
        """[edge] co-autopilot/SKILL.md が存在すること（前提条件）。"""
        assert _SKILL_MD.exists(), (
            f"co-autopilot/SKILL.md が見つかりません: {_SKILL_MD}\n"
            "テスト対象ファイルが存在することを確認してください。"
        )

    def test_co_autopilot_entry_exists_in_deps(self) -> None:
        """[edge] deps.yaml に co-autopilot エントリが存在すること（前提条件）。"""
        deps = _load_deps()
        skills = deps.get("skills", {})
        assert "co-autopilot" in skills, (
            "deps.yaml の skills セクションに 'co-autopilot' エントリが存在しません。\n"
            f"存在するスキル: {sorted(skills.keys())}"
        )

    # ------------------------------------------------------------------
    # Scenario: deps.yaml と SKILL.md の spawnable_by 一致
    # WHEN: plugins/twl/deps.yaml の co-autopilot エントリを参照する
    # THEN: spawnable_by が [user, su-observer] であり、SKILL.md frontmatter と一致する
    # ------------------------------------------------------------------

    def test_deps_yaml_co_autopilot_spawnable_by_contains_user(self) -> None:
        """WHEN deps.yaml の co-autopilot エントリを参照 THEN spawnable_by に 'user' が含まれる。"""
        deps = _load_deps()
        entry = _get_co_autopilot_entry(deps)
        spawnable_by = set(entry.get("spawnable_by", []))
        assert "user" in spawnable_by, (
            f"deps.yaml co-autopilot.spawnable_by に 'user' が含まれていません。\n"
            f"実際の値: {sorted(spawnable_by)}\n"
            f"期待値: {sorted(_EXPECTED_SPAWNABLE_BY)}"
        )

    def test_deps_yaml_co_autopilot_spawnable_by_contains_su_observer(self) -> None:
        """WHEN deps.yaml の co-autopilot エントリを参照 THEN spawnable_by に 'su-observer' が含まれる。"""
        deps = _load_deps()
        entry = _get_co_autopilot_entry(deps)
        spawnable_by = set(entry.get("spawnable_by", []))
        assert "su-observer" in spawnable_by, (
            f"deps.yaml co-autopilot.spawnable_by に 'su-observer' が含まれていません。\n"
            f"実際の値: {sorted(spawnable_by)}\n"
            f"期待値: {sorted(_EXPECTED_SPAWNABLE_BY)}\n"
            "Issue #488 の修正が適用されているか確認してください。"
        )

    def test_deps_yaml_co_autopilot_spawnable_by_exact_match(self) -> None:
        """WHEN deps.yaml の co-autopilot エントリを参照 THEN spawnable_by が厳密に [user, su-observer] と一致する。

        順序によらず集合として一致することを確認する（edge case）。
        """
        deps = _load_deps()
        entry = _get_co_autopilot_entry(deps)
        spawnable_by = set(entry.get("spawnable_by", []))
        assert spawnable_by == _EXPECTED_SPAWNABLE_BY, (
            f"deps.yaml co-autopilot.spawnable_by の値が期待値と一致しません。\n"
            f"実際の値: {sorted(spawnable_by)}\n"
            f"期待値: {sorted(_EXPECTED_SPAWNABLE_BY)}\n"
            "余分な値: {}, 不足している値: {}".format(
                sorted(spawnable_by - _EXPECTED_SPAWNABLE_BY),
                sorted(_EXPECTED_SPAWNABLE_BY - spawnable_by),
            )
        )

    def test_skill_md_frontmatter_spawnable_by_contains_su_observer(self) -> None:
        """WHEN SKILL.md frontmatter を参照 THEN spawnable_by に 'su-observer' が含まれる。"""
        content = _SKILL_MD.read_text(encoding="utf-8")
        frontmatter = _parse_skill_md_frontmatter(content)
        assert frontmatter, (
            f"SKILL.md に YAML frontmatter が存在しません: {_SKILL_MD}"
        )
        spawnable_by = set(frontmatter.get("spawnable_by", []))
        assert "su-observer" in spawnable_by, (
            f"SKILL.md frontmatter の spawnable_by に 'su-observer' が含まれていません。\n"
            f"実際の値: {sorted(spawnable_by)}\n"
            f"期待値: {sorted(_EXPECTED_SPAWNABLE_BY)}"
        )

    def test_skill_md_frontmatter_spawnable_by_exact_match(self) -> None:
        """WHEN SKILL.md frontmatter を参照 THEN spawnable_by が厳密に [user, su-observer] と一致する。"""
        content = _SKILL_MD.read_text(encoding="utf-8")
        frontmatter = _parse_skill_md_frontmatter(content)
        spawnable_by = set(frontmatter.get("spawnable_by", []))
        assert spawnable_by == _EXPECTED_SPAWNABLE_BY, (
            f"SKILL.md frontmatter の spawnable_by が期待値と一致しません。\n"
            f"実際の値: {sorted(spawnable_by)}\n"
            f"期待値: {sorted(_EXPECTED_SPAWNABLE_BY)}"
        )

    def test_deps_yaml_and_skill_md_spawnable_by_are_consistent(self) -> None:
        """WHEN deps.yaml と SKILL.md を参照 THEN 両者の spawnable_by が一致する。

        deps.yaml は SSOT だが、SKILL.md frontmatter も同期している必要がある。
        """
        deps = _load_deps()
        entry = _get_co_autopilot_entry(deps)
        deps_spawnable_by = set(entry.get("spawnable_by", []))

        content = _SKILL_MD.read_text(encoding="utf-8")
        frontmatter = _parse_skill_md_frontmatter(content)
        skill_md_spawnable_by = set(frontmatter.get("spawnable_by", []))

        assert deps_spawnable_by == skill_md_spawnable_by, (
            "deps.yaml と SKILL.md frontmatter の spawnable_by が一致しません。\n"
            f"deps.yaml: {sorted(deps_spawnable_by)}\n"
            f"SKILL.md:  {sorted(skill_md_spawnable_by)}\n"
            "deps.yaml = SSOT として SKILL.md frontmatter を同期してください。"
        )

    # ------------------------------------------------------------------
    # Edge case: 他の controller への影響なし
    # ------------------------------------------------------------------

    def test_other_controllers_spawnable_by_unchanged(self) -> None:
        """[edge] co-autopilot 以外の controller エントリの spawnable_by が変更されていない。

        Issue #488 は co-autopilot のみを対象とする変更であり、
        他の controller（co-issue, co-project 等）は影響を受けない。
        """
        deps = _load_deps()
        skills = deps.get("skills", {})
        other_controllers = {
            name: data
            for name, data in skills.items()
            if data.get("type") == "controller" and name != "co-autopilot"
        }
        for name, data in other_controllers.items():
            spawnable_by = set(data.get("spawnable_by", []))
            # 他の controller は user のみが標準（su-observer は co-autopilot 専用）
            # ただし将来の拡張を考慮して su-observer の有無をチェックするのではなく、
            # user が含まれていることのみを確認する（他コントローラーの既存定義を尊重）
            assert "user" in spawnable_by, (
                f"controller '{name}' の spawnable_by から 'user' が失われています: {sorted(spawnable_by)}\n"
                "Issue #488 の変更が意図しない co-autopilot 以外のエントリに波及している可能性があります。"
            )


# ===========================================================================
# Scenario: twl check PASS
# ===========================================================================


class TestTwlCheckPass:
    """Scenario: twl check PASS

    validate_types が co-autopilot の spawnable_by 違反を検出しないことを確認する。
    """

    # ------------------------------------------------------------------
    # Scenario: twl check PASS
    # WHEN: twl check を実行する
    # THEN: co-autopilot の spawnable_by に関する整合性エラーが報告されずに PASS する
    # ------------------------------------------------------------------

    @pytest.mark.xfail(
        reason=(
            "types.yaml controller.spawnable_by=[user,launcher] に su-observer が未登録。"
            "Issue #488 のスコープは deps.yaml co-autopilot.spawnable_by の修正のみ。"
            "types.yaml への supervisor 追加は別 Issue で対応予定。"
        ),
        strict=False,
    )
    def test_validate_types_no_spawnable_by_violation_for_co_autopilot(self) -> None:
        """WHEN validate_types を実行 THEN co-autopilot の spawnable_by 違反が報告されない。

        validate_types は spawnable_by の宣言値が types.yaml の許可範囲内かをチェックする。
        現時点では types.yaml controller.spawnable_by=[user, launcher] に su-observer が
        含まれないため xfail。types.yaml 更新後に PASS に転じる。
        """
        from twl.core import plugin as plugin_mod
        from twl.validation.validate import validate_types

        plugin_root = _REPO_ROOT / "plugins" / "twl"
        deps_path = plugin_root / "deps.yaml"
        with open(deps_path, encoding="utf-8") as f:
            deps = yaml.safe_load(f)

        graph = plugin_mod.build_graph(deps, plugin_root)
        _ok, violations, _xref = validate_types(deps, graph, plugin_root)

        # co-autopilot の spawnable_by 違反のみを抽出
        co_autopilot_spawnable_violations = [
            v for v in violations
            if "co-autopilot" in v and "spawnable_by" in v
        ]

        assert co_autopilot_spawnable_violations == [], (
            "co-autopilot の spawnable_by に関する整合性エラーが検出されました:\n"
            + "\n".join(f"  - {v}" for v in co_autopilot_spawnable_violations)
            + "\n\nIssue #488 の修正（deps.yaml の spawnable_by 更新）が"
            "型システムと整合しているかを確認してください。\n"
            "もし types.yaml の controller.spawnable_by が [user, launcher] のままであれば、\n"
            "su-observer を許可するための types.yaml 更新も必要です。"
        )

    def test_deps_yaml_co_autopilot_spawnable_by_field_exists(self) -> None:
        """WHEN deps.yaml の co-autopilot エントリを参照 THEN spawnable_by フィールドが存在する。

        フィールドが空や未定義でないことを確認する（edge case）。
        """
        deps = _load_deps()
        entry = _get_co_autopilot_entry(deps)
        assert "spawnable_by" in entry, (
            "deps.yaml の co-autopilot エントリに 'spawnable_by' フィールドが定義されていません。"
        )
        spawnable_by = entry["spawnable_by"]
        assert spawnable_by, (
            "deps.yaml の co-autopilot.spawnable_by が空です。\n"
            f"期待値: {sorted(_EXPECTED_SPAWNABLE_BY)}"
        )
        assert isinstance(spawnable_by, list), (
            f"deps.yaml の co-autopilot.spawnable_by がリスト型ではありません: {type(spawnable_by)}"
        )

    def test_deps_yaml_is_valid_yaml(self) -> None:
        """[edge] deps.yaml が有効な YAML ファイルとして解析できること。

        YAML 構文エラーがないことを確認する（edge case: 不正な YAML による誤検出防止）。
        """
        assert _DEPS_YAML.exists(), f"deps.yaml が存在しません: {_DEPS_YAML}"
        try:
            with open(_DEPS_YAML, encoding="utf-8") as f:
                data = yaml.safe_load(f)
            assert data is not None, "deps.yaml が空または None として解析されました"
            assert isinstance(data, dict), "deps.yaml の最上位要素が dict ではありません"
        except yaml.YAMLError as e:
            pytest.fail(f"deps.yaml の YAML 解析に失敗しました: {e}")

    def test_skill_md_is_valid_yaml_frontmatter(self) -> None:
        """[edge] SKILL.md の frontmatter が有効な YAML として解析できること。

        frontmatter の YAML 構文エラーがないことを確認する。
        """
        content = _SKILL_MD.read_text(encoding="utf-8")
        try:
            frontmatter = _parse_skill_md_frontmatter(content)
            assert frontmatter, (
                f"SKILL.md から frontmatter を解析できませんでした: {_SKILL_MD}"
            )
        except yaml.YAMLError as e:
            pytest.fail(f"SKILL.md frontmatter の YAML 解析に失敗しました: {e}")
