"""Tests for Issue #1265: explore-summary Recommended Structure.

TDD RED phase -- すべてのテストは実装前に FAIL する。
explore-summary の `## Recommended Structure` セクション対応を検証する。
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# パス定数
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).parents[3]
PLUGINS_TWL = REPO_ROOT / "plugins" / "twl"
CO_EXPLORE_SKILL = PLUGINS_TWL / "skills" / "co-explore" / "SKILL.md"
CO_ARCHITECT_SKILL = PLUGINS_TWL / "skills" / "co-architect" / "SKILL.md"
REF_ARCH_SPEC = PLUGINS_TWL / "refs" / "ref-architecture-spec.md"
COMPLETENESS_CHECK = PLUGINS_TWL / "commands" / "architect-completeness-check.md"


# ---------------------------------------------------------------------------
# AC1: explore-summary の `## Recommended Structure` を co-architect Step 2 がパースし
#      type: 値が TI-1 提供の ProjectType パイプラインを通じて伝搬される
# ---------------------------------------------------------------------------

class TestAC1RecommendedStructureParsing:
    """AC1: co-architect Step 2 が explore-summary の Recommended Structure をパースする。"""

    def test_ac1_co_architect_step2_reads_recommended_structure(self):
        # AC: co-architect SKILL.md Step 2 で explore-summary の
        #     ## Recommended Structure セクションを読み込む記述がある
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        step2_match = re.search(
            r"## Step 2:.*?(?=\n## Step 3:|\Z)",
            text,
            re.DOTALL,
        )
        assert step2_match is not None, (
            "AC1: co-architect/SKILL.md に '## Step 2:' セクションが見当たらない"
        )
        step2_text = step2_match.group(0)
        assert "Recommended Structure" in step2_text, (
            "AC1: co-architect/SKILL.md Step 2 に 'Recommended Structure' の"
            f"パース処理が見当たらない。Step 2 テキスト:\n{step2_text[:500]}"
        )

    def test_ac1_co_architect_step2_propagates_project_type(self):
        # AC: co-architect SKILL.md Step 2 で type: 値を ProjectType パイプラインに
        #     伝搬する記述がある
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        step2_match = re.search(
            r"## Step 2:.*?(?=\n## Step 3:|\Z)",
            text,
            re.DOTALL,
        )
        assert step2_match is not None, (
            "AC1: co-architect/SKILL.md に '## Step 2:' セクションが見当たらない"
        )
        step2_text = step2_match.group(0)
        # type: 値の伝搬または ProjectType パイプラインへの言及
        has_type_propagation = (
            "ProjectType" in step2_text
            or "project_type" in step2_text
            or "type:" in step2_text
            or "--type" in step2_text
        )
        assert has_type_propagation, (
            "AC1: co-architect/SKILL.md Step 2 に ProjectType パイプラインへの"
            f"type: 値伝搬が見当たらない。Step 2 テキスト:\n{step2_text[:500]}"
        )

    def test_ac1_co_architect_step2_handles_include_list(self):
        # AC1 coverage: co-architect Step 2 が include: リストを処理することを検証
        # Issue body の技術アプローチ: type: / skip: / include: 抽出が明記されている
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        step2_match = re.search(
            r"## Step 2:.*?(?=\n## Step 3:|\Z)",
            text,
            re.DOTALL,
        )
        assert step2_match is not None, (
            "AC1 coverage: co-architect/SKILL.md に '## Step 2:' セクションが見当たらない"
        )
        step2_text = step2_match.group(0)
        assert "include:" in step2_text or "include" in step2_text.lower(), (
            "AC1 coverage: co-architect/SKILL.md Step 2 に 'include:' フィールドの処理記述が"
            "見当たらない。技術アプローチに type: / skip: / include: 抽出が明記されている。"
            f"Step 2 テキスト:\n{step2_text[:500]}"
        )


# ---------------------------------------------------------------------------
# AC2: `skip:` リスト内の必須ファイルは `architect-completeness-check` で
#      FAIL → INFO に降格される
# ---------------------------------------------------------------------------

class TestAC2SkipListDemotion:
    """AC2: skip: リスト内の必須ファイルが architect-completeness-check で INFO に降格される。"""

    def test_ac2_completeness_check_mentions_skip_list(self):
        # AC: architect-completeness-check.md に skip: リストの処理記述がある
        text = COMPLETENESS_CHECK.read_text(encoding="utf-8")
        has_skip = "skip:" in text or "skip_list" in text or "skip list" in text.lower()
        assert has_skip, (
            "AC2: architect-completeness-check.md に 'skip:' リストの処理が見当たらない。"
            f"ファイル: {COMPLETENESS_CHECK}"
        )

    def test_ac2_completeness_check_demotes_fail_to_info(self):
        # AC: skip: リスト内の必須ファイルに対して FAIL を INFO に降格する記述がある
        text = COMPLETENESS_CHECK.read_text(encoding="utf-8")
        # FAIL から INFO への降格処理
        has_demotion = (
            ("FAIL" in text and "INFO" in text)
            and ("降格" in text or "demote" in text.lower() or "downgrade" in text.lower())
        )
        assert has_demotion, (
            "AC2: architect-completeness-check.md に FAIL → INFO 降格処理が見当たらない。"
            "skip: リスト内のファイルは INFO レベルに降格されるべき。"
            f"ファイル: {COMPLETENESS_CHECK}"
        )

    def test_ac2_ref_arch_spec_mentions_skip_list(self):
        # AC: ref-architecture-spec.md に skip: リスト仕様が定義されている
        text = REF_ARCH_SPEC.read_text(encoding="utf-8")
        has_skip = "skip:" in text or "skip_list" in text or "skip list" in text.lower()
        assert has_skip, (
            "AC2: ref-architecture-spec.md に 'skip:' リスト仕様が見当たらない。"
            f"ファイル: {REF_ARCH_SPEC}"
        )


# ---------------------------------------------------------------------------
# AC3: `Recommended Structure` 不在時のフォールバック（= `--type=ddd` default）が動作する
# ---------------------------------------------------------------------------

class TestAC3FallbackDefault:
    """AC3: Recommended Structure 不在時のフォールバック（--type=ddd default）が動作する。"""

    def test_ac3_co_architect_step2_has_fallback_when_no_recommended_structure(self):
        # AC: co-architect SKILL.md Step 2 に Recommended Structure 不在時の
        #     フォールバック記述がある（単なる DDD 言及ではなく、明示的な fallback 処理）
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        step2_match = re.search(
            r"## Step 2:.*?(?=\n## Step 3:|\Z)",
            text,
            re.DOTALL,
        )
        assert step2_match is not None, (
            "AC3: co-architect/SKILL.md に '## Step 2:' セクションが見当たらない"
        )
        step2_text = step2_match.group(0)
        # 明示的なフォールバック処理: Recommended Structure 不在時の条件分岐が必要
        # 単なる "DDD" への言及（例: "DDD の Bounded Context"）は対象外
        has_explicit_fallback = (
            "--type=ddd" in step2_text
            or "fallback" in step2_text.lower()
            or "フォールバック" in step2_text
            or ("Recommended Structure" in step2_text and "不在" in step2_text)
            or ("Recommended Structure" in step2_text and "ない" in step2_text)
            or ("Recommended Structure" in step2_text and "default" in step2_text.lower())
        )
        assert has_explicit_fallback, (
            "AC3: co-architect/SKILL.md Step 2 に Recommended Structure 不在時の"
            "明示的なフォールバック（--type=ddd default）記述が見当たらない。"
            "'DDD の Bounded Context' のような一般的な言及では不十分。"
            f"Step 2 テキスト:\n{step2_text[:500]}"
        )

    def test_ac3_fallback_is_ddd_type(self):
        # AC: フォールバックが明示的に ddd type であることが co-architect SKILL.md Step 2 に記述されている
        # ファイル全体スキャンではなく Step 2 スコープに限定する（他箇所の DDD 言及と区別）
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        step2_match = re.search(
            r"## Step 2:.*?(?=\n## Step 3:|\Z)",
            text,
            re.DOTALL,
        )
        assert step2_match is not None, (
            "AC3: co-architect/SKILL.md に '## Step 2:' セクションが見当たらない"
        )
        step2_text = step2_match.group(0)
        assert "--type=ddd" in step2_text or "type=ddd" in step2_text, (
            "AC3: co-architect/SKILL.md Step 2 に '--type=ddd' フォールバックが明示されていない。"
            "Recommended Structure 不在時のフォールバックは Step 2 に明記すること。"
            f"Step 2 テキスト:\n{step2_text[:500]}"
        )


# ---------------------------------------------------------------------------
# AC4: Recommended Structure の内容をユーザーが確認できる HUMAN GATE がある
#      （architect の自律的反映を防止、ADR-030 準拠）
# ---------------------------------------------------------------------------

HUMAN_GATE_MARKER = "★HUMAN GATE"


class TestAC4HumanGate:
    """AC4: Recommended Structure 反映前にユーザー確認 HUMAN GATE がある（ADR-030 準拠）。"""

    def test_ac4_co_architect_has_human_gate_for_recommended_structure(self):
        # AC: co-architect SKILL.md に Recommended Structure 確認用の HUMAN GATE がある
        # 単に ★HUMAN GATE が存在するだけでは不十分。
        # "Recommended Structure" の処理ロジック（例: parse/パース/structure）の近傍（500文字以内）に
        # ★HUMAN GATE が存在することを検証する。
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")

        rs_pos = text.find("Recommended Structure")
        if rs_pos == -1:
            pytest.fail(
                "AC4: co-architect/SKILL.md に 'Recommended Structure' が見当たらない。"
                "AC1 の実装（parse ロジック追加）が前提条件。"
            )

        hg_pos = text.find(HUMAN_GATE_MARKER, rs_pos - 1000)
        if hg_pos == -1:
            pytest.fail(
                f"AC4: co-architect/SKILL.md の 'Recommended Structure' 近傍（前後1000文字）に "
                f"'{HUMAN_GATE_MARKER}' が見当たらない。"
                "Recommended Structure 内容のユーザー確認 HUMAN GATE が必要（ADR-030 準拠）。"
            )

        distance = abs(rs_pos - hg_pos)
        assert distance <= 1000, (
            f"AC4: co-architect/SKILL.md の 'Recommended Structure' と '{HUMAN_GATE_MARKER}' の距離が "
            f"{distance} 文字と離れすぎている（上限: 1000 文字）。"
            "HUMAN GATE は Recommended Structure 処理の近傍に配置すること。"
        )

    def test_ac4_human_gate_is_near_recommended_structure_handling(self):
        # AC: HUMAN GATE マーカーが Recommended Structure の処理ロジックの近傍にある
        # さらに A/B/C 選択肢（受諾/修正/DDD default）への言及が HUMAN GATE 周辺にあることを検証
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        rs_pos = text.find("Recommended Structure")

        if rs_pos == -1:
            pytest.fail(
                "AC4: co-architect/SKILL.md に 'Recommended Structure' が見当たらない。"
                "AC1 の実装が前提条件。"
            )

        # 1つ目のテストと同じく rs_pos - 1000 から前方検索でロジックを統一
        hg_pos = text.find(HUMAN_GATE_MARKER, rs_pos - 1000)
        if hg_pos == -1:
            pytest.fail(
                f"AC4: co-architect/SKILL.md の 'Recommended Structure' 近傍（前後1000文字）に "
                f"'{HUMAN_GATE_MARKER}' が見当たらない。"
            )

        distance = abs(rs_pos - hg_pos)
        assert distance <= 1000, (
            f"AC4: 'Recommended Structure'（pos={rs_pos}）と"
            f"'{HUMAN_GATE_MARKER}'（pos={hg_pos}）の距離が {distance} 文字と離れすぎている。"
            "HUMAN GATE は Recommended Structure 処理の近傍に配置すること。"
        )

        # A/B/C 選択肢（受諾 / 修正 / DDD default）への言及
        # HUMAN GATE の前後2000文字以内にユーザー選択肢の記述があること
        context_start = max(0, hg_pos - 1000)
        context_end = min(len(text), hg_pos + 1000)
        hg_context = text[context_start:context_end]
        has_choices = (
            ("受諾" in hg_context or "accept" in hg_context.lower())
            and ("修正" in hg_context or "修正" in hg_context or "modify" in hg_context.lower())
        )
        assert has_choices, (
            "AC4: HUMAN GATE 近傍に選択肢（受諾/修正/DDD default）の記述が見当たらない。"
            "ADR-030 準拠: ユーザーに具体的な選択肢を提示すること（A/B/C: 受諾 / 修正 / DDD default 等）。"
            f"HUMAN GATE 周辺テキスト:\n{hg_context[:500]}"
        )


# ---------------------------------------------------------------------------
# AC5: co-explore SKILL.md で summary template に `## Recommended Structure`
#      セクション追加（optional セクションとして明示）
# ---------------------------------------------------------------------------

class TestAC5CoExploreSummaryTemplate:
    """AC5: co-explore SKILL.md の summary template に ## Recommended Structure が追加されている。"""

    def test_ac5_co_explore_skill_contains_recommended_structure_section(self):
        # AC: co-explore SKILL.md に ## Recommended Structure セクションが記述されている
        text = CO_EXPLORE_SKILL.read_text(encoding="utf-8")
        assert "Recommended Structure" in text, (
            "AC5: co-explore/SKILL.md に 'Recommended Structure' セクションが見当たらない。"
            "summary template に ## Recommended Structure を追加すること。"
            f"ファイル: {CO_EXPLORE_SKILL}"
        )

    def test_ac5_recommended_structure_is_marked_as_optional(self):
        # AC: ## Recommended Structure が optional セクションとして明示されている
        text = CO_EXPLORE_SKILL.read_text(encoding="utf-8")
        # Recommended Structure の周辺に optional の記述があること
        rs_match = re.search(
            r"Recommended Structure.*?(?=\n##|\Z)",
            text,
            re.DOTALL,
        )
        if rs_match is None:
            pytest.fail(
                "AC5: co-explore/SKILL.md に 'Recommended Structure' が見当たらない。"
                "AC5 実装後に再実行してください。"
            )
        rs_context = text[max(0, rs_match.start() - 200): rs_match.end()]
        is_optional = (
            "optional" in rs_context.lower()
            or "オプション" in rs_context
            or "任意" in rs_context
            or "(optional)" in rs_context.lower()
        )
        assert is_optional, (
            "AC5: co-explore/SKILL.md の 'Recommended Structure' セクションが"
            "optional として明示されていない。"
            f"周辺テキスト:\n{rs_context[:400]}"
        )


# ---------------------------------------------------------------------------
# AC6: パース失敗時のエラーメッセージが明確（どのフィールドがパース不可か表示）
# ---------------------------------------------------------------------------

class TestAC6ParseErrorMessage:
    """AC6: パース失敗時のエラーメッセージが明確（どのフィールドがパース不可か表示）。"""

    def test_ac6_co_architect_mentions_parse_error_handling(self):
        # AC: co-architect SKILL.md にパース失敗時のエラーメッセージ処理が記述されている
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        has_error_handling = (
            "パース" in text or "parse" in text.lower() or "解析" in text
        ) and (
            "エラー" in text or "error" in text.lower() or "失敗" in text
        )
        assert has_error_handling, (
            "AC6: co-architect/SKILL.md にパース失敗時のエラーメッセージ処理が見当たらない。"
            "どのフィールドがパース不可かを表示する仕様が必要。"
            f"ファイル: {CO_ARCHITECT_SKILL}"
        )

    def test_ac6_parse_error_shows_field_name(self):
        # AC: パース失敗時にどのフィールドが不可かを示す記述がある
        text = CO_ARCHITECT_SKILL.read_text(encoding="utf-8")
        # フィールド名表示への言及（field, フィールド, type:, key, キー など）
        has_field_reference = (
            "フィールド" in text or "field" in text.lower()
        )
        has_parse_fail = (
            "パース失敗" in text
            or bool(re.search(r"parse.*fail", text.lower()))
            or "パース不可" in text
            or "解析エラー" in text
        )
        assert has_field_reference and has_parse_fail, (
            "AC6: co-architect/SKILL.md のパースエラー処理がフィールド名を特定して"
            "表示する仕様になっていない。"
            f"has_field_reference={has_field_reference}, has_parse_fail={has_parse_fail}。"
            f"ファイル: {CO_ARCHITECT_SKILL}"
        )


# ---------------------------------------------------------------------------
# AC7: `recommended_structure` の例が co-explore SKILL.md にある
# ---------------------------------------------------------------------------

class TestAC7RecommendedStructureExample:
    """AC7: co-explore SKILL.md に recommended_structure の例がある。"""

    def test_ac7_co_explore_skill_has_recommended_structure_example(self):
        # AC: co-explore/SKILL.md に recommended_structure の例（サンプル）が記述されている
        text = CO_EXPLORE_SKILL.read_text(encoding="utf-8")
        # 例示には type: や recommended_structure キーワードが伴うことが多い
        has_example = (
            "recommended_structure" in text
            or "Recommended Structure" in text
        )
        assert has_example, (
            "AC7: co-explore/SKILL.md に 'recommended_structure' または"
            " 'Recommended Structure' の例が見当たらない。"
            f"ファイル: {CO_EXPLORE_SKILL}"
        )

    def test_ac7_recommended_structure_example_contains_type_field(self):
        # AC: recommended_structure の例に type: フィールドが含まれている
        text = CO_EXPLORE_SKILL.read_text(encoding="utf-8")
        # Recommended Structure セクションを探す
        rs_match = re.search(
            r"(## Recommended Structure|recommended_structure).*?(?=\n##|\Z)",
            text,
            re.DOTALL | re.IGNORECASE,
        )
        if rs_match is None:
            pytest.fail(
                "AC7: co-explore/SKILL.md に 'Recommended Structure' セクションが見当たらない。"
                "AC5 の実装が前提条件。"
            )
        rs_text = rs_match.group(0)
        assert "type:" in rs_text, (
            "AC7: co-explore/SKILL.md の Recommended Structure セクションの例に"
            f"'type:' フィールドが含まれていない。\nセクションテキスト:\n{rs_text[:400]}"
        )
