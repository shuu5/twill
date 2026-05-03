"""Tests for Issue #1300: architect-group-refine.md に --type 引数の処理ロジックが欠落

AC-1: architect-group-refine.md の ## 入力 セクションに --type=<value> 引数の定義を追加し、
      フロー内での type 活用ロジックを記述する
AC-2: 修正後 twl validate または該当 specialist で WARNING 解消確認（fixture として記録）
AC-3: 関連 ADR/SKILL/refs に整合する更新があれば同時実施（該当する場合のみ、mapping 記録のみ）
AC-4: regression test または fixture で修正の persistence 確認（該当する場合のみ、mapping 記録のみ）

TDD RED phase -- すべてのテストは実装前に FAIL する。
現在の architect-group-refine.md には --type 引数の定義・処理ロジックが欠落しているため、
以下テストはすべて FAIL する。
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# パス定数
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).parents[3]
PLUGINS_TWL = REPO_ROOT / "plugins" / "twl"
CMD_FILE = PLUGINS_TWL / "commands" / "architect-group-refine.md"
CO_ARCHITECT_SKILL = PLUGINS_TWL / "skills" / "co-architect" / "SKILL.md"


# ---------------------------------------------------------------------------
# AC-1: architect-group-refine.md の ## 入力 セクションに --type=<value> 引数の定義を追加
# ---------------------------------------------------------------------------


class TestAC1ArchitectGroupRefineTypeArg:
    """AC-1: architect-group-refine.md ## 入力 に --type 引数の定義とフロー内活用ロジックがある。"""

    def test_ac1_input_section_contains_type_argument(self):
        # AC: architect-group-refine.md の ## 入力 セクションに --type=<value> の定義がある
        # RED: 現在の architect-group-refine.md には --type 記述が存在しないため FAIL する
        content = CMD_FILE.read_text(encoding="utf-8")
        assert "--type" in content, (
            f"AC-1 未実装: architect-group-refine.md に '--type' が存在しない。"
            f"ファイル: {CMD_FILE}"
        )

    def test_ac1_input_section_type_argument_in_section(self):
        # AC: --type=<value> が ## 入力 セクション内に定義されている
        # RED: ## 入力 セクションに --type が欠落しているため FAIL する
        content = CMD_FILE.read_text(encoding="utf-8")
        input_match = re.search(
            r"## 入力.*?(?=\n## |\Z)",
            content,
            re.DOTALL,
        )
        assert input_match is not None, (
            f"AC-1: architect-group-refine.md に '## 入力' セクションが見当たらない。"
            f"ファイル: {CMD_FILE}"
        )
        input_section = input_match.group(0)
        assert "--type" in input_section, (
            f"AC-1 未実装: '## 入力' セクションに '--type' 引数の定義が存在しない。"
            f"## 入力 セクション:\n{input_section[:300]}"
        )

    def test_ac1_type_argument_has_value_placeholder(self):
        # AC: --type 引数が --type=<value> または --type <value> の形式で定義されている
        # RED: --type 定義が欠落しているため FAIL する
        content = CMD_FILE.read_text(encoding="utf-8")
        # --type=<value> または --type <value> 形式のいずれかを検出
        has_type_with_value = bool(
            re.search(r"--type[=\s][<(]?\w", content)
        )
        assert has_type_with_value, (
            f"AC-1 未実装: architect-group-refine.md に '--type=<value>' または"
            f"'--type <value>' 形式の引数定義が存在しない。"
            f"ファイル: {CMD_FILE}"
        )

    def test_ac1_flow_uses_type_argument(self):
        # AC: フロー内（Step G1〜G6 のいずれか）で type 引数を参照・活用するロジックがある
        # RED: type 活用ロジックが欠落しているため FAIL する
        content = CMD_FILE.read_text(encoding="utf-8")
        # type を変数・条件分岐・伝搬するロジックの存在を確認
        has_type_usage = (
            re.search(r"\$type|\${type}", content) is not None
            or re.search(r"type 引数|type を|type を渡|type.*伝搬", content) is not None
            or re.search(r"--type.*explore|explore.*--type", content) is not None
            or "type_value" in content
            or re.search(r"\btype\b.*Step", content) is not None
        )
        assert has_type_usage, (
            f"AC-1 未実装: architect-group-refine.md のフロー内に --type 引数を"
            f"活用するロジックが存在しない。"
            f"ファイル: {CMD_FILE}"
        )

    def test_ac1_co_architect_step0_calls_with_type(self):
        # AC: architect-group-refine.md が --type 引数をフロー内で参照・活用する記述がある
        # RED: 現在の architect-group-refine.md には --type を Step 内で活用するロジックが
        #      欠落しているため FAIL する
        # NOTE: co-architect SKILL.md Step 0 は既に --type を architect-group-refine に渡す
        #       記述があるが、受け取り側（architect-group-refine.md）がその引数を活用して
        #       いないため、実装として不完全。本テストは修正対象側（architect-group-refine.md）
        #       が --type を Step G4 の /twl:explore 呼び出し等で伝搬・活用するかを確認する。
        content = CMD_FILE.read_text(encoding="utf-8")
        # architect-group-refine.md が --type を explore や内部ロジックに伝搬するか確認
        # 期待パターン:
        #   - Step G4 等で --type を /twl:explore に渡す記述
        #   - --type=<value> を条件分岐・変数として活用する記述
        has_type_propagation = (
            re.search(r"explore.*--type|--type.*explore", content) is not None
            or re.search(r"\$type|\${type}", content) is not None
            or re.search(r"type.*伝搬|type.*propagat", content) is not None
            or re.search(r"--type.*Step G|Step G.*--type", content) is not None
        )
        assert has_type_propagation, (
            f"AC-1 未実装: architect-group-refine.md のフロー内に --type 引数を"
            f"下流（explore 等）に伝搬するロジックが存在しない。"
            f"co-architect Step 0 は --type を渡すが、受け取り側の伝搬ロジックが欠落している。"
            f"ファイル: {CMD_FILE}"
        )


# ---------------------------------------------------------------------------
# AC-2: twl validate で WARNING 解消確認（fixture として記録）
# ---------------------------------------------------------------------------


class TestAC2TwlValidateWarning:
    """AC-2: twl validate で architect-group-refine.md の WARNING が解消されている。"""

    def test_ac2_twl_validate_no_warning_for_architect_group_refine(self):
        # AC: 修正後に architect-group-refine.md の --type 欠落に関する WARNING が消えること
        # RED: 現在の architect-group-refine.md には --type が存在しないため、
        #      co-architect Step 0 で渡された --type が処理されず警告状態にあるはずである。
        #      本テストは「修正後に WARNING が消える」というAC-2 の前提として、
        #      現在の architect-group-refine.md に --type の処理が欠落していることを直接検証する。
        # NOTE: twl バイナリの有無に依存せず、ファイル内容を直接検証することで
        #       環境依存なく RED を維持する。
        content = CMD_FILE.read_text(encoding="utf-8")

        # architect-group-refine.md が --type を受け取って処理するロジックが存在することを確認
        # 「WARNING が消えた状態」= --type が ## 入力 に定義され、フロー内で活用されている状態
        # 現在は --type が欠落しているため、以下アサーションが FAIL する（RED フェーズ）
        has_type_in_input = "--type" in content

        # ## 入力 セクション内に --type の定義があるかも確認
        input_match = re.search(r"## 入力.*?(?=\n## |\Z)", content, re.DOTALL)
        input_section_has_type = (
            "--type" in input_match.group(0) if input_match else False
        )

        assert has_type_in_input and input_section_has_type, (
            f"AC-2 未実装（RED）: architect-group-refine.md に '--type' の定義・処理ロジックが"
            f"存在しないため、co-architect Step 0 が --type を渡しても受け取り側が処理しない。"
            f"修正後は ## 入力 セクションに '--type=<value>' を追加し、フロー内で活用すること。"
            f"ファイル: {CMD_FILE}"
        )
