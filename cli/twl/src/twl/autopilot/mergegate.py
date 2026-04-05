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
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

_ISSUE_RE = re.compile(r"^\d+$")
_PR_RE = re.compile(r"^\d+$")
_BRANCH_RE = re.compile(r"^[a-zA-Z0-9._/\-]+$")
_OWNER_RE = re.compile(r"^[a-zA-Z0-9_-]+$")
_REPO_RE = re.compile(r"^[a-zA-Z0-9_.-]+$")


class MergeGateError(Exception):
    """Raised for validation or execution errors."""


def _require_env(name: str, pattern: re.Pattern[str]) -> str:
    val = os.environ.get(name, "")
    if not pattern.match(val):
        raise MergeGateError(f"不正な{name}: {val!r}")
    return val


def _env_opt(name: str) -> str:
    return os.environ.get(name, "")


# ---------------------------------------------------------------------------
# State helpers (wraps python3 -m twl.autopilot.state)
# ---------------------------------------------------------------------------


def _state_write(issue: str, role: str, **kwargs: str) -> None:
    """Write autopilot state fields via twl.autopilot.state module."""
    cmd = [
        sys.executable, "-m", "twl.autopilot.state",
        "write",
        "--type", "issue",
        "--issue", issue,
        "--role", role,
    ]
    for k, v in kwargs.items():
        cmd += ["--set", f"{k}={v}"]
    subprocess.run(cmd, check=False)


def _state_read(issue: str, field: str) -> str:
    """Read a single autopilot state field."""
    result = subprocess.run(
        [sys.executable, "-m", "twl.autopilot.state",
         "read", "--type", "issue", "--issue", issue, "--field", field],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout.strip()
    return ""


# ---------------------------------------------------------------------------
# Guard helpers
# ---------------------------------------------------------------------------


def _check_worktree_guard(cwd: str) -> None:
    """Reject execution from within a worktree (invariant B/C)."""
    if "/worktrees/" in cwd:
        raise MergeGateError(
            "worktrees/ 配下からの実行は禁止されています。"
            "main/ worktree から実行してください（不変条件B/C）"
        )


def _check_worker_window_guard() -> None:
    """Reject execution from autopilot Worker tmux window (defense-in-depth)."""
    result = subprocess.run(
        ["tmux", "display-message", "-p", "#W"],
        capture_output=True, text=True,
    )
    window = result.stdout.strip() if result.returncode == 0 else ""
    if re.match(r"^ap-#\d+$", window):
        safe_window = re.sub(r"[^a-zA-Z0-9#_-]", "", window)
        raise MergeGateError(
            f"autopilot Worker（{safe_window}）からの merge 実行は禁止されています（不変条件C）"
        )


def _check_running_guard(autopilot_status: str) -> None:
    """Reject merge when status=running (Worker has not declared merge-ready)."""
    if autopilot_status == "running":
        raise MergeGateError(
            "status=running（merge-ready 未宣言）での merge 実行は禁止されています（不変条件C）"
        )


# ---------------------------------------------------------------------------
# Board status update helper
# ---------------------------------------------------------------------------


def _board_update(issue: str, scripts_root: Path, status: str = "Done") -> None:
    runner = scripts_root / "chain-runner.sh"
    if runner.exists():
        subprocess.run(
            ["bash", str(runner), "board-status-update", issue, status],
            check=False,
        )


# ---------------------------------------------------------------------------
# Repo mode detection
# ---------------------------------------------------------------------------


def _detect_repo_mode() -> str:
    """Return 'worktree' or 'standard' based on git dir type."""
    result = subprocess.run(
        ["git", "rev-parse", "--git-dir"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise MergeGateError("git リポジトリ外で実行されています")
    git_dir = result.stdout.strip()
    return "standard" if git_dir == ".git" else "worktree"


# ---------------------------------------------------------------------------
# MergeGate class
# ---------------------------------------------------------------------------


class MergeGate:
    """Manage merge-gate operations: merge, reject, reject-final.

    Mirrors the logic of merge-gate-execute.sh with the same environment
    variable contract and exit code behaviour.
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
        _check_running_guard(autopilot_status)

        repo_mode = _detect_repo_mode()
        gh_repo_flag = self._gh_repo_flag()

        print(
            f"[merge-gate] Issue #{self.issue}: "
            f"PR #{self.pr_number} のマージを実行... (REPO_MODE={repo_mode})"
        )

        merge_ok = self._run_merge(gh_repo_flag)
        if merge_ok:
            self._post_merge_cleanup(repo_mode, autopilot_status)
            _state_write(
                self.issue, "pilot",
                status="done",
                merged_at=self._now_iso(),
            )
            print(f"[merge-gate] Issue #{self.issue}: マージ完了")
            _board_update(self.issue, self.scripts_root, "Done")
        else:
            sys.exit(1)

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

    def _run_merge(self, gh_repo_flag: list[str]) -> bool:
        """Execute gh pr merge --squash. Returns True on success."""
        error_log = tempfile.NamedTemporaryFile(
            prefix="merge-error-", suffix=".log", delete=False, mode="w"
        )
        try:
            result = subprocess.run(
                ["gh", "pr", "merge", self.pr_number, *gh_repo_flag, "--squash"],
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                return True

            # Mask credentials in error
            raw_err = result.stderr
            raw_err = re.sub(r"ghp_[a-zA-Z0-9]+", "ghp_***MASKED***", raw_err)
            raw_err = re.sub(r"Bearer\s+\S+", "Bearer ***MASKED***", raw_err)
            raw_err = raw_err[:500]

            failure = json.dumps({
                "reason": "merge_failed",
                "details": raw_err,
                "step": "merge-gate",
                "pr": f"#{self.pr_number}",
            })
            _state_write(self.issue, "pilot", status="failed", failure=failure)
            print(
                f"[merge-gate] Issue #{self.issue}: マージ失敗 - {raw_err}",
                file=sys.stderr,
            )
            return False
        finally:
            error_log.close()
            Path(error_log.name).unlink(missing_ok=True)

    def _post_merge_cleanup(self, repo_mode: str, autopilot_status: str) -> None:
        """Clean up worktree/branch after successful merge (non-autopilot path only)."""
        issue_json = self.autopilot_dir / "issues" / f"issue-{self.issue}.json"
        if issue_json.exists():
            print(
                f"[merge-gate] Issue #{self.issue}: "
                f"autopilot 検出 — クリーンアップを Pilot へ委譲"
            )
            return

        # Non-autopilot: perform cleanup
        if repo_mode == "worktree":
            self._remove_worktree()
            self._delete_remote_branch()
        else:
            self._delete_remote_branch()
            subprocess.run(["git", "branch", "-D", self.branch], check=False)

        self._kill_worker_window()

    def _remove_worktree(self) -> None:
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            capture_output=True, text=True,
        )
        worktree_path = ""
        current_wt = ""
        for line in result.stdout.splitlines():
            if line.startswith("worktree "):
                current_wt = line[len("worktree "):]
            elif line == f"branch refs/heads/{self.branch}":
                worktree_path = current_wt
                break

        if worktree_path:
            r = subprocess.run(
                ["git", "worktree", "remove", "--force", worktree_path],
                capture_output=True,
            )
            if r.returncode == 0:
                print(f"[merge-gate] Issue #{self.issue}: worktree 削除成功: {worktree_path}")
            else:
                print(
                    f"[merge-gate] Issue #{self.issue}: "
                    f"⚠️ worktree 削除失敗（マージは成功）: {worktree_path}",
                    file=sys.stderr,
                )

    def _delete_remote_branch(self) -> None:
        r = subprocess.run(
            ["git", "push", "origin", "--delete", self.branch],
            capture_output=True,
        )
        if r.returncode == 0:
            print(f"[merge-gate] Issue #{self.issue}: リモートブランチ削除成功: {self.branch}")
        else:
            print(
                f"[merge-gate] Issue #{self.issue}: "
                f"⚠️ リモートブランチ削除失敗（マージは成功）: {self.branch}",
                file=sys.stderr,
            )

    def _kill_worker_window(self) -> None:
        subprocess.run(
            ["tmux", "kill-window", "-t", f"ap-#{self.issue}"],
            capture_output=True,
        )

    @staticmethod
    def _now_iso() -> str:
        from datetime import datetime, timezone
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    @staticmethod
    def _detect_autopilot_dir() -> Path:
        env = os.environ.get("AUTOPILOT_DIR", "")
        if env:
            p = Path(env)
            if ".." in p.parts:
                p = Path(".autopilot")
            return p
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            return Path(root) / ".autopilot"
        except Exception:
            return Path.cwd() / ".autopilot"

    @staticmethod
    def _detect_scripts_root() -> Path:
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            return Path(root) / "plugins" / "twl" / "scripts"
        except Exception:
            return Path.cwd() / "scripts"


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

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
