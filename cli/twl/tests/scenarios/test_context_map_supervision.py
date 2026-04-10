#!/usr/bin/env python3
"""Tests for Context Map Supervision renaming requirements.

Spec: deltaspec/changes/issue-352/specs/context-map-supervision/spec.md

Verifies that plugins/twl/architecture/domain/context-map.md reflects
the Observer -> Supervision rename across all four locations:
  1. Context 分類テーブル
  2. 依存関係図 (Mermaid graph TD)
  3. DCI フロー図 (Mermaid graph LR) のサブグラフ名
  4. 関係の詳細テーブル
"""

import re
from pathlib import Path

import pytest

# plugins/twl/ lives at the repository root, two levels above cli/twl/
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent.parent
CONTEXT_MAP_PATH = (
    _REPO_ROOT / "plugins" / "twl" / "architecture" / "domain" / "context-map.md"
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _read_context_map() -> str:
    """Read context-map.md and return its full content."""
    assert CONTEXT_MAP_PATH.exists(), (
        f"context-map.md not found at {CONTEXT_MAP_PATH}\n"
        f"(resolved from __file__={__file__})"
    )
    return CONTEXT_MAP_PATH.read_text(encoding="utf-8")


def _extract_table_rows(content: str, section_heading: str) -> list[str]:
    """Return the raw Markdown table rows that follow a given section heading.

    Searches for the heading and collects non-empty ``|``-prefixed lines
    until an empty line or next heading is encountered.
    """
    # Locate the heading line
    # Note: use a raw string with literal braces for the quantifier to avoid
    # f-string interpretation of {1,4}
    heading_pattern = re.compile(
        r"^#{1,4}\s+" + re.escape(section_heading) + r"\s*$", re.MULTILINE
    )
    m = heading_pattern.search(content)
    if m is None:
        return []

    after = content[m.end():]
    rows: list[str] = []
    for line in after.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):  # Next heading
            break
        if stripped.startswith("|"):
            rows.append(stripped)
    return rows


def _extract_mermaid_blocks(content: str) -> list[str]:
    """Return all raw Mermaid code blocks (without the fence lines)."""
    return re.findall(r"```mermaid\s*\n(.*?)```", content, re.DOTALL)


# ---------------------------------------------------------------------------
# Scenario: Context 分類の更新確認
# ---------------------------------------------------------------------------

class TestContextClassificationTable:
    """Requirement: Context 分類テーブルの Supervision 更新

    WHEN context-map.md の Context 分類テーブルを参照する
    THEN ``Cross-cutting | Supervision`` 行が存在し、``Observer`` 行が存在しない
    """

    def test_supervision_row_exists_in_classification_table(self) -> None:
        """Context 分類テーブルに Cross-cutting | Supervision 行が存在する。"""
        content = _read_context_map()
        rows = _extract_table_rows(content, "Context 分類")
        assert rows, "Context 分類 section not found or contains no table rows"

        supervision_rows = [r for r in rows if "Supervision" in r]
        assert len(supervision_rows) >= 1, (
            "No row containing 'Supervision' found in Context 分類 table.\n"
            f"Actual rows:\n" + "\n".join(rows)
        )
        # The row must also carry the Cross-cutting category
        for row in supervision_rows:
            assert "Cross-cutting" in row, (
                f"'Supervision' row does not contain 'Cross-cutting': {row!r}"
            )

    def test_observer_row_absent_from_classification_table(self) -> None:
        """Context 分類テーブルに Observer 行が存在しない。

        Note: the row ``| Cross-cutting | Observer | … |`` should be gone;
        incidental occurrences of the word "Observer" in other columns or in
        prose are acceptable.
        """
        content = _read_context_map()
        rows = _extract_table_rows(content, "Context 分類")
        assert rows, "Context 分類 section not found or contains no table rows"

        observer_data_rows = [
            r for r in rows
            # Skip header / separator lines that only contain dashes
            if not re.match(r"^\|[-|\s]+\|$", r)
            and "Cross-cutting" in r
            and "Observer" in r
            # Allow "Live Observation" which is a different context
            and "Live Observation" not in r
            # Exclude the Supervision row itself (contains both for transitional docs)
            and "Supervision" not in r
        ]
        assert len(observer_data_rows) == 0, (
            "Found 'Observer' Cross-cutting row(s) that should have been removed:\n"
            + "\n".join(observer_data_rows)
        )

    # Edge case: the table must have exactly one Cross-cutting entry of this kind
    def test_exactly_one_cross_cutting_supervision_row(self) -> None:
        """Cross-cutting | Supervision が重複して存在しない。"""
        content = _read_context_map()
        rows = _extract_table_rows(content, "Context 分類")
        cross_supervision = [
            r for r in rows
            if "Cross-cutting" in r and "Supervision" in r
        ]
        assert len(cross_supervision) == 1, (
            f"Expected exactly 1 'Cross-cutting | Supervision' row, "
            f"got {len(cross_supervision)}:\n" + "\n".join(cross_supervision)
        )


# ---------------------------------------------------------------------------
# Scenario: 依存関係図のノード確認
# ---------------------------------------------------------------------------

class TestDependencyGraphNodes:
    """Requirement: 依存関係図の Supervision ノード更新

    WHEN Mermaid 依存関係図を確認する
    THEN Cross-cutting サブグラフに ``Supervision`` ノードが存在し、
         ``Observer`` ノードが存在しない
    """

    def _get_dependency_graph(self) -> str:
        """Return the first graph TD block in context-map.md."""
        content = _read_context_map()
        blocks = _extract_mermaid_blocks(content)
        td_blocks = [b for b in blocks if re.search(r"^\s*graph\s+TD", b, re.MULTILINE)]
        assert td_blocks, "No 'graph TD' Mermaid block found in context-map.md"
        return td_blocks[0]

    def test_supervision_node_in_cross_cutting_subgraph(self) -> None:
        """Cross-cutting サブグラフに Supervision ノードが定義されている。"""
        block = self._get_dependency_graph()

        # Locate the Cross-cutting subgraph boundaries
        cross_match = re.search(
            r'subgraph\s+"Cross-cutting"([\s\S]*?)end', block
        )
        assert cross_match is not None, (
            "Could not locate 'Cross-cutting' subgraph in dependency graph"
        )
        subgraph_body = cross_match.group(1)

        assert "Supervision" in subgraph_body, (
            "No 'Supervision' node found in Cross-cutting subgraph.\n"
            f"Subgraph body:\n{subgraph_body}"
        )

    def test_observer_node_absent_from_cross_cutting_subgraph(self) -> None:
        """Cross-cutting サブグラフに Observer ノードが存在しない。

        Edge case: The subgraph body must not declare a node whose label
        contains 'Observer' (e.g. ``COBS["Observer\\n(Meta-cognitive)"]``).
        """
        block = self._get_dependency_graph()
        cross_match = re.search(
            r'subgraph\s+"Cross-cutting"([\s\S]*?)end', block
        )
        assert cross_match is not None, (
            "Could not locate 'Cross-cutting' subgraph in dependency graph"
        )
        subgraph_body = cross_match.group(1)

        # A node declaration looks like: COBS["Observer..."]
        observer_node = re.search(r'\["Observer', subgraph_body)
        assert observer_node is None, (
            "Found an 'Observer' node declaration inside Cross-cutting subgraph. "
            "It should have been renamed to 'Supervision'.\n"
            f"Context: {subgraph_body}"
        )

    def test_supervision_node_has_meta_cognitive_label(self) -> None:
        """Supervision ノードのラベルにメタ認知の説明が含まれる（内容保持の確認）。"""
        block = self._get_dependency_graph()
        # The renamed node should still carry its descriptive label
        assert re.search(r'Supervision', block), (
            "Supervision node not found anywhere in the dependency graph"
        )

    def test_no_orphan_observer_node_references(self) -> None:
        """依存関係図全体で COBS["Observer..."] 宣言が残っていない。

        Edge case: ノード定義が残っているが辺だけ変更されていない状態を検出する。
        """
        block = self._get_dependency_graph()
        # Detect node-definition pattern with Observer label
        observer_definitions = re.findall(r'\w+\["Observer[^"]*"\]', block)
        assert not observer_definitions, (
            "Observer node definition(s) still present in dependency graph: "
            + str(observer_definitions)
        )


# ---------------------------------------------------------------------------
# Scenario: DCI フロー図のサブグラフ確認
# ---------------------------------------------------------------------------

class TestDciFlowSubgraph:
    """Requirement: DCI フロー図の su-observer サブグラフ更新

    WHEN Mermaid DCI フロー図（graph LR）を確認する
    THEN ``subgraph "su-observer"`` が存在し、
         ``subgraph "co-observer"`` が存在しない
    """

    def _get_dci_graph(self) -> str:
        """Return the first graph LR block in context-map.md."""
        content = _read_context_map()
        blocks = _extract_mermaid_blocks(content)
        lr_blocks = [b for b in blocks if re.search(r"^\s*graph\s+LR", b, re.MULTILINE)]
        assert lr_blocks, "No 'graph LR' Mermaid block found in context-map.md"
        return lr_blocks[0]

    def test_su_observer_subgraph_exists(self) -> None:
        """DCI フロー図に ``subgraph "su-observer"`` が存在する。"""
        block = self._get_dci_graph()
        assert re.search(r'subgraph\s+"su-observer"', block), (
            'subgraph "su-observer" not found in DCI flow graph (graph LR).\n'
            f"Graph content:\n{block}"
        )

    def test_co_observer_subgraph_absent(self) -> None:
        """DCI フロー図に ``subgraph "co-observer"`` が存在しない。"""
        block = self._get_dci_graph()
        assert not re.search(r'subgraph\s+"co-observer"', block), (
            'Old subgraph "co-observer" still present in DCI flow graph. '
            'It should have been renamed to "su-observer".'
        )

    def test_su_observer_subgraph_has_nodes(self) -> None:
        """su-observer サブグラフが空でなくノードを含む。

        Edge case: リネームだけ行ってノード定義が消えた状態を検出する。
        """
        block = self._get_dci_graph()
        su_match = re.search(
            r'subgraph\s+"su-observer"([\s\S]*?)end', block
        )
        assert su_match is not None, (
            'subgraph "su-observer" body could not be located'
        )
        body = su_match.group(1).strip()
        assert body, (
            'subgraph "su-observer" is empty — node definitions may have been lost'
        )

    def test_no_co_observer_string_in_subgraph_declarations(self) -> None:
        """``co-observer`` という文字列がサブグラフ宣言として残っていない。

        Edge case: コメントや prose への混入も含めて確認する（サブグラフ宣言限定）。
        """
        block = self._get_dci_graph()
        # Only flag actual subgraph declarations, not comments or labels
        co_observer_declarations = re.findall(
            r'subgraph\s+"co-observer"', block
        )
        assert not co_observer_declarations, (
            '"co-observer" subgraph declaration(s) still present: '
            + str(co_observer_declarations)
        )


# ---------------------------------------------------------------------------
# Scenario: 関係テーブルの更新確認
# ---------------------------------------------------------------------------

class TestRelationshipTable:
    """Requirement: 関係の詳細テーブルの Supervision 更新

    WHEN 関係の詳細テーブルを参照する
    THEN Upstream 列に ``Supervision`` が存在し、``Observer`` が存在しない
    """

    def _get_relationship_rows(self) -> list[str]:
        content = _read_context_map()
        rows = _extract_table_rows(content, "関係の詳細")
        assert rows, "関係の詳細 section not found or contains no table rows"
        # Exclude separator rows and the column-header row.
        # The header row has "Upstream" as its first cell with no preceding text.
        return [
            r for r in rows
            if not re.match(r"^\|[-|\s]+\|$", r)
            and not re.match(r"^\|\s*Upstream\s*\|", r)  # skip column-header row only
        ]

    def test_supervision_upstream_rows_exist(self) -> None:
        """Upstream 列に Supervision を持つ行が存在する。"""
        rows = self._get_relationship_rows()
        # In a Markdown table ``| Upstream | Downstream | … |``
        # the first cell is Upstream; check that cell specifically
        supervision_rows = [
            r for r in rows
            if re.match(r"^\|\s*Supervision\s*\|", r)
        ]
        assert len(supervision_rows) >= 1, (
            "No rows with 'Supervision' in the Upstream column found in "
            "関係の詳細 table.\n"
            f"Actual data rows:\n" + "\n".join(rows)
        )

    def test_observer_upstream_rows_absent(self) -> None:
        """Upstream 列に Observer を持つ行が存在しない。

        Edge case: ``| Observer |`` として始まる行を検出する。
        ``Live Observation`` や ``Live Observation | …`` は別物なので除外。
        """
        rows = self._get_relationship_rows()
        observer_upstream_rows = [
            r for r in rows
            # First cell is strictly "Observer", not "Live Observation"
            if re.match(r"^\|\s*Observer\s*\|", r)
        ]
        assert len(observer_upstream_rows) == 0, (
            "Found row(s) with 'Observer' in the Upstream column that should "
            "have been renamed to 'Supervision':\n"
            + "\n".join(observer_upstream_rows)
        )

    def test_supervision_rows_preserve_downstream_relationships(self) -> None:
        """Supervision 行が旧 Observer 行と同じ Downstream を持つ。

        Edge case: リネームだけ行い関係先が欠落した状態を検出する。
        旧 Observer は Autopilot, Issue Mgmt, Live Observation の 3 行を持っていた。
        """
        rows = self._get_relationship_rows()
        supervision_rows = [
            r for r in rows
            if re.match(r"^\|\s*Supervision\s*\|", r)
        ]
        # Extract Downstream values from those rows
        downstreams = set()
        for row in supervision_rows:
            cells = [c.strip() for c in row.split("|") if c.strip()]
            if len(cells) >= 2:
                downstreams.add(cells[1])

        expected_downstreams = {"Autopilot", "Issue Mgmt", "Live Observation"}
        missing = expected_downstreams - downstreams
        assert not missing, (
            "Supervision rows are missing Downstream relationship(s) that "
            f"Observer previously had: {missing}\n"
            f"Found Supervision Downstream values: {downstreams}"
        )

    def test_no_partial_rename_observer_rows(self) -> None:
        """関係テーブルに Observer で始まり Supervision が含まれない行がない。

        Edge case: 一部だけリネームされて不整合が残るパターンを検出する。
        """
        rows = self._get_relationship_rows()
        # Rows that start with Observer in Upstream but don't mention Supervision at all
        partial_rows = [
            r for r in rows
            if re.match(r"^\|\s*Observer\s*\|", r)
        ]
        assert not partial_rows, (
            "Partial or unrenamed 'Observer' Upstream rows detected:\n"
            + "\n".join(partial_rows)
        )
