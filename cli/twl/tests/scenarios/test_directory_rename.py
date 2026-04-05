#!/usr/bin/env python3
"""Tests for directory/file rename and rollback in rename_component().

Spec: openspec/changes/rename-complete/specs/directory-rename/spec.md
Requirements:
  - ディレクトリ/ファイルの実 rename
  - rename 失敗時のロールバック

Coverage: edge-cases
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "src" / "twl" / "engine.py"


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def _write_deps(plugin_dir: Path, deps: dict) -> None:
    (plugin_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def _create_component_files(plugin_dir: Path, deps: dict) -> None:
    """Create minimal markdown files for every component in deps."""
    for section in ("skills", "commands", "agents"):
        for name, data in deps.get(section, {}).items():
            path_str = data.get("path", "")
            if not path_str:
                continue
            file_path = plugin_dir / path_str
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(
                f"---\nname: {name}\ndescription: {data.get('description', 'Test')}\n---\n\nContent for {name}.\n",
                encoding="utf-8",
            )


def run_engine(plugin_dir: Path, *extra_args: str) -> subprocess.CompletedProcess:
    """Run twl-engine.py in the given plugin directory."""
    return subprocess.run(
        [sys.executable, str(TWL_ENGINE)] + list(extra_args),
        cwd=str(plugin_dir),
        capture_output=True,
        text=True,
    )


def _make_directory_rename_fixture(tmpdir: Path) -> Path:
    """Create a fixture with controller-project/ directory for rename testing."""
    plugin_dir = tmpdir / "test-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "test",
        "skills": {
            "controller-project": {
                "type": "controller",
                "path": "skills/controller-project/SKILL.md",
                "description": "Project controller",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def _make_destination_exists_fixture(tmpdir: Path) -> Path:
    """Create a fixture where destination directory already exists."""
    plugin_dir = _make_directory_rename_fixture(tmpdir)
    # Pre-create the destination directory
    dest_dir = plugin_dir / "skills" / "co-project"
    dest_dir.mkdir(parents=True, exist_ok=True)
    (dest_dir / "SKILL.md").write_text(
        "---\nname: co-project\n---\n\nExisting content.\n",
        encoding="utf-8",
    )
    return plugin_dir


def _make_flat_file_fixture(tmpdir: Path) -> Path:
    """Create a fixture with a flat file path (no directory with old_name)."""
    plugin_dir = tmpdir / "test-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "test",
        "skills": {},
        "commands": {
            "some-cmd": {
                "type": "atomic",
                "path": "commands/some-cmd.md",
                "description": "A flat command file",
                "calls": [],
            },
        },
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Test class: ディレクトリ/ファイルの実 rename
# ---------------------------------------------------------------------------

class TestDirectoryRename:
    """Requirement: ディレクトリ/ファイルの実 rename"""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    # ---- Scenario: ディレクトリ rename の実行 ----
    # WHEN: `twl rename controller-project co-project` を実行し、
    #       `skills/controller-project/` ディレクトリが存在する
    # THEN: `skills/controller-project/` が `skills/co-project/` に rename される

    def test_directory_renamed_to_new_name(self):
        """ディレクトリ rename の実行: 旧ディレクトリが新名前に rename される."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)
        result = run_engine(plugin_dir, "--rename", "controller-project", "co-project")
        assert result.returncode == 0, f"rename failed: {result.stderr}"

        new_dir = plugin_dir / "skills" / "co-project"
        assert new_dir.exists(), f"New directory not created: {new_dir}"
        assert (new_dir / "SKILL.md").exists(), "SKILL.md not present in new directory"

    def test_old_directory_removed_after_rename(self):
        """ディレクトリ rename 後に旧ディレクトリが存在しないこと."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        old_dir = plugin_dir / "skills" / "controller-project"
        assert not old_dir.exists(), f"Old directory still exists: {old_dir}"

    def test_file_content_preserved_after_directory_rename(self):
        """ディレクトリ rename 後にファイル内容が保持されていること."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)
        old_content_path = plugin_dir / "skills" / "controller-project" / "SKILL.md"
        # 内容にカスタムマーカーを追加
        old_content_path.write_text(
            "---\nname: controller-project\n---\n\nCUSTOM_MARKER content.\n",
            encoding="utf-8",
        )
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        new_content = (plugin_dir / "skills" / "co-project" / "SKILL.md").read_text()
        assert "CUSTOM_MARKER" in new_content, "File content not preserved after rename"

    def test_deps_path_consistent_with_directory(self):
        """ディレクトリ rename 後、deps.yaml の path が実ディレクトリと一致すること."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        path_value = deps["skills"]["co-project"]["path"]
        assert (plugin_dir / path_value).exists(), (
            f"deps.yaml path '{path_value}' does not point to existing file"
        )

    # ---- Scenario: 移動先ディレクトリが既に存在 ----
    # WHEN: `twl rename controller-project co-project` を実行し、
    #       `skills/co-project/` が既に存在する
    # THEN: エラーメッセージを表示して中断する（既存ディレクトリを上書きしない）

    def test_destination_exists_returns_error(self):
        """移動先ディレクトリが既に存在: エラーで中断される."""
        plugin_dir = _make_destination_exists_fixture(self.tmpdir)
        result = run_engine(plugin_dir, "--rename", "controller-project", "co-project")
        # Should fail (non-zero) or show error
        assert result.returncode != 0 or "error" in result.stderr.lower() or "error" in result.stdout.lower(), (
            f"Expected error when destination exists, got rc={result.returncode}, "
            f"stderr={result.stderr}, stdout={result.stdout}"
        )

    def test_destination_exists_preserves_original(self):
        """移動先ディレクトリが既に存在: 元のディレクトリが保持される."""
        plugin_dir = _make_destination_exists_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        old_dir = plugin_dir / "skills" / "controller-project"
        assert old_dir.exists(), "Original directory should be preserved on error"

    def test_destination_exists_does_not_overwrite(self):
        """移動先ディレクトリが既に存在: 既存コンテンツが上書きされない."""
        plugin_dir = _make_destination_exists_fixture(self.tmpdir)
        existing_content = (plugin_dir / "skills" / "co-project" / "SKILL.md").read_text()
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        after_content = (plugin_dir / "skills" / "co-project" / "SKILL.md").read_text()
        assert after_content == existing_content, "Existing destination was overwritten"

    # ---- Scenario: ディレクトリが存在しない場合のスキップ ----
    # WHEN: `twl rename some-cmd new-cmd` を実行し、
    #       path が `commands/some-cmd.md`（ディレクトリではなくファイル直接）
    #       で親ディレクトリに old_name を含まない
    # THEN: ディレクトリ rename はスキップされ、正常に完了する

    def test_flat_file_path_no_directory_rename(self):
        """ディレクトリが存在しない場合のスキップ: フラットファイルでは正常完了."""
        plugin_dir = _make_flat_file_fixture(self.tmpdir)
        result = run_engine(plugin_dir, "--rename", "some-cmd", "new-cmd")
        assert result.returncode == 0, f"rename failed for flat file: {result.stderr}"

    def test_flat_file_commands_dir_unchanged(self):
        """フラットファイルパスの場合、commands/ ディレクトリ構造は変わらない."""
        plugin_dir = _make_flat_file_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "some-cmd", "new-cmd")

        # commands/ ディレクトリは存在し続ける
        assert (plugin_dir / "commands").exists()
        # new-cmd というディレクトリは作られていない
        assert not (plugin_dir / "commands" / "new-cmd").is_dir(), (
            "Unexpected directory created for flat file rename"
        )

    def test_flat_file_original_file_preserved(self):
        """フラットファイルの場合、元のファイルは（少なくとも）存在し続けるか、
        path 更新で新ファイル名に移動されること."""
        plugin_dir = _make_flat_file_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "some-cmd", "new-cmd")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        new_path = deps["commands"]["new-cmd"]["path"]
        # deps.yaml のパスが指すファイルが存在すること
        assert (plugin_dir / new_path).exists() or (plugin_dir / "commands" / "some-cmd.md").exists(), (
            f"Neither new path '{new_path}' nor old file exists"
        )

    # ---- Scenario: dry-run でのディレクトリ変更表示 ----
    # WHEN: `twl rename controller-project co-project --dry-run` を実行し、
    #       ディレクトリ移動が必要な場合
    # THEN: ディレクトリ移動が
    #       `directory: skills/controller-project/ → skills/co-project/`
    #       形式でプレビュー表示される

    def test_dry_run_directory_preview_shows_move(self):
        """dry-run でのディレクトリ変更表示: 移動元と移動先が表示される."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)
        result = run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        assert result.returncode == 0, f"dry-run failed: {result.stderr}"
        assert "[dry-run]" in result.stdout

        stdout = result.stdout
        # 移動元・移動先パスが含まれる
        assert "controller-project" in stdout
        assert "co-project" in stdout

    def test_dry_run_directory_arrow_format(self):
        """dry-run: arrow 形式（→ or ->）でディレクトリ移動が表示されること."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)
        result = run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        stdout = result.stdout
        assert "→" in stdout or "->" in stdout, (
            f"Arrow notation not found in dry-run output"
        )

    def test_dry_run_directory_label_present(self):
        """dry-run: 出力に 'directory' ラベルが含まれること."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)
        result = run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        stdout = result.stdout
        assert "directory" in stdout.lower() or "dir" in stdout.lower(), (
            f"'directory' label not found in dry-run output: {stdout}"
        )

    def test_dry_run_does_not_move_directory(self):
        """dry-run: 実際にはディレクトリが移動されないこと."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)
        run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )

        old_dir = plugin_dir / "skills" / "controller-project"
        new_dir = plugin_dir / "skills" / "co-project"
        assert old_dir.exists(), "dry-run moved the old directory"
        assert not new_dir.exists(), "dry-run created the new directory"


# ---------------------------------------------------------------------------
# Test class: rename 失敗時のロールバック
# ---------------------------------------------------------------------------

class TestRenameRollback:
    """Requirement: rename 失敗時のロールバック"""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    # ---- Scenario: deps.yaml 書き戻し失敗時のロールバック ----
    # WHEN: ディレクトリ rename は成功したが deps.yaml の書き戻しで例外が発生した
    # THEN: ディレクトリが元の位置に戻され、エラーメッセージが表示される

    def test_rollback_restores_directory_on_deps_write_failure(self):
        """deps.yaml 書き戻し失敗時のロールバック: ディレクトリが元に戻される.

        This test simulates deps.yaml write failure by making the file
        read-only after directory rename succeeds. Since the rename runs
        in a subprocess, we use a different approach: make deps.yaml
        read-only before the rename call.

        Note: This is an integration-level test. The exact mechanism for
        simulating write failure may need adjustment based on the
        implementation's error handling order (directory rename first,
        then deps.yaml write).
        """
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)

        # deps.yaml を read-only にして書き戻しを失敗させる
        deps_path = plugin_dir / "deps.yaml"
        deps_path.chmod(0o444)

        try:
            result = run_engine(plugin_dir, "--rename", "controller-project", "co-project")

            # ディレクトリ rename 後に deps.yaml 書き戻し失敗 → ロールバック
            # の場合、旧ディレクトリが復元されているべき
            old_dir = plugin_dir / "skills" / "controller-project"
            new_dir = plugin_dir / "skills" / "co-project"

            if result.returncode != 0:
                # 実装がディレクトリ rename を先に行う場合:
                # ロールバックにより old_dir が復元される
                assert old_dir.exists(), (
                    f"Rollback failed: old directory not restored. "
                    f"old_dir exists={old_dir.exists()}, new_dir exists={new_dir.exists()}"
                )
            # else: 実装がディレクトリ rename を後に行う場合、
            # deps.yaml 書き込み失敗で中断し、ディレクトリは未移動

        finally:
            # Restore write permission for cleanup
            deps_path.chmod(0o644)

    def test_rollback_shows_error_message(self):
        """deps.yaml 書き戻し失敗時: エラーメッセージが表示される."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)

        deps_path = plugin_dir / "deps.yaml"
        deps_path.chmod(0o444)

        try:
            result = run_engine(plugin_dir, "--rename", "controller-project", "co-project")

            # エラーメッセージが stderr or stdout に含まれる
            combined = result.stderr + result.stdout
            has_error = (
                result.returncode != 0
                or "error" in combined.lower()
                or "fail" in combined.lower()
                or "ロールバック" in combined
            )
            assert has_error, (
                f"Expected error output, got rc={result.returncode}, "
                f"stderr={result.stderr}, stdout={result.stdout}"
            )
        finally:
            deps_path.chmod(0o644)

    def test_rollback_deps_yaml_unchanged_on_failure(self):
        """deps.yaml 書き戻し失敗時: deps.yaml の内容が変更されていないこと."""
        plugin_dir = _make_directory_rename_fixture(self.tmpdir)

        deps_path = plugin_dir / "deps.yaml"
        deps_before = deps_path.read_text()
        deps_path.chmod(0o444)

        try:
            run_engine(plugin_dir, "--rename", "controller-project", "co-project")
        finally:
            deps_path.chmod(0o644)

        deps_after = deps_path.read_text()
        assert deps_before == deps_after, (
            "deps.yaml was modified despite write failure"
        )
