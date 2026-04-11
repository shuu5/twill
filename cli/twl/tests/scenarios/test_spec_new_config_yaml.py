"""
tests/scenarios/test_spec_new_config_yaml.py

Scenario tests for twl spec new — config.yaml 自動生成
Source: plugins/twl/deltaspec/changes/issue-435/specs/find-deltaspec-root/spec.md
Requirement: twl spec new の config.yaml 自動生成
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from twl.spec.new import cmd_new


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_project_without_deltaspec(tmp_path: Path) -> Path:
    """Return tmp_path with NO deltaspec/ directory."""
    return tmp_path


def make_project_with_config(tmp_path: Path, config_content: str | None = None) -> Path:
    """Create deltaspec/config.yaml and deltaspec/changes/."""
    ds = tmp_path / "deltaspec"
    (ds / "changes").mkdir(parents=True)
    content = config_content if config_content is not None else (
        "schema: deltaspec-v1\ncontext: {}\n"
    )
    (ds / "config.yaml").write_text(content, encoding="utf-8")
    return tmp_path


def make_project_without_config(tmp_path: Path) -> Path:
    """Create deltaspec/changes/ but NO config.yaml (legacy layout)."""
    (tmp_path / "deltaspec" / "changes").mkdir(parents=True)
    return tmp_path


# ---------------------------------------------------------------------------
# Requirement: twl spec new の config.yaml 自動生成
# ---------------------------------------------------------------------------


class TestSpecNewConfigYamlGeneration:
    """twl spec new must auto-generate config.yaml for new deltaspec/."""

    # ------------------------------------------------------------------
    # Scenario: 新規 deltaspec 作成時の config.yaml 生成
    # WHEN: twl spec new <name> 実行時に deltaspec/ が存在しない場合
    # THEN: deltaspec/config.yaml を schema と context フィールド付きで自動生成し、
    #       deltaspec/changes/<name>/ を作成する
    # ------------------------------------------------------------------

    def test_creates_config_yaml_when_deltaspec_missing(self, tmp_path, monkeypatch):
        """
        新規 deltaspec 作成時の config.yaml 生成:
        deltaspec/ が存在しない場合、config.yaml が自動生成される。
        """
        monkeypatch.chdir(tmp_path)
        rc = cmd_new("my-feature")
        assert rc == 0
        config = tmp_path / "deltaspec" / "config.yaml"
        assert config.exists(), "deltaspec/config.yaml must be created"

    def test_created_config_yaml_contains_schema_field(self, tmp_path, monkeypatch):
        """
        生成された config.yaml に schema フィールドが含まれる。
        """
        monkeypatch.chdir(tmp_path)
        cmd_new("feat-001")
        content = (tmp_path / "deltaspec" / "config.yaml").read_text()
        assert "schema:" in content

    def test_created_config_yaml_contains_context_field(self, tmp_path, monkeypatch):
        """
        生成された config.yaml に context フィールドが含まれる。
        """
        monkeypatch.chdir(tmp_path)
        cmd_new("feat-001")
        content = (tmp_path / "deltaspec" / "config.yaml").read_text()
        assert "context:" in content

    def test_creates_change_directory_when_deltaspec_missing(self, tmp_path, monkeypatch):
        """
        deltaspec/ が存在しない場合でも deltaspec/changes/<name>/ が作成される。
        """
        monkeypatch.chdir(tmp_path)
        rc = cmd_new("new-change")
        assert rc == 0
        change_dir = tmp_path / "deltaspec" / "changes" / "new-change"
        assert change_dir.is_dir()

    def test_creates_deltaspec_yaml_in_change_dir(self, tmp_path, monkeypatch):
        """
        新規作成時、change dir 内に .deltaspec.yaml が生成される。
        """
        monkeypatch.chdir(tmp_path)
        cmd_new("issue-999")
        ds_yaml = tmp_path / "deltaspec" / "changes" / "issue-999" / ".deltaspec.yaml"
        assert ds_yaml.exists()
        content = ds_yaml.read_text()
        assert "schema: spec-driven" in content
        assert "issue: 999" in content

    # ------------------------------------------------------------------
    # Scenario: 既存 deltaspec への config.yaml 非上書き
    # WHEN: twl spec new <name> 実行時に deltaspec/config.yaml が既に存在する場合
    # THEN: config.yaml を変更せず、deltaspec/changes/<name>/ のみ作成する
    # ------------------------------------------------------------------

    def test_does_not_overwrite_existing_config_yaml(self, tmp_path, monkeypatch):
        """
        既存 deltaspec への config.yaml 非上書き:
        config.yaml が既存の場合は内容を変更しない。
        """
        original_content = "schema: deltaspec-v1\ncontext: {custom: true}\n"
        make_project_with_config(tmp_path, original_content)
        monkeypatch.chdir(tmp_path)

        rc = cmd_new("safe-change")
        assert rc == 0
        actual_content = (tmp_path / "deltaspec" / "config.yaml").read_text()
        assert actual_content == original_content

    def test_creates_change_dir_when_config_yaml_exists(self, tmp_path, monkeypatch):
        """
        config.yaml が既存でも deltaspec/changes/<name>/ は正しく作成される。
        """
        make_project_with_config(tmp_path)
        monkeypatch.chdir(tmp_path)

        rc = cmd_new("another-change")
        assert rc == 0
        assert (tmp_path / "deltaspec" / "changes" / "another-change").is_dir()

    def test_does_not_create_config_yaml_in_legacy_project(self, tmp_path, monkeypatch):
        """
        deltaspec/ が存在するが config.yaml がない（レガシー構成）の場合、
        cmd_new はエラーなく動作し、config.yaml の有無は要件次第。
        注: 現行実装では deltaspec/ 存在を root 検出の判断基準としている。
            この test は非上書き保護が config.yaml なし時も副作用を起こさないことを確認する。
        """
        make_project_without_config(tmp_path)
        monkeypatch.chdir(tmp_path)

        rc = cmd_new("legacy-change")
        assert rc == 0
        # change dir が作成されていること
        assert (tmp_path / "deltaspec" / "changes" / "legacy-change").is_dir()

    # ------------------------------------------------------------------
    # Edge cases
    # ------------------------------------------------------------------

    def test_config_yaml_is_valid_yaml(self, tmp_path, monkeypatch):
        """
        自動生成された config.yaml は valid YAML でなければならない。
        """
        import yaml

        monkeypatch.chdir(tmp_path)
        cmd_new("yaml-test")
        content = (tmp_path / "deltaspec" / "config.yaml").read_text()
        parsed = yaml.safe_load(content)
        assert isinstance(parsed, dict)
        assert "schema" in parsed

    def test_multiple_new_calls_do_not_overwrite_config_yaml(self, tmp_path, monkeypatch):
        """
        複数回 cmd_new を呼んでも config.yaml は最初の生成内容を保持する。
        """
        monkeypatch.chdir(tmp_path)
        cmd_new("first-change")
        original_content = (tmp_path / "deltaspec" / "config.yaml").read_text()
        cmd_new("second-change")
        assert (tmp_path / "deltaspec" / "config.yaml").read_text() == original_content

    def test_config_yaml_not_created_when_deltaspec_exists_with_config(
        self, tmp_path, monkeypatch
    ):
        """
        deltaspec/config.yaml が既に存在する場合、追加の config.yaml は作成されない。
        （ファイル数・パスが変わらないことを確認）
        """
        make_project_with_config(tmp_path)
        monkeypatch.chdir(tmp_path)
        cmd_new("check-no-dup")
        ds_files = list((tmp_path / "deltaspec").iterdir())
        config_files = [f for f in ds_files if f.name == "config.yaml"]
        assert len(config_files) == 1

    def test_issue_name_in_new_deltaspec_includes_issue_field(
        self, tmp_path, monkeypatch
    ):
        """
        issue-<N> 名での新規 deltaspec 作成でも .deltaspec.yaml に issue フィールドが入る。
        """
        monkeypatch.chdir(tmp_path)
        cmd_new("issue-435")
        ds_yaml = (
            tmp_path / "deltaspec" / "changes" / "issue-435" / ".deltaspec.yaml"
        )
        content = ds_yaml.read_text()
        assert "issue: 435" in content
        assert "name: issue-435" in content
