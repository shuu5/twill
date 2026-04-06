"""Worktree management for autopilot operations.

Replaces: worktree-create.sh

CLI usage:
    python3 -m twl.autopilot.worktree create <branch-name|#issue> [--from <base>]
                                              [-R <owner/repo>] [--repo-path <path>]
    python3 -m twl.autopilot.worktree list [--repo-path <path>]
    python3 -m twl.autopilot.worktree cd <branch-name> [--repo-path <path>]
    python3 -m twl.autopilot.worktree start <branch-name> [--repo-path <path>]
"""

from __future__ import annotations

import json
import os
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


# ---------------------------------------------------------------------------
# Hook helpers
# ---------------------------------------------------------------------------


def _run_hook(hook_name: str, worktree_dir: Path, project_dir: Path) -> bool:
    """Find and run .twl/<hook_name> executable. Returns True if hook was executed.

    Search order:
    1. <worktree_dir>/.twl/<hook_name>  (committed to the branch)
    2. <project_dir>/main/.twl/<hook_name>  (project-root fallback)

    Non-zero exit codes from the hook are printed as warnings; the hook is
    still considered "executed" (returns True) so _sync_deps() is skipped.
    Environment variable TWL_PROJECT_ROOT is passed to the hook.
    """
    candidates = [
        worktree_dir / ".twl" / hook_name,
        project_dir / "main" / ".twl" / hook_name,
    ]
    env = {**os.environ, "TWL_PROJECT_ROOT": str(project_dir)}

    for hook_path in candidates:
        if hook_path.is_file() and os.access(hook_path, os.X_OK):
            print(f"  フック実行中: {hook_path}")
            result = subprocess.run(
                [str(hook_path)],
                cwd=str(worktree_dir),
                env=env,
            )
            if result.returncode != 0:
                print(
                    f"  警告: フック {hook_name} が非0終了コードで終了しました"
                    f" (rc={result.returncode})"
                )
            return True
    return False


def _project_dir_from_worktree(worktree_dir: Path) -> Path | None:
    """Resolve project_dir (parent of .bare) from a worktree directory."""
    result = subprocess.run(
        ["git", "rev-parse", "--git-common-dir"],
        capture_output=True, text=True, cwd=str(worktree_dir),
    )
    if result.returncode != 0:
        return None
    git_common_dir = Path(result.stdout.strip()).resolve()
    return git_common_dir.parent


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

        # Run setup hook (or fall back to _sync_deps)
        print("セットアップを実行中...")
        hook_ran = _run_hook("setup", worktree_dir, project_dir)
        if not hook_ran:
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

    def _list_worktrees(self, project_dir: Path, git_common_dir: Path) -> list[tuple[str, Path]]:
        """Return [(branch_name, worktree_path)] for entries under worktrees/."""
        git_dir = _resolve_git_dir(project_dir, git_common_dir)
        result = subprocess.run(
            ["git", "--git-dir", str(git_dir), "worktree", "list", "--porcelain"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise WorktreeError("git worktree list に失敗しました")

        worktrees_dir = project_dir / "worktrees"
        entries: list[tuple[str, Path]] = []
        current_path: Path | None = None
        current_branch: str | None = None

        for line in result.stdout.splitlines():
            if line.startswith("worktree "):
                current_path = Path(line[len("worktree "):])
                current_branch = None
            elif line.startswith("branch "):
                ref = line[len("branch "):]
                # refs/heads/feat/17-foo → feat/17-foo
                current_branch = ref.removeprefix("refs/heads/")
            elif line == "" and current_path is not None:
                try:
                    current_path.relative_to(worktrees_dir)
                    if current_branch:
                        entries.append((current_branch, current_path))
                except ValueError:
                    pass
                current_path = None
                current_branch = None

        # Flush last entry if file doesn't end with blank line
        if current_path is not None and current_branch is not None:
            try:
                current_path.relative_to(worktrees_dir)
                entries.append((current_branch, current_path))
            except ValueError:
                pass

        return entries

    def _resolve_worktree(
        self, branch_query: str, project_dir: Path, git_common_dir: Path
    ) -> tuple[str, Path]:
        """Resolve a (possibly partial) branch name to (branch, path).

        Exact match takes priority over substring match.
        Raises WorktreeError if no match or multiple substring matches.
        """
        entries = self._list_worktrees(project_dir, git_common_dir)
        # Exact match takes priority
        exact = [(b, p) for b, p in entries if b == branch_query]
        if exact:
            return exact[0]
        matches = [(b, p) for b, p in entries if branch_query in b]
        if not matches:
            raise WorktreeError(
                f"worktree が見つかりません: {branch_query!r}\n"
                f"利用可能な worktree: {[b for b, _ in entries] or '(なし)'}"
            )
        if len(matches) > 1:
            candidates = "\n".join(f"  {b}  {p}" for b, p in matches)
            raise WorktreeError(
                f"複数の worktree がマッチしました: {branch_query!r}\n{candidates}"
            )
        return matches[0]

    def list(self) -> None:
        """Print worktrees under worktrees/ with optional autopilot state."""
        git_common_dir, project_dir = _resolve_git_common_dir(self.repo_path)
        entries = self._list_worktrees(project_dir, git_common_dir)
        if not entries:
            print("(worktree なし)")
            return

        autopilot_dir = project_dir / ".autopilot" / "issues"
        for branch, path in entries:
            state = ""
            if autopilot_dir.is_dir():
                # Try to find a matching state file by branch name
                for state_file in autopilot_dir.glob("issue-*.json"):
                    try:
                        data = json.loads(state_file.read_text())
                        if data.get("branch") == branch:
                            state = f"[{data.get('status', '')}]"
                            break
                    except (json.JSONDecodeError, OSError):
                        pass
            print(f"{branch}\t{path}\t{state}".rstrip())

    def cd(self, branch_query: str) -> None:
        """Print the path of a worktree matching branch_query to stdout."""
        git_common_dir, project_dir = _resolve_git_common_dir(self.repo_path)
        _, worktree_path = self._resolve_worktree(branch_query, project_dir, git_common_dir)
        print(worktree_path)

    def start(self, branch_query: str) -> None:
        """Exec into a worktree and resume the Claude Code session (claude -c)."""
        git_common_dir, project_dir = _resolve_git_common_dir(self.repo_path)
        _, worktree_path = self._resolve_worktree(branch_query, project_dir, git_common_dir)
        if not worktree_path.is_dir():
            raise WorktreeError(f"worktree ディレクトリが存在しません: {worktree_path}")
        os.chdir(worktree_path)
        try:
            os.execvp("claude", ["claude", "-c"])
        except FileNotFoundError:
            raise WorktreeError("claude コマンドが見つかりません。Claude Code がインストールされているか確認してください")

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

    @staticmethod
    def run_teardown_hook(worktree_dir: Path) -> None:
        """Run .twl/teardown hook for the given worktree directory.

        Resolves project_dir via git, then delegates to _run_hook().
        Safe to call even when worktree_dir does not exist (no-op).
        """
        if not worktree_dir.is_dir():
            return
        project_dir = _project_dir_from_worktree(worktree_dir)
        if project_dir is None:
            print("  警告: git common dir を解決できませんでした。teardown フックをスキップします")
            return
        _run_hook("teardown", worktree_dir, project_dir)


# ---------------------------------------------------------------------------
# Completion script generation
# ---------------------------------------------------------------------------

_BASH_COMPLETION_TEMPLATE = """\
_twl_worktree_complete() {{
    local cur prev subcmds
    cur="${{COMP_WORDS[COMP_CWORD]}}"
    prev="${{COMP_WORDS[COMP_CWORD-1]}}"
    subcmds="create list cd start completions"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=($(compgen -W "${{subcmds}}" -- "${{cur}}"))
        return
    fi

    case "${{prev}}" in
        cd|start)
            local branches
            branches=$(git worktree list --porcelain 2>/dev/null | awk '/^branch /{{sub(/^refs\\/heads\\//, "", $2); print $2}}')
            COMPREPLY=($(compgen -W "${{branches}}" -- "${{cur}}"))
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}}

complete -F _twl_worktree_complete {cmd_name}
"""

_ZSH_COMPLETION_TEMPLATE = """\
_twl_worktree_zsh_complete() {{
    local -a subcmds
    subcmds=(create list cd start completions)

    if (( CURRENT == 2 )); then
        _describe 'subcommand' subcmds
        return
    fi

    case "${{words[2]}}" in
        cd|start)
            local -a branches
            branches=(${{(f)"$(git worktree list --porcelain 2>/dev/null | awk '/^branch /{{sub(/refs\\/heads\\//, "", $2); print $2}}')"}})
            _describe 'branch' branches
            ;;
    esac
}}

compdef _twl_worktree_zsh_complete {cmd_name}
"""


def generate_bash_completion(cmd_name: str = "twl-worktree") -> str:
    """Return a bash completion script for the given command name."""
    return _BASH_COMPLETION_TEMPLATE.format(cmd_name=cmd_name)


def generate_zsh_completion(cmd_name: str = "twl-worktree") -> str:
    """Return a zsh completion script for the given command name."""
    return _ZSH_COMPLETION_TEMPLATE.format(cmd_name=cmd_name)


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


_USAGE = """\
Usage: python3 -m twl.autopilot.worktree <command> [options]

Commands:
  create <branch-name|#issue> [--from <base>] [-R <owner/repo>] [--repo-path <path>]
  list [--repo-path <path>]
  cd <branch-name> [--repo-path <path>]
      Output the worktree path; use with a shell function:
        twlcd() { cd "$(python3 -m twl.autopilot.worktree cd "$1")"; }
  start <branch-name> [--repo-path <path>]
      Change to the worktree directory and exec 'claude -c'.
  completions --shell bash|zsh [--cmd <name>]
      Print a shell completion script (eval to activate).
"""


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    if not args:
        print(_USAGE, file=sys.stderr)
        return 1

    command = args[0]
    rest = args[1:]

    if command == "teardown-hook":
        if not rest:
            print("エラー: worktree ディレクトリを指定してください", file=sys.stderr)
            print(
                "使用方法: python3 -m twl.autopilot.worktree teardown-hook <worktree-dir>",
                file=sys.stderr,
            )
            return 2
        worktree_dir = Path(rest[0])
        WorktreeManager.run_teardown_hook(worktree_dir)
        return 0

    if command == "completions":
        shell: str | None = None
        cmd_name = "twl-worktree"
        i = 0
        while i < len(rest):
            if rest[i] == "--shell" and i + 1 < len(rest):
                shell = rest[i + 1]
                i += 2
            elif rest[i] == "--cmd" and i + 1 < len(rest):
                cmd_name = rest[i + 1]
                i += 2
            else:
                i += 1
        _CMD_NAME_RE = re.compile(r"^[a-zA-Z0-9_-]+$")
        if not _CMD_NAME_RE.match(cmd_name):
            print("エラー: --cmd には英数字・ハイフン・アンダースコアのみ使用できます", file=sys.stderr)
            return 2
        if shell == "bash":
            print(generate_bash_completion(cmd_name), end="")
            return 0
        elif shell == "zsh":
            print(generate_zsh_completion(cmd_name), end="")
            return 0
        else:
            print("エラー: --shell bash または --shell zsh を指定してください", file=sys.stderr)
            return 2

    if command not in ("create", "list", "cd", "start"):
        print(f"Unknown command: {command}", file=sys.stderr)
        return 1

    # Parse shared --repo-path option
    repo_path: str | None = None
    filtered: list[str] = []
    i = 0
    while i < len(rest):
        if rest[i] == "--repo-path" and i + 1 < len(rest):
            repo_path = rest[i + 1]
            i += 2
        else:
            filtered.append(rest[i])
            i += 1
    rest = filtered

    try:
        mgr = WorktreeManager(repo_path=repo_path)

        if command == "list":
            mgr.list()
            return 0

        if command == "cd":
            if not rest:
                print("エラー: ブランチ名を指定してください", file=sys.stderr)
                return 2
            mgr.cd(rest[0])
            return 0

        if command == "start":
            if not rest:
                print("エラー: ブランチ名を指定してください", file=sys.stderr)
                return 2
            mgr.start(rest[0])
            return 0  # unreachable after execvp, but satisfies type checker

        # command == "create"
        branch_name = ""
        base_branch = "main"
        repo: str | None = None

        i = 0
        while i < len(rest):
            arg = rest[i]
            if arg == "--from" and i + 1 < len(rest):
                base_branch = rest[i + 1]
                i += 2
            elif arg == "-R" and i + 1 < len(rest):
                repo = rest[i + 1]
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
