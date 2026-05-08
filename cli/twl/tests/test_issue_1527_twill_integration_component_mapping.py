"""TDD RED phase tests for Issue #1527.

twill-integration.md Phase 2 Component Mapping テーブルに
Tier 1+ 6 tool (spawn/observation/budget 系) を追記する。

AC 1件につき 1テスト。全テストは実装前に FAIL（RED）する。
"""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).parents[3]
TWILL_INTEGRATION_MD = (
    REPO_ROOT / "plugins" / "twl" / "architecture" / "domain" / "contexts" / "twill-integration.md"
)


def _read_doc() -> str:
    return TWILL_INTEGRATION_MD.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# AC1: Phase 2 Component Mapping テーブルに twl_spawn_session が記載されていること
# ---------------------------------------------------------------------------


def test_ac1_spawn_session_in_component_mapping():
    """AC1: twill-integration.md の Phase 2 Component Mapping テーブルに
    twl_spawn_session が含む tool 群として記載されていること。
    """
    content = _read_doc()
    assert "twl_spawn_session" in content, (
        "Phase 2 Component Mapping に twl_spawn_session が未記載 (AC1 未実装)"
    )


# ---------------------------------------------------------------------------
# AC2: Phase 2 Component Mapping テーブルに twl_spawn_controller が記載されていること
# ---------------------------------------------------------------------------


def test_ac2_spawn_controller_in_component_mapping():
    """AC2: twill-integration.md の Phase 2 Component Mapping テーブルに
    twl_spawn_controller が含む tool 群として記載されていること。
    """
    content = _read_doc()
    assert "twl_spawn_controller" in content, (
        "Phase 2 Component Mapping に twl_spawn_controller が未記載 (AC2 未実装)"
    )


# ---------------------------------------------------------------------------
# AC3: Phase 2 Component Mapping テーブルに twl_capture_pane が記載されていること
# ---------------------------------------------------------------------------


def test_ac3_capture_pane_in_component_mapping():
    """AC3: twill-integration.md の Phase 2 Component Mapping テーブルに
    twl_capture_pane が含む tool 群として記載されていること。
    """
    content = _read_doc()
    assert "twl_capture_pane" in content, (
        "Phase 2 Component Mapping に twl_capture_pane が未記載 (AC3 未実装)"
    )


# ---------------------------------------------------------------------------
# AC4: Phase 2 Component Mapping テーブルに twl_list_windows が記載されていること
# ---------------------------------------------------------------------------


def test_ac4_list_windows_in_component_mapping():
    """AC4: twill-integration.md の Phase 2 Component Mapping テーブルに
    twl_list_windows が含む tool 群として記載されていること。
    """
    content = _read_doc()
    assert "twl_list_windows" in content, (
        "Phase 2 Component Mapping に twl_list_windows が未記載 (AC4 未実装)"
    )


# ---------------------------------------------------------------------------
# AC5: Phase 2 Component Mapping テーブルに twl_get_session_state の拡張が記載されていること
# ---------------------------------------------------------------------------


def test_ac5_get_session_state_in_component_mapping():
    """AC5: twill-integration.md の Phase 2 Component Mapping テーブルに
    twl_get_session_state（拡張）が含む tool 群として記載されていること。
    """
    content = _read_doc()
    assert "twl_get_session_state" in content, (
        "Phase 2 Component Mapping に twl_get_session_state が未記載 (AC5 未実装)"
    )


# ---------------------------------------------------------------------------
# AC6: Phase 2 Component Mapping テーブルに twl_get_budget が記載されていること
# ---------------------------------------------------------------------------


def test_ac6_get_budget_in_component_mapping():
    """AC6: twill-integration.md の Phase 2 Component Mapping テーブルに
    twl_get_budget が含む tool 群として記載されていること。
    """
    content = _read_doc()
    assert "twl_get_budget" in content, (
        "Phase 2 Component Mapping に twl_get_budget が未記載 (AC6 未実装)"
    )
