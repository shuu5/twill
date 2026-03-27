#!/usr/bin/env python3
"""Tests for domain model detail requirements.

Spec: openspec/changes/arch-spec-refine/specs/model-detail.md

Verifies that architecture/domain/model.md contains detailed class diagrams
with typed attributes, aggregate boundaries, and value object listings.
"""

import re
from pathlib import Path

import pytest

ARCH_ROOT = Path(__file__).parent.parent.parent / "architecture"
MODEL_PATH = ARCH_ROOT / "domain" / "model.md"


def _read_model() -> str:
    """Read model.md and return its content."""
    assert MODEL_PATH.exists(), f"model.md not found at {MODEL_PATH}"
    return MODEL_PATH.read_text(encoding="utf-8")


def _extract_mermaid_classes(content: str) -> dict[str, list[str]]:
    """Extract class names and their attributes from Mermaid classDiagram blocks.

    Returns {class_name: [attribute_lines]}.
    """
    classes: dict[str, list[str]] = {}
    # Find all mermaid blocks
    mermaid_pattern = re.compile(
        r"```mermaid\s*\n(.*?)```", re.DOTALL
    )
    for block_match in mermaid_pattern.finditer(content):
        block = block_match.group(1)
        # Find class definitions
        class_pattern = re.compile(
            r"class\s+(\w+)\s*\{([^}]*)\}", re.DOTALL
        )
        for cls_match in class_pattern.finditer(block):
            cls_name = cls_match.group(1)
            body = cls_match.group(2).strip()
            attrs = [
                line.strip() for line in body.splitlines()
                if line.strip()
            ]
            classes[cls_name] = attrs
    return classes


class TestClassDiagramAttributes:
    """Scenario: クラス図の属性詳細度

    WHEN: domain/model.md のクラス図を確認する
    THEN: Plugin, Component, Type, Chain の各エンティティに型付き属性が定義されている
    """

    REQUIRED_ENTITIES = {"Plugin", "Component", "Type", "Chain"}

    def test_required_entities_exist_in_class_diagram(self) -> None:
        """Plugin, Component, Type, Chain are all defined in the class diagram."""
        content = _read_model()
        classes = _extract_mermaid_classes(content)
        for entity in self.REQUIRED_ENTITIES:
            assert entity in classes, (
                f"Entity '{entity}' not found in class diagram. "
                f"Found: {sorted(classes.keys())}"
            )

    def test_entities_have_typed_attributes(self) -> None:
        """Each required entity has at least one typed attribute (name: type)."""
        content = _read_model()
        classes = _extract_mermaid_classes(content)
        typed_attr_pattern = re.compile(r"[+\-#~]?\w+\s*:\s*\S+")
        for entity in self.REQUIRED_ENTITIES:
            if entity not in classes:
                pytest.skip(f"Entity '{entity}' not in class diagram")
            attrs = classes[entity]
            typed_attrs = [a for a in attrs if typed_attr_pattern.match(a)]
            assert len(typed_attrs) >= 1, (
                f"Entity '{entity}' has no typed attributes. "
                f"Attributes found: {attrs}"
            )

    def test_plugin_has_deps_yaml_fields(self) -> None:
        """Plugin entity reflects deps.yaml top-level fields."""
        content = _read_model()
        classes = _extract_mermaid_classes(content)
        if "Plugin" not in classes:
            pytest.skip("Plugin entity not in class diagram")
        plugin_text = "\n".join(classes["Plugin"]).lower()
        # At minimum, name and version should be present
        assert "name" in plugin_text, "Plugin missing 'name' attribute"
        assert "version" in plugin_text, "Plugin missing 'version' attribute"

    def test_component_has_deps_yaml_fields(self) -> None:
        """Component entity reflects deps.yaml component fields."""
        content = _read_model()
        classes = _extract_mermaid_classes(content)
        if "Component" not in classes:
            pytest.skip("Component entity not in class diagram")
        comp_text = "\n".join(classes["Component"]).lower()
        for field in ("name", "type", "path"):
            assert field in comp_text, (
                f"Component missing '{field}' attribute"
            )


class TestAggregateBoundaries:
    """Scenario: 集約境界の記述確認

    WHEN: domain/model.md の集約セクションを確認する
    THEN: 各集約のルートエンティティと境界内エンティティが明示されている
    """

    def test_aggregate_section_exists(self) -> None:
        """model.md contains an aggregate boundary section."""
        content = _read_model()
        # Check for "Aggregate" or "集約" heading
        has_aggregate = bool(
            re.search(r"#{2,4}\s+.*[Aa]ggregate|#{2,4}\s+.*集約", content)
        )
        assert has_aggregate, (
            "model.md does not contain an Aggregate/集約 section"
        )

    def test_aggregate_root_entities_identified(self) -> None:
        """Aggregate root entities are explicitly identified."""
        content = _read_model()
        # Look for terms like "root", "aggregate root", "ルート集約", "ルートエンティティ"
        has_root_mention = bool(
            re.search(
                r"[Aa]ggregate\s+[Rr]oot|ルートエンティティ|ルート集約|root\s+entity",
                content,
            )
        )
        assert has_root_mention, (
            "model.md does not identify aggregate root entities"
        )

    def test_aggregate_boundary_entities_listed(self) -> None:
        """Each aggregate lists its boundary (internal) entities."""
        content = _read_model()
        # After aggregate section, look for entity listings
        # (bullet points or table rows with entity names)
        aggregate_match = re.search(
            r"(#{2,4}\s+.*[Aa]ggregate.*|#{2,4}\s+.*集約.*)\n([\s\S]*?)(?=\n#{2}\s|\Z)",
            content,
        )
        assert aggregate_match is not None, (
            "Could not find aggregate boundary section content"
        )
        section_content = aggregate_match.group(2)
        # Should contain at least 2 entity references (root + member)
        entity_refs = re.findall(r"(?:Plugin|Component|Type|Chain|Path|Section|Call)", section_content)
        assert len(entity_refs) >= 2, (
            f"Aggregate section has too few entity references: {entity_refs}"
        )


class TestValueObjects:
    """Scenario: 値オブジェクトの識別

    WHEN: domain/model.md を確認する
    THEN: 値オブジェクトがエンティティとは別に列挙されている
    """

    EXPECTED_VALUE_OBJECTS = {"Path", "Section", "Call"}

    def test_value_objects_section_exists(self) -> None:
        """model.md has a section distinguishing value objects from entities."""
        content = _read_model()
        has_vo_section = bool(
            re.search(
                r"#{2,4}\s+.*[Vv]alue\s+[Oo]bject|#{2,4}\s+.*値オブジェクト",
                content,
            )
        )
        assert has_vo_section, (
            "model.md does not have a Value Object/値オブジェクト section"
        )

    def test_expected_value_objects_listed(self) -> None:
        """Path, Section, Call are identified as value objects."""
        content = _read_model()
        # Find value object section
        vo_match = re.search(
            r"(#{2,4}\s+.*[Vv]alue\s+[Oo]bject.*|#{2,4}\s+.*値オブジェクト.*)\n([\s\S]*?)(?=\n#{2,4}\s|\Z)",
            content,
        )
        assert vo_match is not None, (
            "Could not find value object section content"
        )
        section_content = vo_match.group(2)
        for vo in self.EXPECTED_VALUE_OBJECTS:
            assert vo in section_content, (
                f"Value object '{vo}' not listed in value object section"
            )
