"""
tests/scenarios/test_find_deltaspec_root.py

Scenario tests for find_deltaspec_root() — config.yaml マーカーベース検出
Source: plugins/twl/deltaspec/changes/issue-435/specs/find-deltaspec-root/spec.md
"""

import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from twl.spec.paths import DeltaspecNotFound, find_deltaspec_root


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_deltaspec_root(path: Path, *, with_config: bool = True) -> Path:
    """Create a deltaspec/ dir under *path*; optionally write config.yaml."""
    ds = path / "deltaspec"
    ds.mkdir(parents=True, exist_ok=True)
    if with_config:
        (ds / "config.yaml").write_text(
            "schema: deltaspec-v1\ncontext: {}\n", encoding="utf-8"
        )
    return path


# ---------------------------------------------------------------------------
# Requirement: config.yaml マーカーベース検出
# ---------------------------------------------------------------------------


class TestConfigYamlMarkerDetection:
    """find_deltaspec_root() must use config.yaml as validity marker."""

    # ------------------------------------------------------------------
    # Scenario: config.yaml なし deltaspec/ のスキップ
    # WHEN: cwd の上位パスに deltaspec/（config.yaml なし）が存在し、
    #       さらに上位に deltaspec/config.yaml が存在する場合
    # THEN: config.yaml を持つ上位の deltaspec/ を返す
    # ------------------------------------------------------------------

    def test_skips_deltaspec_without_config_yaml(self, tmp_path):
        """
        config.yaml なし deltaspec/ のスキップ:
        intermediate deltaspec/ without config.yaml must be ignored;
        the ancestor that has config.yaml must be returned.
        """
        # Layout:
        #   tmp_path/               ← valid root (has deltaspec/config.yaml)
        #   tmp_path/sub/           ← invalid root (has deltaspec/ but NO config.yaml)
        #   tmp_path/sub/work/      ← cwd
        make_deltaspec_root(tmp_path, with_config=True)  # valid ancestor
        make_deltaspec_root(tmp_path / "sub", with_config=False)  # invalid intermediate
        cwd = tmp_path / "sub" / "work"
        cwd.mkdir(parents=True)

        result = find_deltaspec_root(cwd)
        assert result == tmp_path

    def test_skips_deltaspec_without_config_yaml_at_cwd_level(self, tmp_path):
        """
        cwd 直下に config.yaml なし deltaspec/ がある場合もスキップする。
        """
        make_deltaspec_root(tmp_path, with_config=True)  # valid ancestor
        child = tmp_path / "child"
        make_deltaspec_root(child, with_config=False)  # invalid: no config.yaml

        result = find_deltaspec_root(child)
        assert result == tmp_path

    def test_finds_valid_root_with_config_yaml(self, tmp_path):
        """
        config.yaml を持つ deltaspec/ を正しく検出する（基本ケース）。
        """
        make_deltaspec_root(tmp_path, with_config=True)
        assert find_deltaspec_root(tmp_path) == tmp_path

    def test_finds_valid_root_from_deep_subdir(self, tmp_path):
        """
        深いサブディレクトリから walk-up して config.yaml を持つ root を返す。
        """
        make_deltaspec_root(tmp_path, with_config=True)
        deep = tmp_path / "a" / "b" / "c"
        deep.mkdir(parents=True)
        assert find_deltaspec_root(deep) == tmp_path

    # ------------------------------------------------------------------
    # Scenario: walk-down fallback
    # WHEN: walk-up で config.yaml を持つ deltaspec/ が見つからず、
    #       git toplevel 配下に **/deltaspec/config.yaml（maxdepth=3）が存在する場合
    # THEN: cwd に最も近い（最長共通パス）deltaspec root を返す
    # ------------------------------------------------------------------

    def test_walk_down_fallback_finds_config_yaml(self, tmp_path, monkeypatch):
        """
        walk-up で見つからない場合、git toplevel 配下を walk-down して
        deltaspec/config.yaml を持つ root を返す。
        """
        # git toplevel = tmp_path (make it a fake git repo)
        (tmp_path / ".git").mkdir()
        # Valid deltaspec/ is NOT on any ancestor of cwd, but IS under git toplevel
        sub_project = tmp_path / "plugins" / "twl"
        make_deltaspec_root(sub_project, with_config=True)
        # cwd is outside of sub_project hierarchy
        cwd = tmp_path / "other"
        cwd.mkdir()

        result = find_deltaspec_root(cwd)
        assert result == sub_project

    def test_walk_down_fallback_respects_maxdepth_3(self, tmp_path, monkeypatch):
        """
        walk-down は maxdepth=3 の制約を持つ（depth=4 の deltaspec/ は検出しない）。
        depth は git toplevel からの相対深度で計算する。
        """
        (tmp_path / ".git").mkdir()
        # Place valid deltaspec/ at depth=4 (too deep)
        deep_dir = tmp_path / "a" / "b" / "c" / "d"
        make_deltaspec_root(deep_dir, with_config=True)
        cwd = tmp_path / "other"
        cwd.mkdir()

        with pytest.raises(DeltaspecNotFound):
            find_deltaspec_root(cwd)

    def test_walk_down_fallback_depth_3_is_found(self, tmp_path, monkeypatch):
        """
        walk-down maxdepth=3 ぴったりの deltaspec/ は検出される。
        """
        (tmp_path / ".git").mkdir()
        # depth=3 from git root: tmp_path/a/b/c/deltaspec/config.yaml
        depth3_dir = tmp_path / "a" / "b" / "c"
        make_deltaspec_root(depth3_dir, with_config=True)
        cwd = tmp_path / "other"
        cwd.mkdir()

        result = find_deltaspec_root(cwd)
        assert result == depth3_dir

    # ------------------------------------------------------------------
    # Scenario: 複数ヒット時の選択
    # WHEN: walk-down で複数の deltaspec/config.yaml が発見される場合
    # THEN: cwd との共通パスが最長のものを返す
    # ------------------------------------------------------------------

    def test_multiple_hits_selects_longest_common_path(self, tmp_path):
        """
        複数ヒット時の選択: cwd と最長共通パスを持つ deltaspec root を返す。
        """
        (tmp_path / ".git").mkdir()
        # Two valid deltaspec roots under git toplevel
        root_a = tmp_path / "plugins" / "twl"
        root_b = tmp_path / "plugins" / "session"
        make_deltaspec_root(root_a, with_config=True)
        make_deltaspec_root(root_b, with_config=True)
        # cwd is inside root_a subtree
        cwd = tmp_path / "plugins" / "twl" / "src"
        cwd.mkdir(parents=True)

        result = find_deltaspec_root(cwd)
        assert result == root_a

    def test_multiple_hits_selects_closest_to_cwd(self, tmp_path):
        """
        複数ヒット時に cwd が root_b 配下の場合は root_b を選択する。
        """
        (tmp_path / ".git").mkdir()
        root_a = tmp_path / "a"
        root_b = tmp_path / "a" / "b"
        make_deltaspec_root(root_a, with_config=True)
        make_deltaspec_root(root_b, with_config=True)
        cwd = tmp_path / "a" / "b" / "c"
        cwd.mkdir(parents=True)

        result = find_deltaspec_root(cwd)
        assert result == root_b

    # ------------------------------------------------------------------
    # Scenario: 検出失敗
    # WHEN: walk-up および walk-down のいずれでも config.yaml を持つ deltaspec/ が
    #       見つからない場合
    # THEN: DeltaspecNotFoundError を raise する
    # ------------------------------------------------------------------

    def test_raises_when_no_deltaspec_found(self, tmp_path):
        """
        検出失敗: 有効な deltaspec root が存在しない場合は DeltaspecNotFound を raise。
        """
        with pytest.raises(DeltaspecNotFound):
            find_deltaspec_root(tmp_path)

    def test_raises_when_only_deltaspec_without_config_yaml(self, tmp_path):
        """
        deltaspec/ は存在するが config.yaml がない場合も DeltaspecNotFound を raise。
        """
        make_deltaspec_root(tmp_path, with_config=False)
        with pytest.raises(DeltaspecNotFound):
            find_deltaspec_root(tmp_path)

    def test_raises_when_walk_up_exhausted_and_no_git(self, tmp_path):
        """
        walk-up が filesystem root まで達し、git repo もない場合は DeltaspecNotFound。
        """
        cwd = tmp_path / "isolated" / "dir"
        cwd.mkdir(parents=True)
        with pytest.raises(DeltaspecNotFound):
            find_deltaspec_root(cwd)

    def test_raises_when_walk_down_finds_no_config_yaml(self, tmp_path):
        """
        git repo 内に deltaspec/ はあるが config.yaml なし → DeltaspecNotFound。
        """
        (tmp_path / ".git").mkdir()
        make_deltaspec_root(tmp_path / "sub", with_config=False)
        cwd = tmp_path / "other"
        cwd.mkdir()

        with pytest.raises(DeltaspecNotFound):
            find_deltaspec_root(cwd)

    # ------------------------------------------------------------------
    # Edge cases
    # ------------------------------------------------------------------

    def test_config_yaml_empty_file_is_still_valid(self, tmp_path):
        """
        config.yaml が空ファイルでも存在すれば有効なマーカーとして扱う。
        """
        ds = tmp_path / "deltaspec"
        ds.mkdir()
        (ds / "config.yaml").write_text("", encoding="utf-8")
        assert find_deltaspec_root(tmp_path) == tmp_path

    def test_config_yaml_symlink_is_valid(self, tmp_path):
        """
        config.yaml がシンボリックリンクでも存在確認で True になれば有効とする。
        """
        ds = tmp_path / "deltaspec"
        ds.mkdir()
        real_config = tmp_path / "real_config.yaml"
        real_config.write_text("schema: deltaspec-v1\n", encoding="utf-8")
        (ds / "config.yaml").symlink_to(real_config)
        assert find_deltaspec_root(tmp_path) == tmp_path

    def test_walk_up_stops_at_first_valid_root(self, tmp_path):
        """
        複数の valid root が walk-up パス上にある場合、最初（最も近い）ものを返す。
        """
        make_deltaspec_root(tmp_path, with_config=True)
        child = tmp_path / "child"
        make_deltaspec_root(child, with_config=True)
        cwd = child / "work"
        cwd.mkdir()

        result = find_deltaspec_root(cwd)
        assert result == child
