"""
tests/scenarios/test_issue_485_paths_error_message.py

Issue #485: find_deltaspec_root エラーメッセージ強化
Source: deltaspec/changes/issue-485/specs/auto-init-suppression/spec.md

Coverage:
  Requirement: find_deltaspec_root エラーメッセージ強化
    Scenario: walk-up/walk-down 両方失敗時の詳細エラー

TDD: これらのテストは実装前に書かれており、最初は失敗する。
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from twl.spec.paths import DeltaspecNotFound, find_deltaspec_root


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _isolated_dir(tmp_path: Path) -> Path:
    """Return a directory with no deltaspec/ and no .git, isolated from fs root."""
    d = tmp_path / "isolated" / "project"
    d.mkdir(parents=True)
    return d


# ---------------------------------------------------------------------------
# Requirement: find_deltaspec_root エラーメッセージ強化
# ---------------------------------------------------------------------------


class TestFindDeltaspecRootDetailedError:
    """
    Scenario: walk-up/walk-down 両方失敗時の詳細エラー

    WHEN walk-up と walk-down の両方で deltaspec/config.yaml が見つからない
    THEN エラーメッセージに
         - Walked up from: <path>
         - Searched git root: <git_top or "(no .git found)">
         - Hint: git rebase origin/main を検討してください
         を含む DeltaspecNotFound が raise される
    """

    def test_raises_deltaspec_not_found_when_both_fail(
        self, tmp_path: Path
    ) -> None:
        """
        walk-up と walk-down 両方失敗時に DeltaspecNotFound が raise される
        """
        d = _isolated_dir(tmp_path)
        with pytest.raises(DeltaspecNotFound):
            find_deltaspec_root(d)

    def test_error_message_contains_walked_up_from(
        self, tmp_path: Path
    ) -> None:
        """
        エラーメッセージに 'Walked up from:' が含まれる
        """
        d = _isolated_dir(tmp_path)
        with pytest.raises(DeltaspecNotFound) as exc_info:
            find_deltaspec_root(d)

        msg = str(exc_info.value)
        assert "Walked up from:" in msg or "walked up from" in msg.lower(), (
            f"Expected 'Walked up from:' in error message, got: {msg!r}"
        )

    def test_error_message_contains_start_path(
        self, tmp_path: Path
    ) -> None:
        """
        エラーメッセージに walk-up の開始パスが含まれる
        """
        d = _isolated_dir(tmp_path)
        with pytest.raises(DeltaspecNotFound) as exc_info:
            find_deltaspec_root(d)

        msg = str(exc_info.value)
        # 開始パスの一部が含まれていること（resolved path）
        assert str(d.resolve()) in msg or "isolated" in msg, (
            f"Expected start path in error message, got: {msg!r}"
        )

    def test_error_message_contains_searched_git_root_label(
        self, tmp_path: Path
    ) -> None:
        """
        エラーメッセージに 'Searched git root:' が含まれる
        """
        d = _isolated_dir(tmp_path)
        with pytest.raises(DeltaspecNotFound) as exc_info:
            find_deltaspec_root(d)

        msg = str(exc_info.value)
        assert "Searched git root:" in msg or "searched git root" in msg.lower(), (
            f"Expected 'Searched git root:' in error message, got: {msg!r}"
        )

    def test_error_message_contains_no_git_found_when_no_git(
        self, tmp_path: Path
    ) -> None:
        """
        .git が存在しない場合、エラーメッセージに '(no .git found)' が含まれる
        """
        d = _isolated_dir(tmp_path)
        with pytest.raises(DeltaspecNotFound) as exc_info:
            find_deltaspec_root(d)

        msg = str(exc_info.value)
        assert "(no .git found)" in msg or "no .git" in msg.lower(), (
            f"Expected '(no .git found)' in error message when .git is absent, got: {msg!r}"
        )

    def test_error_message_contains_git_root_path_when_git_exists(
        self, tmp_path: Path
    ) -> None:
        """
        .git が存在する場合、エラーメッセージに git root パスが含まれる
        """
        # .git を作成するが deltaspec/config.yaml は作らない
        (tmp_path / ".git").mkdir()
        cwd = tmp_path / "sub"
        cwd.mkdir()

        with pytest.raises(DeltaspecNotFound) as exc_info:
            find_deltaspec_root(cwd)

        msg = str(exc_info.value)
        assert str(tmp_path.resolve()) in msg or "tmp" in msg or ".git" in msg, (
            f"Expected git root path in error message, got: {msg!r}"
        )

    def test_error_message_contains_rebase_hint(
        self, tmp_path: Path
    ) -> None:
        """
        エラーメッセージに 'git rebase origin/main' の Hint が含まれる
        """
        d = _isolated_dir(tmp_path)
        with pytest.raises(DeltaspecNotFound) as exc_info:
            find_deltaspec_root(d)

        msg = str(exc_info.value)
        assert "git rebase origin/main" in msg or "rebase" in msg.lower(), (
            f"Expected rebase hint in error message, got: {msg!r}"
        )

    def test_error_message_contains_hint_label(
        self, tmp_path: Path
    ) -> None:
        """
        エラーメッセージに 'Hint:' ラベルが含まれる
        """
        d = _isolated_dir(tmp_path)
        with pytest.raises(DeltaspecNotFound) as exc_info:
            find_deltaspec_root(d)

        msg = str(exc_info.value)
        assert "Hint:" in msg or "hint" in msg.lower(), (
            f"Expected 'Hint:' in error message, got: {msg!r}"
        )

    # ------------------------------------------------------------------
    # Edge cases
    # ------------------------------------------------------------------

    def test_error_contains_all_required_fields(
        self, tmp_path: Path
    ) -> None:
        """
        エラーメッセージに Walked up from / Searched git root / Hint: の3要素が全て含まれる
        """
        d = _isolated_dir(tmp_path)
        with pytest.raises(DeltaspecNotFound) as exc_info:
            find_deltaspec_root(d)

        msg = str(exc_info.value)
        checks = {
            "Walked up from": "Walked up from:" in msg or "walked up from" in msg.lower(),
            "Searched git root": "Searched git root:" in msg or "searched git root" in msg.lower(),
            "Hint / rebase": "Hint:" in msg or "rebase" in msg.lower(),
        }
        missing = [k for k, v in checks.items() if not v]
        assert not missing, (
            f"Missing fields in error message {missing!r}. Full message: {msg!r}"
        )

    def test_existing_deltaspec_raises_no_error(
        self, tmp_path: Path
    ) -> None:
        """
        正常ケース: deltaspec/config.yaml が存在する場合は DeltaspecNotFound を raise しない
        """
        ds = tmp_path / "deltaspec"
        ds.mkdir()
        (ds / "config.yaml").write_text("schema: spec-driven\ncontext: {}\n", encoding="utf-8")

        result = find_deltaspec_root(tmp_path)
        assert result == tmp_path
