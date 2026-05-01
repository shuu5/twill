"""Worker launcher — spawn Worker (cld) in a tmux window.

Replaces: autopilot-launch.sh

CLI usage:
    python3 -m twl.autopilot.launcher --issue N --project-dir DIR --autopilot-dir DIR [OPTIONS]

Exit codes:
    0: Worker 起動成功
    1: バリデーションエラー
    2: 外部コマンド不在 (cld / tmux)
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


class LaunchError(Exception):
    """Raised for launch errors (exit code 1)."""


class LaunchDependencyError(Exception):
    """Raised when cld/tmux not found (exit code 2)."""


def _record_failure(
    issue: str,
    message: str,
    step: str,
    autopilot_dir: str,
    repo_id: str = "",
) -> None:
    """Record failure to issue state file."""
    failure_json = json.dumps({"message": message, "step": step})
    cmd = [
        sys.executable, "-m", "twl.autopilot.state",
        "write", "--type", "issue", "--issue", issue,
        "--role", "pilot",
        "--set", "status=failed",
        "--set", f"failure={failure_json}",
    ]
    if repo_id:
        cmd += ["--repo", repo_id]
    subprocess.run(
        cmd,
        capture_output=True,
        env={**os.environ, "AUTOPILOT_DIR": autopilot_dir},
    )


def _validate_absolute_path(name: str, value: str, issue: str, autopilot_dir: str, repo_id: str = "") -> None:
    if not value.startswith("/"):
        _record_failure(issue, f"invalid_{name.lower().replace('-','_')}", "launch_worker", autopilot_dir, repo_id)
        raise LaunchError(f"--{name} は絶対パスで指定してください: {value}")
    if "/.." in value or value.endswith("/.."):
        _record_failure(issue, f"invalid_{name.lower().replace('-','_')}", "launch_worker", autopilot_dir, repo_id)
        raise LaunchError(f"--{name} にパストラバーサルは使用できません: {value}")


_STATUS_GATE_LOG = os.environ.get(
    "STATUS_GATE_LOG",
    str(Path(tempfile.gettempdir()) / "refined-status-gate.log"),
)
_ALLOWED_STATUSES = {"Refined", "In Progress", "Done"}


_DUAL_WRITE_LOG = "/tmp/refined-dual-write.log"


def _log_gate_event(event: str) -> None:
    try:
        from datetime import datetime, timezone
        ts = datetime.now(timezone.utc).isoformat()
        with open(_STATUS_GATE_LOG, "a") as f:
            f.write(f"[{ts}] {event}\n")
    except Exception:
        pass


def _check_dual_write_log(issue_num: str) -> str | None:
    """Return actionable hint if label_add_failed found for issue_num, else None."""
    try:
        with open(_DUAL_WRITE_LOG, "r") as f:
            lines = f.readlines()[-200:]
    except (OSError, FileNotFoundError):
        return None
    search_key = f"issue=#{issue_num}"
    for line in reversed(lines):
        if search_key in line and "label_add_failed" in line:
            m = re.search(r"repo=(\S+)", line)
            repo = m.group(1) if m else "OWNER/REPO"
            return (
                f"\n[hint] label add 失敗が観測されています ({_DUAL_WRITE_LOG})。\n"
                f"対処: gh label create refined --repo {repo} --color 8B5CF6 を実行してから再 refine してください。"
            )
    return None


def _check_refined_status(issue: str, bypass: bool = False) -> None:
    """Check that Issue has Status=Refined (or allowed) before launching Worker.

    Uses gh issue view --json projectItems to fetch project Board status.
    Retry 3 times with exponential backoff on API failure.
    Falls back to refined label check for cross-repo / Board-unregistered issues.

    Raises LaunchError on deny.
    """
    if bypass:
        _log_gate_event(f"BYPASS issue=#{issue}")
        return

    max_attempts = 3
    delays = [1, 2, 4]
    project_items_raw = ""
    last_returncode = 0

    for attempt in range(max_attempts):
        result = subprocess.run(
            ["gh", "issue", "view", issue, "--json", "projectItems"],
            capture_output=True, text=True,
        )
        last_returncode = result.returncode
        if result.returncode == 0 and result.stdout.strip():
            project_items_raw = result.stdout
            break
        if attempt < max_attempts - 1:
            time.sleep(delays[attempt])

    def _label_fallback(issue_num: str) -> bool:
        r = subprocess.run(
            ["gh", "issue", "view", issue_num, "--json", "labels"],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            return False
        try:
            data = json.loads(r.stdout)
            return any(
                lb.get("name") == "refined"
                for lb in data.get("labels", [])
            )
        except (json.JSONDecodeError, AttributeError):
            return False

    if not project_items_raw:
        # API 障害（auth scope 不足等）→ label fallback 試行
        if _label_fallback(issue):
            _log_gate_event(f"ALLOW_LABEL_FALLBACK issue=#{issue}")
            return
        _log_gate_event(f"DENY_API_FAILURE issue=#{issue}")
        raise LaunchError(
            f"Issue #{issue}: GitHub API 障害により Status を取得できませんでした (3 回リトライ後)。\n"
            "  対処: gh auth refresh -s project を実行してから再試行してください。"
        )

    try:
        data = json.loads(project_items_raw)
        nodes = data.get("projectItems", {}).get("nodes", [])
    except (json.JSONDecodeError, AttributeError):
        nodes = []

    if not nodes:
        # Board 未登録 → label fallback 試行（cross-repo Issue 対応）
        if _label_fallback(issue):
            _log_gate_event(f"ALLOW_LABEL_FALLBACK issue=#{issue}")
            return
        _log_gate_event(f"DENY_NOT_ON_BOARD issue=#{issue}")
        raise LaunchError(
            f"Issue #{issue} は Project Board に登録されていません。\n"
            "  対処: Board に Issue を add してから再試行してください。"
        )

    # nodes の最初のエントリから status を取得
    status_obj = nodes[0].get("status") if nodes else None
    status = status_obj.get("name", "") if isinstance(status_obj, dict) else (status_obj or "")

    if status in _ALLOWED_STATUSES:
        _log_gate_event(f"ALLOW status={status} issue=#{issue}")
        return

    _log_gate_event(f"DENY status={status} issue=#{issue}")
    _deny_msg = (
        f"Issue #{issue} の Status={status} です。Refined への遷移が必要です。\n"
        f"  現在: {status} → 必要: Refined\n"
        "  対処: /twl:workflow-issue-refine を実行して Specialist review を完了してください。"
    )
    hint = _check_dual_write_log(issue)
    if hint:
        _deny_msg += hint
    raise LaunchError(_deny_msg)


class WorkerLauncher:
    """Launch autopilot Worker processes in tmux windows."""

    def __init__(
        self,
        scripts_root: Path | None = None,
    ) -> None:
        self.scripts_root = scripts_root or self._detect_scripts_root()

    def launch(
        self,
        issue: str,
        project_dir: str,
        autopilot_dir: str,
        model: str = "sonnet",
        context: str = "",
        repo_owner: str = "",
        repo_name: str = "",
        repo_path: str = "",
        worktree_dir: str = "",
        bypass_status_gate: bool = False,
    ) -> str:
        """Launch Worker. Returns OK message."""
        # Validate issue
        if not re.match(r"^[1-9]\d*$", issue):
            raise LaunchError(f"--issue は正の整数で指定してください: {issue}")

        # Validate model
        if not re.match(r"^[a-zA-Z0-9._-]+$", model):
            raise LaunchError(f"--model の形式が正しくありません: {model}")

        # Compute repo_id
        repo_id = f"{repo_owner}-{repo_name}" if repo_owner and repo_name else ""

        # Validate paths
        _validate_absolute_path("project-dir", project_dir, issue, autopilot_dir, repo_id)
        _validate_absolute_path("autopilot-dir", autopilot_dir, issue, autopilot_dir, repo_id)

        if repo_owner and not re.match(r"^[a-zA-Z0-9_-]+$", repo_owner):
            _record_failure(issue, "invalid_repo_owner", "launch_worker", autopilot_dir, repo_id)
            raise LaunchError(f"--repo-owner の形式が正しくありません: {repo_owner}")

        if repo_name and not re.match(r"^[a-zA-Z0-9_.-]+$", repo_name):
            _record_failure(issue, "invalid_repo_name", "launch_worker", autopilot_dir, repo_id)
            raise LaunchError(f"--repo-name の形式が正しくありません: {repo_name}")

        if repo_path:
            _validate_absolute_path("repo-path", repo_path, issue, autopilot_dir, repo_id)
            if not Path(repo_path).is_dir():
                _record_failure(issue, "repo_path_not_found", "launch_worker", autopilot_dir, repo_id)
                raise LaunchError(f"--repo-path が見つかりません: {repo_path}")

        if worktree_dir:
            _validate_absolute_path("worktree-dir", worktree_dir, issue, autopilot_dir, repo_id)
            if not Path(worktree_dir).is_dir():
                _record_failure(issue, "worktree_dir_not_found", "launch_worker", autopilot_dir, repo_id)
                raise LaunchError(f"--worktree-dir が見つかりません: {worktree_dir}")

        # Status pre-check (AC5/6/7): fail-closed, cross-repo fallback, observability
        try:
            _check_refined_status(issue, bypass=bypass_status_gate)
        except LaunchError:
            _record_failure(issue, "status_gate_deny", "status_pre_check", autopilot_dir, repo_id)
            raise

        # Check cld
        cld_path = shutil.which("cld")
        if not cld_path:
            _record_failure(issue, "cld_not_found", "launch_worker", autopilot_dir, repo_id)
            raise LaunchDependencyError("cld が見つかりません")

        # Initialize issue state
        state_cmd = [
            sys.executable, "-m", "twl.autopilot.state",
            "write", "--type", "issue", "--issue", issue,
            "--role", "worker", "--init",
        ]
        if repo_id:
            state_cmd += ["--repo", repo_id]
        subprocess.run(
            state_cmd,
            env={**os.environ, "AUTOPILOT_DIR": autopilot_dir},
        )

        # Determine launch directory
        effective_project_dir = repo_path if repo_path else project_dir

        if not worktree_dir and Path(effective_project_dir).joinpath(".bare").is_dir():
            worktree_dir = self._create_or_find_worktree(
                issue, effective_project_dir, repo_path,
                repo_owner, repo_name,
            )
            if worktree_dir:
                print(f"Worktree: {worktree_dir}")

        if worktree_dir:
            launch_dir = worktree_dir
        elif Path(effective_project_dir).joinpath(".bare").is_dir():
            launch_dir = str(Path(effective_project_dir) / "main")
        else:
            launch_dir = effective_project_dir

        # Build environment
        window_name = f"ap-#{issue}"
        prompt = f"/twl:workflow-setup #{issue}"

        # Pass env vars via tmux -e flags to avoid nested shell quoting issues
        env_flags: list[str] = [
            "-e", f"AUTOPILOT_DIR={autopilot_dir}",
            "-e", f"WORKER_ISSUE_NUM={issue}",
        ]
        if repo_owner and repo_name:
            env_flags += ["-e", f"REPO_OWNER={repo_owner}", "-e", f"REPO_NAME={repo_name}"]

        # audit 環境変数の伝搬（is_audit_active で OR 条件判定、resolve_audit_dir で絶対パス解決）
        try:
            from twl.autopilot.audit import is_audit_active, resolve_audit_dir
            if is_audit_active():
                audit_dir_path = resolve_audit_dir()
                if audit_dir_path is not None:
                    env_flags += ["-e", "TWL_AUDIT=1", "-e", f"TWL_AUDIT_DIR={audit_dir_path}"]
        except Exception:
            pass

        cld_args = [cld_path, "--model", model]
        if context:
            cld_args += ["--append-system-prompt", context]
        cld_args.append(prompt)

        tmux_argv = (
            ["tmux", "new-window", "-d", "-n", window_name, "-c", launch_dir]
            + env_flags
            + ["--"]
            + cld_args
        )

        result = subprocess.run(tmux_argv)
        if result.returncode != 0:
            raise LaunchError(f"tmux new-window 失敗")

        # Set crash detection hook
        subprocess.run(
            ["tmux", "set-option", "-t", window_name, "remain-on-exit", "on"],
            capture_output=True,
        )
        crash_cmd = (
            f"bash {self._shell_quote(str(self.scripts_root / 'crash-detect.sh'))} "
            f"--issue {self._shell_quote(issue)} --window {self._shell_quote(window_name)}"
        )
        subprocess.run(
            ["tmux", "set-hook", "-t", window_name, "pane-died", f"run-shell '{crash_cmd}'"],
            capture_output=True,
        )

        return f"Worker 起動完了: Issue #{issue} (window={window_name}, model={model}, dir={launch_dir})"

    def _create_or_find_worktree(
        self,
        issue: str,
        effective_project_dir: str,
        repo_path: str,
        repo_owner: str,
        repo_name: str,
    ) -> str:
        """Create worktree for issue, or find existing one."""
        create_args = [f"#{issue}"]
        if repo_path:
            create_args += ["--repo-path", repo_path]
        if repo_owner and repo_name:
            create_args += ["-R", f"{repo_owner}/{repo_name}"]

        result = subprocess.run(
            ["python3", "-m", "twl.autopilot.worktree", "create"] + create_args,
            capture_output=True, text=True,
            cwd=str(Path(effective_project_dir) / "main"),
        )

        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if line.startswith("パス: "):
                    return line[len("パス: "):].strip()
        else:
            # Try to find existing worktree
            result2 = subprocess.run(
                ["git", "--git-dir", str(Path(effective_project_dir) / ".bare"),
                 "worktree", "list"],
                capture_output=True, text=True,
            )
            for line in result2.stdout.splitlines():
                if f"/{issue}-" in line or f"[{issue}-" in line:
                    return line.split()[0]

        return ""

    def _detect_scripts_root(self) -> Path:
        try:
            common_dir = subprocess.check_output(
                ["git", "rev-parse", "--git-common-dir"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip()
            repo_root = Path(common_dir).resolve().parent
            return repo_root / "plugins" / "twl" / "scripts"
        except Exception:
            return Path.cwd() / "plugins" / "twl" / "scripts"

    @staticmethod
    def _shell_quote(s: str) -> str:
        import shlex
        return shlex.quote(s)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {
        "issue": "",
        "project_dir": "",
        "autopilot_dir": "",
        "model": "sonnet",
        "context": "",
        "repo_owner": "",
        "repo_name": "",
        "repo_path": "",
        "worktree_dir": "",
        "bypass_status_gate": False,
    }
    value_opts = {
        "--issue": "issue", "--project-dir": "project_dir", "--autopilot-dir": "autopilot_dir",
        "--model": "model", "--context": "context", "--repo-owner": "repo_owner",
        "--repo-name": "repo_name", "--repo-path": "repo_path", "--worktree-dir": "worktree_dir",
    }
    flag_opts = {"--bypass-status-gate": "bypass_status_gate"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print("Usage: python3 -m twl.autopilot.launcher --issue N --project-dir DIR --autopilot-dir DIR")
            sys.exit(0)
        elif a in value_opts:
            if i + 1 >= len(argv):
                print(f"Error: {a} には値が必要です", file=sys.stderr)
                sys.exit(1)
            args[value_opts[a]] = argv[i + 1]
            i += 2
        elif a in flag_opts:
            args[flag_opts[a]] = True
            i += 1
        else:
            print(f"Error: 不明なオプション: {a}", file=sys.stderr)
            sys.exit(1)
    return args


def main(argv: list[str] | None = None) -> int:
    args_list = argv if argv is not None else sys.argv[1:]
    parsed = _parse_args(args_list)

    if not parsed["issue"] or not parsed["project_dir"] or not parsed["autopilot_dir"]:
        print("Error: --issue, --project-dir, --autopilot-dir は必須です", file=sys.stderr)
        return 1

    launcher = WorkerLauncher()
    try:
        msg = launcher.launch(
            issue=parsed["issue"],
            project_dir=parsed["project_dir"],
            autopilot_dir=parsed["autopilot_dir"],
            model=parsed["model"],
            context=parsed["context"],
            repo_owner=parsed["repo_owner"],
            repo_name=parsed["repo_name"],
            repo_path=parsed["repo_path"],
            worktree_dir=parsed["worktree_dir"],
            bypass_status_gate=parsed["bypass_status_gate"],
        )
        print(msg)
        return 0
    except LaunchDependencyError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2
    except LaunchError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
