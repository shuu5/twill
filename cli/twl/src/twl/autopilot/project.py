"""Project scaffolding and migration for autopilot operations.

Replaces: project-create.sh, project-migrate.sh

CLI usage:
    python3 -m twl.autopilot.project create <project-name>
                                            [--type <type>]
                                            [--root <path>]
                                            [--no-github]
    python3 -m twl.autopilot.project migrate [--type <type>] [--dry-run]
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


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$")
_REPO_RE = re.compile(r"^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$")

AVAILABLE_TYPES = ("rnaseq", "webapp-llm", "webapp-hono")

_CO_AUTHOR = "Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

# Type → default project root env var
_TYPE_ROOT_ENV: dict[str, str] = {
    "webapp-llm": "WEBAPP_PROJECTS_ROOT",
    "webapp-hono": "WEBAPP_PROJECTS_ROOT",
    "rnaseq": "OMICS_PROJECTS_ROOT",
}


# ---------------------------------------------------------------------------
# Error types
# ---------------------------------------------------------------------------


class ProjectError(Exception):
    """Raised for project operation errors (exit code 1)."""


class ProjectArgError(Exception):
    """Raised for argument errors (exit code 2)."""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _run(args: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def _resolve_project_root(project_type: str, explicit_root: str | None) -> Path:
    if explicit_root:
        return Path(explicit_root)
    env_key = _TYPE_ROOT_ENV.get(project_type, "PROJECTS_ROOT")
    root = os.environ.get(env_key) or os.environ.get("PROJECTS_ROOT")
    return Path(root) if root else Path.home() / "projects"


def _cleanup_deprecated_local(project_dir: Path) -> None:
    """Remove project-local opsx commands and deltaspec skills (deprecated)."""
    opsx_dir = project_dir / ".claude" / "commands" / "opsx"
    if opsx_dir.is_dir():
        shutil.rmtree(opsx_dir)
        print("   ✓ プロジェクトローカル opsx コマンドを削除（グローバルに委譲）")

    found = False
    for skill_dir in (project_dir / ".claude" / "skills").glob("deltaspec-*/"):
        if skill_dir.is_dir():
            shutil.rmtree(skill_dir)
            found = True
    if found:
        print("   ✓ プロジェクトローカル deltaspec スキルを削除（グローバルに委譲）")


# ---------------------------------------------------------------------------
# Template copying helpers
# ---------------------------------------------------------------------------


def _copy_template_layer(
    layer_dir: Path,
    dest_dir: Path,
    claude_md_parts: list[str],
) -> None:
    """Copy a template layer into dest_dir, accumulating CLAUDE.md content."""
    if not layer_dir.is_dir():
        return

    print(f"   レイヤー: {layer_dir}")

    for item in layer_dir.iterdir():
        name = item.name
        if name == "CLAUDE.md" and item.is_file():
            claude_md_parts.append(item.read_text(encoding="utf-8"))
            continue
        if item.is_dir() and name in ("agents", "commands", "rules"):
            continue
        if name == ".claude":
            continue

        dest = dest_dir / name
        if item.is_dir():
            shutil.copytree(item, dest, dirs_exist_ok=True)
        else:
            shutil.copy2(item, dest)

    # Also copy hidden files (excluding .claude)
    for item in layer_dir.glob(".[!.]*"):
        if item.name == ".claude":
            continue
        dest = dest_dir / item.name
        if item.is_dir():
            shutil.copytree(item, dest, dirs_exist_ok=True)
        else:
            shutil.copy2(item, dest)


# ---------------------------------------------------------------------------
# ProjectManager
# ---------------------------------------------------------------------------


class ProjectManager:
    """Create and migrate bare-repo projects from templates."""

    def __init__(self, templates_base: Path | None = None) -> None:
        self.templates_base = templates_base or (Path.home() / ".claude" / "templates")

    # ------------------------------------------------------------------
    # create
    # ------------------------------------------------------------------

    def create(
        self,
        project_name: str,
        project_type: str = "",
        project_root: str | None = None,
        no_github: bool = False,
    ) -> Path:
        """Create a new project with bare-repo structure.

        Mirrors project-create.sh 6-stage scaffolding.

        Args:
            project_name: Name for the project (lowercase alphanumeric + hyphens).
            project_type: Template type (rnaseq, webapp-llm, webapp-hono, or "").
            project_root: Override the project root directory.
            no_github: Skip GitHub repository creation.

        Returns:
            Path to the created main worktree.

        Raises:
            ProjectArgError: On invalid arguments.
            ProjectError: On scaffolding failure.
        """
        # Validate project name
        if not project_name:
            raise ProjectArgError("プロジェクト名を指定してください")
        if not _NAME_RE.match(project_name):
            raise ProjectArgError(
                "プロジェクト名は英小文字、数字、ハイフンのみ使用可能です"
            )

        # Validate project type
        if project_type and not (self.templates_base / project_type).is_dir():
            raise ProjectArgError(
                f"不明なプロジェクトタイプ: {project_type}\n"
                f"利用可能なタイプ: {', '.join(AVAILABLE_TYPES)}"
            )

        projects_dir = _resolve_project_root(project_type, project_root)
        project_dir = projects_dir / project_name
        main_dir = project_dir / "main"

        projects_dir.mkdir(parents=True, exist_ok=True)

        if project_dir.exists():
            raise ProjectError(
                f"エラー: プロジェクト '{project_name}' は既に存在します: {project_dir}"
            )

        print(f"=== プロジェクト作成開始: {project_name} ===")
        if project_type:
            print(f"タイプ: {project_type}")
        print(f"ルート: {projects_dir}")

        # 1. Create project directory
        print("1. プロジェクトディレクトリを作成...")
        project_dir.mkdir(parents=True)

        # 2. Init bare git repo
        print("2. Gitリポジトリを初期化...")
        r = _run(["git", "init", "--bare", str(project_dir / ".bare")])
        if r.returncode != 0:
            raise ProjectError(f"git init --bare に失敗しました:\n{r.stderr}")
        (project_dir / ".git").write_text("gitdir: .bare\n", encoding="utf-8")

        # 3. Create main worktree
        print("3. main worktreeを作成...")
        r = _run([
            "git", "-C", str(project_dir / ".bare"),
            "worktree", "add", str(main_dir), "-b", "main", "--orphan",
        ])
        if r.returncode != 0:
            raise ProjectError(f"worktree add に失敗しました:\n{r.stderr}")

        # 4. Create .claude directory
        print("4. .claudeディレクトリを作成...")
        (main_dir / ".claude").mkdir(parents=True, exist_ok=True)

        # 5. Copy templates
        print("5. テンプレートファイルをコピー...")
        claude_md_parts: list[str] = []
        inheritance_chain = self._build_inheritance_chain(project_type)
        print(f"   継承チェーン: {' '.join(inheritance_chain) if inheritance_chain else '(なし)'}")

        for layer in inheritance_chain:
            _copy_template_layer(
                self.templates_base / layer,
                main_dir,
                claude_md_parts,
            )

        if claude_md_parts:
            combined = "\n\n".join(claude_md_parts)
            combined = combined.replace("{{PROJECT_NAME}}", project_name)
            (main_dir / "CLAUDE.md").write_text(combined, encoding="utf-8")

        # 5.5. Process .template files
        print("5.5. テンプレートファイルを処理...")
        for tmpl in main_dir.rglob("*.template"):
            output = tmpl.with_suffix("")
            print(f"   処理: {tmpl.name} → {output.name}")
            content = tmpl.read_text(encoding="utf-8").replace(
                "{{PROJECT_NAME}}", project_name
            )
            output.write_text(content, encoding="utf-8")
            tmpl.unlink()

        # 6. Type-specific setup
        if project_type == "rnaseq":
            print("6. renv + uv環境を初期化...")
            for d in ("analysis", "data/raw", "data/processed", "results", "R/functions", "tests"):
                (main_dir / d).mkdir(parents=True, exist_ok=True)
        else:
            print("6. 基本ディレクトリを作成...")
            (main_dir / "src").mkdir(parents=True, exist_ok=True)
            (main_dir / "tests").mkdir(parents=True, exist_ok=True)

        # 7. DeltaSpec init
        print("7. DeltaSpecを初期化...")
        r = _run(["which", "deltaspec"])
        if r.returncode == 0:
            (main_dir / "deltaspec" / "specs").mkdir(parents=True, exist_ok=True)
            (main_dir / "deltaspec" / "changes").mkdir(parents=True, exist_ok=True)
            print("   DeltaSpec initialized")
            _cleanup_deprecated_local(main_dir)
        else:
            print("   警告: deltaspec CLIが見つかりません")

        # 7.5. .claude symlink at bare repo root
        print("7.5. bare repo rootに.claude symlinkを作成...")
        symlink = project_dir / ".claude"
        symlink.symlink_to(Path("main") / ".claude")
        print(f"   symlink: {symlink} -> main/.claude")

        # 8. Initial commit
        print("8. 初回コミットを作成...")
        r = _run(["git", "-C", str(main_dir), "add", "-A"])
        if r.returncode != 0:
            raise ProjectError(f"git add に失敗しました:\n{r.stderr}")

        inheritance_str = " ".join(inheritance_chain) if inheritance_chain else "none"
        commit_msg = (
            f"feat: Initial project setup\n\n"
            f"- Type: {project_type or 'generic'}\n"
            f"- Template inheritance: {inheritance_str}\n"
            f"- Project-specific CLAUDE.md\n\n"
            f"{_CO_AUTHOR}"
        )
        r = _run(["git", "-C", str(main_dir), "commit", "-m", commit_msg])
        if r.returncode != 0:
            raise ProjectError(f"git commit に失敗しました:\n{r.stderr}")

        board_url = ""

        # 9. GitHub repository creation
        if not no_github:
            board_url = self._create_github_repo(project_name, main_dir)
        else:
            print("9. GitHubリポジトリ作成をスキップ（--no-github指定）")

        print("")
        print("=== プロジェクト作成完了 ===")
        print(f"パス: {main_dir}")
        print(f"タイプ: {project_type or 'generic'}")
        print(f"ルート: {projects_dir}")
        if board_url:
            print(f"Board: {board_url}")
        print("")
        print("次のステップ:")
        print(f"  cd {main_dir}")

        return main_dir

    def _build_inheritance_chain(self, project_type: str) -> list[str]:
        """Return ordered list of template layers to apply."""
        if not project_type:
            return []
        # Current type map has no inheritance; extend here if needed
        return [project_type]

    def _create_github_repo(self, project_name: str, main_dir: Path) -> str:
        """Create GitHub repository and Project Board. Returns board URL."""
        print("9. GitHubリポジトリを作成...")

        # Check gh auth
        r = _run(["gh", "auth", "status"])
        if r.returncode != 0:
            print("   警告: gh CLIが認証されていません。手動でリモートを設定してください")
            return ""

        r = _run(["gh", "repo", "create", project_name, "--private"])
        if r.returncode != 0:
            print("   警告: GitHubリポジトリの作成に失敗しました（同名リポジトリが存在する可能性）")
            return ""

        github_user_r = _run(["gh", "api", "user", "-q", ".login"])
        github_user = github_user_r.stdout.strip() if github_user_r.returncode == 0 else "unknown"
        repo_url = f"https://github.com/{github_user}/{project_name}.git"

        r = _run(["git", "-C", str(main_dir), "remote", "add", "origin", repo_url])
        if r.returncode != 0:
            print("   警告: remoteの追加に失敗しました（既に存在する可能性）")
            return ""

        # bare repo では fetch refspec が自動設定されないため明示的に追加
        _run(["git", "-C", str(main_dir), "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"])

        r = _run(["git", "-C", str(main_dir), "push", "-u", "origin", "main"])
        if r.returncode != 0:
            print("   警告: pushに失敗しました。後で手動で実行してください:")
            print(f"   cd {main_dir} && git push -u origin main")
            return ""

        print(f"   リポジトリ作成完了: https://github.com/{github_user}/{project_name}")

        # Protect main branch
        if github_user != "unknown":
            ruleset_body = (
                '{"name":"protect-main","target":"branch","enforcement":"active",'
                '"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},'
                '"rules":[{"type":"non_fast_forward"}]}'
            )
            r = _run([
                "gh", "api",
                f"repos/{github_user}/{project_name}/rulesets",
                "--method", "POST",
                "--input", "-",
            ], input=ruleset_body)
            if r.returncode == 0:
                print("   Ruleset適用: main force push 禁止")
            else:
                print("   警告: Ruleset作成に失敗しました（後で手動適用可）")

        # Project Board setup
        print("9.5. Project Boardを初期設定...")
        board_url = self._setup_project_board(github_user, project_name)
        return board_url

    def _setup_project_board(self, github_user: str, project_name: str) -> str:
        """Create GitHub Project V2 Board and link repo. Returns board URL."""
        # Check project scope
        r = _run(["gh", "project", "list", "--owner", "@me", "--limit", "1"])
        if r.returncode != 0:
            print("   ⚠️ gh トークンに project スコープがありません")
            print("   以下を実行してスコープを追加してください:")
            print("     gh auth refresh -s project")
            return ""

        # Get repo node ID
        repo_query = (
            'query($owner: String!, $name: String!) {'
            '  repository(owner: $owner, name: $name) { id } }'
        )
        r = _run([
            "gh", "api", "graphql",
            "-f", f"query={repo_query}",
            "-f", f"owner={github_user}",
            "-f", f"name={project_name}",
            "--jq", ".data.repository.id",
        ])
        if r.returncode != 0 or not r.stdout.strip():
            print("   警告: リポジトリ情報の取得に失敗しました")
            return ""
        repo_node_id = r.stdout.strip()

        # Get owner node ID
        user_query = 'query($login: String!) { user(login: $login) { id } }'
        r = _run([
            "gh", "api", "graphql",
            "-f", f"query={user_query}",
            "-f", f"login={github_user}",
            "--jq", ".data.user.id",
        ])
        if r.returncode != 0 or not r.stdout.strip():
            print("   警告: GitHub ユーザー情報の取得に失敗しました")
            return ""
        owner_id = r.stdout.strip()

        # Create Project V2 Board
        create_query = (
            'mutation($ownerId: ID!, $title: String!) {'
            '  createProjectV2(input: {ownerId: $ownerId, title: $title}) {'
            '    projectV2 { id number url } } }'
        )
        r = _run([
            "gh", "api", "graphql",
            "-f", f"query={create_query}",
            "-f", f"ownerId={owner_id}",
            "-f", f"title={project_name}",
        ])
        if r.returncode != 0:
            print("   警告: Project Board の作成に失敗しました")
            return ""

        data = json.loads(r.stdout)
        proj = data.get("data", {}).get("createProjectV2", {}).get("projectV2", {})
        board_project_id = proj.get("id", "")
        board_url = proj.get("url", "")

        if not board_project_id:
            print("   警告: Project Board の作成に失敗しました")
            return ""

        print(f"   Board作成: {board_url}")

        # Link repository
        link_query = (
            'mutation($projectId: ID!, $repositoryId: ID!) {'
            '  linkProjectV2ToRepository(input: {projectId: $projectId, repositoryId: $repositoryId}) {'
            '    repository { id } } }'
        )
        r = _run([
            "gh", "api", "graphql",
            "-f", f"query={link_query}",
            "-f", f"projectId={board_project_id}",
            "-f", f"repositoryId={repo_node_id}",
        ])
        if r.returncode == 0:
            print("   リポジトリリンク: 完了")
        else:
            print("   警告: リポジトリリンクに失敗しました")

        return board_url

    # ------------------------------------------------------------------
    # migrate
    # ------------------------------------------------------------------

    def migrate(
        self,
        project_type: str = "",
        dry_run: bool = False,
        project_dir: Path | None = None,
    ) -> None:
        """Migrate existing project to latest template.

        Mirrors project-migrate.sh behaviour.

        Args:
            project_type: Override detected project type.
            dry_run: If True, show plan without applying changes.
            project_dir: Override CWD as project directory.

        Raises:
            ProjectArgError: On invalid arguments.
            ProjectError: On migration failure.
        """
        cwd = project_dir or Path.cwd()

        # Worktree detection
        git_file = cwd / ".git"
        if git_file.is_dir() and (cwd / "main").is_dir() and (cwd / "main" / ".git").is_file():
            raise ProjectError(
                "エラー: worktree形式のプロジェクトです。main/で実行してください:\n"
                "  cd main && python3 -m twl.autopilot.project migrate"
            )

        if not git_file.exists() and not (cwd / "CLAUDE.md").exists():
            raise ProjectError(
                "エラー: プロジェクトルートで実行してください（.gitまたはCLAUDE.mdが必要）"
            )

        is_worktree = git_file.is_file()
        project_name = (cwd.parent.name if is_worktree else cwd.name)

        print(f"=== プロジェクト移行分析: {project_name} ===")
        print("")

        # Validate explicit project_type
        if project_type and project_type not in AVAILABLE_TYPES:
            raise ProjectArgError(
                f"不明なプロジェクトタイプ: {project_type}\n"
                f"利用可能なタイプ: {', '.join(AVAILABLE_TYPES)}"
            )

        # 1. Analyse current state
        print("1. 現状分析...")
        deltaspec_version = self._detect_deltaspec_version(cwd)
        resolved_type = project_type or self._detect_project_type(cwd)

        if not (cwd / "CLAUDE.md").exists():
            print("   CLAUDE.md: なし → 作成が必要")
        else:
            print("   CLAUDE.md: 存在")

        print("")

        # 2. Build migration plan
        print("2. 移行プラン...")
        print("")
        changes: list[str] = []

        if deltaspec_version in ("v0.x", "partial", "none"):
            action = "移行（project.md削除、config.yaml生成）" if deltaspec_version == "v0.x" else "初期化（config.yaml生成）"
            changes.append(f"DeltaSpec {deltaspec_version} → {action}")

        if (cwd / "CLAUDE.md").exists():
            changes.append("CLAUDE.md 更新（テンプレートとマージ）")
        else:
            changes.append("CLAUDE.md 作成（テンプレートからコピー）")

        if not changes:
            print("   変更なし: プロジェクトは最新です")
            return

        print("   予定される変更:")
        for i, change in enumerate(changes, 1):
            print(f"   [{i}] {change}")
        print("")

        if dry_run:
            print("=== dry-run 完了 ===")
            print("実際に適用するには --dry-run を外して実行してください")
            return

        # 3. Confirm (non-interactive in Python: auto-apply)
        print("4. 変更を適用...")

        # DeltaSpec
        if deltaspec_version != "v1.x":
            self._apply_deltaspec(cwd)

        # CLAUDE.md
        self._apply_claude_md(cwd, resolved_type, project_name)

        # Check archived specs
        archive_dir = cwd / "deltaspec" / "archive"
        if archive_dir.is_dir():
            archived = list(archive_dir.rglob("spec.md"))
            if archived:
                print(f"      {len(archived)}個のアーカイブ済みspecを検出")
                print("      注: アーカイブされたspecsは完了済み機能のため移行しません。")

        print("")
        print("=== 移行完了 ===")
        print("")
        print("次のステップ:")
        print("  git add -A && git commit -m 'chore: migrate to latest template'")

    def _detect_deltaspec_version(self, project_dir: Path) -> str:
        if (project_dir / "deltaspec" / "config.yaml").exists():
            print("   DeltaSpec: v1.x (config.yaml)")
            return "v1.x"
        elif (project_dir / "deltaspec" / "project.md").exists():
            print("   DeltaSpec: v0.x (project.md) → 移行が必要")
            return "v0.x"
        elif (project_dir / "deltaspec").is_dir():
            print("   DeltaSpec: 部分的 → 再初期化が必要")
            return "partial"
        else:
            print("   DeltaSpec: なし → 新規初期化")
            return "none"

    def _detect_project_type(self, project_dir: Path) -> str:
        if (project_dir / "renv.lock").exists() or (project_dir / "R").is_dir():
            print("   タイプ検出: rnaseq (renv/Rディレクトリ)")
            return "rnaseq"

        pkg_json = project_dir / "package.json"
        pkg_json_content = pkg_json.read_text(encoding="utf-8", errors="ignore") if pkg_json.exists() else ""
        backend_pkg_json = project_dir / "apps" / "backend" / "package.json"
        backend_content = backend_pkg_json.read_text(encoding="utf-8", errors="ignore") if backend_pkg_json.exists() else ""
        if (
            (pkg_json.exists() and '"hono"' in pkg_json_content)
            or (backend_pkg_json.exists() and '"@hono/zod-openapi"' in backend_content)
            or (project_dir / "packages" / "schema").is_dir()
        ):
            print("   タイプ検出: webapp-hono (Hono/Zod monorepo構造)")
            return "webapp-hono"

        if (
            pkg_json.exists()
            or (project_dir / "src" / "app").is_dir()
            or (project_dir / "frontend" / "package.json").exists()
            or (project_dir / "backend").is_dir()
        ):
            print("   タイプ検出: webapp-llm (Next.js/FastAPI構造)")
            return "webapp-llm"

        raise ProjectArgError(
            "プロジェクトタイプを自動検出できません\n"
            "--type オプションで指定してください: --type rnaseq, --type webapp-llm, または --type webapp-hono"
        )

    def _apply_deltaspec(self, project_dir: Path) -> None:
        r = _run(["which", "deltaspec"])
        if r.returncode == 0:
            print("   DeltaSpec 初期化...")
            (project_dir / "deltaspec" / "specs").mkdir(parents=True, exist_ok=True)
            (project_dir / "deltaspec" / "changes").mkdir(parents=True, exist_ok=True)
            print("      DeltaSpec 初期化完了")
            _cleanup_deprecated_local(project_dir)
        else:
            print("      警告: deltaspec CLIが見つかりません")

    def _apply_claude_md(self, project_dir: Path, project_type: str, project_name: str) -> None:
        template_claude = self.templates_base / project_type / "CLAUDE.md"
        if not template_claude.exists():
            print(f"   警告: テンプレート {template_claude} が見つかりません")
            return

        template_content = template_claude.read_text(encoding="utf-8").replace(
            "<project>", project_name
        )
        target = project_dir / "CLAUDE.md"

        if target.exists():
            print("   CLAUDE.md マージ...")
            backup = project_dir / "CLAUDE.md.backup"
            backup.write_text(target.read_text(encoding="utf-8"), encoding="utf-8")
            print("      既存ファイルを CLAUDE.md.backup に保存")

            # Keep project-specific section
            existing = target.read_text(encoding="utf-8")
            project_specific = ""
            marker = "## プロジェクト固有"
            if marker in existing:
                idx = existing.index(marker)
                project_specific = existing[idx:]

            combined = template_content
            if project_specific:
                combined = combined.rstrip() + "\n\n" + project_specific

            target.write_text(combined, encoding="utf-8")
            print("      CLAUDE.md 更新完了")
        else:
            print("   CLAUDE.md 作成...")
            target.write_text(template_content, encoding="utf-8")
            print("      CLAUDE.md 作成完了")


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def _show_help() -> None:
    print("使用方法: python3 -m twl.autopilot.project <command> [options]")
    print("")
    print("コマンド:")
    print("  create <project-name> [--type <type>] [--root <path>] [--no-github]")
    print("  migrate               [--type <type>] [--dry-run]")
    print("")
    print(f"タイプ: {', '.join(AVAILABLE_TYPES)}")


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    if not args or args[0] in ("-h", "--help"):
        _show_help()
        return 0

    command = args[0]
    rest = args[1:]

    mgr = ProjectManager()

    try:
        if command == "create":
            project_name = ""
            project_type = ""
            project_root: str | None = None
            no_github = False

            i = 0
            while i < len(rest):
                arg = rest[i]
                if arg == "--type" and i + 1 < len(rest):
                    project_type = rest[i + 1]
                    i += 2
                elif arg == "--root" and i + 1 < len(rest):
                    project_root = rest[i + 1]
                    i += 2
                elif arg == "--no-github":
                    no_github = True
                    i += 1
                elif arg in ("-h", "--help"):
                    _show_help()
                    return 0
                else:
                    if not project_name:
                        project_name = arg
                    i += 1

            if not project_name:
                print("エラー: プロジェクト名を指定してください", file=sys.stderr)
                _show_help()
                return 2

            mgr.create(project_name, project_type, project_root, no_github)
            return 0

        elif command == "migrate":
            project_type = ""
            dry_run = False

            i = 0
            while i < len(rest):
                arg = rest[i]
                if arg == "--type" and i + 1 < len(rest):
                    project_type = rest[i + 1]
                    i += 2
                elif arg == "--dry-run":
                    dry_run = True
                    i += 1
                elif arg in ("-h", "--help"):
                    _show_help()
                    return 0
                else:
                    i += 1

            mgr.migrate(project_type, dry_run)
            return 0

        else:
            print(f"Unknown command: {command}", file=sys.stderr)
            _show_help()
            return 1

    except ProjectArgError as e:
        print(f"エラー: {e}", file=sys.stderr)
        return 2
    except ProjectError as e:
        print(f"エラー: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
