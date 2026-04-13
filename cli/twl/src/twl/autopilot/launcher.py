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
        "--set", f"status=failed",
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

        # Detect quick label
        is_quick = self._detect_quick_label(issue, repo_owner, repo_name)

        if is_quick:
            quick_instruction = (
                "[quick Issue] このIssueにはquickラベルが付いています。"
                "workflow-test-readyは実行してはいけません。"
                "直接実装→commit→push→gh pr create --fill --label quick→merge-gateのみを実行してください。"
            )
            context = f"{context}\n\n{quick_instruction}" if context else quick_instruction

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

    def _detect_quick_label(self, issue: str, repo_owner: str, repo_name: str) -> bool:
        flags: list[str] = []
        if repo_owner and repo_name:
            flags = ["--repo", f"{repo_owner}/{repo_name}"]
        try:
            result = subprocess.run(
                ["gh", "issue", "view", issue] + flags +
                ["--json", "labels", "--jq", ".labels[].name"],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode == 0:
                return "quick" in result.stdout.splitlines()
        except Exception:
            pass
        return False

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
    }
    value_opts = {
        "--issue": "issue", "--project-dir": "project_dir", "--autopilot-dir": "autopilot_dir",
        "--model": "model", "--context": "context", "--repo-owner": "repo_owner",
        "--repo-name": "repo_name", "--repo-path": "repo_path", "--worktree-dir": "worktree_dir",
    }
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
