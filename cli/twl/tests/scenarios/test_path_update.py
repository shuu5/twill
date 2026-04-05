#!/usr/bin/env python3
"""Tests for path field auto-update in rename_component().

Spec: openspec/changes/rename-complete/specs/path-update/spec.md
Requirement: path フィールドの自動更新

Coverage: edge-cases
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

TWL_ENGINE = Path(__file__).parent.parent.parent / "twl-engine.py"


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


def _make_path_update_fixture(tmpdir: Path) -> Path:
    """Create a fixture with controller-project skill for path update testing."""
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


def _make_partial_match_fixture(tmpdir: Path) -> Path:
    """Create a fixture that tests partial match prevention.

    co-auto is the rename target, co-autopilot-launch is a bystander
    whose path must NOT be affected.
    """
    plugin_dir = tmpdir / "test-plugin"
    plugin_dir.mkdir()

    deps = {
        "version": "2.0",
        "plugin": "test",
        "skills": {
            "co-auto": {
                "type": "controller",
                "path": "skills/co-auto/SKILL.md",
                "description": "Auto controller",
                "calls": [],
            },
            "co-autopilot-launch": {
                "type": "workflow",
                "path": "skills/co-autopilot-launch/SKILL.md",
                "description": "Autopilot launch workflow",
                "calls": [],
            },
        },
        "commands": {},
        "agents": {},
    }
    _write_deps(plugin_dir, deps)
    _create_component_files(plugin_dir, deps)
    return plugin_dir


# ---------------------------------------------------------------------------
# Test class: path フィールドの自動更新
# ---------------------------------------------------------------------------

class TestPathUpdate:
    """Requirement: path フィールドの自動更新"""

    def setup_method(self):
        self.tmpdir = Path(tempfile.mkdtemp())

    def teardown_method(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    # ---- Scenario: 標準的な path 更新 ----
    # WHEN: `twl rename controller-project co-project` を実行し、
    #       対象の path が `skills/controller-project/SKILL.md` である
    # THEN: path は `skills/co-project/SKILL.md` に更新される

    def test_path_update_when_rename_then_path_field_updated(self):
        """標準的な path 更新: path フィールド内の old_name がパス境界で new_name に置換される."""
        plugin_dir = _make_path_update_fixture(self.tmpdir)
        result = run_engine(plugin_dir, "--rename", "controller-project", "co-project")
        assert result.returncode == 0, f"rename failed: {result.stderr}"

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        updated_path = deps["skills"]["co-project"]["path"]
        assert updated_path == "skills/co-project/SKILL.md", (
            f"Expected path 'skills/co-project/SKILL.md', got '{updated_path}'"
        )

    def test_path_update_old_path_segment_gone(self):
        """path フィールドに old_name のパスセグメントが残っていないことを確認."""
        plugin_dir = _make_path_update_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "controller-project", "co-project")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        updated_path = deps["skills"]["co-project"]["path"]
        # パスセグメント単位で old_name が存在しないこと
        segments = Path(updated_path).parts
        assert "controller-project" not in segments, (
            f"Old name 'controller-project' still present as path segment in '{updated_path}'"
        )

    # ---- Scenario: 部分一致しない ----
    # WHEN: `twl rename co-auto co-autopilot` を実行し、
    #       別コンポーネントの path に `skills/co-autopilot-launch/SKILL.md` がある
    # THEN: 別コンポーネントの path は変更されない

    def test_partial_match_prevention_bystander_path_unchanged(self):
        """部分一致しない: 別コンポーネントの path が部分文字列一致で書き換わらないこと."""
        plugin_dir = _make_partial_match_fixture(self.tmpdir)
        result = run_engine(plugin_dir, "--rename", "co-auto", "co-autopilot")
        assert result.returncode == 0, f"rename failed: {result.stderr}"

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        bystander_path = deps["skills"]["co-autopilot-launch"]["path"]
        assert bystander_path == "skills/co-autopilot-launch/SKILL.md", (
            f"Bystander path was incorrectly modified to '{bystander_path}'"
        )

    def test_partial_match_prevention_target_path_updated(self):
        """部分一致しない: rename 対象自身の path は正しく更新されること."""
        plugin_dir = _make_partial_match_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "co-auto", "co-autopilot")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        target_path = deps["skills"]["co-autopilot"]["path"]
        assert target_path == "skills/co-autopilot/SKILL.md", (
            f"Target path not updated correctly: '{target_path}'"
        )

    def test_partial_match_no_substring_contamination_in_longer_name(self):
        """Edge case: 'co-autopilot-launch' の path に 'co-autopilot' が
        部分文字列として含まれるが、パス境界でないため置換されないこと."""
        plugin_dir = _make_partial_match_fixture(self.tmpdir)
        run_engine(plugin_dir, "--rename", "co-auto", "co-autopilot")

        deps = yaml.safe_load((plugin_dir / "deps.yaml").read_text())
        # co-autopilot-launch のパスが co-autopilot/... に書き変わっていないこと
        bystander_path = deps["skills"]["co-autopilot-launch"]["path"]
        assert "co-autopilot-launch" in bystander_path, (
            f"Bystander path corrupted: '{bystander_path}'"
        )
        assert bystander_path.count("co-autopilot") == 1 or "co-autopilot-launch" in bystander_path

    # ---- Scenario: dry-run での path 変更表示 ----
    # WHEN: `twl rename controller-project co-project --dry-run` を実行する
    # THEN: path の変更が `path: skills/controller-project/SKILL.md → skills/co-project/SKILL.md`
    #       形式でプレビュー表示される

    def test_dry_run_path_preview_shows_arrow_format(self):
        """dry-run での path 変更表示: arrow 形式で path 変更がプレビューされる."""
        plugin_dir = _make_path_update_fixture(self.tmpdir)
        result = run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        assert result.returncode == 0, f"dry-run failed: {result.stderr}"
        assert "[dry-run]" in result.stdout

        # path 変更プレビューが arrow 形式を含むこと
        stdout = result.stdout
        assert "skills/controller-project/SKILL.md" in stdout, (
            f"Old path not shown in dry-run output"
        )
        assert "skills/co-project/SKILL.md" in stdout, (
            f"New path not shown in dry-run output"
        )
        # arrow 表記（→ or ->）が path 行に含まれる
        assert "→" in stdout or "->" in stdout, (
            f"Arrow notation not found in dry-run output"
        )

    def test_dry_run_does_not_modify_deps(self):
        """dry-run: deps.yaml が変更されないことを確認."""
        plugin_dir = _make_path_update_fixture(self.tmpdir)
        deps_before = (plugin_dir / "deps.yaml").read_text()
        run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        deps_after = (plugin_dir / "deps.yaml").read_text()
        assert deps_before == deps_after, "dry-run modified deps.yaml"

    def test_dry_run_path_preview_contains_path_label(self):
        """dry-run: 出力に 'path:' ラベルが含まれること."""
        plugin_dir = _make_path_update_fixture(self.tmpdir)
        result = run_engine(
            plugin_dir, "--rename", "controller-project", "co-project", "--dry-run"
        )
        stdout = result.stdout
        # "path:" or "path" label in the preview line
        assert "path" in stdout.lower(), (
            f"'path' label not found in dry-run output: {stdout}"
        )
