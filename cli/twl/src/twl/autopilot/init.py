"""Autopilot directory initialization and session exclusivity control.

Replaces: autopilot-init.sh

CLI usage:
    python3 -m twl.autopilot.init [--check-only] [--force]
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _autopilot_dir() -> Path:
    env = os.environ.get("AUTOPILOT_DIR", "")
    if env:
        return Path(env)
    try:
        import subprocess
        root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return Path(root) / ".autopilot"
    except Exception:
        return Path.cwd() / ".autopilot"


def _project_root(autopilot_dir: Path) -> Path:
    return autopilot_dir.parent


def _is_session_completed(session_file: Path) -> bool:
    """Return True if all issues in session are done (or no issues field)."""
    try:
        data = json.loads(session_file.read_text(encoding="utf-8"))
    except Exception:
        return False
    if not data.get("issues"):
        return True
    return all(iss.get("status") == "done" for iss in data["issues"])


class InitError(Exception):
    """Raised for initialization errors (exit code 1)."""


class InitArgError(Exception):
    """Raised for argument errors (exit code 2)."""


class AutopilotInitializer:
    """Initialize .autopilot/ directory with session exclusivity control."""

    def __init__(self, autopilot_dir: Path | None = None) -> None:
        self.autopilot_dir = autopilot_dir or _autopilot_dir()

    def run(self, check_only: bool = False, force: bool = False) -> str:
        """Initialize .autopilot/ directory.

        Returns OK message on success.
        Raises InitError on session conflict.
        """
        session_file = self.autopilot_dir / "session.json"

        if session_file.is_file():
            result = self._check_existing_session(session_file, force)
            if result == "removed":
                pass  # session removed, proceed
            elif result == "stale_warn":
                raise InitError(
                    f"stale セッションが検出されました。削除するには --force を指定してください"
                )
            elif result == "running":
                raise InitError(
                    "既存セッションが実行中です。"
                    "同一プロジェクトでの複数 autopilot セッションの同時実行は禁止されています"
                )

        if check_only:
            return "OK: 実行中のセッションはありません"

        return self._initialize_directories()

    def _check_existing_session(self, session_file: Path, force: bool) -> str:
        """Check existing session. Returns 'removed', 'stale_warn', or 'running'."""
        try:
            data = json.loads(session_file.read_text(encoding="utf-8"))
        except Exception:
            return "running"

        started_at = data.get("started_at", "")
        session_id = data.get("session_id", "unknown")

        # Parse elapsed time
        hours = 0
        if started_at and re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", started_at):
            try:
                dt = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
                now = datetime.now(timezone.utc)
                elapsed_secs = int((now - dt).total_seconds())
                hours = elapsed_secs // 3600
            except Exception:
                hours = 0

        is_completed = _is_session_completed(session_file)

        if force and is_completed:
            import sys
            print(f"WARN: 完了済みセッション ({hours}h経過) を強制削除します: {session_id}", file=sys.stderr)
            session_file.unlink(missing_ok=True)
            issues_dir = self.autopilot_dir / "issues"
            if issues_dir.is_dir():
                for f in issues_dir.glob("issue-*.json"):
                    f.unlink(missing_ok=True)
            return "removed"

        if hours >= 24:
            if force:
                import sys
                print(f"WARN: stale セッション ({hours}h経過) を強制削除します: {session_id}", file=sys.stderr)
                session_file.unlink(missing_ok=True)
                issues_dir = self.autopilot_dir / "issues"
                if issues_dir.is_dir():
                    for f in issues_dir.glob("issue-*.json"):
                        f.unlink(missing_ok=True)
                return "removed"
            else:
                return "stale_warn"

        return "running"

    def _initialize_directories(self) -> str:
        """Create directory structure. Returns OK message."""
        # Atomic lock using directory creation
        lock_dir = self.autopilot_dir / ".lock"
        self.autopilot_dir.mkdir(parents=True, exist_ok=True)

        try:
            lock_dir.mkdir()
        except FileExistsError:
            raise InitError(f"別のプロセスが初期化中です（ロック: {lock_dir}）")

        try:
            issues_dir = self.autopilot_dir / "issues"
            archive_dir = self.autopilot_dir / "archive"
            issues_dir.mkdir(parents=True, exist_ok=True)
            archive_dir.mkdir(parents=True, exist_ok=True)

            # Cross-repo: create repos namespace directories from plan.yaml
            repos_dir = self._create_repo_dirs()

            # Add .autopilot/ to .gitignore
            self._update_gitignore()

            lines = [
                "OK: .autopilot/ を初期化しました",
                f"  issues: {issues_dir}",
                f"  archive: {archive_dir}",
            ]
            if repos_dir and repos_dir.is_dir():
                lines.append(f"  repos: {repos_dir}")
                for d in sorted(repos_dir.iterdir()):
                    if d.is_dir():
                        lines.append(f"    - {d.name}")

            return "\n".join(lines)
        finally:
            try:
                lock_dir.rmdir()
            except Exception:
                pass

    def _create_repo_dirs(self) -> Path | None:
        """Create per-repo directories if plan.yaml has repos section."""
        plan_file = self.autopilot_dir / "plan.yaml"
        if not plan_file.is_file():
            return None

        content = plan_file.read_text(encoding="utf-8")
        if "repos:" not in content:
            return None

        repos_dir = self.autopilot_dir / "repos"

        # Extract repo_ids from repos: section (2-space indented keys)
        in_repos = False
        for line in content.splitlines():
            if line.startswith("repos:"):
                in_repos = True
                continue
            if in_repos:
                if line and not line.startswith(" "):
                    break
                m = re.match(r"^  ([a-zA-Z0-9_-]+):", line)
                if m:
                    repo_id = m.group(1)
                    (repos_dir / repo_id / "issues").mkdir(parents=True, exist_ok=True)

        return repos_dir

    def _update_gitignore(self) -> None:
        """Add .autopilot/ to .gitignore if not present."""
        project_root = _project_root(self.autopilot_dir)
        gitignore = project_root / ".gitignore"

        entry = ".autopilot/"
        if gitignore.is_file():
            content = gitignore.read_text(encoding="utf-8")
            if entry not in content.splitlines():
                with gitignore.open("a", encoding="utf-8") as f:
                    f.write(f"\n{entry}\n")
        else:
            gitignore.write_text(f"{entry}\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    check_only = False
    force = False

    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-h", "--help"):
            print("Usage: python3 -m twl.autopilot.init [--check-only] [--force]")
            return 0
        elif a == "--check-only":
            check_only = True
            i += 1
        elif a == "--force":
            force = True
            i += 1
        else:
            print(f"ERROR: 不明なオプション: {a}", file=sys.stderr)
            return 1

    initializer = AutopilotInitializer()
    try:
        msg = initializer.run(check_only=check_only, force=force)
        print(msg)
        return 0
    except InitArgError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    except InitError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
