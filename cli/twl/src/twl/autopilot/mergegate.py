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
import subprocess
import sys
from pathlib import Path
from typing import Any

from twl.autopilot.worktree import WorktreeManager


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

    def _gh_issue_state(self, gh_repo_flag: list[str]) -> str:
        """Return GitHub Issue state ('OPEN', 'CLOSED', or '' on error)."""
        result = subprocess.run(
            ["gh", "issue", "view", self.issue, *gh_repo_flag,
             "--json", "state", "-q", ".state"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            return ""
        return result.stdout.strip()

    def _verify_and_close_issue(self, gh_repo_flag: list[str]) -> bool:
        """Verify Issue is CLOSED on GitHub. Try to close if not.

        Returns True if Issue is CLOSED (or successfully closed, or state
        could not be queried — skip case preserves legacy behaviour).
        Returns False only if OPEN and close attempt failed.
        """
        state = self._gh_issue_state(gh_repo_flag)
        if state == "CLOSED":
            return True
        if state == "":
            # 取得失敗時は warning + True（既存挙動・gh 不在環境互換）
            print(
                f"[merge-gate] Issue #{self.issue}: "
                f"⚠️ Issue 状態取得失敗 — close 確認をスキップ",
                file=sys.stderr,
            )
            return True

        # OPEN — 明示的 close を試行
        print(
            f"[merge-gate] Issue #{self.issue}: "
            f"PR merge 後も Issue が OPEN — 明示的 close を試行"
        )
        result = subprocess.run(
            ["gh", "issue", "close", self.issue, *gh_repo_flag],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(
                f"[merge-gate] Issue #{self.issue}: "
                f"⚠️ gh issue close 失敗: {result.stderr.strip()}",
                file=sys.stderr,
            )
            return False

        # 再確認
        state_after = self._gh_issue_state(gh_repo_flag)
        return state_after == "CLOSED"

    def _ensure_closes_link(self, gh_repo_flag: list[str]) -> None:
        """Ensure PR body contains Closes #N before merge.

        Issue #136 — GitHub の auto-close は PR 本文 (body) に
        ``Closes|Fixes|Resolves #N`` がある場合のみ発火する。
        merge 直前に PR 本文を確認し、無ければ ``gh pr edit --body`` で
        機械的に追記する pre-merge fail-safe。

        本文取得失敗時は既存挙動を維持するためスキップ（warning も出さない）。
        """
        result = subprocess.run(
            ["gh", "pr", "view", self.pr_number, *gh_repo_flag,
             "--json", "body", "-q", ".body"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            return  # 取得失敗時は既存挙動維持
        body = result.stdout.rstrip("\n")
        closes_pattern = re.compile(
            rf"\b(Closes|Fixes|Resolves)\s+#{re.escape(self.issue)}\b",
            re.IGNORECASE,
        )
        if closes_pattern.search(body):
            return  # 既に存在
        new_body = f"{body}\n\nCloses #{self.issue}\n"
        edit_result = subprocess.run(
            ["gh", "pr", "edit", self.pr_number, *gh_repo_flag,
             "--body", new_body],
            capture_output=True, text=True,
        )
        if edit_result.returncode == 0:
            print(
                f"[merge-gate] Issue #{self.issue}: "
                f"PR #{self.pr_number} 本文に Closes #{self.issue} を機械的に追記"
            )
        else:
            print(
                f"[merge-gate] Issue #{self.issue}: "
                f"⚠️ PR 本文への Closes 追記失敗（merge は継続）: "
                f"{edit_result.stderr.strip()}",
                file=sys.stderr,
            )

    def _check_base_drift(self) -> None:
        """Detect silent file deletions caused by worker base staleness."""
        if os.environ.get("MERGE_GATE_SKIP_DRIFT_CHECK") == "1":
            print(
                f"[merge-gate] Issue #{self.issue}: ⚠️ "
                f"MERGE_GATE_SKIP_DRIFT_CHECK=1 で base drift 検知をスキップ",
                file=sys.stderr,
            )
            return
        fetch_result = subprocess.run(
            ["git", "fetch", "origin", "main"],
            check=False,
            capture_output=True,
        )
        if fetch_result.returncode != 0:
            return  # fail-open: ネットワーク断で merge が止まらないようにする
        diff_result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=D", "origin/main...HEAD"],
            capture_output=True,
            text=True,
        )
        if diff_result.returncode != 0:
            return
        deleted_files = [line for line in diff_result.stdout.splitlines() if line.strip()]
        if not deleted_files:
            return

        mb_result = subprocess.run(
            ["git", "merge-base", "HEAD", "origin/main"],
            capture_output=True,
            text=True,
        )
        if mb_result.returncode != 0:
            return
        merge_base = mb_result.stdout.strip()

        silent_deletions = []
        for path in deleted_files:
            # MUST: レンジを {merge_base}..HEAD に限定する。
            # 限定しないとリポジトリ全履歴の削除 commit を拾い、silent deletion を取りこぼす。
            log_result = subprocess.run(
                ["git", "log", "--format=%H", "--diff-filter=D",
                 f"{merge_base}..HEAD", "--", path],
                capture_output=True,
                text=True,
            )
            if not log_result.stdout.strip():
                silent_deletions.append(path)

        if silent_deletions:
            paths_str = "\n  - " + "\n  - ".join(silent_deletions[:10])
            if len(silent_deletions) > 10:
                paths_str += f"\n  - ... and {len(silent_deletions) - 10} more"
            raise MergeGateError(
                f"base drift 検出: PR 内に削除 commit の無いファイルが "
                f"{len(silent_deletions)} 件含まれています。"
                f"`git rebase origin/main` → `git push --force-with-lease` を実行してください。"
                f"{paths_str}"
            )

    def _find_worktree_path(self) -> str:
        """Return the local worktree path for self.branch, or empty string if not found."""
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            capture_output=True, text=True,
        )
        current_wt = ""
        for line in result.stdout.splitlines():
            if line.startswith("worktree "):
                current_wt = line[len("worktree "):]
            elif line == f"branch refs/heads/{self.branch}":
                return current_wt
        return ""

    def _check_deps_yaml_conflict_and_rebase(self) -> None:
        """Detect deps.yaml conflict pre-merge and auto-rebase if needed. Issue #229.

        Uses git merge-tree to detect if merging self.branch into origin/main would
        produce a deps.yaml conflict. On conflict, attempts rebase in the branch's
        worktree (max 1 retry, consistent with invariant E). On rebase failure,
        transitions to conflict status.
        """
        # Fetch latest origin/main
        subprocess.run(
            ["git", "fetch", "origin", "main"],
            capture_output=True,
        )

        # Use git merge-tree to detect conflicts (git >= 2.38 write-tree mode)
        mt_result = subprocess.run(
            ["git", "merge-tree", "--write-tree", "--no-messages",
             "origin/main", self.branch],
            capture_output=True, text=True,
        )
        # Exit code 0 = clean merge, 1 = conflicts
        if mt_result.returncode == 0:
            return

        # Check if deps.yaml is among the conflicting files
        conflicted_files = mt_result.stderr or mt_result.stdout
        if "deps.yaml" not in conflicted_files:
            # Non-deps.yaml conflict: let _run_merge handle it normally
            return

        print(
            f"[merge-gate] Issue #{self.issue}: deps.yaml コンフリクト検出 - 自動 rebase を試行",
            file=sys.stderr,
        )

        worktree_path = self._find_worktree_path()
        if not worktree_path:
            print(
                f"[merge-gate] Issue #{self.issue}: ⚠️ worktree が見つかりません - rebase をスキップ",
                file=sys.stderr,
            )
            return

        # Attempt rebase in the branch's worktree
        rebase_result = subprocess.run(
            ["git", "-C", worktree_path, "rebase", "origin/main"],
            capture_output=True, text=True,
        )

        if rebase_result.returncode != 0:
            # Abort the failed rebase
            subprocess.run(
                ["git", "-C", worktree_path, "rebase", "--abort"],
                capture_output=True,
            )
            failure = json.dumps({
                "reason": "deps_yaml_rebase_failed",
                "details": rebase_result.stderr[:500],
                "step": "merge-gate-pre-rebase",
                "pr": f"#{self.pr_number}",
            })
            _state_write(self.issue, "pilot", status="conflict", failure=failure)
            print(
                f"[merge-gate] Issue #{self.issue}: rebase 失敗 - status=conflict に遷移。"
                f"手動で rebase → push 後に status=merge-ready に戻してリトライ可能",
                file=sys.stderr,
            )
            sys.exit(1)

        # Rebase succeeded: push the rebased branch
        push_result = subprocess.run(
            ["git", "-C", worktree_path, "push", "--force-with-lease"],
            capture_output=True, text=True,
        )
        if push_result.returncode != 0:
            failure = json.dumps({
                "reason": "deps_yaml_rebase_push_failed",
                "details": push_result.stderr[:500],
                "step": "merge-gate-pre-rebase",
                "pr": f"#{self.pr_number}",
            })
            _state_write(self.issue, "pilot", status="conflict", failure=failure)
            print(
                f"[merge-gate] Issue #{self.issue}: rebase 後 push 失敗 - status=conflict に遷移",
                file=sys.stderr,
            )
            sys.exit(1)

        # Re-validate after rebase
        twl_path = self.scripts_root.parent / "twl" / "twl"
        if twl_path.exists():
            check_result = subprocess.run(
                [str(twl_path), "--check"],
                capture_output=True, text=True,
                cwd=worktree_path,
            )
            if check_result.returncode != 0:
                failure = json.dumps({
                    "reason": "deps_yaml_rebase_check_failed",
                    "details": check_result.stdout[:500],
                    "step": "merge-gate-pre-rebase",
                    "pr": f"#{self.pr_number}",
                })
                _state_write(self.issue, "pilot", status="conflict", failure=failure)
                print(
                    f"[merge-gate] Issue #{self.issue}: rebase 後 twl --check 失敗 - status=conflict に遷移",
                    file=sys.stderr,
                )
                sys.exit(1)

        print(
            f"[merge-gate] Issue #{self.issue}: deps.yaml 自動 rebase 成功 - merge を続行",
        )

    def _run_merge(self, gh_repo_flag: list[str]) -> bool:
        """Execute gh pr merge --squash. Returns True on success."""
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

        # Detect merge conflict vs other failures
        is_conflict = any(
            kw in raw_err.lower()
            for kw in ("conflict", "not mergeable", "merge conflict")
        )

        if is_conflict:
            failure = json.dumps({
                "reason": "merge_conflict",
                "details": raw_err,
                "step": "merge-gate",
                "pr": f"#{self.pr_number}",
            })
            _state_write(self.issue, "pilot", status="conflict", failure=failure)
            print(
                f"[merge-gate] Issue #{self.issue}: コンフリクト検出 - "
                f"Pilot がリベース→push 後に status=merge-ready に戻してリトライ可能",
                file=sys.stderr,
            )
        else:
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
            # Run teardown hook before removing the worktree
            WorktreeManager.run_teardown_hook(Path(worktree_path))

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
            # Security: reject path traversal
            if ".." in p.parts:
                return Path(".autopilot")
            # Security: reject absolute paths that escape git root
            if p.is_absolute():
                try:
                    root = subprocess.check_output(
                        ["git", "rev-parse", "--show-toplevel"],
                        stderr=subprocess.DEVNULL,
                        text=True,
                    ).strip()
                    p.relative_to(root)  # raises ValueError if outside root
                except (subprocess.CalledProcessError, ValueError, OSError):
                    return Path(".autopilot")
            return p
        try:
            common_dir = subprocess.check_output(
                ["git", "rev-parse", "--git-common-dir"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            repo_root = Path(common_dir).resolve().parent
            return repo_root / ".autopilot"
        except Exception:
            return Path.cwd() / ".autopilot"

    @staticmethod
    def _detect_scripts_root() -> Path:
        try:
            common_dir = subprocess.check_output(
                ["git", "rev-parse", "--git-common-dir"],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
            repo_root = Path(common_dir).resolve().parent
            return repo_root / "plugins" / "twl" / "scripts"
        except Exception:
            return Path.cwd() / "scripts"


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
