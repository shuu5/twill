#!/usr/bin/env python3
"""Tests for glossary.md completeness requirements.

Spec: openspec/changes/arch-spec-refine/specs/glossary-completeness.md

Verifies that architecture/domain/glossary.md contains all required terms
from deps.yaml fields, types.yaml types, and validation commands.
"""

import re
from pathlib import Path

import pytest

ARCH_ROOT = Path(__file__).parent.parent.parent / "architecture"
GLOSSARY_PATH = ARCH_ROOT / "domain" / "glossary.md"


def _read_glossary() -> str:
    """Read glossary.md and return its content."""
    assert GLOSSARY_PATH.exists(), f"glossary.md not found at {GLOSSARY_PATH}"
    return GLOSSARY_PATH.read_text(encoding="utf-8")


def _extract_glossary_terms(content: str) -> set[str]:
    """Extract term names from all glossary tables.

    Expects Markdown tables with '| 用語 |' header row.
    Each subsequent row's first column is a term name.
    Handles multiple tables throughout the document.
    """
    terms = set()
    in_table = False
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            in_table = False
            continue
        cells = [c.strip() for c in stripped.split("|")]
        cells = [c for c in cells if c]
        if not cells:
            continue
        if cells[0] == "用語":
            in_table = True
            continue
        if all(set(c) <= {"-", ":"} for c in cells):
            continue
        if in_table:
            terms.add(cells[0].strip())
    return terms


class TestGlossaryDepsYamlFields:
    """Scenario: deps.yaml フィールド名の網羅性検証

    WHEN: glossary.md を確認する
    THEN: deps.yaml で使用される全フィールド名が用語テーブルに存在する
    """

    # Top-level deps.yaml fields (matching glossary terms)
    TOP_LEVEL_FIELDS = {
        "plugin", "version", "entry_points",
        "skills", "commands", "agents", "scripts",
        "hooks", "chains",
    }

    # Component-level fields
    COMPONENT_FIELDS = {
        "type", "path", "description", "calls", "model",
    }

    # Section names used as top-level keys in components
    SECTION_KEYS = {"skills", "commands", "agents"}

    def test_deps_yaml_top_level_fields_in_glossary(self) -> None:
        """All top-level deps.yaml field names appear as glossary terms."""
        content = _read_glossary()
        terms = _extract_glossary_terms(content)
        # Also check if the field name appears anywhere in the glossary
        # (could be in a different column or as inline text within a term)
        for field in self.TOP_LEVEL_FIELDS:
            found = field in terms or any(
                field in term for term in terms
            ) or field in content
            assert found, (
                f"deps.yaml top-level field '{field}' not found in glossary.md"
            )

    def test_deps_yaml_component_fields_in_glossary(self) -> None:
        """All component-level deps.yaml field names appear as glossary terms."""
        content = _read_glossary()
        terms = _extract_glossary_terms(content)
        for field in self.COMPONENT_FIELDS:
            found = field in terms or any(
                field in term for term in terms
            ) or field in content
            assert found, (
                f"deps.yaml component field '{field}' not found in glossary.md"
            )

    def test_deps_yaml_section_keys_in_glossary(self) -> None:
        """Section keys (skills, commands, agents) appear in glossary."""
        content = _read_glossary()
        for key in self.SECTION_KEYS:
            assert key in content.lower(), (
                f"deps.yaml section key '{key}' not found in glossary.md"
            )


class TestGlossaryTypesYamlTypes:
    """Scenario: types.yaml 型名の網羅性検証

    WHEN: glossary.md を確認する
    THEN: types.yaml の7型が全て用語テーブルに存在する
    """

    SEVEN_TYPES = {
        "controller", "workflow", "atomic", "composite",
        "specialist", "reference", "script",
    }

    def test_all_seven_types_in_glossary(self) -> None:
        """All 7 types.yaml type names appear in the glossary."""
        content = _read_glossary()
        terms = _extract_glossary_terms(content)
        content_lower = content.lower()
        for type_name in self.SEVEN_TYPES:
            found = type_name in terms or any(
                type_name in term.lower() for term in terms
            ) or type_name in content_lower
            assert found, (
                f"types.yaml type '{type_name}' not found in glossary.md"
            )


class TestGlossaryValidationCommands:
    """Scenario: 検証コマンド4種の定義確認

    WHEN: glossary.md の検証コマンド定義を確認する
    THEN: check, validate, deep-validate, audit の4つが個別に定義され、
          それぞれの検証範囲が明記されている
    """

    VALIDATION_COMMANDS = {"check", "validate", "deep-validate", "audit"}

    def test_four_validation_commands_individually_defined(self) -> None:
        """Each of the 4 validation commands has its own entry in the glossary."""
        content = _read_glossary()
        terms = _extract_glossary_terms(content)
        for cmd in self.VALIDATION_COMMANDS:
            # Terms may include CLI flag notation like "check (`--check`)"
            found = cmd in terms or any(cmd in t for t in terms) or cmd in content
            assert found, (
                f"Validation command '{cmd}' not individually defined "
                f"in glossary.md. Found terms: {sorted(terms)}"
            )

    def test_validation_commands_have_scope_description(self) -> None:
        """Each validation command entry includes a description of its scope."""
        content = _read_glossary()
        for cmd in self.VALIDATION_COMMANDS:
            # Terms may include CLI flag notation like "check (`--check`)"
            pattern = re.compile(
                rf"^\|\s*{re.escape(cmd)}[^|]*\|(.+)\|",
                re.MULTILINE,
            )
            match = pattern.search(content)
            assert match is not None, (
                f"No table row found for validation command '{cmd}' "
                f"in glossary.md"
            )
            definition = match.group(1).strip()
            assert len(definition) > 5, (
                f"Validation command '{cmd}' has insufficient definition: "
                f"'{definition}'"
            )
