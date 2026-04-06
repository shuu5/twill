"""Tests for twl.autopilot.worktree.

Covers:
- Branch name generation from Issue (slug + prefix logic) - AC2, AC5
- Branch name validation
- WorktreeManager.create (subprocess interactions mocked)
- CLI main() exit codes
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch, call

import pytest

from twl.autopilot.worktree import (
    WorktreeManager,
    WorktreeError,
    WorktreeArgError,
    generate_branch_name,
    validate_branch_name,
    _slugify,
    _label_to_prefix,
    _run_hook,
    _project_dir_from_worktree,
    main,
)


# ---------------------------------------------------------------------------
# _slugify
# ---------------------------------------------------------------------------


class TestSlugify:
    def test_removes_bracket_prefix(self) -> None:
        assert _slugify("[Feature] My Great Feature") == "my-great-feature"

    def test_removes_bug_prefix(self) -> None:
        assert _slugify("[Bug] Fix something") == "fix-something"

    def test_lowercases(self) -> None:
        assert _slugify("Hello World") == "hello-world"

    def test_removes_non_alnum(self) -> None:
        # Japanese characters removed, hyphens kept
        assert _slugify("src/twl/autopilot/project — Python化") == "srctwlautopilotproject-python"

    def test_deduplicates_hyphens(self) -> None:
        assert _slugify("foo  bar") == "foo-bar"

    def test_trims_hyphens(self) -> None:
        assert _slugify("[X] - hello -") == "-hello-".strip("-")

    def test_empty_string(self) -> None:
        assert _slugify("") == ""

    def test_bracket_only(self) -> None:
        assert _slugify("[Feature]") == ""

    def test_real_issue_17_title(self) -> None:
        title = "[Feature] src/twl/autopilot/project — プロジェクト/worktree 管理の Python 化"
        slug = _slugify(title)
        assert slug.startswith("srctwlautopilot")
        assert "-" in slug
        assert slug == slug.lower()


# ---------------------------------------------------------------------------
# _label_to_prefix
# ---------------------------------------------------------------------------


class TestLabelToPrefix:
    def test_bug_label(self) -> None:
        assert _label_to_prefix(["bug", "enhancement"]) == "fix"

    def test_documentation_label(self) -> None:
        assert _label_to_prefix(["documentation"]) == "docs"

    def test_refactor_label(self) -> None:
        assert _label_to_prefix(["refactor"]) == "refactor"

    def test_enhancement_defaults_to_feat(self) -> None:
        assert _label_to_prefix(["enhancement"]) == "feat"

    def test_empty_labels_defaults_to_feat(self) -> None:
        assert _label_to_prefix([]) == "feat"

    def test_bug_takes_priority(self) -> None:
        assert _label_to_prefix(["bug", "documentation"]) == "fix"

    def test_case_insensitive(self) -> None:
        assert _label_to_prefix(["Bug"]) == "fix"
        assert _label_to_prefix(["Documentation"]) == "docs"


# ---------------------------------------------------------------------------
# generate_branch_name
# ---------------------------------------------------------------------------


def _make_gh_result(title: str, labels: list[str]) -> MagicMock:
    m = MagicMock()
    m.returncode = 0
    m.stdout = json.dumps({
        "title": title,
        "labels": [{"name": lb} for lb in labels],
    })
    return m


class TestGenerateBranchName:
    def test_feat_prefix_from_enhancement(self) -> None:
        with patch("subprocess.run", return_value=_make_gh_result(
            "[Feature] Add new thing", ["enhancement"]
        )):
            branch = generate_branch_name("42")
        assert branch.startswith("feat/42-")
        assert "add-new-thing" in branch

    def test_fix_prefix_from_bug(self) -> None:
        with patch("subprocess.run", return_value=_make_gh_result(
            "[Bug] Crash on startup", ["bug"]
        )):
            branch = generate_branch_name("7")
        assert branch.startswith("fix/7-")

    def test_docs_prefix_from_documentation(self) -> None:
        with patch("subprocess.run", return_value=_make_gh_result(
            "Update README", ["documentation"]
        )):
            branch = generate_branch_name("3")
        assert branch.startswith("docs/3-")

    def test_max_50_chars(self) -> None:
        long_title = "A" * 200
        with patch("subprocess.run", return_value=_make_gh_result(long_title, [])):
            branch = generate_branch_name("1")
        assert len(branch) <= 50

    def test_no_trailing_hyphen_after_truncation(self) -> None:
        # Slug that would end with hyphen after truncation
        title = "[Feature] " + "ab-" * 20
        with patch("subprocess.run", return_value=_make_gh_result(title, [])):
            branch = generate_branch_name("1")
        assert not branch.endswith("-")

    def test_gh_failure_raises(self) -> None:
        fail = MagicMock()
        fail.returncode = 1
        with patch("subprocess.run", return_value=fail):
            with pytest.raises(WorktreeError, match="見つかりません"):
                generate_branch_name("99")

    def test_invalid_issue_num_raises(self) -> None:
        with pytest.raises(WorktreeArgError):
            generate_branch_name("abc")

    def test_invalid_repo_raises(self) -> None:
        with pytest.raises(WorktreeArgError):
            generate_branch_name("1", repo="bad repo!")

    def test_repo_flag_passed_to_gh(self) -> None:
        calls: list[Any] = []
        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            calls.append(args)
            return _make_gh_result("title", [])
        with patch("subprocess.run", side_effect=fake_run):
            generate_branch_name("5", repo="owner/repo")
        assert "-R" in calls[0]
        assert "owner/repo" in calls[0]

    def test_real_issue_17(self) -> None:
        title = "[Feature] src/twl/autopilot/project — プロジェクト/worktree 管理の Python 化"
        with patch("subprocess.run", return_value=_make_gh_result(
            title, ["enhancement", "refined", "ctx/autopilot", "scope/plugins-twl"]
        )):
            branch = generate_branch_name("17")
        assert branch.startswith("feat/17-")
        assert len(branch) <= 50
        assert branch == branch.lower()
        assert re.match(r"^[a-z0-9/-]+$", branch)


# ---------------------------------------------------------------------------
# validate_branch_name
# ---------------------------------------------------------------------------


class TestValidateBranchName:
    def test_valid_feat(self) -> None:
        validate_branch_name("feat/17-some-feature")  # no raise

    def test_valid_fix(self) -> None:
        validate_branch_name("fix/42-crash")

    def test_valid_docs(self) -> None:
        validate_branch_name("docs/3-update-readme")

    def test_valid_refactor(self) -> None:
        validate_branch_name("refactor/10-cleanup")

    def test_valid_test(self) -> None:
        validate_branch_name("test/5-add-tests")

    def test_valid_chore(self) -> None:
        validate_branch_name("chore/1-update-deps")

    def test_reserved_main(self) -> None:
        with pytest.raises(WorktreeArgError, match="予約語"):
            validate_branch_name("main")

    def test_reserved_master(self) -> None:
        with pytest.raises(WorktreeArgError, match="予約語"):
            validate_branch_name("master")

    def test_reserved_head(self) -> None:
        with pytest.raises(WorktreeArgError, match="予約語"):
            validate_branch_name("HEAD")

    def test_unknown_prefix_with_slash(self) -> None:
        with pytest.raises(WorktreeArgError, match="プレフィックス"):
            validate_branch_name("unknown/foo")

    def test_uppercase_rejected(self) -> None:
        with pytest.raises(WorktreeArgError, match="英小文字"):
            validate_branch_name("feat/Foo")

    def test_too_long(self) -> None:
        with pytest.raises(WorktreeArgError, match="50文字"):
            validate_branch_name("feat/" + "a" * 50)

    def test_no_slash_allowed_without_prefix(self) -> None:
        # Plain name without slash is fine (no prefix constraint)
        validate_branch_name("my-branch")  # no raise


# ---------------------------------------------------------------------------
# WorktreeManager.create
# ---------------------------------------------------------------------------


class TestWorktreeManagerCreate:
    """Integration-style tests with subprocess mocked."""

    def _make_completed(self, rc: int = 0, stdout: str = "", stderr: str = "") -> MagicMock:
        m = MagicMock(spec=subprocess.CompletedProcess)
        m.returncode = rc
        m.stdout = stdout
        m.stderr = stderr
        return m

    def test_creates_worktree_directory(self, tmp_path: Path) -> None:
        # Simulate a git bare repo structure
        bare = tmp_path / ".bare"
        bare.mkdir()
        main_dir = tmp_path / "main"
        main_dir.mkdir()

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd = " ".join(str(a) for a in args)
            if "rev-parse" in cmd and "git-common-dir" in cmd:
                return self._make_completed(0, stdout=str(bare))
            if "worktree add" in cmd:
                # Simulate worktree creation
                target = Path(args[args.index(str(tmp_path / "worktrees" / "feat" / "1-test"))])
                target.mkdir(parents=True, exist_ok=True)
                return self._make_completed(0)
            # push, which/uv/rscript → success
            return self._make_completed(0)

        with patch("subprocess.run", side_effect=fake_run):
            mgr = WorktreeManager()
            result = mgr.create("feat/1-test")
        assert "feat/1-test" in str(result)

    def test_existing_worktree_raises(self, tmp_path: Path) -> None:
        bare = tmp_path / ".bare"
        bare.mkdir()
        existing = tmp_path / "worktrees" / "feat" / "1-exists"
        existing.mkdir(parents=True)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd = " ".join(str(a) for a in args)
            if "git-common-dir" in cmd:
                return self._make_completed(0, stdout=str(bare))
            return self._make_completed(0)

        with patch("subprocess.run", side_effect=fake_run):
            mgr = WorktreeManager()
            with pytest.raises(WorktreeError, match="既に存在"):
                mgr.create("feat/1-exists")

    def test_invalid_repo_flag_raises(self) -> None:
        mgr = WorktreeManager()
        with pytest.raises(WorktreeArgError):
            mgr.create("feat/1-test", repo="bad repo!")

    def test_issue_number_resolves_branch(self, tmp_path: Path) -> None:
        bare = tmp_path / ".bare"
        bare.mkdir()

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd = " ".join(str(a) for a in args)
            if "issue view" in cmd:
                return self._make_completed(
                    0,
                    stdout=json.dumps({"title": "[Feature] My feat", "labels": []}),
                )
            if "git-common-dir" in cmd:
                return self._make_completed(0, stdout=str(bare))
            if "worktree add" in cmd:
                # find the target dir in args and create it
                for i, a in enumerate(args):
                    if "worktrees" in str(a):
                        Path(a).mkdir(parents=True, exist_ok=True)
                        break
                return self._make_completed(0)
            return self._make_completed(0)

        with patch("subprocess.run", side_effect=fake_run):
            mgr = WorktreeManager()
            result = mgr.create("#42")
        assert "feat/42-" in str(result)


# ---------------------------------------------------------------------------
# CLI main()
# ---------------------------------------------------------------------------


class TestMain:
    def test_no_args_returns_1(self) -> None:
        assert main([]) == 1

    def test_unknown_command_returns_1(self) -> None:
        assert main(["delete", "foo"]) == 1

    def test_create_no_branch_returns_2(self) -> None:
        assert main(["create"]) == 2

    def test_invalid_repo_flag_returns_2(self) -> None:
        # bad -R triggers WorktreeArgError inside create
        with patch(
            "twl.autopilot.worktree.WorktreeManager.create",
            side_effect=WorktreeArgError("bad repo"),
        ):
            assert main(["create", "feat/1-foo", "-R", "bad repo!"]) == 2

    def test_worktree_error_returns_1(self) -> None:
        with patch(
            "twl.autopilot.worktree.WorktreeManager.create",
            side_effect=WorktreeError("something failed"),
        ):
            assert main(["create", "feat/1-test"]) == 1

    def test_success_returns_0(self) -> None:
        with patch(
            "twl.autopilot.worktree.WorktreeManager.create",
            return_value=Path("/tmp/worktrees/feat/1-test"),
        ):
            assert main(["create", "feat/1-test"]) == 0

    def test_from_flag_passed(self) -> None:
        captured: dict[str, Any] = {}

        def fake_create(self_, branch, base_branch="main", repo=None):  # type: ignore[no-untyped-def]
            captured["base_branch"] = base_branch
            return Path("/tmp/wt")

        with patch.object(WorktreeManager, "create", fake_create):
            main(["create", "feat/1-test", "--from", "develop"])
        assert captured["base_branch"] == "develop"

    def test_teardown_hook_no_args_returns_2(self) -> None:
        assert main(["teardown-hook"]) == 2

    def test_teardown_hook_calls_run_teardown_hook(self, tmp_path: Path) -> None:
        called_with: list[Path] = []

        def fake_teardown(wt_dir: Path) -> None:
            called_with.append(wt_dir)

        with patch.object(WorktreeManager, "run_teardown_hook", staticmethod(fake_teardown)):
            result = main(["teardown-hook", str(tmp_path)])
        assert result == 0
        assert called_with == [tmp_path]


# ---------------------------------------------------------------------------
# _run_hook
# ---------------------------------------------------------------------------


class TestRunHook:
    def test_runs_worktree_hook_first(self, tmp_path: Path) -> None:
        project_dir = tmp_path / "project"
        worktree_dir = tmp_path / "worktrees" / "feat" / "1-test"
        worktree_hook = worktree_dir / ".twl" / "setup"
        worktree_hook.parent.mkdir(parents=True)
        worktree_hook.write_text("#!/bin/sh\nexit 0\n")
        worktree_hook.chmod(0o755)

        # Also create project root hook (should NOT be called)
        main_hook = project_dir / "main" / ".twl" / "setup"
        main_hook.parent.mkdir(parents=True)
        main_hook.write_text("#!/bin/sh\nexit 0\n")
        main_hook.chmod(0o755)

        calls: list[Any] = []
        original_run = subprocess.run

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            calls.append(args)
            return MagicMock(returncode=0)

        with patch("subprocess.run", side_effect=fake_run):
            result = _run_hook("setup", worktree_dir, project_dir)

        assert result is True
        assert any(str(worktree_hook) in str(a) for a in calls[0])

    def test_falls_back_to_project_root_hook(self, tmp_path: Path) -> None:
        project_dir = tmp_path / "project"
        worktree_dir = tmp_path / "worktrees" / "feat" / "1-test"
        worktree_dir.mkdir(parents=True)

        main_hook = project_dir / "main" / ".twl" / "setup"
        main_hook.parent.mkdir(parents=True)
        main_hook.write_text("#!/bin/sh\nexit 0\n")
        main_hook.chmod(0o755)

        calls: list[Any] = []

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            calls.append(args)
            return MagicMock(returncode=0)

        with patch("subprocess.run", side_effect=fake_run):
            result = _run_hook("setup", worktree_dir, project_dir)

        assert result is True
        assert any(str(main_hook) in str(a) for a in calls[0])

    def test_returns_false_when_no_hook(self, tmp_path: Path) -> None:
        project_dir = tmp_path / "project"
        worktree_dir = tmp_path / "worktrees" / "feat" / "1-test"
        worktree_dir.mkdir(parents=True)
        (project_dir / "main" / ".twl").mkdir(parents=True)

        result = _run_hook("setup", worktree_dir, project_dir)
        assert result is False

    def test_non_executable_hook_ignored(self, tmp_path: Path) -> None:
        project_dir = tmp_path / "project"
        worktree_dir = tmp_path / "worktrees" / "feat" / "1-test"
        hook = worktree_dir / ".twl" / "setup"
        hook.parent.mkdir(parents=True)
        hook.write_text("#!/bin/sh\nexit 0\n")
        hook.chmod(0o644)  # not executable

        result = _run_hook("setup", worktree_dir, project_dir)
        assert result is False

    def test_warning_on_nonzero_exit(self, tmp_path: Path, capsys: Any) -> None:
        project_dir = tmp_path / "project"
        worktree_dir = tmp_path / "worktrees" / "feat" / "1-test"
        hook = worktree_dir / ".twl" / "setup"
        hook.parent.mkdir(parents=True)
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            return MagicMock(returncode=1)

        with patch("subprocess.run", side_effect=fake_run):
            result = _run_hook("setup", worktree_dir, project_dir)

        assert result is True
        captured = capsys.readouterr()
        assert "警告" in captured.out

    def test_twl_project_root_env_passed(self, tmp_path: Path) -> None:
        project_dir = tmp_path / "project"
        worktree_dir = tmp_path / "worktrees" / "feat" / "1-test"
        hook = worktree_dir / ".twl" / "setup"
        hook.parent.mkdir(parents=True)
        hook.write_text("#!/bin/sh\nexit 0\n")
        hook.chmod(0o755)

        captured_kwargs: dict[str, Any] = {}

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            captured_kwargs.update(kwargs)
            return MagicMock(returncode=0)

        with patch("subprocess.run", side_effect=fake_run):
            _run_hook("setup", worktree_dir, project_dir)

        assert captured_kwargs.get("env", {}).get("TWL_PROJECT_ROOT") == str(project_dir)


# ---------------------------------------------------------------------------
# WorktreeManager.run_teardown_hook
# ---------------------------------------------------------------------------


class TestRunTeardownHook:
    def test_skips_when_dir_missing(self, tmp_path: Path) -> None:
        missing = tmp_path / "nonexistent"
        # Should not raise
        WorktreeManager.run_teardown_hook(missing)

    def test_calls_run_hook_when_dir_exists(self, tmp_path: Path) -> None:
        worktree_dir = tmp_path / "wt"
        worktree_dir.mkdir()
        project_dir = tmp_path / "project"

        with patch(
            "twl.autopilot.worktree._project_dir_from_worktree",
            return_value=project_dir,
        ) as mock_proj, patch(
            "twl.autopilot.worktree._run_hook",
        ) as mock_hook:
            WorktreeManager.run_teardown_hook(worktree_dir)

        mock_proj.assert_called_once_with(worktree_dir)
        mock_hook.assert_called_once_with("teardown", worktree_dir, project_dir)

    def test_warns_when_project_dir_unresolvable(
        self, tmp_path: Path, capsys: Any
    ) -> None:
        worktree_dir = tmp_path / "wt"
        worktree_dir.mkdir()

        with patch(
            "twl.autopilot.worktree._project_dir_from_worktree",
            return_value=None,
        ):
            WorktreeManager.run_teardown_hook(worktree_dir)

        captured = capsys.readouterr()
        assert "警告" in captured.out


# ---------------------------------------------------------------------------
# WorktreeManager.create — hook / _sync_deps fallback
# ---------------------------------------------------------------------------


class TestWorktreeManagerCreateHookFallback:
    def _make_completed(self, rc: int = 0, stdout: str = "", stderr: str = "") -> MagicMock:
        m = MagicMock(spec=subprocess.CompletedProcess)
        m.returncode = rc
        m.stdout = stdout
        m.stderr = stderr
        return m

    def test_sync_deps_skipped_when_setup_hook_present(self, tmp_path: Path) -> None:
        bare = tmp_path / ".bare"
        bare.mkdir()

        worktree_dir = tmp_path / "worktrees" / "feat" / "1-test"

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd = " ".join(str(a) for a in args)
            if "git-common-dir" in cmd:
                return self._make_completed(0, stdout=str(bare))
            if "worktree add" in cmd:
                worktree_dir.mkdir(parents=True, exist_ok=True)
                # Create setup hook
                hook = worktree_dir / ".twl" / "setup"
                hook.parent.mkdir()
                hook.write_text("#!/bin/sh\nexit 0\n")
                hook.chmod(0o755)
                return self._make_completed(0)
            return self._make_completed(0)

        with patch("subprocess.run", side_effect=fake_run):
            with patch.object(WorktreeManager, "_sync_deps") as mock_sync:
                mgr = WorktreeManager()
                mgr.create("feat/1-test")
        mock_sync.assert_not_called()

    def test_sync_deps_called_when_no_setup_hook(self, tmp_path: Path) -> None:
        bare = tmp_path / ".bare"
        bare.mkdir()

        worktree_dir = tmp_path / "worktrees" / "feat" / "1-test"

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd = " ".join(str(a) for a in args)
            if "git-common-dir" in cmd:
                return self._make_completed(0, stdout=str(bare))
            if "worktree add" in cmd:
                worktree_dir.mkdir(parents=True, exist_ok=True)
                return self._make_completed(0)
            return self._make_completed(0)

        with patch("subprocess.run", side_effect=fake_run):
            with patch.object(WorktreeManager, "_sync_deps") as mock_sync:
                mgr = WorktreeManager()
                mgr.create("feat/1-test")
        mock_sync.assert_called_once_with(worktree_dir)
