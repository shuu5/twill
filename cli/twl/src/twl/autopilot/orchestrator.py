"""Phase execution orchestrator for autopilot.

Replaces: autopilot-orchestrator.sh

CLI usage:
    python3 -m twl.autopilot.orchestrator \\
        --plan FILE --phase N --session FILE \\
        --project-dir DIR --autopilot-dir DIR [--repos JSON]

    python3 -m twl.autopilot.orchestrator \\
        --summary --session FILE --autopilot-dir DIR
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MAX_PARALLEL = int(os.environ.get("DEV_AUTOPILOT_MAX_PARALLEL", "4"))
MAX_POLL = int(os.environ.get("DEV_AUTOPILOT_MAX_POLL", "360"))
MAX_NUDGE = int(os.environ.get("DEV_AUTOPILOT_MAX_NUDGE", "3"))
NUDGE_TIMEOUT = int(os.environ.get("DEV_AUTOPILOT_NUDGE_TIMEOUT", "30"))
POLL_INTERVAL = 10

_BRANCH_RE = re.compile(r"^[a-zA-Z0-9._/\-]+$")


class OrchestratorError(Exception):
    pass


# ---------------------------------------------------------------------------
# Issue reference helpers
# ---------------------------------------------------------------------------

def _parse_issue_entry(entry: str) -> tuple[str, str]:
    """Parse 'repo_id:number' → (repo_id, number)."""
    if ":" in entry:
        parts = entry.split(":", 1)
        return parts[0], parts[1]
    return "_default", entry


def _window_name(repo_id: str, issue_num: str) -> str:
    if repo_id == "_default":
        return f"ap-#{issue_num}"
    return f"ap-{repo_id}-#{issue_num}"


# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

def _read_state(
    issue: str,
    field: str,
    autopilot_dir: str,
    repo_id: str = "",
) -> str:
    cmd = [
        sys.executable, "-m", "twl.autopilot.state",
        "read", "--type", "issue", "--issue", issue, "--field", field,
    ]
    if repo_id and repo_id != "_default":
        cmd += ["--repo", repo_id]
    r = subprocess.run(
        cmd,
        capture_output=True, text=True,
        env={**os.environ, "AUTOPILOT_DIR": autopilot_dir},
    )
    return r.stdout.strip() if r.returncode == 0 else ""


def _write_state(
    issue: str,
    role: str,
    sets: list[str],
    autopilot_dir: str,
    repo_id: str = "",
) -> None:
    cmd = [
        sys.executable, "-m", "twl.autopilot.state",
        "write", "--type", "issue", "--issue", issue, "--role", role,
    ]
    for kv in sets:
        cmd += ["--set", kv]
    if repo_id and repo_id != "_default":
        cmd += ["--repo", repo_id]
    subprocess.run(
        cmd,
        capture_output=True,
        env={**os.environ, "AUTOPILOT_DIR": autopilot_dir},
    )


# ---------------------------------------------------------------------------
# Plan parsing
# ---------------------------------------------------------------------------

def get_phase_issues(phase: int, plan_file: str) -> list[str]:
    """Parse plan.yaml and return list of 'repo_id:number' entries for phase."""
    content = Path(plan_file).read_text(encoding="utf-8")
    entries: list[str] = []

    # Find phase block
    phase_pattern = re.compile(rf"^\s+- phase: {phase}\s*$", re.MULTILINE)
    next_phase_pattern = re.compile(r"^\s+- phase: \d+\s*$", re.MULTILINE)

    m = phase_pattern.search(content)
    if not m:
        return entries

    block_start = m.end()
    # Find next phase or end of file
    m2 = next_phase_pattern.search(content, block_start)
    block_end = m2.start() if m2 else len(content)
    block = content[block_start:block_end]

    # Cross-repo format: { number: N, repo: repo_id }
    cross_re = re.compile(r"\{\s*number:\s*(\d+),\s*repo:\s*([a-zA-Z0-9_-]+)\s*\}")
    for cm in cross_re.finditer(block):
        num, repo_id = cm.group(1), cm.group(2)
        entries.append(f"{repo_id}:{num}")

    # Legacy format: bare integer  "    - N"
    bare_re = re.compile(r"^\s{4}-\s+(\d+)\s*$", re.MULTILINE)
    for bm in bare_re.finditer(block):
        entries.append(f"_default:{bm.group(1)}")

    return entries


def resolve_repos_config(repos_json: str) -> dict[str, dict[str, str]]:
    if not repos_json:
        return {}
    try:
        return json.loads(repos_json)
    except json.JSONDecodeError:
        return {}


# ---------------------------------------------------------------------------
# Phase orchestrator
# ---------------------------------------------------------------------------

class PhaseOrchestrator:
    def __init__(
        self,
        plan_file: str,
        phase: int,
        session_file: str,
        project_dir: str,
        autopilot_dir: str,
        repos_json: str = "",
        scripts_root: Path | None = None,
    ) -> None:
        self.plan_file = plan_file
        self.phase = phase
        self.session_file = session_file
        self.project_dir = project_dir
        self.autopilot_dir = autopilot_dir
        self.repos = resolve_repos_config(repos_json)
        self.repos_json = repos_json
        self.scripts_root = scripts_root or self._detect_scripts_root()

        self._nudge_counts: dict[str, int] = {}
        self._last_output_hash: dict[str, str] = {}
        self._health_check_counter: dict[str, int] = {}
        # skipped_archives: fail-closed で archive を skip した Issue 番号（Issue #138）
        self._skipped_archives: list[int] = []

    def run(self) -> dict[str, Any]:
        """Execute phase. Returns phase report dict."""
        os.makedirs(f"{self.autopilot_dir}/logs", exist_ok=True)
        print(f"[orchestrator] Phase {self.phase} 開始", file=sys.stderr)

        # Step 1: Get issue list
        all_entries = get_phase_issues(self.phase, self.plan_file)

        if not all_entries:
            print(f"[orchestrator] Phase {self.phase}: Issue なし", file=sys.stderr)
            return self._generate_phase_report([])

        # Step 2: Filter active issues
        active_entries = self._filter_active(all_entries)

        if not active_entries:
            print(f"[orchestrator] Phase {self.phase}: 全 Issue が skip/done", file=sys.stderr)
            all_nums = [_parse_issue_entry(e)[1] for e in all_entries]
            # 先に archive を実行して skipped_archives を集約してからレポート生成（Issue #138）
            self._archive_done_issues(all_nums)
            report = self._generate_phase_report(all_nums)
            return report

        # Step 3: Batch execution
        total = len(active_entries)
        for batch_start in range(0, total, MAX_PARALLEL):
            batch = active_entries[batch_start:batch_start + MAX_PARALLEL]
            self._run_batch(batch)

        # Step 4: Archive (先に archive して skipped_archives を集約)
        all_nums = [_parse_issue_entry(e)[1] for e in all_entries]
        self._archive_done_issues(all_nums)

        # Step 5: Generate report (skipped_archives を含む)
        report = self._generate_phase_report(all_nums)
        return report

    def _filter_active(self, entries: list[str]) -> list[str]:
        active: list[str] = []
        for entry in entries:
            repo_id, issue = _parse_issue_entry(entry)
            status = _read_state(issue, "status", self.autopilot_dir, repo_id)

            if status == "done":
                print(f"[orchestrator] Issue #{issue}: skip (already done)", file=sys.stderr)
                continue

            # Check if should skip (dependency failed)
            skip_result = subprocess.run(
                ["bash", str(self.scripts_root / "autopilot-should-skip.sh"),
                 self.plan_file, issue],
                capture_output=True,
            )
            if skip_result.returncode == 0:
                print(f"[orchestrator] Issue #{issue}: skip (dependency failed)", file=sys.stderr)
                _write_state(issue, "pilot",
                             ["status=failed",
                              'failure={"message":"dependency_failed","step":"skip"}'],
                             self.autopilot_dir, repo_id)
                continue

            active.append(entry)
        return active

    def _run_batch(self, batch: list[str]) -> None:
        launched: list[str] = []

        for entry in batch:
            repo_id, issue = _parse_issue_entry(entry)
            status = _read_state(issue, "status", self.autopilot_dir, repo_id)
            if status == "done":
                continue

            print(f"[orchestrator] Issue #{issue}: Worker 起動", file=sys.stderr)
            if self._launch_worker(entry):
                launched.append(entry)

        if not launched:
            return

        # Poll
        if len(launched) == 1:
            self._poll_single(launched[0])
        else:
            self._poll_phase(launched)

        # merge-gate for merge-ready issues
        for entry in launched:
            repo_id, issue = _parse_issue_entry(entry)
            status = _read_state(issue, "status", self.autopilot_dir, repo_id)
            if status == "merge-ready":
                self._run_merge_gate(entry)
                # Post-merge cleanup
                status_after = _read_state(issue, "status", self.autopilot_dir, repo_id)
                retry = _read_state(issue, "retry_count", self.autopilot_dir, repo_id)
                failure_reason = _read_state(issue, "failure.reason", self.autopilot_dir, repo_id)
                if status_after == "done":
                    self._cleanup_worker(issue, entry)
                elif status_after == "failed":
                    if int(retry or "0") >= 1 or failure_reason == "merge_gate_rejected_final":
                        self._cleanup_worker(issue, entry)

    def _launch_worker(self, entry: str) -> bool:
        """Launch worker for entry. Returns True on success."""
        repo_id, issue = _parse_issue_entry(entry)

        effective_dir = self.project_dir
        repo_info = self.repos.get(repo_id, {})
        repo_path = repo_info.get("path", "")
        if repo_path:
            effective_dir = repo_path

        # Find or create worktree
        worktree_dir = ""
        existing_branch = _read_state(issue, "branch", self.autopilot_dir, repo_id)
        if existing_branch and _BRANCH_RE.match(existing_branch):
            candidate = Path(effective_dir) / "worktrees" / existing_branch
            if candidate.is_dir():
                worktree_dir = str(candidate)
                print(f"[orchestrator] Issue #{issue}: 既存 worktree を使用: {worktree_dir}", file=sys.stderr)

        if not worktree_dir:
            create_args = [f"#{issue}"]
            if repo_path:
                create_args += ["--repo-path", repo_path]
            repo_owner = repo_info.get("owner", "")
            repo_name = repo_info.get("name", "")
            if repo_owner and repo_name:
                create_args += ["-R", f"{repo_owner}/{repo_name}"]

            r = subprocess.run(
                ["python3", "-m", "twl.autopilot.worktree", "create"] + create_args,
                capture_output=True, text=True,
            )
            if r.returncode == 0:
                for line in r.stdout.splitlines():
                    if line.startswith("パス: "):
                        worktree_dir = line[len("パス: "):].strip()
                        break
            if not worktree_dir or not worktree_dir.startswith("/") or not Path(worktree_dir).is_dir():
                print(f"[orchestrator] Issue #{issue}: worktree 作成失敗", file=sys.stderr)
                _write_state(issue, "pilot",
                             ["status=failed",
                              'failure={"message":"worktree_create_failed","step":"launch_worker"}'],
                             self.autopilot_dir, repo_id)
                return False
            print(f"[orchestrator] Issue #{issue}: worktree 作成完了: {worktree_dir}", file=sys.stderr)

        launch_args = [
            "--issue", issue,
            "--project-dir", self.project_dir,
            "--autopilot-dir", self.autopilot_dir,
            "--worktree-dir", worktree_dir,
        ]
        repo_owner = repo_info.get("owner", "")
        repo_name = repo_info.get("name", "")
        if repo_owner and repo_name:
            launch_args += ["--repo-owner", repo_owner, "--repo-name", repo_name]
        if repo_path:
            launch_args += ["--repo-path", repo_path]

        r = subprocess.run(
            ["bash", str(self.scripts_root / "autopilot-launch.sh")] + launch_args,
        )
        return r.returncode == 0

    def _poll_single(self, entry: str) -> None:
        repo_id, issue = _parse_issue_entry(entry)
        wname = _window_name(repo_id, issue)
        poll_count = 0

        while True:
            time.sleep(POLL_INTERVAL)
            poll_count += 1

            status = _read_state(issue, "status", self.autopilot_dir, repo_id)

            if status == "done":
                print(f"[orchestrator] Issue #{issue}: 完了", file=sys.stderr)
                self._cleanup_worker(issue, entry)
                return
            elif status == "failed":
                print(f"[orchestrator] Issue #{issue}: 失敗", file=sys.stderr)
                self._cleanup_worker(issue, entry)
                return
            elif status == "merge-ready":
                print(f"[orchestrator] Issue #{issue}: merge-ready", file=sys.stderr)
                return
            elif status == "running":
                if self._is_crashed(issue, wname):
                    print(f"[orchestrator] Issue #{issue}: ワーカークラッシュ検知", file=sys.stderr)
                    return
                self._check_and_nudge(issue, wname, entry)

            if poll_count >= MAX_POLL:
                print(f"[orchestrator] Issue #{issue}: タイムアウト", file=sys.stderr)
                _write_state(issue, "pilot",
                             ["status=failed",
                              'failure={"message":"poll_timeout","step":"polling"}'],
                             self.autopilot_dir, repo_id)
                self._cleanup_worker(issue, entry)
                return

    def _poll_phase(self, entries: list[str]) -> None:
        poll_count = 0
        cleaned_up: set[str] = set()

        while True:
            all_resolved = True

            for entry in entries:
                repo_id, issue = _parse_issue_entry(entry)
                status = _read_state(issue, "status", self.autopilot_dir, repo_id)
                wname = _window_name(repo_id, issue)

                if status in ("done", "failed"):
                    if entry not in cleaned_up:
                        self._cleanup_worker(issue, entry)
                        cleaned_up.add(entry)
                    continue
                elif status == "merge-ready":
                    continue
                elif status == "running":
                    all_resolved = False
                    if self._is_crashed(issue, wname):
                        print(f"[orchestrator] Issue #{issue}: ワーカークラッシュ検知", file=sys.stderr)
                        _write_state(issue, "pilot",
                                     ["status=failed",
                                      'failure={"message":"worker_crashed","step":"polling"}'],
                                     self.autopilot_dir, repo_id)
                        if entry not in cleaned_up:
                            self._cleanup_worker(issue, entry)
                            cleaned_up.add(entry)
                        continue
                    self._check_and_nudge(issue, wname, entry)
                else:
                    all_resolved = False

            if all_resolved:
                break

            poll_count += 1
            if poll_count >= MAX_POLL:
                print("[orchestrator] Phase: タイムアウト", file=sys.stderr)
                for entry in entries:
                    repo_id, issue = _parse_issue_entry(entry)
                    s = _read_state(issue, "status", self.autopilot_dir, repo_id)
                    if s == "running":
                        _write_state(issue, "pilot",
                                     ["status=failed",
                                      'failure={"message":"poll_timeout","step":"polling"}'],
                                     self.autopilot_dir, repo_id)
                        self._cleanup_worker(issue, entry)
                break

            time.sleep(POLL_INTERVAL)

    def _is_crashed(self, issue: str, window_name: str) -> bool:
        r = subprocess.run(
            ["bash", str(self.scripts_root / "crash-detect.sh"),
             "--issue", issue, "--window", window_name],
            capture_output=True,
        )
        return r.returncode == 2

    def _check_and_nudge(self, issue: str, window_name: str, entry: str) -> bool:
        count = self._nudge_counts.get(issue, 0)
        if count >= MAX_NUDGE:
            return False

        # Check last_hook_nudge_at for conflict prevention
        last_hook = _read_state(issue, "last_hook_nudge_at", self.autopilot_dir)
        if last_hook:
            try:
                dt = datetime.fromisoformat(last_hook.replace("Z", "+00:00"))
                elapsed = int((datetime.now(timezone.utc) - dt).total_seconds())
                if elapsed < NUDGE_TIMEOUT:
                    return False
            except Exception:
                pass

        # Capture pane output
        r = subprocess.run(
            ["tmux", "capture-pane", "-t", window_name, "-p", "-S", "-5"],
            capture_output=True, text=True,
        )
        pane_output = r.stdout if r.returncode == 0 else ""
        if not pane_output:
            return False

        current_hash = hashlib.md5(pane_output.encode()).hexdigest()
        last_hash = self._last_output_hash.get(issue, "")

        if current_hash != last_hash:
            self._last_output_hash[issue] = current_hash
            return False

        # Same output — check for stop patterns
        next_cmd = self._nudge_command_for_pattern(pane_output, issue, entry)
        if next_cmd is None:
            self._last_output_hash[issue] = current_hash
            return False

        print(f"[orchestrator] Issue #{issue}: chain 遷移停止検知 — nudge ({count}/{MAX_NUDGE})", file=sys.stderr)
        subprocess.run(
            ["tmux", "send-keys", "-t", window_name, next_cmd, "Enter"],
            capture_output=True,
        )
        self._nudge_counts[issue] = count + 1
        self._last_output_hash[issue] = current_hash
        return True

    def _nudge_command_for_pattern(self, pane_output: str, issue: str, entry: str) -> str | None:
        """Return nudge command for detected stop pattern, or None if no pattern matches."""
        is_quick = _read_state(issue, "is_quick", self.autopilot_dir) == "true"

        if is_quick:
            if re.search(r"setup chain 完了|workflow-test-ready.*で次に進めます", pane_output):
                return None

        if re.search(r"setup chain 完了", pane_output):
            return f"/twl:workflow-test-ready #{issue}"
        elif re.search(r">>> 提案完了", pane_output):
            return ""
        elif re.search(r"テスト準備.*完了", pane_output):
            return f"/twl:workflow-pr-verify #{issue}"
        elif re.search(r"workflow-pr-verify.*完了", pane_output):
            return f"/twl:workflow-pr-fix #{issue}"
        elif re.search(r"workflow-pr-fix.*完了", pane_output):
            return f"/twl:workflow-pr-merge #{issue}"
        elif re.search(r"PR マージ.*完了|workflow-pr-merge.*完了", pane_output):
            return ""
        elif re.search(r"workflow-test-ready.*で次に進めます", pane_output):
            return f"/twl:workflow-test-ready #{issue}"

        return None

    def _run_merge_gate(self, entry: str) -> None:
        repo_id, issue = _parse_issue_entry(entry)

        pr_number = _read_state(issue, "pr_number", self.autopilot_dir, repo_id)
        branch = _read_state(issue, "branch", self.autopilot_dir, repo_id)

        if not pr_number or not branch:
            print(f"[orchestrator] Issue #{issue}: PR 番号またはブランチが取得できません", file=sys.stderr)
            return

        print(f"[orchestrator] Issue #{issue}: merge-gate 実行 (PR #{pr_number})", file=sys.stderr)

        env = {**os.environ, "ISSUE": issue, "PR_NUMBER": pr_number, "BRANCH": branch}
        r = subprocess.run(
            ["bash", str(self.scripts_root / "merge-gate-execute.sh")],
            env=env,
        )
        if r.returncode == 0:
            print(f"[orchestrator] Issue #{issue}: merge 成功", file=sys.stderr)
        else:
            print(f"[orchestrator] Issue #{issue}: merge 失敗", file=sys.stderr)

    def _cleanup_worker(self, issue: str, entry: str) -> None:
        repo_id, _ = _parse_issue_entry(entry)
        window_name = _window_name(repo_id, issue)
        print(f"[orchestrator] cleanup: Issue #{issue} — window/branch クリーンアップ", file=sys.stderr)

        # Kill tmux window first
        subprocess.run(["tmux", "kill-window", "-t", window_name], capture_output=True)

        # Determine repo mode
        git_dir_r = subprocess.run(
            ["git", "rev-parse", "--git-dir"],
            capture_output=True, text=True,
        )
        git_dir = git_dir_r.stdout.strip()
        repo_mode = "standard" if git_dir == ".git" or not git_dir else "worktree"

        branch = _read_state(issue, "branch", self.autopilot_dir, repo_id)
        if branch and _BRANCH_RE.match(branch):
            if repo_mode == "worktree":
                subprocess.run(
                    ["bash", str(self.scripts_root / "worktree-delete.sh"), branch],
                    capture_output=True,
                )
            # Delete remote branch
            repo_info = self.repos.get(repo_id, {})
            repo_path = repo_info.get("path", "")
            if repo_path and repo_path.startswith("/") and ".." not in repo_path:
                subprocess.run(
                    ["git", "-C", repo_path, "push", "origin", "--delete", branch],
                    capture_output=True,
                )
            else:
                subprocess.run(
                    ["git", "push", "origin", "--delete", branch],
                    capture_output=True,
                )

    def _generate_phase_report(self, all_issue_nums: list[str]) -> dict[str, Any]:
        done: list[int] = []
        failed: list[int] = []
        skipped: list[int] = []
        changed_files: list[str] = []

        for issue in all_issue_nums:
            status = _read_state(issue, "status", self.autopilot_dir)
            if status == "done":
                done.append(int(issue))
                cf = _read_state(issue, "changed_files", self.autopilot_dir)
                if cf and cf != "null":
                    try:
                        changed_files.extend(json.loads(cf))
                    except (json.JSONDecodeError, ValueError):
                        try:
                            import ast
                            parsed = ast.literal_eval(cf)
                            if isinstance(parsed, list):
                                changed_files.extend(parsed)
                        except Exception:
                            pass
            elif status == "failed":
                failed.append(int(issue))
            else:
                skipped.append(int(issue))

        return {
            "signal": "PHASE_COMPLETE",
            "phase": self.phase,
            "results": {
                "done": done,
                "failed": failed,
                "skipped": skipped,
            },
            "skipped_archives": list(self._skipped_archives),
            "changed_files": changed_files,
        }

    def _gh_issue_state(self, issue: str) -> str:
        """Return GitHub Issue state ('OPEN' / 'CLOSED' / '' on failure).

        fail-closed helper: 呼び出し側は空文字 (取得失敗) を "CLOSED でない" として扱う。
        Issue #138: archive_done_issues の二重チェックで使用。
        """
        try:
            r = subprocess.run(
                ["gh", "issue", "view", issue, "--json", "state", "-q", ".state"],
                capture_output=True, text=True, timeout=30,
            )
            if r.returncode != 0:
                return ""
            return r.stdout.strip()
        except Exception:
            return ""

    def _archive_done_issues(self, issue_nums: list[str]) -> None:
        """Fail-closed archive: local status=done かつ GitHub state=CLOSED のみ archive.

        Issue #138: 空文字 (取得失敗) / OPEN は skip し、_skipped_archives に追加する。
        """
        for issue in issue_nums:
            status = _read_state(issue, "status", self.autopilot_dir)
            if status != "done":
                continue

            # NEW: GitHub Issue state 二重チェック (fail-closed)
            gh_state = self._gh_issue_state(issue)
            if gh_state != "CLOSED":
                if not gh_state:
                    print(
                        f"[orchestrator] Issue #{issue}: ⚠️ GitHub state 取得失敗 — fail-closed で archive をスキップ",
                        file=sys.stderr,
                    )
                else:
                    print(
                        f"[orchestrator] Issue #{issue}: ⚠️ ローカル state=done だが GitHub state={gh_state} — archive をスキップ",
                        file=sys.stderr,
                    )
                print(
                    f"[orchestrator] Issue #{issue}: 手動 close または autopilot state 修正が必要です",
                    file=sys.stderr,
                )
                try:
                    self._skipped_archives.append(int(issue))
                except ValueError:
                    pass
                continue

            subprocess.run(
                ["bash", str(self.scripts_root / "chain-runner.sh"),
                 "board-archive", issue],
                capture_output=True,
            )
            self._archive_deltaspec_changes(issue)

    def _archive_deltaspec_changes(self, issue: str) -> None:
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip()
        except Exception:
            return

        if not shutil.which("twl"):
            print(f"[orchestrator] Issue #{issue}: ⚠️ twl CLI が見つかりません", file=sys.stderr)
            return

        changes_dir = Path(root) / "deltaspec" / "changes"
        if not changes_dir.is_dir():
            return

        def _do_archive(change_id: str) -> None:
            r = subprocess.run(
                ["twl", "spec", "archive", "--yes", "--skip-specs", "--", change_id],
                capture_output=True,
            )
            if r.returncode == 0:
                print(f"[orchestrator] Issue #{issue}: DeltaSpec archive 完了: {change_id}")
            else:
                print(f"[orchestrator] Issue #{issue}: ⚠️ DeltaSpec archive 失敗: {change_id}", file=sys.stderr)

        found = False
        # 複数の change が一致する場合は全て archive する（1 issue に複数 change がある正規ケース）
        for yaml_path in changes_dir.rglob(".deltaspec.yaml"):
            content = yaml_path.read_text(encoding="utf-8")
            change_id = yaml_path.parent.name
            # プライマリ: issue: フィールドで検索
            if f"\nissue: {issue}\n" in content or content.startswith(f"issue: {issue}\n"):
                found = True
                _do_archive(change_id)
            # フォールバック1: name: issue-<N> フィールドで検索（issue フィールドなしの change 対応）
            elif f"\nname: issue-{issue}\n" in content or content.startswith(f"name: issue-{issue}\n"):
                found = True
                _do_archive(change_id)
            # フォールバック2: ディレクトリ名パターンで検索（name フィールドもない旧形式の change 対応）
            elif change_id == f"issue-{issue}":
                found = True
                _do_archive(change_id)

        if not found:
            print(f"[orchestrator] Issue #{issue}: DeltaSpec change が見つかりません", file=sys.stderr)

    def _detect_scripts_root(self) -> Path:
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip()
            return Path(root) / "plugins" / "twl" / "scripts"
        except Exception:
            return Path.cwd() / "plugins" / "twl" / "scripts"


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

def generate_summary(autopilot_dir: str) -> dict[str, Any]:
    issues_dir = Path(autopilot_dir) / "issues"
    if not issues_dir.is_dir():
        raise OrchestratorError("issues directory not found")

    done: list[int] = []
    failed: list[int] = []
    skipped: list[int] = []
    total = 0

    for issue_file in sorted(issues_dir.glob("issue-*.json")):
        if not issue_file.is_file():
            continue
        total += 1
        m = re.search(r"\d+", issue_file.name)
        if not m:
            continue
        issue_num = int(m.group())
        try:
            data = json.loads(issue_file.read_text(encoding="utf-8"))
            status = data.get("status", "unknown")
        except Exception:
            status = "unknown"

        if status == "done":
            done.append(issue_num)
        elif status == "failed":
            failed.append(issue_num)
        else:
            skipped.append(issue_num)

    return {
        "signal": "SUMMARY",
        "total": total,
        "results": {
            "done": {"count": len(done), "issues": done},
            "failed": {"count": len(failed), "issues": failed},
            "skipped": {"count": len(skipped), "issues": skipped},
        },
    }


# ---------------------------------------------------------------------------
# Path validation helper
# ---------------------------------------------------------------------------

def _validate_path(name: str, value: str) -> None:
    if not value.startswith("/"):
        raise OrchestratorError(f"--{name} は絶対パスで指定してください: {value}")
    if "/.." in value or value.endswith("/.."):
        raise OrchestratorError(f"--{name} にパストラバーサルは使用できません: {value}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {
        "plan": "", "phase": "", "session": "",
        "project_dir": "", "autopilot_dir": "", "repos": "",
        "summary": False,
    }
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print("Usage: python3 -m twl.autopilot.orchestrator [OPTIONS]")
            sys.exit(0)
        elif a in ("--plan", "--phase", "--session", "--project-dir", "--autopilot-dir", "--repos"):
            if i + 1 >= len(argv):
                print(f"Error: {a} には値が必要です", file=sys.stderr)
                sys.exit(1)
            if a == "--plan":
                args["plan"] = argv[i + 1]
            elif a == "--phase":
                args["phase"] = argv[i + 1]
            elif a == "--session":
                args["session"] = argv[i + 1]
            elif a == "--project-dir":
                args["project_dir"] = argv[i + 1]
            elif a == "--autopilot-dir":
                args["autopilot_dir"] = argv[i + 1]
            elif a == "--repos":
                args["repos"] = argv[i + 1]
            i += 2
        elif a == "--summary":
            args["summary"] = True; i += 1
        else:
            print(f"Error: 不明なオプション: {a}", file=sys.stderr)
            sys.exit(1)
    return args


def main(argv: list[str] | None = None) -> int:
    args_list = argv if argv is not None else sys.argv[1:]
    parsed = _parse_args(args_list)

    autopilot_dir = parsed["autopilot_dir"]

    try:
        if parsed["summary"]:
            if not parsed["session"] or not autopilot_dir:
                print("Error: --summary には --session と --autopilot-dir が必須です", file=sys.stderr)
                return 1
            _validate_path("session", parsed["session"])
            _validate_path("autopilot-dir", autopilot_dir)
            os.environ["AUTOPILOT_DIR"] = autopilot_dir

            result = generate_summary(autopilot_dir)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0

        # Phase execution mode
        plan = parsed["plan"]
        phase_str = parsed["phase"]
        session = parsed["session"]
        project_dir = parsed["project_dir"]

        if not plan or not phase_str or not session or not project_dir or not autopilot_dir:
            print("Error: --plan, --phase, --session, --project-dir, --autopilot-dir は必須です", file=sys.stderr)
            return 1

        if not re.match(r"^[1-9]\d*$", phase_str):
            print(f"Error: --phase は正の整数で指定してください: {phase_str}", file=sys.stderr)
            return 1

        for name, value in [("plan", plan), ("session", session),
                             ("project-dir", project_dir), ("autopilot-dir", autopilot_dir)]:
            _validate_path(name, value)

        os.environ["AUTOPILOT_DIR"] = autopilot_dir

        orchestrator = PhaseOrchestrator(
            plan_file=plan,
            phase=int(phase_str),
            session_file=session,
            project_dir=project_dir,
            autopilot_dir=autopilot_dir,
            repos_json=parsed["repos"],
        )
        report = orchestrator.run()
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0

    except OrchestratorError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
