"""MergeGate — merge execution, reject, and reject-final operations.

Replaces: merge-gate-execute.sh, merge-gate-init.sh

CLI usage:
    python3 -m twl.autopilot.mergegate [--reject | --reject-final]

Required environment variables:
    ISSUE       - Issue number (integer)
    PR_NUMBER   - PR number (integer)
    BRANCH      - Branch name

Optional environment variables:
    FINDING_SUMMARY   - Reject reason summary (--reject / --reject-final)
    FIX_INSTRUCTIONS  - Fix instructions text (--reject)
    REPO_OWNER        - Cross-repo owner
    REPO_NAME         - Cross-repo repo name
    AUTOPILOT_DIR     - Override .autopilot directory path
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from twl.autopilot.mergegate_guards import (
    MergeGateError,
    _board_update,
    _check_phase_review_guard,
    _check_running_guard,
    _check_worker_window_guard,
    _check_worktree_guard,
    _detect_repo_mode,
    _state_read,
    _state_write,
)
from twl.autopilot.mergegate_ops import MergeGateOperationsMixin


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

_ISSUE_RE = re.compile(r"^\d+$")
_PR_RE = re.compile(r"^\d+$")
_BRANCH_RE = re.compile(r"^[a-zA-Z0-9._/\-]+$")
_OWNER_RE = re.compile(r"^[a-zA-Z0-9_-]+$")
_REPO_RE = re.compile(r"^[a-zA-Z0-9_.-]+$")


def _require_env(name: str, pattern: re.Pattern[str]) -> str:
    val = os.environ.get(name, "")
    if not pattern.match(val):
        raise MergeGateError(f"不正な{name}: {val!r}")
    return val


def _env_opt(name: str) -> str:
    return os.environ.get(name, "")


# ---------------------------------------------------------------------------
# MergeGate class
# ---------------------------------------------------------------------------


class MergeGate(MergeGateOperationsMixin):
    """Manage merge-gate operations: merge, reject, reject-final.

    Mirrors the logic of merge-gate-execute.sh with the same environment
    variable contract and exit code behaviour.
    Internal helper methods are provided by MergeGateOperationsMixin.
    """

    def __init__(
        self,
        issue: str,
        pr_number: str,
        branch: str,
        *,
        finding_summary: str = "",
        fix_instructions: str = "",
        repo_owner: str = "",
        repo_name: str = "",
        autopilot_dir: Path | None = None,
        scripts_root: Path | None = None,
        force: bool = False,
    ) -> None:
        self.issue = issue
        self.pr_number = pr_number
        self.branch = branch
        self.finding_summary = finding_summary
        self.fix_instructions = fix_instructions
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.autopilot_dir = autopilot_dir or self._detect_autopilot_dir()
        self.scripts_root = scripts_root or self._detect_scripts_root()
        self.force = force

    # ------------------------------------------------------------------
    # Factory from environment variables (mirrors merge-gate-execute.sh)
    # ------------------------------------------------------------------

    @classmethod
    def from_env(cls) -> "MergeGate":
        issue = _require_env("ISSUE", _ISSUE_RE)
        pr_number = _require_env("PR_NUMBER", _PR_RE)
        branch = _require_env("BRANCH", _BRANCH_RE)

        repo_owner = _env_opt("REPO_OWNER")
        repo_name = _env_opt("REPO_NAME")
        if repo_owner and not _OWNER_RE.match(repo_owner):
            raise MergeGateError(f"不正な REPO_OWNER: {repo_owner!r}")
        if repo_name and not _REPO_RE.match(repo_name):
            raise MergeGateError(f"不正な REPO_NAME: {repo_name!r}")

        return cls(
            issue=issue,
            pr_number=pr_number,
            branch=branch,
            finding_summary=_env_opt("FINDING_SUMMARY"),
            fix_instructions=_env_opt("FIX_INSTRUCTIONS"),
            repo_owner=repo_owner,
            repo_name=repo_name,
        )

    # ------------------------------------------------------------------
    # Public operations
    # ------------------------------------------------------------------

    def execute(self) -> None:
        """Perform squash merge and transition state to done."""
        cwd = os.getcwd()
        _check_worktree_guard(cwd)
        _check_worker_window_guard()

        autopilot_status = _state_read(self.issue, "status")
        if autopilot_status == "merge-ready":
            print(
                f"[merge-gate-execute] autopilot 検出 (status=merge-ready): "
                f"Pilot セッションとして merge を実行"
            )
        if not self.force:
            _check_running_guard(autopilot_status)

        # Pre-merge check: phase-review checkpoint guard (Issue #439).
        issue_labels = self._get_issue_labels()
        _check_phase_review_guard(
            autopilot_dir=self.autopilot_dir,
            issue_labels=issue_labels,
            force=self.force,
        )

        repo_mode = _detect_repo_mode()
        gh_repo_flag = self._gh_repo_flag()

        print(
            f"[merge-gate] Issue #{self.issue}: "
            f"PR #{self.pr_number} のマージを実行... (REPO_MODE={repo_mode})"
        )

        # Pre-merge fail-safe: ensure PR body contains Closes #N so GitHub
        # auto-close fires on merge. Issue #136.
        self._ensure_closes_link(gh_repo_flag)

        # Pre-merge check: detect silent file deletions from base staleness. Issue #166.
        self._check_base_drift()

        # Pre-merge check: detect deps.yaml conflict and auto-rebase if needed. Issue #229.
        self._check_deps_yaml_conflict_and_rebase()

        merge_ok = self._run_merge(gh_repo_flag)
        if not merge_ok:
            sys.exit(1)

        self._post_merge_cleanup(repo_mode, autopilot_status)

        # Layered defense: verify GitHub Issue is CLOSED before status=done.
        # PR body 経由の auto-close 仕様に依存せず、明示的に close を試行する。
        issue_closed = self._verify_and_close_issue(gh_repo_flag)
        if not issue_closed:
            # 不変条件 A 強化: merge-ready → done の前提条件
            # (GitHub Issue が CLOSED) が満たされない場合は failed に遷移。
            # retry_count 管理との整合のため merge-ready 維持ではなく failed。
            failure = json.dumps({
                "message": "PR merged but Issue could not be closed",
                "step": "merge-gate-issue-close",
                "timestamp": self._now_iso(),
                "reason": "issue_not_closed_after_merge",
                "pr": int(self.pr_number),
            })
            _state_write(
                self.issue, "pilot",
                status="failed",
                failure=failure,
            )
            print(
                f"[merge-gate] Issue #{self.issue}: ⚠️ PR merge 成功したが Issue close 失敗。"
                f"status=failed に遷移。Pilot retrospective で escalate されます。",
                file=sys.stderr,
            )
            # board status は Done に遷移させない（In Progress のまま）
            sys.exit(2)

        _state_write(
            self.issue, "pilot",
            status="done",
            merged_at=self._now_iso(),
        )
        print(f"[merge-gate] Issue #{self.issue}: マージ完了 + Issue CLOSED 確認済み")
        _board_update(self.issue, self.scripts_root, "Done")

    def reject(self) -> None:
        """Reject (1st time): transition state to failed + record retry."""
        print(
            f"[merge-gate] Issue #{self.issue}: "
            f"リジェクト（Critical/High 問題検出）",
            file=sys.stderr,
        )
        failure = json.dumps({
            "reason": "merge_gate_rejected",
            "details": self.finding_summary,
            "step": "merge-gate",
            "retry_count": 1,
            "fix_instructions": self.fix_instructions,
        })
        _state_write(self.issue, "pilot", status="failed", failure=failure)
        self._kill_worker_window()

    def reject_final(self) -> None:
        """Final rejection (2nd time): transition state to failed (no retry)."""
        print(
            f"[merge-gate] Issue #{self.issue}: 確定失敗（2回目のリジェクト）",
            file=sys.stderr,
        )
        failure = json.dumps({
            "reason": "merge_gate_rejected_final",
            "details": self.finding_summary,
            "step": "merge-gate",
            "retry_count": 2,
        })
        _state_write(self.issue, "pilot", status="failed", failure=failure)
        self._kill_worker_window()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _gh_repo_flag(self) -> list[str]:
        if self.repo_owner and self.repo_name:
            return ["-R", f"{self.repo_owner}/{self.repo_name}"]
        return []



# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    import argparse

    args = argv if argv is not None else sys.argv[1:]

    if args and args[0] == "merge":
        # New subcommand mode: merge --issue N --pr N --branch BRANCH [--force]
        parser = argparse.ArgumentParser(prog="python3 -m twl.autopilot.mergegate merge")
        parser.add_argument("--issue", required=True, help="Issue number")
        parser.add_argument("--pr", required=True, dest="pr_number", help="PR number")
        parser.add_argument("--branch", required=True, help="Branch name")
        parser.add_argument(
            "--force", action="store_true", default=False,
            help="Skip status=running guard (Emergency Bypass use only)",
        )
        try:
            parsed = parser.parse_args(args[1:])
        except SystemExit:
            return 1

        for name, val, pattern in [
            ("--issue", parsed.issue, _ISSUE_RE),
            ("--pr", parsed.pr_number, _PR_RE),
            ("--branch", parsed.branch, _BRANCH_RE),
        ]:
            if not pattern.match(val):
                print(f"[merge-gate] Error: 不正な{name}: {val!r}", file=sys.stderr)
                return 1

        gate = MergeGate(
            issue=parsed.issue,
            pr_number=parsed.pr_number,
            branch=parsed.branch,
            force=parsed.force,
        )
        try:
            gate.execute()
        except MergeGateError as e:
            print(f"[merge-gate-execute] ERROR: {e}", file=sys.stderr)
            return 1
        return 0

    # Legacy env-var mode (backward compatible)
    try:
        gate = MergeGate.from_env()
    except MergeGateError as e:
        print(f"[merge-gate-execute] Error: {e}", file=sys.stderr)
        return 1

    mode = args[0] if args else "merge"

    try:
        if mode == "--reject":
            gate.reject()
        elif mode == "--reject-final":
            gate.reject_final()
        else:
            gate.execute()
    except MergeGateError as e:
        print(f"[merge-gate-execute] ERROR: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
