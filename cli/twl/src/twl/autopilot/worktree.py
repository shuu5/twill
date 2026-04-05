"""Worktree management for autopilot operations.

Replaces: worktree-create.sh

CLI usage:
    python3 -m twl.autopilot.worktree create <branch-name|#issue> [--from <base>]
                                              [-R <owner/repo>] [--repo-path <path>]
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

_ISSUE_NUM_RE = re.compile(r"^\d+$")
_REPO_RE = re.compile(r"^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$")
_RESERVED_NAMES_RE = re.compile(r"^(main|master|HEAD)$")
_ALLOWED_PREFIXES = ("feat/", "fix/", "refactor/", "docs/", "test/", "chore/")
_BRANCH_CHAR_RE = re.compile(r"^[a-z0-9/-]+$")
_BASE_BRANCH_RE = re.compile(r"^[a-zA-Z0-9/_.-]+$")
_BRACKET_PREFIX_RE = re.compile(r"^\[[^\]]*\]\s*")


# ---------------------------------------------------------------------------
# Error types
# ---------------------------------------------------------------------------


class WorktreeError(Exception):
    """Raised for worktree operation errors (exit code 1)."""


class WorktreeArgError(Exception):
    """Raised for argument errors (exit code 2)."""


# ---------------------------------------------------------------------------
# Slug / branch name generation
# ---------------------------------------------------------------------------


def _slugify(title: str) -> str:
    """Convert an issue title to a URL-safe slug.

    Steps:
      1. Remove leading bracket prefix like ``[Feature]``.
      2. Lowercase.
      3. Replace spaces with hyphens.
      4. Remove characters that are not alphanumeric or hyphens.
      5. Collapse consecutive hyphens.
      6. Strip leading/trailing hyphens.
    """
    slug = _BRACKET_PREFIX_RE.sub("", title)
    slug = slug.lower()
    slug = slug.replace(" ", "-")
    slug = re.sub(r"[^a-z0-9-]", "", slug)
    slug = re.sub(r"-+", "-", slug)
    slug = slug.strip("-")
    return slug


def _label_to_prefix(labels: list[str]) -> str:
    """Determine branch prefix from issue labels."""
    joined = " ".join(labels).lower()
    if "bug" in joined:
        return "fix"
    if "documentation" in joined:
        return "docs"
    if "refactor" in joined:
        return "refactor"
    return "feat"


def generate_branch_name(issue_number: str, repo: str | None = None) -> str:
    """Generate a branch name from a GitHub Issue number.

    Mirrors ``generate_branch_name_from_issue()`` in worktree-create.sh.

    Args:
        issue_number: Integer string of the Issue number.
        repo: Optional ``owner/repo`` for cross-repo access.

    Returns:
        Branch name like ``feat/17-some-title``.

    Raises:
        WorktreeError: On gh CLI failure.
    """
    if not _ISSUE_NUM_RE.match(issue_number):
        raise WorktreeArgError(f"Issue番号は整数である必要があります: {issue_number!r}")
    if repo and not _REPO_RE.match(repo):
        raise WorktreeArgError(f"不正な -R 引数: {repo!r}（owner/repo 形式が必要）")

    repo_args = ["-R", repo] if repo else []
    cmd = ["gh", "issue", "view", issue_number, *repo_args, "--json", "title,labels"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise WorktreeError(f"エラー: Issue #{issue_number} が見つかりません")

    data: dict[str, Any] = json.loads(result.stdout)
    title: str = data.get("title") or ""
    label_names: list[str] = [lb["name"] for lb in data.get("labels") or []]

    prefix = _label_to_prefix(label_names)
    slug = _slugify(title)

    # 50-char total limit: prefix + "/" + issue_number + "-" + slug
    max_slug_len = max(0, 45 - len(prefix) - len(issue_number))
    if len(slug) > max_slug_len:
        slug = slug[:max_slug_len].rstrip("-")

    return f"{prefix}/{issue_number}-{slug}"


# ---------------------------------------------------------------------------
# Branch name validation
# ---------------------------------------------------------------------------


def validate_branch_name(branch: str) -> None:
    """Raise WorktreeArgError if branch name is invalid.

    Rules mirror worktree-create.sh validation:
    - Not a reserved name (main, master, HEAD).
    - If contains slash: must start with an allowed prefix.
    - Only lowercase alphanumeric, hyphens, and slashes.
    - Max 50 characters.
    """
    if _RESERVED_NAMES_RE.match(branch):
        raise WorktreeArgError(f"'{branch}' は予約語です")

    if "/" in branch:
        if not any(branch.startswith(p) for p in _ALLOWED_PREFIXES):
            raise WorktreeArgError(
                "スラッシュを使用する場合は許可されたプレフィックスを使用してください: "
                + ", ".join(_ALLOWED_PREFIXES)
            )

    if not _BRANCH_CHAR_RE.match(branch):
        raise WorktreeArgError(
            "ブランチ名には英小文字、数字、ハイフン、スラッシュのみ使用できます"
        )

    if len(branch) > 50:
        raise WorktreeArgError("ブランチ名は50文字以下にしてください")


# ---------------------------------------------------------------------------
# WorktreeManager
# ---------------------------------------------------------------------------


def _resolve_git_common_dir(repo_path: str | None) -> tuple[Path, Path]:
    """Return (git_common_dir, project_dir).

    Mirrors the project-root resolution logic in worktree-create.sh.
    """
    if repo_path:
        p = Path(repo_path)
        if not p.is_dir():
            raise WorktreeError(f"リポジトリパスが見つかりません: {repo_path}")
        if (p / ".bare").is_dir():
            return p / ".bare", p
        if (p / ".git").is_dir():
            return p / ".git", p
        raise WorktreeError(f"{repo_path} は git リポジトリではありません")

    result = subprocess.run(
        ["git", "rev-parse", "--git-common-dir"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise WorktreeError("gitリポジトリ内で実行してください")
    git_common_dir = Path(result.stdout.strip()).resolve()
    project_dir = git_common_dir.parent
    return git_common_dir, project_dir


def _resolve_git_dir(project_dir: Path, git_common_dir: Path) -> Path:
    """Return the git directory for worktree add."""
    if (project_dir / ".bare").is_dir():
        return project_dir / ".bare"
    if (project_dir / ".git").is_dir():
        return project_dir / ".git"
    return git_common_dir


class WorktreeManager:
    """Manages git worktrees for bare-repo projects."""

    def __init__(self, repo_path: str | None = None) -> None:
        self.repo_path = repo_path

    def create(
        self,
        branch_name: str,
        base_branch: str = "main",
        repo: str | None = None,
    ) -> Path:
        """Create a new worktree.

        Args:
            branch_name: Branch name or ``#123`` Issue reference.
            base_branch: Base branch to derive from.
            repo: Optional ``owner/repo`` for Issue lookup.

        Returns:
            Path to the created worktree directory.

        Raises:
            WorktreeError: On failure.
            WorktreeArgError: On invalid arguments.
        """
        if repo and not _REPO_RE.match(repo):
            raise WorktreeArgError(f"不正な -R 引数: {repo!r}（owner/repo 形式が必要）")

        if not _BASE_BRANCH_RE.match(base_branch):
            raise WorktreeArgError(
                f"不正な --from 引数: {base_branch!r}（英数字・スラッシュ・ハイフン・ドットのみ許可）"
            )

        issue_number: str | None = None

        # Resolve #N → branch name
        issue_match = re.match(r"^#(\d+)$", branch_name)
        if issue_match:
            issue_number = issue_match.group(1)
            print(f"Issue #{issue_number} からブランチ名を生成中...")
            branch_name = generate_branch_name(issue_number, repo)
            print(f"生成されたブランチ名: {branch_name}")

        validate_branch_name(branch_name)

        git_common_dir, project_dir = _resolve_git_common_dir(self.repo_path)
        git_dir = _resolve_git_dir(project_dir, git_common_dir)

        worktree_dir = project_dir / "worktrees" / branch_name

        if worktree_dir.exists():
            raise WorktreeError(f"エラー: worktree '{branch_name}' は既に存在します")

        print(f"=== worktree作成: {branch_name} ===")
        print(f"派生元: {base_branch}")

        worktree_dir.parent.mkdir(parents=True, exist_ok=True)

        result = subprocess.run(
            ["git", "--git-dir", str(git_dir), "worktree", "add",
             "-b", branch_name, str(worktree_dir), base_branch],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise WorktreeError(f"worktree 作成に失敗しました:\n{result.stderr}")

        # Sync dependencies
        print("依存関係を同期中...")
        self._sync_deps(worktree_dir)

        # Push upstream
        print("upstream を設定中...")
        push_result = subprocess.run(
            ["git", "-C", str(worktree_dir), "push", "-u", "origin", branch_name],
            capture_output=True, text=True,
        )
        if push_result.returncode != 0:
            print("  警告: upstream push 失敗（ネットワークエラー等）。worktree 作成は成功しています。")

        print("")
        print("=== worktree作成完了 ===")
        print(f"パス: {worktree_dir}")
        if issue_number:
            print(f"Issue: #{issue_number}")
        print("")
        print("次のステップ:")
        print(f"  cd {worktree_dir}")

        return worktree_dir

    @staticmethod
    def _sync_deps(worktree_dir: Path) -> None:
        """Sync language-specific dependencies if lock files are present."""
        if (worktree_dir / "renv.lock").is_file():
            print("  renv::restore() を実行中...")
            result = subprocess.run(
                ["Rscript", "-e", "renv::restore(prompt = FALSE)"],
                capture_output=True, text=True, cwd=worktree_dir,
            )
            if result.returncode != 0:
                print("  警告: renv::restore() に失敗しました")

        if (worktree_dir / "pyproject.toml").is_file():
            print("  uv sync を実行中...")
            result = subprocess.run(
                ["uv", "sync"],
                capture_output=True, text=True, cwd=worktree_dir,
            )
            if result.returncode != 0:
                print("  警告: uv sync に失敗しました")


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    if not args:
        print(
            "Usage: python3 -m twl.autopilot.worktree create <branch-name|#issue>"
            " [--from <base>] [-R <owner/repo>] [--repo-path <path>]",
            file=sys.stderr,
        )
        return 1

    command = args[0]
    rest = args[1:]

    if command != "create":
        print(f"Unknown command: {command}", file=sys.stderr)
        return 1

    # Parse create arguments
    branch_name = ""
    base_branch = "main"
    repo: str | None = None
    repo_path: str | None = None

    i = 0
    while i < len(rest):
        arg = rest[i]
        if arg == "--from" and i + 1 < len(rest):
            base_branch = rest[i + 1]
            i += 2
        elif arg == "-R" and i + 1 < len(rest):
            repo = rest[i + 1]
            i += 2
        elif arg == "--repo-path" and i + 1 < len(rest):
            repo_path = rest[i + 1]
            i += 2
        else:
            if not branch_name:
                branch_name = arg
            i += 1

    if not branch_name:
        print("エラー: ブランチ名を指定してください", file=sys.stderr)
        print(
            "使用方法: python3 -m twl.autopilot.worktree create"
            " <branch-name | #issue-number> [--from <base-branch>]",
            file=sys.stderr,
        )
        return 2

    try:
        mgr = WorktreeManager(repo_path=repo_path)
        mgr.create(branch_name, base_branch=base_branch, repo=repo)
        return 0
    except WorktreeArgError as e:
        print(f"エラー: {e}", file=sys.stderr)
        return 2
    except WorktreeError as e:
        print(f"エラー: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
