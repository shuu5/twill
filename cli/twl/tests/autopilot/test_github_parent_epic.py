"""Tests for extract_parent_epic in github.py (Issue #1026 ADR-024 AC1).

Covers:
  - extract_parent_epic returns parent number from `Parent: #N` line
  - extract_parent_epic returns None when no Parent line
  - extract_parent_epic raises GitHubError for invalid issue_num
  - extract_parent_epic handles multiline body correctly
  - CLI dispatch `extract-parent-epic` returns exit 0 (with number) or exit 2 (not found)
"""

from __future__ import annotations

import subprocess
from unittest.mock import patch

import pytest

from twl.autopilot.github import (
    GitHubError,
    extract_parent_epic,
    main,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _gh_response(stdout: str, returncode: int = 0) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(args=[], returncode=returncode, stdout=stdout, stderr="")


# ---------------------------------------------------------------------------
# extract_parent_epic
# ---------------------------------------------------------------------------


class TestExtractParentEpic:
    def test_parent_found(self) -> None:
        """Body contains `Parent: #42` → returns 42."""
        body = "## 概要\n\nSome text.\n\n## Related\nParent: #42\n"
        with patch(
            "twl.autopilot.github._gh_json",
            return_value={"body": body, "number": 999},
        ):
            assert extract_parent_epic("999") == 42

    def test_no_parent_line(self) -> None:
        """Body without Parent line → returns None."""
        body = "## 概要\n\nSome text.\n\n## Related\nRelated: #100\n"
        with patch(
            "twl.autopilot.github._gh_json",
            return_value={"body": body, "number": 999},
        ):
            assert extract_parent_epic("999") is None

    def test_empty_body(self) -> None:
        """Empty body → returns None (not error, since parent is optional)."""
        with patch(
            "twl.autopilot.github._gh_json",
            return_value={"body": "", "number": 999},
        ):
            assert extract_parent_epic("999") is None

    def test_invalid_issue_num(self) -> None:
        """Non-integer issue_num → raises GitHubError."""
        with pytest.raises(GitHubError, match="Issue番号"):
            extract_parent_epic("abc")

    def test_parent_in_middle_of_body(self) -> None:
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
        with patch(
            "twl.autopilot.github._gh_json",
            return_value={"body": body, "number": 999},
        ):
            assert extract_parent_epic("999") == 555

    def test_parent_with_leading_whitespace(self) -> None:
        """Body with `  Parent: #N` (leading whitespace) → still extracts."""
        body = "Some text\n  Parent: #777\n"
        with patch(
            "twl.autopilot.github._gh_json",
            return_value={"body": body, "number": 999},
        ):
            assert extract_parent_epic("999") == 777

    def test_invalid_repo(self) -> None:
        """Invalid repo format → raises GitHubError."""
        with pytest.raises(GitHubError, match="不正な owner/repo"):
            extract_parent_epic("999", repo="invalid format")


# ---------------------------------------------------------------------------
# CLI dispatch: extract-parent-epic
# ---------------------------------------------------------------------------


class TestCLIExtractParentEpic:
    def test_cli_parent_found(self, capsys: pytest.CaptureFixture[str]) -> None:
        """CLI with parent found → prints number and exits 0."""
        body = "Parent: #42\n"
        with patch(
            "twl.autopilot.github._gh_json",
            return_value={"body": body, "number": 999},
        ):
            exit_code = main(["extract-parent-epic", "999"])
        captured = capsys.readouterr()
        assert exit_code == 0
        assert captured.out.strip() == "42"

    def test_cli_parent_not_found(self, capsys: pytest.CaptureFixture[str]) -> None:
        """CLI with no parent → exits 2 (distinct exit code for not-found)."""
        body = "No parent here\n"
        with patch(
            "twl.autopilot.github._gh_json",
            return_value={"body": body, "number": 999},
        ):
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
