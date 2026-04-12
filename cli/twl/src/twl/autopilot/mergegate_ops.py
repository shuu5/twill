"""MergeGate internal operations mixin — GitHub, git, and cleanup methods.

Extracted from mergegate.py to keep module size manageable (Phase B).
MergeGateOperationsMixin is inherited by MergeGate; all methods here require
MergeGate instance attributes (self.issue, self.branch, etc.).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from twl.autopilot.mergegate_guards import MergeGateError, _state_write
from twl.autopilot.worktree import WorktreeManager


class MergeGateOperationsMixin:
    """Internal operations for MergeGate: GitHub, git checks, and cleanup.

    All methods require MergeGate instance attributes:
        self.issue, self.branch, self.pr_number, self.scripts_root,
        self.autopilot_dir, self.repo_owner, self.repo_name
    """

    # ------------------------------------------------------------------
    # GitHub helpers
    # ------------------------------------------------------------------

    def _get_issue_labels(self) -> list[str]:
        """Return list of label names for this issue. Returns [] on error."""
        gh_repo_flag = self._gh_repo_flag()  # type: ignore[attr-defined]
        result = subprocess.run(
            ["gh", "issue", "view", self.issue, *gh_repo_flag,  # type: ignore[attr-defined]
             "--json", "labels", "-q", "[.labels[].name]"],
            capture_output=True, text=True,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return []
        try:
            return json.loads(result.stdout.strip())
        except (json.JSONDecodeError, TypeError):
            return []

    def _gh_issue_state(self, gh_repo_flag: list[str]) -> str:
        """Return GitHub Issue state ('OPEN', 'CLOSED', or '' on error)."""
        result = subprocess.run(
            ["gh", "issue", "view", self.issue, *gh_repo_flag,  # type: ignore[attr-defined]
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
                f"[merge-gate] Issue #{self.issue}: "  # type: ignore[attr-defined]
                f"⚠️ Issue 状態取得失敗 — close 確認をスキップ",
                file=sys.stderr,
            )
            return True

        # OPEN — 明示的 close を試行
        print(
            f"[merge-gate] Issue #{self.issue}: "  # type: ignore[attr-defined]
            f"PR merge 後も Issue が OPEN — 明示的 close を試行"
        )
        result = subprocess.run(
            ["gh", "issue", "close", self.issue, *gh_repo_flag],  # type: ignore[attr-defined]
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(
                f"[merge-gate] Issue #{self.issue}: "  # type: ignore[attr-defined]
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
            ["gh", "pr", "view", self.pr_number, *gh_repo_flag,  # type: ignore[attr-defined]
             "--json", "body", "-q", ".body"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            return  # 取得失敗時は既存挙動維持
        body = result.stdout.rstrip("\n")
        closes_pattern = re.compile(
            rf"\b(Closes|Fixes|Resolves)\s+#{re.escape(self.issue)}\b",  # type: ignore[attr-defined]
            re.IGNORECASE,
        )
        if closes_pattern.search(body):
            return  # 既に存在
        new_body = f"{body}\n\nCloses #{self.issue}\n"  # type: ignore[attr-defined]
        edit_result = subprocess.run(
            ["gh", "pr", "edit", self.pr_number, *gh_repo_flag,  # type: ignore[attr-defined]
             "--body", new_body],
            capture_output=True, text=True,
        )
        if edit_result.returncode == 0:
            print(
                f"[merge-gate] Issue #{self.issue}: "  # type: ignore[attr-defined]
                f"PR #{self.pr_number} 本文に Closes #{self.issue} を機械的に追記"  # type: ignore[attr-defined]
            )
        else:
            print(
                f"[merge-gate] Issue #{self.issue}: "  # type: ignore[attr-defined]
                f"⚠️ PR 本文への Closes 追記失敗（merge は継続）: "
                f"{edit_result.stderr.strip()}",
                file=sys.stderr,
            )

    # ------------------------------------------------------------------
    # Pre-merge checks
    # ------------------------------------------------------------------

    def _check_base_drift(self) -> None:
        """Detect silent file deletions caused by worker base staleness."""
        if os.environ.get("MERGE_GATE_SKIP_DRIFT_CHECK") == "1":
            print(
                f"[merge-gate] Issue #{self.issue}: ⚠️ "  # type: ignore[attr-defined]
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
            elif line == f"branch refs/heads/{self.branch}":  # type: ignore[attr-defined]
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
             "origin/main", self.branch],  # type: ignore[attr-defined]
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
            f"[merge-gate] Issue #{self.issue}: deps.yaml コンフリクト検出 - 自動 rebase を試行",  # type: ignore[attr-defined]
            file=sys.stderr,
        )

        worktree_path = self._find_worktree_path()
        if not worktree_path:
            print(
                f"[merge-gate] Issue #{self.issue}: ⚠️ worktree が見つかりません - rebase をスキップ",  # type: ignore[attr-defined]
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
                "pr": f"#{self.pr_number}",  # type: ignore[attr-defined]
            })
            _state_write(self.issue, "pilot", status="conflict", failure=failure)  # type: ignore[attr-defined]
            print(
                f"[merge-gate] Issue #{self.issue}: rebase 失敗 - status=conflict に遷移。"  # type: ignore[attr-defined]
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
                "pr": f"#{self.pr_number}",  # type: ignore[attr-defined]
            })
            _state_write(self.issue, "pilot", status="conflict", failure=failure)  # type: ignore[attr-defined]
            print(
                f"[merge-gate] Issue #{self.issue}: rebase 後 push 失敗 - status=conflict に遷移",  # type: ignore[attr-defined]
                file=sys.stderr,
            )
            sys.exit(1)

        # Re-validate after rebase
        twl_path = self.scripts_root.parent / "twl" / "twl"  # type: ignore[attr-defined]
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
                    "pr": f"#{self.pr_number}",  # type: ignore[attr-defined]
                })
                _state_write(self.issue, "pilot", status="conflict", failure=failure)  # type: ignore[attr-defined]
                print(
                    f"[merge-gate] Issue #{self.issue}: rebase 後 twl --check 失敗 - status=conflict に遷移",  # type: ignore[attr-defined]
                    file=sys.stderr,
                )
                sys.exit(1)

        print(
            f"[merge-gate] Issue #{self.issue}: deps.yaml 自動 rebase 成功 - merge を続行",  # type: ignore[attr-defined]
        )

    # ------------------------------------------------------------------
    # Merge execution and cleanup
    # ------------------------------------------------------------------

    def _run_merge(self, gh_repo_flag: list[str]) -> bool:
        """Execute gh pr merge --squash. Returns True on success."""
        result = subprocess.run(
            ["gh", "pr", "merge", self.pr_number, *gh_repo_flag, "--squash"],  # type: ignore[attr-defined]
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
                "pr": f"#{self.pr_number}",  # type: ignore[attr-defined]
            })
            _state_write(self.issue, "pilot", status="conflict", failure=failure)  # type: ignore[attr-defined]
            print(
                f"[merge-gate] Issue #{self.issue}: コンフリクト検出 - "  # type: ignore[attr-defined]
                f"Pilot がリベース→push 後に status=merge-ready に戻してリトライ可能",
                file=sys.stderr,
            )
        else:
            failure = json.dumps({
                "reason": "merge_failed",
                "details": raw_err,
                "step": "merge-gate",
                "pr": f"#{self.pr_number}",  # type: ignore[attr-defined]
            })
            _state_write(self.issue, "pilot", status="failed", failure=failure)  # type: ignore[attr-defined]
            print(
                f"[merge-gate] Issue #{self.issue}: マージ失敗 - {raw_err}",  # type: ignore[attr-defined]
                file=sys.stderr,
            )
        return False

    def _post_merge_cleanup(self, repo_mode: str, autopilot_status: str) -> None:
        """Clean up worktree/branch after successful merge (non-autopilot path only)."""
        issue_json = self.autopilot_dir / "issues" / f"issue-{self.issue}.json"  # type: ignore[attr-defined]
        if issue_json.exists():
            print(
                f"[merge-gate] Issue #{self.issue}: "  # type: ignore[attr-defined]
                f"autopilot 検出 — クリーンアップを Pilot へ委譲"
            )
            return

        # Non-autopilot: perform cleanup
        if repo_mode == "worktree":
            self._remove_worktree()
            self._delete_remote_branch()
        else:
            self._delete_remote_branch()
            subprocess.run(["git", "branch", "-D", self.branch], check=False)  # type: ignore[attr-defined]

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
            elif line == f"branch refs/heads/{self.branch}":  # type: ignore[attr-defined]
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
                print(f"[merge-gate] Issue #{self.issue}: worktree 削除成功: {worktree_path}")  # type: ignore[attr-defined]
            else:
                print(
                    f"[merge-gate] Issue #{self.issue}: "  # type: ignore[attr-defined]
                    f"⚠️ worktree 削除失敗（マージは成功）: {worktree_path}",
                    file=sys.stderr,
                )

    def _delete_remote_branch(self) -> None:
        r = subprocess.run(
            ["git", "push", "origin", "--delete", self.branch],  # type: ignore[attr-defined]
            capture_output=True,
        )
        if r.returncode == 0:
            print(f"[merge-gate] Issue #{self.issue}: リモートブランチ削除成功: {self.branch}")  # type: ignore[attr-defined]
        else:
            print(
                f"[merge-gate] Issue #{self.issue}: "  # type: ignore[attr-defined]
                f"⚠️ リモートブランチ削除失敗（マージは成功）: {self.branch}",  # type: ignore[attr-defined]
                file=sys.stderr,
            )

    def _kill_worker_window(self) -> None:
        subprocess.run(
            ["tmux", "kill-window", "-t", f"ap-#{self.issue}"],  # type: ignore[attr-defined]
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
