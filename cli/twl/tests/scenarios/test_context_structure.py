#!/usr/bin/env python3
"""Tests for Context file structure requirements.

Spec: deltaspec/changes/arch-spec-refine/specs/context-structure.md

Verifies that architecture/domain/contexts/*.md files contain the required
3-section structure (Key Entities, Dependencies, Constraints), detailed
entity descriptions, and CLI command mappings.
"""

import re
from pathlib import Path

import pytest

ARCH_ROOT = Path(__file__).parent.parent.parent / "architecture"
CONTEXTS_DIR = ARCH_ROOT / "domain" / "contexts"


def _get_context_files() -> list[Path]:
    """Return all .md files in the contexts directory."""
    assert CONTEXTS_DIR.exists(), (
        f"Contexts directory not found at {CONTEXTS_DIR}"
    )
    files = sorted(CONTEXTS_DIR.glob("*.md"))
    assert len(files) > 0, "No .md files found in contexts directory"
    return files


def _extract_headings(content: str) -> list[str]:
    """Extract all headings from Markdown content (any level)."""
    return [
        m.group(1).strip()
        for m in re.finditer(r"^#{1,6}\s+(.+)$", content, re.MULTILINE)
    ]


def _extract_section_content(content: str, heading: str) -> str | None:
    """Extract the content under a specific heading until the next same-level heading."""
    pattern = re.compile(
        rf"(#{{{1,6}}})\s+{re.escape(heading)}\s*\n([\s\S]*?)(?=\n\1\s|\Z)"
    )
    # Try with flexible heading level
    for level in range(2, 5):
        hashes = "#" * level
        p = re.compile(
            rf"^{hashes}\s+{re.escape(heading)}\s*\n([\s\S]*?)(?=\n{hashes}\s|\Z)",
            re.MULTILINE,
        )
        match = p.search(content)
        if match:
            return match.group(1)
    return None


class TestContextThreeSectionStructure:
    """Scenario: Context ファイル構造検証

    WHEN: architecture/domain/contexts/ 配下の任意の .md ファイルを確認する
    THEN: Key Entities, Dependencies, Constraints の3セクションが存在する
    """

    REQUIRED_SECTIONS = {"Key Entities", "Dependencies", "Constraints"}

    @pytest.fixture
    def context_files(self) -> list[Path]:
        return _get_context_files()

    def test_all_context_files_have_three_sections(
        self, context_files: list[Path],
    ) -> None:
        """Every context file contains Key Entities, Dependencies, Constraints."""
        errors = []
        for filepath in context_files:
            content = filepath.read_text(encoding="utf-8")
            headings = {h.strip() for h in _extract_headings(content)}
            for section in self.REQUIRED_SECTIONS:
                if not any(section in h for h in headings):
                    errors.append(
                        f"{filepath.name}: missing '{section}' section"
                    )
        assert not errors, (
            "Context files missing required sections:\n"
            + "\n".join(f"  - {e}" for e in errors)
        )

    def test_no_standalone_responsibility_section(
        self, context_files: list[Path],
    ) -> None:
        """Responsibility section should be integrated into Key Entities.

        The old 'Responsibility' standalone section should not exist as a
        separate heading (it may appear within Key Entities content).
        """
        warnings = []
        for filepath in context_files:
            content = filepath.read_text(encoding="utf-8")
            headings = _extract_headings(content)
            # Check if Responsibility exists as a standalone top-level heading
            for h in headings:
                if h.strip() == "Responsibility":
                    warnings.append(
                        f"{filepath.name}: has standalone 'Responsibility' "
                        f"section (should be merged into Key Entities)"
                    )
        assert not warnings, (
            "Context files with deprecated Responsibility section:\n"
            + "\n".join(f"  - {w}" for w in warnings)
        )


class TestKeyEntitiesDetail:
    """Scenario: Key Entities の詳細度検証

    WHEN: 任意の Context ファイルの Key Entities セクションを確認する
    THEN: 各エンティティに名前と責務の説明が記載されている
    """

    @pytest.fixture
    def context_files(self) -> list[Path]:
        return _get_context_files()

    def test_key_entities_have_structured_list(
        self, context_files: list[Path],
    ) -> None:
        """Key Entities section has structured entity listings, not just a summary."""
        errors = []
        for filepath in context_files:
            content = filepath.read_text(encoding="utf-8")
            section = _extract_section_content(content, "Key Entities")
            if section is None:
                errors.append(f"{filepath.name}: Key Entities section not found")
                continue
            # Check for list items (- or *) or table rows
            has_list = bool(re.search(r"^\s*[-*]\s+\S", section, re.MULTILINE))
            has_table = bool(re.search(r"^\|", section, re.MULTILINE))
            if not has_list and not has_table:
                errors.append(
                    f"{filepath.name}: Key Entities has no structured list "
                    f"or table"
                )
        assert not errors, (
            "Key Entities sections lacking structure:\n"
            + "\n".join(f"  - {e}" for e in errors)
        )

    def test_key_entities_have_name_and_description(
        self, context_files: list[Path],
    ) -> None:
        """Each entity in Key Entities has a name and a description of its role."""
        errors = []
        for filepath in context_files:
            content = filepath.read_text(encoding="utf-8")
            section = _extract_section_content(content, "Key Entities")
            if section is None:
                continue
            # Find list items and check they have descriptive text
            items = re.findall(
                r"^\s*[-*]\s+(.+)$", section, re.MULTILINE,
            )
            if not items:
                continue
            for item in items:
                # Each item should have both a name-like token and description
                # Minimum: "EntityName - description" or "EntityName: description"
                # or at least more than one word
                words = item.split()
                if len(words) < 2:
                    errors.append(
                        f"{filepath.name}: entity item too brief: '{item}'"
                    )
        assert not errors, (
            "Key entity items lacking description:\n"
            + "\n".join(f"  - {e}" for e in errors)
        )


class TestCliCommandMapping:
    """Scenario: CLI コマンドマッピング検証

    WHEN: 任意の Context ファイルを確認する
    THEN: その Context に対応する twl CLI コマンドが列挙されている
    """

    @pytest.fixture
    def context_files(self) -> list[Path]:
        return _get_context_files()

    def test_context_files_list_cli_commands(
        self, context_files: list[Path],
    ) -> None:
        """Each context file contains a CLI command listing."""
        errors = []
        for filepath in context_files:
            content = filepath.read_text(encoding="utf-8")
            # Check for CLI command references:
            # - A dedicated section (e.g., "## CLI Commands" or "## CLI コマンド")
            # - Or references to `twl <command>` in the content
            has_cli_section = bool(
                re.search(
                    r"#{2,4}\s+.*(?:CLI|コマンド|Command)",
                    content,
                    re.IGNORECASE,
                )
            )
            has_twl_commands = bool(
                re.search(r"twl\s+\w+", content)
            )
            has_command_backtick = bool(
                re.search(r"`(?:check|validate|deep-validate|audit|chain|promote|rename|sync-docs|visualize|init)`", content)
            )
            if not (has_cli_section or has_twl_commands or has_command_backtick):
                errors.append(
                    f"{filepath.name}: no CLI command mapping found"
                )
        assert not errors, (
            "Context files missing CLI command mappings:\n"
            + "\n".join(f"  - {e}" for e in errors)
        )
