#!/usr/bin/env python3
"""Tests for entry_points list auto-update in rename_component().

Spec: openspec/changes/rename-complete/specs/entry-points-update/spec.md
Requirement: entry_points リストの自動更新

Coverage: edge-cases
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

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


def _make_entry_points_fixture(tmpdir: Path) -> Path:
    """Create a fixture with entry_points containing the rename target."""
    plugin_dir = tmpdir / "test-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "test",
        "entry_points": [
            "skills/controller-project/SKILL.md",
            "skills/other-skill/SKILL.md",
        ],
        "skills": {
            "controller-project": {
                "type": "controller",
                "path": "skills/controller-project/SKILL.md",
                "description": "Project controller",
                "calls": [],
            },
            "other-skill": {
                "type": "reference",
                "path": "skills/other-skill/SKILL.md",
                "description": "Another skill",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def _make_no_entry_points_fixture(tmpdir: Path) -> Path:
    """Create a fixture WITHOUT entry_points key in deps.yaml."""
    plugin_dir = tmpdir / "test-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "test",
        "skills": {
            "some-cmd": {
                "type": "controller",
                "path": "skills/some-cmd/SKILL.md",
                "description": "A skill",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


def _make_multiple_entry_points_fixture(tmpdir: Path) -> Path:
    """Create a fixture with multiple entry_points entries referencing the target."""
    plugin_dir = tmpdir / "test-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "test",
        "entry_points": [
            "skills/controller-project/SKILL.md",
            "commands/controller-project-init.md",
            "skills/unrelated/SKILL.md",
        ],
        "skills": {
            "controller-project": {
                "type": "controller",
                "path": "skills/controller-project/SKILL.md",
                "description": "Project controller",
                "calls": [],
            },
            "unrelated": {
                "type": "reference",
                "path": "skills/unrelated/SKILL.md",
                "description": "Unrelated",
                "calls": [],
            },
        },
        "commands": {
            "controller-project-init": {
                "type": "atomic",
                "path": "commands/controller-project-init.md",
                "description": "Init command",
                "calls": [],
            },
        },
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Test class: entry_points リストの自動更新
# ---------------------------------------------------------------------------

class TestEntryPointsUpdate:
    """Requirement: entry_points リストの自動更新"""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    # ---- Scenario: entry_points 内のパス更新 ----
    # WHEN: `twl rename controller-project co-project` を実行し、
    #       entry_points に `skills/controller-project/SKILL.md` が含まれる
    # THEN: entry_points の該当エントリが `skills/co-project/SKILL.md` に更新される

    def test_entry_points_path_updated_on_rename(self):
        """entry_points 内のパス更新: 該当エントリが new_name ベースに置換される."""
        plugin_dir = _make_entry_points_fixture(self.tmpdir)
        result = run_engine(plugin_dir, "--rename", "controller-project", "co-project")
        assert result.returncode == 0, f"rename failed: {result.stderr}"

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        entry_points = deps.get("entry_points", [])
        assert "skills/co-project/SKILL.md" in entry_points, (
            f"Expected 'skills/co-project/SKILL.md' in entry_points, got {entry_points}"
        )

    def test_entry_points_old_path_removed(self):
        """entry_points から old_name ベースのパスが除去されていること."""
        plugin_dir = _make_entry_points_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        entry_points = deps.get("entry_points", [])
        assert "skills/controller-project/SKILL.md" not in entry_points, (
            f"Old entry_point still present: {entry_points}"
        )

    def test_entry_points_unrelated_entries_preserved(self):
        """entry_points の無関係なエントリは変更されないこと."""
        plugin_dir = _make_entry_points_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        entry_points = deps.get("entry_points", [])
        assert "skills/other-skill/SKILL.md" in entry_points, (
            f"Unrelated entry_point was removed: {entry_points}"
        )

    def test_entry_points_boundary_match_only(self):
        """entry_points の置換はパスコンポーネント境界でのみ行われること.

        controller-project-init のパスは controller-project を部分文字列として
        含むが、境界一致ではないので変更されない."""
        plugin_dir = _make_multiple_entry_points_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        entry_points = deps.get("entry_points", [])
        # controller-project-init のエントリは変更されないこと
        # (controller-project-init 自体は rename 対象ではないので元のまま)
        assert any("controller-project-init" in ep for ep in entry_points), (
            f"Boundary violation: controller-project-init entry was modified: {entry_points}"
        )

    # ---- Scenario: entry_points が未定義 ----
    # WHEN: `twl rename some-cmd new-cmd` を実行し、
    #       deps.yaml に entry_points キーが存在しない
    # THEN: エラーなく正常に完了する（entry_points 更新はスキップされる）

    def test_no_entry_points_key_succeeds(self):
        """entry_points が未定義: entry_points キーがなくてもエラーにならない."""
        plugin_dir = _make_no_entry_points_fixture(self.tmpdir)
        result = run_engine(plugin_dir, "--rename", "some-cmd", "new-cmd")
        assert result.returncode == 0, (
            f"rename failed when entry_points absent: {result.stderr}"
        )

    def test_no_entry_points_key_not_created(self):
        """entry_points が未定義: rename 後も entry_points キーが追加されないこと."""
        plugin_dir = _make_no_entry_points_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "some-cmd", "new-cmd")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        assert "entry_points" not in deps, (
            f"entry_points key was unexpectedly created: {deps.get('entry_points')}"
        )

    def test_no_entry_points_rename_still_works(self):
        """entry_points が未定義でも他の rename 処理は正常に行われること."""
        plugin_dir = _make_no_entry_points_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "some-cmd", "new-cmd")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        assert "new-cmd" in deps["skills"], (
            f"Rename not applied: {list(deps['skills'].keys())}"
        )
        assert "some-cmd" not in deps["skills"]

    # ---- Scenario: dry-run での entry_points 変更表示 ----
    # WHEN: `twl rename controller-project co-project --dry-run` を実行し、
    #       entry_points に該当パスが含まれる
    # THEN: entry_points の変更が
    #       `entry_points: skills/controller-project/SKILL.md → skills/co-project/SKILL.md`
    #       形式でプレビュー表示される

    def test_dry_run_entry_points_preview_shows_changes(self):
        """dry-run での entry_points 変更表示: 変更内容がプレビューに含まれる."""
        plugin_dir = _make_entry_points_fixture(self.tmpdir)
        result = run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        assert result.returncode == 0, f"dry-run failed: {result.stderr}"
        assert "[dry-run]" in result.stdout

        stdout = result.stdout
        assert "skills/controller-project/SKILL.md" in stdout, (
            f"Old entry_point path not shown in dry-run"
        )
        assert "skills/co-project/SKILL.md" in stdout, (
            f"New entry_point path not shown in dry-run"
        )

    def test_dry_run_entry_points_arrow_format(self):
        """dry-run: arrow 形式（→ or ->）で entry_points 変更が表示されること."""
        plugin_dir = _make_entry_points_fixture(self.tmpdir)
        result = run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        stdout = result.stdout
        assert "→" in stdout or "->" in stdout, (
            f"Arrow notation not found in dry-run output"
        )

    def test_dry_run_entry_points_label_present(self):
        """dry-run: 出力に 'entry_points' ラベルが含まれること."""
        plugin_dir = _make_entry_points_fixture(self.tmpdir)
        result = run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        stdout = result.stdout
        assert "entry_points" in stdout.lower() or "entry-points" in stdout.lower(), (
            f"'entry_points' label not found in dry-run output: {stdout}"
        )

    def test_dry_run_does_not_modify_deps(self):
        """dry-run: deps.yaml が変更されないことを確認."""
        plugin_dir = _make_entry_points_fixture(self.tmpdir)
        deps_before = (plugin_dir / "deps.yaml").read_text()
        run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        deps_after = (plugin_dir / "deps.yaml").read_text()
        assert deps_before == deps_after, "dry-run modified deps.yaml"
