"""Tests for Issue #1302: domain/model.md に Protocol/CrossRepoDependency エンティティを追加。

TDD RED phase tests — all tests FAIL before implementation (intentional RED).

AC list:
  AC-1: domain/model.md のクラス図に Protocol エンティティ（attributes: participants,
        pinned_sha, interface_contract）と CrossRepoDependency との関係定義（Provider/Consumer）を追加
  AC-2: 修正後 twl validate または worker-arch-doc-reviewer / worker-architecture で WARNING 解消確認
  AC-3: 関連 ADR/SKILL/refs に整合する更新があれば同時実施（ADR-033 との整合性）
  AC-4: regression test または fixture で修正の persistence 確認（該当する場合のみ）
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

WORKTREE_ROOT = Path(__file__).resolve().parents[3]
DOMAIN_MODEL = WORKTREE_ROOT / "plugins/twl/architecture/domain/model.md"


def _find_adr_033() -> Path | None:
    candidates = list((WORKTREE_ROOT / "plugins/twl/architecture/decisions").glob("ADR-033-*.md"))
    return candidates[0] if candidates else None


def _classDiagram_text() -> str:
    """model.md の最初の classDiagram ブロックを返す。"""
    text = DOMAIN_MODEL.read_text(encoding="utf-8")
    match = re.search(r"```mermaid\s+classDiagram(.*?)```", text, re.DOTALL)
    assert match is not None, "domain/model.md に classDiagram ブロックが存在しない"
    return match.group(1)


# ---------------------------------------------------------------------------
# AC-1: Protocol エンティティと CrossRepoDependency 関係の追加
# ---------------------------------------------------------------------------


class TestAC1ProtocolEntityInDomainModel:
    """AC-1: classDiagram に Protocol クラスと CrossRepoDependency 関係が存在すること."""

    def test_ac1_protocol_class_exists(self):
        # AC: classDiagram ブロックに `class Protocol {` が存在すること
        # RED: 現在の model.md には Protocol クラスが存在しないため FAIL する
        assert DOMAIN_MODEL.exists(), f"domain/model.md が存在しない: {DOMAIN_MODEL}"
        diagram = _classDiagram_text()
        assert "class Protocol" in diagram, (
            "AC-1 未実装: domain/model.md の classDiagram に Protocol クラスが存在しない"
        )

    def test_ac1_protocol_has_participants_attribute(self):
        # AC: Protocol クラスに participants 属性が存在すること
        # RED: Protocol クラス自体が存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        assert "participants" in diagram, (
            "AC-1 未実装: Protocol クラスに participants 属性が存在しない"
        )

    def test_ac1_protocol_has_pinned_sha_attribute(self):
        # AC: Protocol クラスに pinned_sha 属性が存在すること
        # RED: Protocol クラス自体が存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        assert "pinned_sha" in diagram, (
            "AC-1 未実装: Protocol クラスに pinned_sha 属性が存在しない"
        )

    def test_ac1_protocol_has_interface_contract_attribute(self):
        # AC: Protocol クラスに interface_contract 属性が存在すること
        # RED: Protocol クラス自体が存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        assert "interface_contract" in diagram, (
            "AC-1 未実装: Protocol クラスに interface_contract 属性が存在しない"
        )

    def test_ac1_cross_repo_dependency_class_exists(self):
        # AC: classDiagram ブロックに CrossRepoDependency クラスが存在すること
        # RED: 現在の model.md には CrossRepoDependency クラスが存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        assert "CrossRepoDependency" in diagram, (
            "AC-1 未実装: domain/model.md の classDiagram に CrossRepoDependency クラスが存在しない"
        )

    def test_ac1_provider_consumer_relationship_defined(self):
        # AC: Protocol と CrossRepoDependency の Provider/Consumer 関係が定義されていること
        # RED: Protocol も CrossRepoDependency も存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        has_provider = "Provider" in diagram
        has_consumer = "Consumer" in diagram
        assert has_provider and has_consumer, (
            f"AC-1 未実装: Provider/Consumer 関係が classDiagram に存在しない "
            f"(Provider={'あり' if has_provider else 'なし'}, "
            f"Consumer={'あり' if has_consumer else 'なし'})"
        )


# ---------------------------------------------------------------------------
# AC-2: 修正後に classDiagram の整合性が保たれること（validate 代替静的チェック）
# ---------------------------------------------------------------------------


class TestAC2DiagramConsistency:
    """AC-2: classDiagram 内の全関係定義で使用されるクラスが定義されていること."""

    def test_ac2_protocol_class_defined_before_use_in_relations(self):
        # AC: Protocol が関係行に現れる場合、class Protocol { が存在すること
        # RED: Protocol が存在しないため、実装後に追加されるまで FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        # Protocol が関係行に使われているかを確認
        protocol_in_relation = bool(re.search(r"\bProtocol\b\s+(?:-->|\.\.>|\*--)", diagram) or
                                     re.search(r"(?:-->|\.\.>|\*--)\s+\bProtocol\b", diagram))
        if protocol_in_relation:
            assert "class Protocol" in diagram, (
                "AC-2: Protocol が関係定義で使用されているが class Protocol { が定義されていない"
            )
        else:
            # Protocol が関係にも定義にも存在しない → AC-1 未実装
            assert "class Protocol" in diagram, (
                "AC-2 未実装: classDiagram に Protocol クラスが存在しない（AC-1 が未実装）"
            )

    def test_ac2_cross_repo_dependency_defined_before_use_in_relations(self):
        # AC: CrossRepoDependency が関係行に現れる場合、class CrossRepoDependency { が存在すること
        # RED: CrossRepoDependency が存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        cross_in_relation = bool(re.search(r"\bCrossRepoDependency\b\s+(?:-->|\.\.>|\*--)", diagram) or
                                  re.search(r"(?:-->|\.\.>|\*--)\s+\bCrossRepoDependency\b", diagram))
        if cross_in_relation:
            assert "class CrossRepoDependency" in diagram, (
                "AC-2: CrossRepoDependency が関係定義で使用されているが class 定義が存在しない"
            )
        else:
            assert "CrossRepoDependency" in diagram, (
                "AC-2 未実装: classDiagram に CrossRepoDependency が存在しない（AC-1 が未実装）"
            )


# ---------------------------------------------------------------------------
# AC-3: ADR-033 との整合性確認
# ---------------------------------------------------------------------------


class TestAC3AlignmentWithADR033:
    """AC-3: ADR-033 の Protocol 概念が domain/model.md に反映されていること."""

    def test_ac3_adr033_exists(self):
        # NOTE: ADR-033 は PR #1297 で作成済み → このテストは PASS するはず
        adr033 = _find_adr_033()
        assert adr033 is not None, (
            "AC-3 前提: plugins/twl/architecture/decisions/ADR-033-*.md が存在しない"
        )

    def test_ac3_model_reflects_adr033_pinned_sha_concept(self):
        # AC: ADR-033 が定義する pinned_sha（Pinned Reference）概念が model.md の
        #     Protocol エンティティに反映されていること
        # RED: 現在の model.md には Protocol クラスが存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        text = DOMAIN_MODEL.read_text(encoding="utf-8")
        assert "pinned_sha" in text, (
            "AC-3 未実装: domain/model.md の Protocol クラスに ADR-033 の "
            "Pinned Reference 概念（pinned_sha）が反映されていない"
        )

    def test_ac3_model_reflects_adr033_protocols_directory(self):
        # AC: domain/model.md の Protocol エンティティが ADR-033 の protocols/ ディレクトリ概念と
        #     整合していること（Protocol クラスが classDiagram に存在すること）
        # RED: 現在の model.md には Protocol クラスが存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        assert "class Protocol" in diagram, (
            "AC-3 未実装: domain/model.md の classDiagram に Protocol クラスが存在しない。"
            "ADR-033 の protocols/ ディレクトリ概念がモデルに反映されていない"
        )


# ---------------------------------------------------------------------------
# AC-4: 永続化確認（regression テスト）
# ---------------------------------------------------------------------------


class TestAC4RegressionPersistence:
    """AC-4: Protocol と CrossRepoDependency が classDiagram に永続化されていること."""

    def test_ac4_protocol_entity_persists_in_classDiagram(self):
        # AC: classDiagram ブロック内に Protocol エンティティが存在すること（回帰テスト）
        # RED: 現在の model.md には Protocol クラスが存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        assert "class Protocol" in diagram, (
            "AC-4 回帰テスト失敗: classDiagram ブロック内に Protocol エンティティが存在しない"
        )

    def test_ac4_cross_repo_dependency_persists_in_classDiagram(self):
        # AC: classDiagram ブロック内に CrossRepoDependency が存在すること（回帰テスト）
        # RED: 現在の model.md には CrossRepoDependency クラスが存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        assert "CrossRepoDependency" in diagram, (
            "AC-4 回帰テスト失敗: classDiagram ブロック内に CrossRepoDependency が存在しない"
        )

    def test_ac4_all_three_protocol_attributes_present(self):
        # AC: participants / pinned_sha / interface_contract の3属性がすべて存在すること
        # RED: Protocol クラスが存在しないため FAIL する
        assert DOMAIN_MODEL.exists()
        diagram = _classDiagram_text()
        missing = [
            attr for attr in ("participants", "pinned_sha", "interface_contract")
            if attr not in diagram
        ]
        assert not missing, (
            f"AC-4 回帰テスト失敗: Protocol クラスに以下の属性が存在しない: {missing}"
        )
