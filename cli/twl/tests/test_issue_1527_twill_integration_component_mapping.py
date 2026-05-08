"""TDD tests for Issue #1527.

twill-integration.md Phase 2 Component Mapping テーブルに
Tier 1+ 6 tool (spawn/observation/budget 系) を追記する。

AC 1件につき 1テスト。
"""

from __future__ import annotations

import pytest
from pathlib import Path

REPO_ROOT = Path(__file__).parents[3]
TWILL_INTEGRATION_MD = (
    REPO_ROOT / "plugins" / "twl" / "architecture" / "domain" / "contexts" / "twill-integration.md"
)

if not TWILL_INTEGRATION_MD.exists():
    pytest.skip(f"{TWILL_INTEGRATION_MD} not found", allow_module_level=True)

_DOC_CONTENT = TWILL_INTEGRATION_MD.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# AC1: Phase 2 Component Mapping テーブルに twl_spawn_session が記載されていること
# ---------------------------------------------------------------------------


class TestAC1SpawnSession:
    """AC1: twill-integration.md Phase 2 Component Mapping に twl_spawn_session が記載されていること。"""

    def test_ac1_spawn_session_in_component_mapping(self):
        assert "twl_spawn_session" in _DOC_CONTENT, (
            "Phase 2 Component Mapping に twl_spawn_session が未記載 (AC1 未実装)"
        )


# ---------------------------------------------------------------------------
# AC2: Phase 2 Component Mapping テーブルに twl_spawn_controller が記載されていること
# ---------------------------------------------------------------------------


class TestAC2SpawnController:
    """AC2: twill-integration.md Phase 2 Component Mapping に twl_spawn_controller が記載されていること。"""

    def test_ac2_spawn_controller_in_component_mapping(self):
        assert "twl_spawn_controller" in _DOC_CONTENT, (
            "Phase 2 Component Mapping に twl_spawn_controller が未記載 (AC2 未実装)"
        )


# ---------------------------------------------------------------------------
# AC3: Phase 2 Component Mapping テーブルに twl_capture_pane が記載されていること
# ---------------------------------------------------------------------------


class TestAC3CapturePane:
    """AC3: twill-integration.md Phase 2 Component Mapping に twl_capture_pane が記載されていること。"""

    def test_ac3_capture_pane_in_component_mapping(self):
        assert "twl_capture_pane" in _DOC_CONTENT, (
            "Phase 2 Component Mapping に twl_capture_pane が未記載 (AC3 未実装)"
        )


# ---------------------------------------------------------------------------
# AC4: Phase 2 Component Mapping テーブルに twl_list_windows が記載されていること
# ---------------------------------------------------------------------------


class TestAC4ListWindows:
    """AC4: twill-integration.md Phase 2 Component Mapping に twl_list_windows が記載されていること。"""

    def test_ac4_list_windows_in_component_mapping(self):
        assert "twl_list_windows" in _DOC_CONTENT, (
            "Phase 2 Component Mapping に twl_list_windows が未記載 (AC4 未実装)"
        )


# ---------------------------------------------------------------------------
# AC5: Phase 2 Component Mapping テーブルに twl_get_session_state の拡張が記載されていること
# ---------------------------------------------------------------------------


class TestAC5GetSessionState:
    """AC5: twill-integration.md Phase 2 Component Mapping に twl_get_session_state（拡張）が記載されていること。"""

    def test_ac5_get_session_state_in_component_mapping(self):
        assert "twl_get_session_state" in _DOC_CONTENT, (
            "Phase 2 Component Mapping に twl_get_session_state が未記載 (AC5 未実装)"
        )


# ---------------------------------------------------------------------------
# AC6: Phase 2 Component Mapping テーブルに twl_get_budget が記載されていること
# ---------------------------------------------------------------------------


class TestAC6GetBudget:
    """AC6: twill-integration.md Phase 2 Component Mapping に twl_get_budget が記載されていること。"""

    def test_ac6_get_budget_in_component_mapping(self):
        assert "twl_get_budget" in _DOC_CONTENT, (
            "Phase 2 Component Mapping に twl_get_budget が未記載 (AC6 未実装)"
        )
