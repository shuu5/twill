"""Tests for Closes-AC parser + Epic AC checkbox flipper (Issue #1070).

Covers:
  - _patch_checkbox_in_text: pure function flipping `- [ ] **AC{N}**` to `- [x]`
  - extract_closes_ac: parse `Closes-AC: #EPIC:ACN` lines from child Issue body
  - flip_epic_ac_checkbox: I/O wrapper that fetches Epic body, patches, edits
  - update_epic_ac_checklist: orchestrator + CLI dispatch
"""

from __future__ import annotations

from typing import Any, Callable
from unittest.mock import MagicMock

import pytest

from twl.autopilot.github import (
    GitHubError,
    _patch_checkbox_in_text,
    extract_closes_ac,
    flip_epic_ac_checkbox,
    main,
    update_epic_ac_checklist,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_issue_body(
    monkeypatch: pytest.MonkeyPatch,
) -> Callable[[str, int], None]:
    """Factory fixture: monkeypatch _gh_json with a fixed body."""

    def _factory(body: str, number: int = 999) -> None:
        monkeypatch.setattr(
            "twl.autopilot.github._gh_json",
            lambda *a, **kw: {"body": body, "number": number},
        )

    return _factory


@pytest.fixture
def mock_gh_calls(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    """Capture _gh_json reads + _gh writes for assertion."""
    calls: dict[str, Any] = {"json_reads": [], "edits": []}

    def fake_gh_json(*args: str) -> dict[str, Any]:
        calls["json_reads"].append(args)
        body = calls.get("_next_body", "")
        return {"body": body, "number": 999}

    def fake_gh(*args: str, check: bool = True) -> Any:
        calls["edits"].append((args, check))
        result = MagicMock()
        result.returncode = 0
        result.stdout = ""
        result.stderr = ""
        return result

    monkeypatch.setattr("twl.autopilot.github._gh_json", fake_gh_json)
    monkeypatch.setattr("twl.autopilot.github._gh", fake_gh)
    return calls


# ---------------------------------------------------------------------------
# _patch_checkbox_in_text — pure function, 8 tests
# ---------------------------------------------------------------------------


class TestPatchCheckboxInText:
    """Pure regex-based body patcher. Strict match: `- [ ] **AC{N}**` only."""

    def test_flips_unchecked_basic(self) -> None:
        """Basic unchecked AC1 → checked."""
        body = "- [ ] **AC1** (Phase 0): description\n"
        patched, changed = _patch_checkbox_in_text(body, 1)
        assert changed is True
        assert "- [x] **AC1**" in patched
        assert "- [ ] **AC1**" not in patched

    def test_already_checked_idempotent(self) -> None:
        """Already `[x]` → no change, returns same body."""
        body = "- [x] **AC1** (Phase 0): description\n"
        patched, changed = _patch_checkbox_in_text(body, 1)
        assert changed is False
        assert patched == body

    def test_no_bold_not_matched(self) -> None:
        """Strict format: bare `- [ ] AC1` (no bold) is NOT matched."""
        body = "- [ ] AC1: description\n"
        patched, changed = _patch_checkbox_in_text(body, 1)
        assert changed is False
        assert patched == body

    def test_wrong_ac_number_unchanged(self) -> None:
        """`- [ ] **AC2**` not flipped when patching AC1."""
        body = "- [ ] **AC2** (Phase 0): description\n"
        patched, changed = _patch_checkbox_in_text(body, 1)
        assert changed is False
        assert patched == body

    def test_multiple_acs_only_target_flipped(self) -> None:
        """When body has AC1 + AC2 + AC3, patching AC2 only flips AC2."""
        body = (
            "- [ ] **AC1** (Phase 0): first\n"
            "- [ ] **AC2** (Phase 0): second\n"
            "- [ ] **AC3** (Phase 0): third\n"
        )
        patched, changed = _patch_checkbox_in_text(body, 2)
        assert changed is True
        # AC2 is now [x]
        assert "- [x] **AC2** (Phase 0): second" in patched
        # AC1 and AC3 are unchanged
        assert "- [ ] **AC1** (Phase 0): first" in patched
        assert "- [ ] **AC3** (Phase 0): third" in patched

    def test_with_leading_whitespace(self) -> None:
        """Leading spaces/tabs preserved when flipping."""
        body = "  - [ ] **AC5** (Phase 1): nested item\n"
        patched, changed = _patch_checkbox_in_text(body, 5)
        assert changed is True
        assert "  - [x] **AC5** (Phase 1): nested item" in patched

    def test_empty_body(self) -> None:
        """Empty body → no change, no error."""
        patched, changed = _patch_checkbox_in_text("", 1)
        assert changed is False
        assert patched == ""

    def test_two_digit_ac_number(self) -> None:
        """AC numbers > 9 (e.g., AC10) work correctly without AC1 false match."""
        body = (
            "- [ ] **AC1** (Phase 0): one\n"
            "- [ ] **AC10** (Architecture): ten\n"
        )
        patched, changed = _patch_checkbox_in_text(body, 10)
        assert changed is True
        assert "- [x] **AC10** (Architecture): ten" in patched
        # AC1 should remain unchecked — strict number match required
        assert "- [ ] **AC1** (Phase 0): one" in patched


# ---------------------------------------------------------------------------
# extract_closes_ac — I/O via _gh_json, 6 tests
# ---------------------------------------------------------------------------


class TestExtractClosesAc:
    def test_single_ref(self, mock_issue_body: Callable[[str, int], None]) -> None:
        """One Closes-AC line → single tuple."""
        mock_issue_body("Parent: #945\nCloses-AC: #945:AC8\n")
        result = extract_closes_ac("999")
        assert result == [(945, 8)]

    def test_multi_ref(self, mock_issue_body: Callable[[str, int], None]) -> None:
        """Multiple Closes-AC lines → multiple tuples in document order."""
        body = (
            "Parent: #945\n"
            "Closes-AC: #945:AC6\n"
            "Closes-AC: #945:AC7\n"
        )
        mock_issue_body(body)
        result = extract_closes_ac("999")
        assert result == [(945, 6), (945, 7)]

    def test_no_refs_returns_empty(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """Body without Closes-AC → empty list (NOT exception)."""
        mock_issue_body("Parent: #945\nRelated: #100\n")
        assert extract_closes_ac("999") == []

    def test_empty_body(self, mock_issue_body: Callable[[str, int], None]) -> None:
        """Empty body → empty list."""
        mock_issue_body("")
        assert extract_closes_ac("999") == []

    def test_invalid_issue_num_raises(self) -> None:
        """Non-integer issue_num → GitHubError."""
        with pytest.raises(GitHubError, match="Issue番号"):
            extract_closes_ac("abc")

    def test_invalid_repo_raises(self) -> None:
        """Invalid repo format → GitHubError."""
        with pytest.raises(GitHubError, match="不正な owner/repo"):
            extract_closes_ac("999", repo="bad format")

    def test_cross_epic_refs(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """Closes-AC across multiple Epics → all extracted."""
        body = (
            "Closes-AC: #945:AC8\n"
            "Closes-AC: #1026:AC3\n"
        )
        mock_issue_body(body)
        result = extract_closes_ac("999")
        assert result == [(945, 8), (1026, 3)]

    def test_fenced_code_block_ignored(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """``` ... ``` で囲まれた Closes-AC (例示) は抽出対象外 (R2-H1 fix)."""
        body = (
            "## 概要\n"
            "下記は規約の例:\n"
            "```\n"
            "Closes-AC: #945:AC8\n"
            "```\n"
            "Parent: #1026\n"
        )
        mock_issue_body(body)
        # Fenced block 内の Closes-AC は ignored
        assert extract_closes_ac("999") == []

    def test_fence_outside_block_still_matched(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """Fenced block の外にある Closes-AC は抽出対象."""
        body = (
            "## 概要\n"
            "```python\n"
            "x = 1  # not a Closes-AC\n"
            "```\n"
            "Closes-AC: #945:AC8\n"
        )
        mock_issue_body(body)
        assert extract_closes_ac("999") == [(945, 8)]

    def test_tilde_fence_also_stripped(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """~~~ ... ~~~ 形式の fence でも例示は ignored."""
        body = (
            "~~~\n"
            "Closes-AC: #999:AC1\n"
            "~~~\n"
            "Closes-AC: #945:AC2\n"
        )
        mock_issue_body(body)
        assert extract_closes_ac("999") == [(945, 2)]

    def test_malformed_no_hash_ignored(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """`Closes-AC: 945:AC8` (no `#`) → ignored, returns []."""
        mock_issue_body("Closes-AC: 945:AC8\n")
        assert extract_closes_ac("999") == []


# ---------------------------------------------------------------------------
# flip_epic_ac_checkbox — I/O wrapping pure patcher, 4 tests
# ---------------------------------------------------------------------------


class TestFlipEpicAcCheckbox:
    def test_flip_calls_edit_when_changed(
        self, mock_gh_calls: dict[str, Any]
    ) -> None:
        """When body has unchecked AC → gh issue edit called once with new body."""
        mock_gh_calls["_next_body"] = "- [ ] **AC8** (Phase 1): foo\n"
        result = flip_epic_ac_checkbox(945, 8)
        assert result is True
        # 1 read + 1 edit call expected
        assert len(mock_gh_calls["json_reads"]) == 1
        assert len(mock_gh_calls["edits"]) == 1
        # The edit args should include `--body` with `[x]`
        edit_args, _check = mock_gh_calls["edits"][0]
        assert "issue" in edit_args
        assert "edit" in edit_args
        assert "945" in edit_args
        assert "--body" in edit_args
        body_idx = list(edit_args).index("--body")
        new_body = edit_args[body_idx + 1]
        assert "- [x] **AC8**" in new_body

    def test_flip_skips_edit_when_already_checked(
        self, mock_gh_calls: dict[str, Any]
    ) -> None:
        """Already `[x]` → no edit call (rate-hit savings)."""
        mock_gh_calls["_next_body"] = "- [x] **AC8** (Phase 1): foo\n"
        result = flip_epic_ac_checkbox(945, 8)
        assert result is False
        # Read happened, but no edit
        assert len(mock_gh_calls["json_reads"]) == 1
        assert len(mock_gh_calls["edits"]) == 0

    def test_flip_returns_false_on_no_match(
        self, mock_gh_calls: dict[str, Any]
    ) -> None:
        """Format-deviated body (`- [ ] AC8` no bold) → no edit, False."""
        mock_gh_calls["_next_body"] = "- [ ] AC8: foo\n"
        result = flip_epic_ac_checkbox(945, 8)
        assert result is False
        assert len(mock_gh_calls["edits"]) == 0

    def test_invalid_epic_num_raises(self) -> None:
        """Non-positive epic_num → GitHubError."""
        with pytest.raises(GitHubError, match="Epic番号"):
            flip_epic_ac_checkbox(0, 1)

    def test_invalid_ac_num_raises(self) -> None:
        """Non-positive ac_num → GitHubError."""
        with pytest.raises(GitHubError, match="AC番号"):
            flip_epic_ac_checkbox(945, 0)


# ---------------------------------------------------------------------------
# update_epic_ac_checklist — orchestrator, 3 tests
# ---------------------------------------------------------------------------


class TestUpdateEpicAcChecklist:
    def test_orchestrator_loops_multi_refs(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Multiple Closes-AC → flip_epic_ac_checkbox called for each."""
        # Stub extract_closes_ac to return 2 refs
        monkeypatch.setattr(
            "twl.autopilot.github.extract_closes_ac",
            lambda issue, repo=None: [(945, 6), (945, 7)],
        )
        flip_calls: list[tuple[int, int]] = []
        monkeypatch.setattr(
            "twl.autopilot.github.flip_epic_ac_checkbox",
            lambda epic, ac, repo=None: (flip_calls.append((epic, ac)) or True),
        )
        result = update_epic_ac_checklist("999")
        assert result is True
        assert flip_calls == [(945, 6), (945, 7)]

    def test_orchestrator_returns_false_no_refs(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """No Closes-AC → no flip calls, returns False."""
        monkeypatch.setattr(
            "twl.autopilot.github.extract_closes_ac",
            lambda issue, repo=None: [],
        )
        result = update_epic_ac_checklist("999")
        assert result is False

    def test_orchestrator_returns_true_if_any_flipped(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Mixed: AC6 already checked, AC7 newly flipped → returns True."""
        monkeypatch.setattr(
            "twl.autopilot.github.extract_closes_ac",
            lambda issue, repo=None: [(945, 6), (945, 7)],
        )

        def fake_flip(epic: int, ac: int, repo: str | None = None) -> bool:
            return ac == 7  # only AC7 newly flipped

        monkeypatch.setattr(
            "twl.autopilot.github.flip_epic_ac_checkbox", fake_flip
        )
        result = update_epic_ac_checklist("999")
        assert result is True

    def test_orchestrator_returns_false_if_all_idempotent(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """All flips return False (idempotent) → returns False."""
        monkeypatch.setattr(
            "twl.autopilot.github.extract_closes_ac",
            lambda issue, repo=None: [(945, 6), (945, 7)],
        )
        monkeypatch.setattr(
            "twl.autopilot.github.flip_epic_ac_checkbox",
            lambda epic, ac, repo=None: False,
        )
        result = update_epic_ac_checklist("999")
        assert result is False

    def test_orchestrator_suppresses_per_epic_errors(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """If one flip raises GitHubError, orchestrator continues with others."""
        monkeypatch.setattr(
            "twl.autopilot.github.extract_closes_ac",
            lambda issue, repo=None: [(945, 6), (1026, 1)],
        )
        flip_calls: list[tuple[int, int]] = []

        def fake_flip(epic: int, ac: int, repo: str | None = None) -> bool:
            flip_calls.append((epic, ac))
            if epic == 945:
                raise GitHubError("API failure")
            return True

        monkeypatch.setattr(
            "twl.autopilot.github.flip_epic_ac_checkbox", fake_flip
        )
        # Should not raise; continue to second flip
        result = update_epic_ac_checklist("999")
        assert result is True
        assert flip_calls == [(945, 6), (1026, 1)]


# ---------------------------------------------------------------------------
# CLI dispatch: update-epic-ac-checklist, 4 tests
# ---------------------------------------------------------------------------


class TestCLIUpdateEpicAcChecklist:
    def test_cli_exit_0_on_flip(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """At least one flip occurred → exit 0."""
        monkeypatch.setattr(
            "twl.autopilot.github.update_epic_ac_checklist",
            lambda issue, repo=None: True,
        )
        exit_code = main(["update-epic-ac-checklist", "999"])
        assert exit_code == 0

    def test_cli_exit_2_on_no_change(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """No flips occurred → exit 2 (idempotent skip signal)."""
        monkeypatch.setattr(
            "twl.autopilot.github.update_epic_ac_checklist",
            lambda issue, repo=None: False,
        )
        exit_code = main(["update-epic-ac-checklist", "999"])
        assert exit_code == 2

    def test_cli_missing_args_exit_1(
        self, capsys: pytest.CaptureFixture[str]
    ) -> None:
        """Missing issue-num → exit 1 with usage."""
        exit_code = main(["update-epic-ac-checklist"])
        captured = capsys.readouterr()
        assert exit_code == 1
        assert "Usage" in captured.err

    def test_cli_invalid_issue_num_exit_1(self) -> None:
        """Invalid issue-num → exit 1."""
        exit_code = main(["update-epic-ac-checklist", "abc"])
        assert exit_code == 1
