"""Integration tests for issue-437: OpenSpec -> DeltaSpec migration.

Scenario source: deltaspec/changes/issue-437/specs/openspec-migration/spec.md

These tests verify the correctness of the migration procedure (data-migration,
no Python code changes). Each test sets up a tmp_path environment that mirrors
the real repository structure, performs the migration steps being validated,
and asserts the expected post-migration state.
"""

import sys
import shutil
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from twl.spec.archive import cmd_archive
from twl.spec.list import cmd_list


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_openspec_change(
    changes_dir: Path,
    name: str,
    *,
    archive: bool = False,
    spec_content: str | None = None,
) -> Path:
    """Create a change directory containing a .openspec.yaml (old format)."""
    parent = changes_dir / "archive" if archive else changes_dir
    change_dir = parent / name
    change_dir.mkdir(parents=True, exist_ok=True)
    (change_dir / ".openspec.yaml").write_text(
        "schema: spec-driven\ncreated: 2026-03-27\n", encoding="utf-8"
    )
    if spec_content is not None:
        specs_dir = change_dir / "specs" / "cap-a"
        specs_dir.mkdir(parents=True, exist_ok=True)
        (specs_dir / "spec.md").write_text(spec_content, encoding="utf-8")
    return change_dir


def _rename_openspec_to_deltaspec(changes_dir: Path) -> list[Path]:
    """
    Migration step: rename all .openspec.yaml files to .deltaspec.yaml and
    ensure required fields (name, status) are present.

    Returns the list of newly created .deltaspec.yaml paths.
    """
    renamed: list[Path] = []
    for openspec_file in changes_dir.rglob(".openspec.yaml"):
        data = yaml.safe_load(openspec_file.read_text(encoding="utf-8")) or {}

        # Ensure required fields exist for active changes
        relative = openspec_file.relative_to(changes_dir)
        is_archive = relative.parts[0] == "archive"
        if not is_archive:
            data.setdefault("name", openspec_file.parent.name)
            data.setdefault("status", "pending")

        deltaspec_file = openspec_file.parent / ".deltaspec.yaml"
        deltaspec_file.write_text(
            yaml.dump(data, allow_unicode=True, default_flow_style=False),
            encoding="utf-8",
        )
        openspec_file.unlink()
        renamed.append(deltaspec_file)
    return renamed


# ---------------------------------------------------------------------------
# Scenario: active changes のリネームと必須フィールド補完
# WHEN  cli/twl/deltaspec/changes/ 配下（archive/ 除く）に .openspec.yaml が存在する
# THEN  各ファイルが .deltaspec.yaml にリネームされ、
#       name フィールドと status: pending フィールドが存在すること
# ---------------------------------------------------------------------------

class TestActiveChangesRenameAndFieldCompletion:
    def test_openspec_yaml_renamed_to_deltaspec_yaml(self, tmp_path, monkeypatch):
        """Active .openspec.yaml is renamed to .deltaspec.yaml."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        _make_openspec_change(changes_dir, "alpha-change")
        _make_openspec_change(changes_dir, "beta-change")

        _rename_openspec_to_deltaspec(changes_dir)

        assert not (changes_dir / "alpha-change" / ".openspec.yaml").exists()
        assert not (changes_dir / "beta-change" / ".openspec.yaml").exists()
        assert (changes_dir / "alpha-change" / ".deltaspec.yaml").exists()
        assert (changes_dir / "beta-change" / ".deltaspec.yaml").exists()

    def test_name_field_added_to_active_change(self, tmp_path, monkeypatch):
        """name field is added when absent in an active change."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        _make_openspec_change(changes_dir, "my-feature")

        _rename_openspec_to_deltaspec(changes_dir)

        data = yaml.safe_load(
            (changes_dir / "my-feature" / ".deltaspec.yaml").read_text(encoding="utf-8")
        )
        assert "name" in data
        assert data["name"] == "my-feature"

    def test_status_pending_added_to_active_change(self, tmp_path, monkeypatch):
        """status: pending is added when absent in an active change."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        _make_openspec_change(changes_dir, "my-feature")

        _rename_openspec_to_deltaspec(changes_dir)

        data = yaml.safe_load(
            (changes_dir / "my-feature" / ".deltaspec.yaml").read_text(encoding="utf-8")
        )
        assert data.get("status") == "pending"

    def test_original_schema_field_preserved(self, tmp_path, monkeypatch):
        """Existing fields (schema, created) are preserved after rename."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        _make_openspec_change(changes_dir, "preserve-fields")

        _rename_openspec_to_deltaspec(changes_dir)

        data = yaml.safe_load(
            (changes_dir / "preserve-fields" / ".deltaspec.yaml").read_text(encoding="utf-8")
        )
        assert data.get("schema") == "spec-driven"
        assert data.get("created") is not None

    def test_multiple_active_changes_all_renamed(self, tmp_path, monkeypatch):
        """All active changes in a directory are renamed in one pass."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        names = [f"change-{i:02d}" for i in range(5)]
        for n in names:
            _make_openspec_change(changes_dir, n)

        _rename_openspec_to_deltaspec(changes_dir)

        for n in names:
            assert not (changes_dir / n / ".openspec.yaml").exists()
            assert (changes_dir / n / ".deltaspec.yaml").exists()


# ---------------------------------------------------------------------------
# Scenario: archived changes のリネーム
# WHEN  cli/twl/deltaspec/changes/archive/ 配下に .openspec.yaml が存在する
# THEN  各ファイルが .deltaspec.yaml にリネームされること
# ---------------------------------------------------------------------------

class TestArchivedChangesRename:
    def test_archived_openspec_yaml_renamed(self, tmp_path, monkeypatch):
        """Archived .openspec.yaml is renamed to .deltaspec.yaml."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        _make_openspec_change(changes_dir, "old-chain-feature", archive=True)

        _rename_openspec_to_deltaspec(changes_dir)

        archive_dir = changes_dir / "archive"
        assert not (archive_dir / "old-chain-feature" / ".openspec.yaml").exists()
        assert (archive_dir / "old-chain-feature" / ".deltaspec.yaml").exists()

    def test_archived_change_does_not_get_status_field(self, tmp_path, monkeypatch):
        """Archived changes are NOT required to have status: pending injected."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        _make_openspec_change(changes_dir, "chain-generate-check-all", archive=True)

        _rename_openspec_to_deltaspec(changes_dir)

        data = yaml.safe_load(
            (
                changes_dir / "archive" / "chain-generate-check-all" / ".deltaspec.yaml"
            ).read_text(encoding="utf-8")
        )
        # status may or may not be present; it must NOT be force-injected as "pending"
        # (archived changes are done, not pending)
        assert data.get("status") != "pending"

    def test_archive_and_active_both_renamed_independently(self, tmp_path, monkeypatch):
        """Active and archived .openspec.yaml files are both renamed in one pass."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        _make_openspec_change(changes_dir, "active-one")
        _make_openspec_change(changes_dir, "archived-one", archive=True)

        _rename_openspec_to_deltaspec(changes_dir)

        assert (changes_dir / "active-one" / ".deltaspec.yaml").exists()
        assert (changes_dir / "archive" / "archived-one" / ".deltaspec.yaml").exists()
        assert not list(changes_dir.rglob(".openspec.yaml"))


# ---------------------------------------------------------------------------
# Scenario: archive 後のアクティブ change ゼロ確認
# WHEN  全 active change に対して twl spec archive --yes を実行した後
# THEN  twl spec list がエラーなく終了し、アクティブ change が 0 件と表示されること
# ---------------------------------------------------------------------------

class TestArchiveAllActiveChanges:
    def _setup_migrated_changes(self, tmp_path: Path, names: list[str]) -> Path:
        """Create active changes with .deltaspec.yaml (post-migration state)."""
        changes_dir = tmp_path / "deltaspec" / "changes"
        for name in names:
            change_dir = changes_dir / name
            change_dir.mkdir(parents=True, exist_ok=True)
            (change_dir / ".deltaspec.yaml").write_text(
                f"schema: spec-driven\nname: {name}\nstatus: pending\ncreated: 2026-03-27\n",
                encoding="utf-8",
            )
        return changes_dir

    def test_list_returns_zero_after_all_archived(self, tmp_path, monkeypatch, capsys):
        """After archiving all active changes, cmd_list reports 0 active changes."""
        monkeypatch.chdir(tmp_path)
        names = ["alpha", "beta", "gamma"]
        self._setup_migrated_changes(tmp_path, names)

        # Archive all active changes
        for name in names:
            rc = cmd_archive(name, yes=True)
            assert rc == 0, f"cmd_archive({name!r}) returned non-zero"

        capsys.readouterr()  # flush
        rc = cmd_list()
        assert rc == 0
        out = capsys.readouterr().out
        assert "No changes found." in out

    def test_list_shows_no_active_after_all_archived(self, tmp_path, monkeypatch, capsys):
        """Active change names must not appear in cmd_list output after archive."""
        monkeypatch.chdir(tmp_path)
        names = ["rename-complete", "chain-validate", "depsyaml-scripts-ssot"]
        self._setup_migrated_changes(tmp_path, names)

        for name in names:
            cmd_archive(name, yes=True)

        capsys.readouterr()
        cmd_list()
        out = capsys.readouterr().out
        for name in names:
            assert name not in out, f"Archived change '{name}' still visible in list"

    def test_archive_directory_contains_all_changes(self, tmp_path, monkeypatch):
        """After archiving, each change directory exists under archive/."""
        monkeypatch.chdir(tmp_path)
        names = ["alpha", "beta"]
        self._setup_migrated_changes(tmp_path, names)

        for name in names:
            cmd_archive(name, yes=True)

        archive_dir = tmp_path / "deltaspec" / "changes" / "archive"
        for name in names:
            assert (archive_dir / name).is_dir(), f"'{name}' not found in archive/"


# ---------------------------------------------------------------------------
# Scenario: 移行後の残存ファイルなし確認
# WHEN  全リネームと archive が完了した後
# THEN  find cli/twl/deltaspec/changes -name ".openspec.yaml" が 0 件を返すこと
# ---------------------------------------------------------------------------

class TestNoRemainingOpenspecFiles:
    def test_no_openspec_yaml_after_rename(self, tmp_path, monkeypatch):
        """No .openspec.yaml remains after running the rename migration."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        # Active changes
        for name in ["alpha", "beta", "gamma"]:
            _make_openspec_change(changes_dir, name)
        # Archived change
        _make_openspec_change(changes_dir, "old-archived", archive=True)

        _rename_openspec_to_deltaspec(changes_dir)

        remaining = list(changes_dir.rglob(".openspec.yaml"))
        assert remaining == [], f"Found residual .openspec.yaml files: {remaining}"

    def test_no_openspec_yaml_after_rename_and_archive(self, tmp_path, monkeypatch):
        """No .openspec.yaml remains after rename + archive of all active changes."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        active_names = ["chain-validate", "model-specialist-validate"]
        for name in active_names:
            _make_openspec_change(changes_dir, name)
        _make_openspec_change(changes_dir, "chain-generate-check-all", archive=True)

        # Step 1: rename all .openspec.yaml to .deltaspec.yaml
        _rename_openspec_to_deltaspec(changes_dir)

        # Step 2: archive all active changes via Python API
        for name in active_names:
            rc = cmd_archive(name, yes=True)
            assert rc == 0

        remaining = list(changes_dir.rglob(".openspec.yaml"))
        assert remaining == [], f"Residual .openspec.yaml files found: {remaining}"

    def test_deltaspec_yaml_created_for_every_former_openspec(self, tmp_path, monkeypatch):
        """Every former .openspec.yaml location has a corresponding .deltaspec.yaml."""
        monkeypatch.chdir(tmp_path)
        changes_dir = tmp_path / "deltaspec" / "changes"
        active_names = ["fix-orphan", "tech-debt"]
        archive_names = ["old-feature"]

        for name in active_names:
            _make_openspec_change(changes_dir, name)
        for name in archive_names:
            _make_openspec_change(changes_dir, name, archive=True)

        _rename_openspec_to_deltaspec(changes_dir)

        for name in active_names:
            assert (changes_dir / name / ".deltaspec.yaml").exists()
        for name in archive_names:
            assert (changes_dir / "archive" / name / ".deltaspec.yaml").exists()

    def test_real_repo_has_no_openspec_yaml(self, monkeypatch):
        """Smoke test: verify the actual worktree has 0 .openspec.yaml files.

        This test is intentionally skipped when run outside the issue-437 worktree.
        It exercises the final post-migration state of the real repository.
        """
        import os

        repo_root = Path(__file__).parent.parent.parent.parent.parent.parent
        changes_dir = repo_root / "cli" / "twl" / "deltaspec" / "changes"
        if not changes_dir.is_dir():
            pytest.skip("Not running inside the twill worktree; skipping real-repo smoke test.")

        remaining = list(changes_dir.rglob(".openspec.yaml"))
        assert remaining == [], (
            f"Migration incomplete: {len(remaining)} .openspec.yaml file(s) still present:\n"
            + "\n".join(f"  {p}" for p in remaining)
        )
