#!/usr/bin/env python3
"""Tests for ADR creation requirements.

Spec: deltaspec/changes/arch-spec-refine/specs/adr-creation.md

Verifies that ADR-0001 and ADR-0002 exist with the required 4-section
structure (Status, Context, Decision, Consequences).
"""

import re
from pathlib import Path

import pytest

ARCH_ROOT = Path(__file__).parent.parent.parent / "architecture"
DECISIONS_DIR = ARCH_ROOT / "decisions"


def _extract_headings(content: str) -> list[str]:
    """Extract all heading texts from Markdown content."""
    return [
        m.group(1).strip()
        for m in re.finditer(r"^#{1,6}\s+(.+)$", content, re.MULTILINE)
    ]


def _assert_four_section_structure(filepath: Path) -> None:
    """Assert that an ADR file has Status, Context, Decision, Consequences sections."""
    content = filepath.read_text(encoding="utf-8")
    headings = _extract_headings(content)
    headings_lower = [h.lower() for h in headings]

    required = ["status", "context", "decision", "consequences"]
    missing = [
        section for section in required
        if not any(section in h for h in headings_lower)
    ]
    assert not missing, (
        f"{filepath.name}: missing ADR sections: {missing}. "
        f"Found headings: {headings}"
    )


class TestAdr0001PythonSingleFile:
    """Scenario: ADR-0001 の存在と構造

    WHEN: architecture/decisions/ADR-0001-python-single-file.md を確認する
    THEN: Status, Context, Decision, Consequences の4セクションが存在し、
          単一ファイル選択の理由が記述されている
    """

    ADR_PATH = DECISIONS_DIR / "ADR-0001-python-single-file.md"

    def test_adr_0001_exists(self) -> None:
        """ADR-0001-python-single-file.md exists."""
        assert self.ADR_PATH.exists(), (
            f"ADR-0001 not found at {self.ADR_PATH}"
        )

    def test_adr_0001_has_four_sections(self) -> None:
        """ADR-0001 contains Status, Context, Decision, Consequences."""
        if not self.ADR_PATH.exists():
            pytest.skip("ADR-0001 does not exist yet")
        _assert_four_section_structure(self.ADR_PATH)

    def test_adr_0001_explains_single_file_rationale(self) -> None:
        """ADR-0001 Decision section explains why a single file was chosen."""
        if not self.ADR_PATH.exists():
            pytest.skip("ADR-0001 does not exist yet")
        content = self.ADR_PATH.read_text(encoding="utf-8")
        # The decision should reference single file / 単一ファイル
        has_rationale = bool(
            re.search(
                r"single\s+file|単一ファイル|twl-engine\.py",
                content,
                re.IGNORECASE,
            )
        )
        assert has_rationale, (
            "ADR-0001 does not contain rationale for single file architecture "
            "(expected mentions of 'single file', '単一ファイル', "
            "or 'twl-engine.py')"
        )


class TestAdr0002TypesYamlExternalization:
    """Scenario: ADR-0002 の存在と構造

    WHEN: architecture/decisions/ADR-0002-types-yaml-externalization.md を確認する
    THEN: Status, Context, Decision, Consequences の4セクションが存在し、
          外部化の理由が記述されている
    """

    ADR_PATH = DECISIONS_DIR / "ADR-0002-types-yaml-externalization.md"

    def test_adr_0002_exists(self) -> None:
        """ADR-0002-types-yaml-externalization.md exists."""
        assert self.ADR_PATH.exists(), (
            f"ADR-0002 not found at {self.ADR_PATH}"
        )

    def test_adr_0002_has_four_sections(self) -> None:
        """ADR-0002 contains Status, Context, Decision, Consequences."""
        if not self.ADR_PATH.exists():
            pytest.skip("ADR-0002 does not exist yet")
        _assert_four_section_structure(self.ADR_PATH)

    def test_adr_0002_explains_externalization_rationale(self) -> None:
        """ADR-0002 Decision section explains why types.yaml was externalized."""
        if not self.ADR_PATH.exists():
            pytest.skip("ADR-0002 does not exist yet")
        content = self.ADR_PATH.read_text(encoding="utf-8")
        # Should reference types.yaml externalization / SSOT
        has_rationale = bool(
            re.search(
                r"types\.yaml|外部化|externali[zs]|SSOT|single\s+source",
                content,
                re.IGNORECASE,
            )
        )
        assert has_rationale, (
            "ADR-0002 does not contain rationale for types.yaml externalization "
            "(expected mentions of 'types.yaml', '外部化', "
            "'externalization', or 'SSOT')"
        )
