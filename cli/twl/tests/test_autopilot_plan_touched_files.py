"""Tests for touched-files extraction and Phase separation in twl.autopilot.plan.

Covers Issue #132: arbitrary file conflict prediction (generalisation of
deps.yaml exclusivity).
"""

from twl.autopilot.plan import (
    _extract_touched_files,
    _extract_touched_files_section,
    _separate_touched_files_phases,
    _separate_deps_yaml_phases,
)


# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

def test_extract_explicit_touched_files_section():
    body = """
## 概要
hi

## Touched files

- cli/twl/src/twl/autopilot/plan.py
- plugins/twl/templates/issue/feature.md

## 受け入れ基準
- [ ] foo
"""
    result = _extract_touched_files_section(body)
    assert result == {
        "cli/twl/src/twl/autopilot/plan.py",
        "plugins/twl/templates/issue/feature.md",
    }


def test_extract_touched_files_section_handles_backticks_and_inline_notes():
    body = """
## Touched files

- `cli/twl/src/twl/autopilot/plan.py` (main change)
- plugins/twl/templates/issue/bug.md
"""
    result = _extract_touched_files_section(body)
    assert "cli/twl/src/twl/autopilot/plan.py" in result
    assert "plugins/twl/templates/issue/bug.md" in result


def test_extract_touched_files_section_stops_at_next_header():
    body = """
## Touched files

- cli/twl/src/twl/autopilot/plan.py

## 補足

- このファイルは無視: docs/other.md
"""
    result = _extract_touched_files_section(body)
    assert result == {"cli/twl/src/twl/autopilot/plan.py"}


def test_extract_falls_back_to_path_heuristics_when_no_section():
    body = """
## 概要
このバグは `cli/twl/src/twl/autopilot/plan.py` の関数で発生しています。
関連: plugins/twl/scripts/foo.sh
"""
    result = _extract_touched_files(body)
    assert "cli/twl/src/twl/autopilot/plan.py" in result
    assert "plugins/twl/scripts/foo.sh" in result


def test_extract_section_takes_priority_over_heuristics():
    body = """
## 概要
mention of cli/twl/src/twl/other.py here

## Touched files

- cli/twl/src/twl/autopilot/plan.py
"""
    result = _extract_touched_files(body)
    # Section is authoritative; the heuristic mention should NOT pollute result.
    assert result == {"cli/twl/src/twl/autopilot/plan.py"}


def test_extract_filters_non_whitelisted_extensions():
    body = "this references foo/bar.xyz and baz.unknown which should be ignored"
    result = _extract_touched_files(body)
    assert result == set()


def test_extract_requires_slash_in_path():
    body = "just plan.py mentioned bare without directory"
    result = _extract_touched_files(body)
    assert "plan.py" not in result


# ---------------------------------------------------------------------------
# Phase separation
# ---------------------------------------------------------------------------

def test_separate_phases_pushes_conflicting_issue_to_next_phase():
    phases = [["A", "B"]]
    touched = {
        "A": {"cli/twl/src/twl/autopilot/worktree.py"},
        "B": {"cli/twl/src/twl/autopilot/worktree.py"},
    }
    result = _separate_touched_files_phases(phases, touched)
    assert result == [["A"], ["B"]]


def test_separate_phases_keeps_non_conflicting_issues_together():
    phases = [["A", "B"]]
    touched = {
        "A": {"cli/twl/src/twl/autopilot/plan.py"},
        "B": {"cli/twl/src/twl/autopilot/state.py"},
    }
    result = _separate_touched_files_phases(phases, touched)
    assert result == [["A", "B"]]


def test_separate_phases_three_way_collision():
    phases = [["A", "B", "C"]]
    touched = {
        "A": {"foo/bar.py"},
        "B": {"foo/bar.py"},
        "C": {"foo/bar.py"},
    }
    result = _separate_touched_files_phases(phases, touched)
    assert result == [["A"], ["B"], ["C"]]


def test_separate_phases_partial_collision_packs_efficiently():
    # A↔B conflict on file1; C is independent → C can pack with A.
    phases = [["A", "B", "C"]]
    touched = {
        "A": {"file1.py", "shared/x.py"},
        "B": {"file1.py"},
        "C": {"unrelated/y.md"},
    }
    result = _separate_touched_files_phases(phases, touched)
    # A and C share first sub-phase; B pushed to next.
    assert result == [["A", "C"], ["B"]]


def test_separate_phases_empty_touched_set_treated_as_no_conflict():
    phases = [["A", "B"]]
    touched = {"A": set(), "B": set()}
    result = _separate_touched_files_phases(phases, touched)
    assert result == [["A", "B"]]


def test_separate_phases_preserves_existing_phase_boundaries():
    phases = [["A"], ["B"]]
    touched = {
        "A": {"x.py"},
        "B": {"x.py"},
    }
    # Already in separate phases; no further splitting needed.
    result = _separate_touched_files_phases(phases, touched)
    assert result == [["A"], ["B"]]


def test_deps_yaml_parallel_allowed_after_touched_files_pass():
    """Invariant H relaxed: deps.yaml issues are allowed in the same phase (parallel execution).
    merge-gate handles conflict resolution via auto-rebase.
    """
    phases = [["A", "B", "C"]]
    deps_yaml_issues = {"A", "B"}
    phases = _separate_deps_yaml_phases(phases, deps_yaml_issues)
    # Then touched-files separation runs over the result.
    touched = {"A": set(), "B": set(), "C": set()}
    final = _separate_touched_files_phases(phases, touched)
    # A and B (deps.yaml) are allowed in the same phase under relaxed invariant H.
    flat_phases = [set(p) for p in final]
    a_phase = next(i for i, p in enumerate(flat_phases) if "A" in p)
    b_phase = next(i for i, p in enumerate(flat_phases) if "B" in p)
    assert a_phase == b_phase, "deps.yaml issues should be in the same phase (parallel allowed)"
