"""Tests for state.py autopilot dir resolution and RBAC fixes (Issue #470).

Covers:
  - _autopilot_dir() bare sibling detection
  - _autopilot_dir() fallback to main worktree
  - Pilot role is allowed to write the `pr` field
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from twl.autopilot.state import StateError, StateManager, _autopilot_dir


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_PORCELAIN_TEMPLATE = """\
worktree {main_wt}
HEAD abc1234def5678901234567890123456789012ab
branch refs/heads/main

worktree {feature_wt}
HEAD def5678901234567890123456789012abcdef12
branch refs/heads/fix/some-issue

"""


def _make_porcelain(main_wt: str, feature_wt: str) -> str:
    return _PORCELAIN_TEMPLATE.format(main_wt=main_wt, feature_wt=feature_wt)


# ---------------------------------------------------------------------------
# _autopilot_dir(): bare sibling detection
# ---------------------------------------------------------------------------


class TestAutopilotDirResolution:
    def test_env_var_takes_priority(self, tmp_path: Path) -> None:
        """AUTOPILOT_DIR env var always wins regardless of filesystem layout."""
        custom = tmp_path / "custom" / ".autopilot"
        custom.mkdir(parents=True)
        with patch.dict("os.environ", {"AUTOPILOT_DIR": str(custom)}):
            result = _autopilot_dir()
        assert result == custom

    def test_bare_sibling_preferred_when_exists(self, tmp_path: Path) -> None:
        """bare sibling (<main_wt>/../.autopilot) is returned when it exists."""
        # Simulate: tmp_path/main/  (main worktree)
        #           tmp_path/.autopilot/  (bare sibling — actual state dir)
        main_wt = tmp_path / "main"
        main_wt.mkdir()
        bare_sibling = tmp_path / ".autopilot"
        bare_sibling.mkdir()

        porcelain = _make_porcelain(str(main_wt), str(tmp_path / "feature"))
        with (
            patch.dict("os.environ", {}, clear=True),
            patch(
                "subprocess.check_output",
                return_value=porcelain,
            ),
        ):
            result = _autopilot_dir()

        assert result == bare_sibling

    def test_main_worktree_fallback_when_no_bare_sibling(self, tmp_path: Path) -> None:
        """Falls back to <main_wt>/.autopilot when bare sibling does not exist."""
        main_wt = tmp_path / "main"
        main_wt.mkdir()
        # bare sibling NOT created intentionally

        porcelain = _make_porcelain(str(main_wt), str(tmp_path / "feature"))
        with (
            patch.dict("os.environ", {}, clear=True),
            patch(
                "subprocess.check_output",
                return_value=porcelain,
            ),
        ):
            result = _autopilot_dir()

        assert result == main_wt / ".autopilot"

    def test_cwd_fallback_on_subprocess_error(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        """Falls back to cwd/.autopilot when git command fails."""
        monkeypatch.chdir(tmp_path)
        with (
            patch.dict("os.environ", {}, clear=True),
            patch("subprocess.check_output", side_effect=Exception("git not found")),
        ):
            result = _autopilot_dir()

        assert result == tmp_path / ".autopilot"


# ---------------------------------------------------------------------------
# Pilot RBAC: `pr` フィールド書き込み許可
# ---------------------------------------------------------------------------


class TestPilotPrWriteAllowed:
    def _make_issue_file(self, autopilot_dir: Path, issue_num: str) -> Path:
        issues = autopilot_dir / "issues"
        issues.mkdir(parents=True, exist_ok=True)
        f = issues / f"issue-{issue_num}.json"
        f.write_text(
            json.dumps(
                {
                    "issue": int(issue_num),
                    "status": "running",
                    "branch": "fix/test",
                    "pr": None,
                    "window": "",
                    "started_at": "2026-01-01T00:00:00Z",
                    "updated_at": "2026-01-01T00:00:00Z",
                    "current_step": "init",
                    "retry_count": 0,
                    "fix_instructions": None,
                    "merged_at": None,
                    "files_changed": [],
                    "failure": None,
                    "implementation_pr": None,
                    "deltaspec_mode": None,
                    "is_quick": False,
                    "is_direct": False,
                    "mode": "propose",
                    "llm_delegated_at": None,
                    "llm_completed_at": None,
                }
            ),
            encoding="utf-8",
        )
        return f

    def test_pilot_pr_write_allowed(self, tmp_path: Path) -> None:
        """Pilot role can write the `pr` field (Issue #470 AC-2)."""
        autopilot_dir = tmp_path / ".autopilot"
        self._make_issue_file(autopilot_dir, "470")

        mgr = StateManager(autopilot_dir=autopilot_dir)
        # Should not raise StateError
        result = mgr.write(
            role="pilot",
            type_="issue",
            issue="470",
            sets=["pr=509"],
        )
        assert "OK" in result

        data = json.loads((autopilot_dir / "issues" / "issue-470.json").read_text())
        assert data["pr"] == 509 or data["pr"] == "509"

    def test_pilot_cannot_write_current_step(self, tmp_path: Path) -> None:
        """Pilot role still cannot write fields not in _PILOT_ISSUE_ALLOWED_KEYS."""
        autopilot_dir = tmp_path / ".autopilot"
        self._make_issue_file(autopilot_dir, "470")

        mgr = StateManager(autopilot_dir=autopilot_dir)
        with pytest.raises(StateError):
            mgr.write(
                role="pilot",
                type_="issue",
                issue="470",
                sets=["current_step=evil"],
            )
