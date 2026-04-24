"""Tests for ADR-025: co-autopilot phase-review guarantee.

RED phase tests — fail until ADR-025 is created.
Issue #940.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

ADR_PATH = Path(__file__).parents[3] / "plugins/twl/architecture/decisions/ADR-025-co-autopilot-phase-review-guarantee.md"


@pytest.fixture(scope="module")
def adr_text() -> str:
    if not ADR_PATH.exists():
        pytest.fail(f"AC1: ADR-025 ファイルが存在しない: {ADR_PATH}")
    return ADR_PATH.read_text()


def test_ac1_adr025_file_exists():
    # AC: plugins/twl/architecture/decisions/ADR-025-co-autopilot-phase-review-guarantee.md を新規作成する
    assert ADR_PATH.exists(), f"ADR-025 ファイルが存在しない: {ADR_PATH}"


def test_ac2_status_proposed_and_five_layers(adr_text: str):
    # AC: Status=Proposed かつ Decision セクションに 5 レイヤーの多層防御を明記する
    assert "**Status**: Proposed" in adr_text or "Status**: Proposed" in adr_text, \
        "Status が Proposed でない"
    for i in range(1, 6):
        assert str(i) in adr_text, f"Decision セクションにレイヤー {i} が見当たらない"


def test_ac3_context_mentions_adr001_and_919(adr_text: str):
    # AC: Context に ADR-001 との関係と #919 事故の要約を記載する
    assert "ADR-001" in adr_text, "Context に ADR-001 への言及がない"
    assert "#919" in adr_text, "Context に #919 への言及がない"


def test_ac4_consequences_chain_and_emergency(adr_text: str):
    # AC: Consequences にテスト時も chain 正規 flow を強制する旨、Emergency bypass は ADR-001 の例外条項に従う旨を記載する
    assert "chain" in adr_text.lower(), "Consequences に chain 正規 flow の記述がない"
    assert "Emergency" in adr_text or "emergency" in adr_text.lower(), \
        "Consequences に Emergency bypass の記述がない"
    assert "ADR-001" in adr_text, "Consequences に ADR-001 の例外条項への言及がない"


def test_ac5_references_include_required(adr_text: str):
    # AC: References に #940, #919, #946, #948, #924, ADR-001 を含める
    required = ["#940", "#919", "#946", "#948", "#924", "ADR-001"]
    missing = [ref for ref in required if ref not in adr_text]
    assert not missing, f"References に以下が不足: {missing}"
