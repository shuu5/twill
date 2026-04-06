#!/usr/bin/env python3
"""Tests for vision.md detail requirements.

Spec: deltaspec/changes/arch-spec-refine/specs/vision-detail.md

Verifies that architecture/vision.md contains detailed technical constraints
and non-goals with reasons.
"""

import re
from pathlib import Path

import pytest

ARCH_ROOT = Path(__file__).parent.parent.parent / "architecture"
VISION_PATH = ARCH_ROOT / "vision.md"


def _read_vision() -> str:
    """Read vision.md and return its content."""
    assert VISION_PATH.exists(), f"vision.md not found at {VISION_PATH}"
    return VISION_PATH.read_text(encoding="utf-8")


def _extract_section_content(content: str, heading: str) -> str | None:
    """Extract content under a heading until the next same-or-higher level heading."""
    for level in range(2, 5):
        hashes = "#" * level
        p = re.compile(
            rf"^{hashes}\s+{re.escape(heading)}\s*\n([\s\S]*?)(?=\n#{{{1},{level}}}\s|\Z)",
            re.MULTILINE,
        )
        match = p.search(content)
        if match:
            return match.group(1)
    return None


class TestTechnicalConstraints:
    """Scenario: 技術的制約の網羅性

    WHEN: vision.md の Constraints セクションを確認する
    THEN: Python バージョン、外部依存の制限、スキーマバージョンに関する記述が存在する
    """

    def test_constraints_section_exists(self) -> None:
        """vision.md has a Constraints section."""
        content = _read_vision()
        assert re.search(
            r"^#{2,4}\s+Constraints", content, re.MULTILINE,
        ), "vision.md does not have a Constraints section"

    def test_python_version_constraint(self) -> None:
        """Constraints section mentions Python version requirements."""
        content = _read_vision()
        section = _extract_section_content(content, "Constraints")
        assert section is not None, "Constraints section not found"
        has_python_version = bool(
            re.search(
                r"[Pp]ython\s+\d|[Pp]ython\s+バージョン|[Pp]ython\s+version",
                section,
            )
        )
        assert has_python_version, (
            "Constraints section does not specify Python version requirements. "
            f"Content: {section[:200]}"
        )

    def test_external_dependency_constraint(self) -> None:
        """Constraints section mentions external dependency restrictions."""
        content = _read_vision()
        section = _extract_section_content(content, "Constraints")
        assert section is not None, "Constraints section not found"
        has_dep_constraint = bool(
            re.search(
                r"外部依存|external\s+dependenc|ライブラリ|library|pip|標準ライブラリ|stdlib|最小限",
                section,
                re.IGNORECASE,
            )
        )
        assert has_dep_constraint, (
            "Constraints section does not mention external dependency "
            "restrictions"
        )

    def test_schema_version_constraint(self) -> None:
        """Constraints section mentions deps.yaml/types.yaml schema version constraints."""
        content = _read_vision()
        section = _extract_section_content(content, "Constraints")
        assert section is not None, "Constraints section not found"
        has_schema_constraint = bool(
            re.search(
                r"スキーマ|schema|deps\.yaml|types\.yaml|バージョン.*制約|version\s+constraint",
                section,
                re.IGNORECASE,
            )
        )
        assert has_schema_constraint, (
            "Constraints section does not mention schema version constraints "
            "for deps.yaml/types.yaml"
        )


class TestNonGoalsWithReasons:
    """Scenario: Non-Goals の理由付き確認

    WHEN: vision.md の Non-Goals セクションを確認する
    THEN: 各 Non-Goal に理由が記述されている
    """

    def test_non_goals_section_exists(self) -> None:
        """vision.md has a Non-Goals section."""
        content = _read_vision()
        assert re.search(
            r"^#{2,4}\s+Non-Goals", content, re.MULTILINE,
        ), "vision.md does not have a Non-Goals section"

    def test_non_goals_have_reasons(self) -> None:
        """Each Non-Goal item includes a reason for exclusion."""
        content = _read_vision()
        section = _extract_section_content(content, "Non-Goals")
        assert section is not None, "Non-Goals section not found"

        # Extract list items
        items = re.findall(r"^\s*[-*]\s+(.+)$", section, re.MULTILINE)
        assert len(items) >= 1, "Non-Goals section has no list items"

        errors = []
        for item in items:
            # A reason is indicated by a parenthetical, a clause after dash/colon,
            # or Japanese reason markers like "ため", "理由", "から"
            has_reason = bool(
                re.search(
                    r"\(.*\)|（.*）|[:：]|ため|理由|から|because|since|YAGNI|責務",
                    item,
                )
            )
            # Or the item is long enough to likely contain an explanation
            # (at least 20 chars suggests more than just a label)
            is_long_enough = len(item) > 30
            if not has_reason and not is_long_enough:
                errors.append(f"Non-Goal without apparent reason: '{item}'")

        assert not errors, (
            "Non-Goals items missing reasons:\n"
            + "\n".join(f"  - {e}" for e in errors)
        )
