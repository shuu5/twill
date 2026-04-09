"""Tests for twl.autopilot.project.

Covers:
- ProjectManager.create: bare repo scaffolding (AC1)
- ProjectManager.migrate: directory restructuring (AC3)
- CLI main() exit codes
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from unittest.mock import MagicMock, patch, call

import pytest

from twl.autopilot.project import (
    ProjectManager,
    ProjectError,
    ProjectArgError,
    _resolve_project_root,
    main,
)


# ---------------------------------------------------------------------------
# _resolve_project_root
# ---------------------------------------------------------------------------


class TestResolveProjectRoot:
    def test_explicit_root_wins(self, tmp_path: Path) -> None:
        result = _resolve_project_root("rnaseq", str(tmp_path))
        assert result == tmp_path

    def test_rnaseq_uses_env(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("OMICS_PROJECTS_ROOT", str(tmp_path))
        result = _resolve_project_root("rnaseq", None)
        assert result == tmp_path

    def test_webapp_uses_env(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("WEBAPP_PROJECTS_ROOT", str(tmp_path))
        result = _resolve_project_root("webapp-llm", None)
        assert result == tmp_path

    def test_fallback_to_projects_env(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.delenv("OMICS_PROJECTS_ROOT", raising=False)
        monkeypatch.setenv("PROJECTS_ROOT", str(tmp_path))
        result = _resolve_project_root("rnaseq", None)
        assert result == tmp_path

    def test_fallback_to_home_projects(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.delenv("OMICS_PROJECTS_ROOT", raising=False)
        monkeypatch.delenv("WEBAPP_PROJECTS_ROOT", raising=False)
        monkeypatch.delenv("PROJECTS_ROOT", raising=False)
        result = _resolve_project_root("", None)
        assert result.name == "projects"


# ---------------------------------------------------------------------------
# ProjectManager.create — validation
# ---------------------------------------------------------------------------


class TestCreateValidation:
    def test_empty_name_raises(self) -> None:
        mgr = ProjectManager()
        with pytest.raises(ProjectArgError, match="プロジェクト名"):
            mgr.create("")

    def test_uppercase_name_raises(self) -> None:
        mgr = ProjectManager()
        with pytest.raises(ProjectArgError, match="英小文字"):
            mgr.create("MyProject")

    def test_name_with_spaces_raises(self) -> None:
        mgr = ProjectManager()
        with pytest.raises(ProjectArgError, match="英小文字"):
            mgr.create("my project")

    def test_unknown_type_raises(self, tmp_path: Path) -> None:
        mgr = ProjectManager(templates_base=tmp_path)
        with pytest.raises(ProjectArgError, match="不明なプロジェクトタイプ"):
            mgr.create("my-proj", project_type="unknown-type")

    def test_existing_project_raises(self, tmp_path: Path) -> None:
        (tmp_path / "my-proj").mkdir()
        mgr = ProjectManager()
        with pytest.raises(ProjectError, match="既に存在"):
            mgr.create("my-proj", project_root=str(tmp_path))

    def test_valid_single_char_name(self, tmp_path: Path) -> None:
        """Single-char project name is valid."""
        runs: list[list[str]] = []

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            runs.append(list(str(a) for a in args))
            return MagicMock(returncode=0, stdout="", stderr="")

        with patch("subprocess.run", side_effect=fake_run):
            mgr = ProjectManager()
            mgr.create("a", project_root=str(tmp_path), no_github=True)

        assert any("init" in " ".join(r) and "--bare" in " ".join(r) for r in runs)


# ---------------------------------------------------------------------------
# ProjectManager.create — scaffolding structure (AC1)
# ---------------------------------------------------------------------------


class TestCreateScaffolding:
    def _make_mgr(self, tmp_path: Path, templates_base: Path | None = None) -> ProjectManager:
        return ProjectManager(templates_base=templates_base or tmp_path / "templates")

    def _run_create(
        self,
        project_name: str,
        project_root: Path,
        mgr: ProjectManager,
        project_type: str = "",
    ) -> Path:
        """Run create with git/gh calls mocked to succeed."""
        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd = " ".join(str(a) for a in args)
            # Simulate git init --bare creating the .bare directory
            if "init" in cmd and "--bare" in cmd:
                for a in args:
                    if str(a).endswith(".bare"):
                        Path(a).mkdir(parents=True, exist_ok=True)
                        break
            # Simulate worktree add creating the main dir
            if "worktree add" in cmd:
                for a in args:
                    if "main" in str(a) and "worktrees" not in str(a):
                        Path(a).mkdir(parents=True, exist_ok=True)
                        break
            return MagicMock(returncode=0, stdout="", stderr="")

        with patch("subprocess.run", side_effect=fake_run):
            return mgr.create(
                project_name,
                project_type=project_type,
                project_root=str(project_root),
                no_github=True,
            )

    def test_bare_git_dir_created(self, tmp_path: Path) -> None:
        self._run_create("my-project", tmp_path, self._make_mgr(tmp_path))
        assert (tmp_path / "my-project" / ".bare").is_dir()

    def test_git_pointer_file_created(self, tmp_path: Path) -> None:
        self._run_create("my-project", tmp_path, self._make_mgr(tmp_path))
        git_file = tmp_path / "my-project" / ".git"
        assert git_file.is_file()
        assert "gitdir: .bare" in git_file.read_text()

    def test_claude_symlink_created(self, tmp_path: Path) -> None:
        self._run_create("my-project", tmp_path, self._make_mgr(tmp_path))
        symlink = tmp_path / "my-project" / ".claude"
        assert symlink.is_symlink()

    def test_deltaspec_dirs_not_created_when_deltaspec_absent(self, tmp_path: Path) -> None:
        """When deltaspec CLI is missing, deltaspec dirs are NOT created
        (matches bash behavior: only deltaspec CLI creates them)."""
        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd = " ".join(str(a) for a in args)
            if "worktree add" in cmd:
                for a in args:
                    if "main" in str(a) and "worktrees" not in str(a):
                        Path(a).mkdir(parents=True, exist_ok=True)
                        break
            if "which" in cmd and "twl" in cmd:
                return MagicMock(returncode=1, stdout="", stderr="")
            return MagicMock(returncode=0, stdout="", stderr="")

        with patch("subprocess.run", side_effect=fake_run):
            self._make_mgr(tmp_path).create(
                "my-project",
                project_root=str(tmp_path),
                no_github=True,
            )
        # When deltaspec is absent, deltaspec dirs are NOT created
        # (matches bash behavior: only deltaspec creates them)
        project_dir = tmp_path / "my-project" / "main"
        assert not (project_dir / "deltaspec").exists()

    def test_src_and_tests_dirs_created_for_generic(self, tmp_path: Path) -> None:
        self._run_create("my-project", tmp_path, self._make_mgr(tmp_path))
        main_dir = tmp_path / "my-project" / "main"
        assert (main_dir / "src").is_dir()
        assert (main_dir / "tests").is_dir()

    def test_rnaseq_dirs_created(self, tmp_path: Path) -> None:
        templates = tmp_path / "templates"
        (templates / "rnaseq").mkdir(parents=True)
        self._run_create("rnaseq-proj", tmp_path, self._make_mgr(tmp_path, templates), "rnaseq")
        main_dir = tmp_path / "rnaseq-proj" / "main"
        assert (main_dir / "analysis").is_dir()
        assert (main_dir / "data" / "raw").is_dir()

    def test_returns_main_worktree_path(self, tmp_path: Path) -> None:
        result = self._run_create("my-project", tmp_path, self._make_mgr(tmp_path))
        assert result == tmp_path / "my-project" / "main"

    def test_git_calls_made(self, tmp_path: Path) -> None:
        """Verify expected git subcommands are invoked."""
        calls: list[str] = []

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd = " ".join(str(a) for a in args)
            calls.append(cmd)
            if "worktree add" in cmd:
                for a in args:
                    if "main" in str(a) and "worktrees" not in str(a):
                        Path(a).mkdir(parents=True, exist_ok=True)
                        break
            return MagicMock(returncode=0, stdout="", stderr="")

        with patch("subprocess.run", side_effect=fake_run):
            self._make_mgr(tmp_path).create(
                "my-project", project_root=str(tmp_path), no_github=True
            )

        git_calls = " ".join(calls)
        assert "init --bare" in git_calls
        assert "worktree add" in git_calls
        assert "git" in git_calls


# ---------------------------------------------------------------------------
# ProjectManager.migrate (AC3)
# ---------------------------------------------------------------------------


class TestMigrate:
    def _make_project(self, tmp_path: Path, has_claude_md: bool = True) -> Path:
        project = tmp_path / "my-project"
        project.mkdir()
        (project / ".git").write_text("gitdir: ../.bare\n")  # worktree .git file
        if has_claude_md:
            (project / "CLAUDE.md").write_text("# existing content\n")
        return project

    def test_dry_run_no_changes_applied(self, tmp_path: Path) -> None:
        project = self._make_project(tmp_path)
        mgr = ProjectManager()

        def fake_detect(_self: ProjectManager, _dir: Path) -> str:
            return "webapp-llm"

        with patch.object(ProjectManager, "_detect_project_type", fake_detect):
            mgr.migrate(dry_run=True, project_dir=project)

        # No backup created in dry-run
        assert not (project / "CLAUDE.md.backup").exists()

    def test_worktree_root_raises(self, tmp_path: Path) -> None:
        """Running migrate at worktree root (with /main subfolder) should raise."""
        project = tmp_path / "proj"
        project.mkdir()
        (project / ".git").mkdir()  # real .git dir = not worktree
        (project / ".git" / "worktrees").mkdir()
        main_dir = project / "main"
        main_dir.mkdir()
        (main_dir / ".git").write_text("gitdir: ../.git/worktrees/main\n")

        mgr = ProjectManager()
        with pytest.raises(ProjectError, match="main/"):
            mgr.migrate(project_dir=project)

    def test_no_git_no_claude_raises(self, tmp_path: Path) -> None:
        empty = tmp_path / "empty"
        empty.mkdir()
        mgr = ProjectManager()
        with pytest.raises(ProjectError, match="プロジェクトルート"):
            mgr.migrate(project_dir=empty)

    def test_detects_v1_deltaspec(self, tmp_path: Path) -> None:
        project = self._make_project(tmp_path)
        (project / "deltaspec").mkdir()
        (project / "deltaspec" / "config.yaml").write_text("")

        changes: list[str] = []

        def fake_detect(_self: ProjectManager, _dir: Path) -> str:
            return "rnaseq"

        original_apply = ProjectManager._apply_claude_md

        def capture_apply(self_, pdir, ptype, pname):  # type: ignore[no-untyped-def]
            changes.append("claude_md")

        with patch.object(ProjectManager, "_detect_project_type", fake_detect), \
             patch.object(ProjectManager, "_apply_claude_md", capture_apply), \
             patch.object(ProjectManager, "_apply_deltaspec") as mock_delta:
            mgr = ProjectManager()
            mgr.migrate(project_dir=project)

        # v1.x → no deltaspec migration needed
        mock_delta.assert_not_called()

    def test_applies_deltaspec_for_v0(self, tmp_path: Path) -> None:
        project = self._make_project(tmp_path)
        (project / "deltaspec").mkdir()
        (project / "deltaspec" / "project.md").write_text("")  # v0.x marker

        def fake_detect(_self: ProjectManager, _dir: Path) -> str:
            return "webapp-llm"

        with patch.object(ProjectManager, "_detect_project_type", fake_detect), \
             patch.object(ProjectManager, "_apply_claude_md"), \
             patch.object(ProjectManager, "_apply_deltaspec") as mock_delta:
            mgr = ProjectManager()
            mgr.migrate(project_dir=project)

        mock_delta.assert_called_once()

    def test_claude_md_backup_created_on_update(self, tmp_path: Path) -> None:
        project = self._make_project(tmp_path, has_claude_md=True)
        templates = tmp_path / "templates"
        (templates / "webapp-llm").mkdir(parents=True)
        (templates / "webapp-llm" / "CLAUDE.md").write_text("# template\n")

        def fake_detect(_self: ProjectManager, _dir: Path) -> str:
            return "webapp-llm"

        with patch.object(ProjectManager, "_detect_project_type", fake_detect), \
             patch.object(ProjectManager, "_apply_deltaspec"):
            mgr = ProjectManager(templates_base=templates)
            mgr.migrate(project_dir=project)

        assert (project / "CLAUDE.md.backup").exists()


# ---------------------------------------------------------------------------
# CLI main()
# ---------------------------------------------------------------------------


class TestMain:
    def test_no_args_shows_help(self, capsys: pytest.CaptureFixture[str]) -> None:
        result = main([])
        assert result == 0
        captured = capsys.readouterr()
        assert "create" in captured.out

    def test_help_flag(self, capsys: pytest.CaptureFixture[str]) -> None:
        result = main(["--help"])
        assert result == 0

    def test_unknown_command_returns_1(self) -> None:
        assert main(["bogus"]) == 1

    def test_create_no_name_returns_2(self) -> None:
        assert main(["create"]) == 2

    def test_create_invalid_name_returns_2(self) -> None:
        assert main(["create", "BadName"]) == 2

    def test_migrate_dry_run_returns_0(self) -> None:
        with patch.object(ProjectManager, "migrate", return_value=None):
            result = main(["migrate", "--dry-run"])
        assert result == 0

    def test_create_success_returns_0(self, tmp_path: Path) -> None:
        with patch.object(
            ProjectManager, "create", return_value=tmp_path / "proj" / "main"
        ):
            result = main(["create", "my-proj", "--no-github"])
        assert result == 0

    def test_create_project_error_returns_1(self) -> None:
        with patch.object(
            ProjectManager, "create", side_effect=ProjectError("fail")
        ):
            result = main(["create", "my-proj", "--no-github"])
        assert result == 1

    def test_create_arg_error_returns_2(self) -> None:
        with patch.object(
            ProjectManager, "create", side_effect=ProjectArgError("bad arg")
        ):
            result = main(["create", "my-proj"])
        assert result == 2
