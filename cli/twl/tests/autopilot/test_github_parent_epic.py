"""Tests for extract_parent_epic in github.py (Issue #1026 ADR-024 AC1).

Covers:
  - extract_parent_epic returns parent number from `Parent: #N` line
  - extract_parent_epic returns None when no Parent line
  - extract_parent_epic raises GitHubError for invalid issue_num
  - extract_parent_epic handles multiline body correctly
  - extract_parent_epic returns first match if multiple Parent lines exist (M1)
  - CLI dispatch `extract-parent-epic` returns exit 0 (with number) or exit 2 (not found)
"""

from __future__ import annotations

from typing import Callable

import pytest

from twl.autopilot.github import (
    GitHubError,
    extract_parent_epic,
    main,
)


# ---------------------------------------------------------------------------
# Fixture: monkeypatch _gh_json with arbitrary body
# Quality Review M2 follow-up: 重複した `with patch(...)` を fixture で共通化
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_issue_body(
    monkeypatch: pytest.MonkeyPatch,
) -> Callable[[str, int], None]:
    """Factory fixture returning a callable that patches _gh_json with given body.

    Usage:
        def test_x(self, mock_issue_body):
            mock_issue_body("Parent: #42\\n", number=999)
            assert extract_parent_epic("999") == 42
    """

    def _factory(body: str, number: int = 999) -> None:
        monkeypatch.setattr(
            "twl.autopilot.github._gh_json",
            lambda *a, **kw: {"body": body, "number": number},
        )

    return _factory


# ---------------------------------------------------------------------------
# extract_parent_epic
# ---------------------------------------------------------------------------


class TestExtractParentEpic:
    def test_parent_found(self, mock_issue_body: Callable[[str, int], None]) -> None:
        """Body contains `Parent: #42` → returns 42."""
        mock_issue_body("## 概要\n\nSome text.\n\n## Related\nParent: #42\n")
        assert extract_parent_epic("999") == 42

    def test_no_parent_line(self, mock_issue_body: Callable[[str, int], None]) -> None:
        """Body without Parent line → returns None."""
        mock_issue_body("## 概要\n\nSome text.\n\n## Related\nRelated: #100\n")
        assert extract_parent_epic("999") is None

    def test_empty_body(self, mock_issue_body: Callable[[str, int], None]) -> None:
        """Empty body → returns None (not error, since parent is optional)."""
        mock_issue_body("")
        assert extract_parent_epic("999") is None

    def test_invalid_issue_num(self) -> None:
        """Non-integer issue_num → raises GitHubError."""
        with pytest.raises(GitHubError, match="Issue番号"):
            extract_parent_epic("abc")

    def test_parent_in_middle_of_body(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """Multiline body with Parent in middle → still extracts correctly."""
        body = (
            "# Title\n"
            "\n"
            "## Description\n"
            "Long description...\n"
            "\n"
            "Parent: #555\n"
            "\n"
            "## Acceptance Criteria\n"
            "- [ ] AC1\n"
        )
        mock_issue_body(body)
        assert extract_parent_epic("999") == 555

    def test_parent_with_leading_whitespace(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """Body with `  Parent: #N` (leading whitespace) → still extracts."""
        mock_issue_body("Some text\n  Parent: #777\n")
        assert extract_parent_epic("999") == 777

    def test_multiple_parent_lines_returns_first(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """When multiple Parent lines exist (body-format error), returns the first match.

        Behavior is consistent with re.search semantics, documented in docstring.
        Quality Review M1 follow-up: 仕様の docstring 明示と test カバレッジ追加。
        """
        mock_issue_body("Parent: #42\nParent: #99\n")
        assert extract_parent_epic("999") == 42

    def test_invalid_repo(self) -> None:
        """Invalid repo format → raises GitHubError."""
        with pytest.raises(GitHubError, match="不正な owner/repo"):
            extract_parent_epic("999", repo="invalid format")


# ---------------------------------------------------------------------------
# CLI dispatch: extract-parent-epic
# ---------------------------------------------------------------------------


class TestCLIExtractParentEpic:
    def test_cli_parent_found(
        self,
        mock_issue_body: Callable[[str, int], None],
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        """CLI with parent found → prints number and exits 0."""
        mock_issue_body("Parent: #42\n")
        exit_code = main(["extract-parent-epic", "999"])
        captured = capsys.readouterr()
        assert exit_code == 0
        assert captured.out.strip() == "42"

    def test_cli_parent_not_found(
        self, mock_issue_body: Callable[[str, int], None]
    ) -> None:
        """CLI with no parent → exits 2 (distinct exit code for not-found)."""
        mock_issue_body("No parent here\n")
        exit_code = main(["extract-parent-epic", "999"])
        assert exit_code == 2

    def test_cli_missing_args(self, capsys: pytest.CaptureFixture[str]) -> None:
        """CLI with no issue_num → exits 1 with usage message."""
        exit_code = main(["extract-parent-epic"])
        captured = capsys.readouterr()
        assert exit_code == 1
        assert "Usage" in captured.err

    def test_cli_invalid_issue_num(self) -> None:
        """CLI with invalid issue_num → exits 1 with error."""
        exit_code = main(["extract-parent-epic", "abc"])
        assert exit_code == 1
