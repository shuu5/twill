"""Tests for Issue #1313: ADR-033 Deprecated/Superseded transition.

RED phase tests — fail until ADR-033 is updated from Accepted to Deprecated.
Issue #1313.

Current state (all tests should FAIL):
- ADR-033 Status is "Accepted" (not "Deprecated")
- No deprecation banner exists
- No Changelog section exists
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

ADR_PATH = Path(__file__).parents[3] / "plugins/twl/architecture/decisions/ADR-033-cross-repo-protocol-pinning.md"


@pytest.fixture(scope="module")
def adr_text() -> str:
    if not ADR_PATH.exists():
        pytest.fail(f"AC1: ADR-033 ファイルが存在しない: {ADR_PATH}")
    return ADR_PATH.read_text()


def test_ac1_status_is_deprecated(adr_text: str):
    # AC-1: Status を Deprecated に更新（protocols/ ディレクトリが未実装のため廃止）
    m = re.search(r"## Status\s*\n+(.+)", adr_text)
    current_value = m.group(1).strip() if m else "不明"
    assert "Deprecated" in adr_text, f"ADR-033 の Status が Deprecated になっていない。現在の値: '{current_value}'"
    assert "Accepted" not in adr_text.split("## Rationale")[0], "Status セクションに 'Accepted' が残っている"


def test_ac1_status_section_value(adr_text: str):
    # AC-1: ## Status セクションの値が Deprecated であること
    # RED: 現在は "Accepted" のため fail する
    status_match = re.search(r"## Status\s*\n+(.+)", adr_text)
    assert status_match is not None, "## Status セクションが見当たらない"
    status_value = status_match.group(1).strip()
    assert "Deprecated" in status_value, (
        f"Status セクションの値が Deprecated でない: '{status_value}'"
    )


def test_ac1_deprecation_banner_exists(adr_text: str):
    # AC-1: ファイル冒頭に廃止バナーを追加（ADR-013 パターン: ブロッククォート形式）
    # RED: 現在は廃止バナーなしのため fail する
    lines = adr_text.splitlines()
    # ヘッダー行（# ADR-033: ...）の直後にバナーが来ることを確認
    # ADR-013 パターン: > **[SUPERSEDED]** または > **[DEPRECATED]**
    has_banner = False
    for line in lines[:10]:  # 冒頭 10 行以内に存在すること
        if line.startswith(">") and ("DEPRECATED" in line or "SUPERSEDED" in line):
            has_banner = True
            break
    assert has_banner, (
        "ファイル冒頭 10 行以内に廃止バナー (> **[DEPRECATED]** ...) が存在しない"
    )


def test_ac1_deprecation_banner_content(adr_text: str):
    # AC-1: 廃止バナーに廃止理由（protocols/ 未実装）の言及があること
    # RED: 現在は廃止バナーなしのため fail する
    banner_match = re.search(r"^>.*\[DEPRECATED\].*$", adr_text, re.MULTILINE)
    assert banner_match is not None, (
        "廃止バナー (> **[DEPRECATED]** ...) が見当たらない"
    )
    banner_text = banner_match.group(0)
    # バナーに廃止理由の手がかりが含まれること
    assert any(keyword in banner_text for keyword in ["protocols", "protocol", "未実装", "廃止"]), (
        f"廃止バナーに廃止理由（protocols/ 未実装など）の言及がない: '{banner_text}'"
    )


def test_ac2_no_accepted_in_status_section(adr_text: str):
    # AC-2: 修正後 twl validate / specialist で WARNING 解消確認
    # — Status セクションに "Accepted" が残っていないことを機械検証で代替
    # RED: 現在は Status: Accepted のため fail する
    # Status セクションのみを抽出して確認
    status_section = re.search(r"(## Status\s*\n+.*?)(?=\n## |\Z)", adr_text, re.DOTALL)
    assert status_section is not None, "## Status セクションが見当たらない"
    section_text = status_section.group(1)
    assert "Accepted" not in section_text, (
        f"Status セクションに 'Accepted' が残っている。セクション内容:\n{section_text}"
    )


def test_ac3_protocols_dir_absence_acknowledged(adr_text: str):
    # AC-3: 関連 ADR/SKILL/refs に整合する更新 — Changelog または廃止バナーに protocols/ 未実装の理由が記録されていること
    # Changelog セクション内か [DEPRECATED] バナー内に protocols/ への言及が必須
    changelog_match = re.search(r"## Changelog\s*\n(.*?)(?=\n## |\Z)", adr_text, re.DOTALL)
    banner_match = re.search(r"^>.*\[DEPRECATED\].*$", adr_text, re.MULTILINE)
    changelog_text = changelog_match.group(1) if changelog_match else ""
    banner_text = banner_match.group(0) if banner_match else ""
    protocols_mentioned = any(
        keyword in (changelog_text + banner_text)
        for keyword in ["protocols/", "protocols/ディレクトリ", "未実装"]
    )
    assert changelog_match is not None, "## Changelog セクションが存在しない"
    assert protocols_mentioned, (
        f"Changelog またはバナーに protocols/ 未実装への言及がない。"
        f"Changelog={changelog_text[:100]!r}, Banner={banner_text!r}"
    )


def test_ac4_changelog_section_exists(adr_text: str):
    # AC-4: regression — Changelog セクションが存在すること
    # RED: 現在は Changelog セクションなしのため fail する
    assert "## Changelog" in adr_text, (
        "Changelog セクション (## Changelog) が存在しない"
    )


def test_ac4_changelog_has_deprecation_reason(adr_text: str):
    # AC-4: Changelog セクションに廃止理由（protocols/ 未実装）が記載されていること
    # RED: 現在は Changelog セクションなしのため fail する
    changelog_match = re.search(r"## Changelog\s*\n(.*?)(?=\n## |\Z)", adr_text, re.DOTALL)
    assert changelog_match is not None, "## Changelog セクションが見当たらない"
    changelog_text = changelog_match.group(1)
    assert any(keyword in changelog_text for keyword in ["Deprecated", "deprecated", "廃止", "protocols/"]), (
        f"Changelog セクションに廃止理由が記載されていない。内容:\n{changelog_text[:200]}"
    )


def test_ac4_file_remains_in_decisions_dir():
    # AC-4: ファイルは decisions/ に残存していること（archive/ に移動していない）
    # GREEN: 現在もファイルは decisions/ に存在するため、このテストは実装前後で PASS する
    # （削除・移動のリグレッションを防ぐ）
    assert ADR_PATH.exists(), (
        f"ADR-033 ファイルが decisions/ に存在しない: {ADR_PATH}"
    )
    assert "decisions" in str(ADR_PATH), (
        f"ADR-033 ファイルが decisions/ 配下にない: {ADR_PATH}"
    )
    archive_path = ADR_PATH.parent.parent / "archive" / ADR_PATH.name
    assert not archive_path.exists(), (
        f"ADR-033 が archive/ に移動されている（decisions/ に残すべき）: {archive_path}"
    )
