"""Tests for Issue #339: auto_init / deltaspec auto-initialization scenarios.

Spec: deltaspec/changes/issue-339/specs/auto-init/spec.md

Coverage (testable against existing Python code):
  - Scenario: deltaspec/ 未存在時に自動作成する
      step_init returns auto_init=True when deltaspec/ does not exist
  - Scenario: 既存 change と衝突した場合に確認する
      twl spec new returns error (exit 1) when change directory already exists

Non-testable scenarios (change-propose.md is a Markdown prompt spec, no runnable code):
  - Scenario: auto_init=true のとき change-id を自動導出する
  - Scenario: auto_init=false のとき既存フローを維持する
  - Scenario: auto_init=true で Step 1 をスキップする
  See test-mapping.yaml for status tracking of these scenarios.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

from twl.autopilot.chain import ChainRunner
from twl.autopilot.state import StateManager


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    return d


@pytest.fixture
def state(autopilot_dir: Path) -> StateManager:
    return StateManager(autopilot_dir=autopilot_dir)


@pytest.fixture
def runner(autopilot_dir: Path, tmp_path: Path) -> ChainRunner:
    scripts_root = tmp_path / "scripts"
    scripts_root.mkdir()
    return ChainRunner(scripts_root=scripts_root, autopilot_dir=autopilot_dir)


def _init_issue(state: StateManager, issue: str = "339") -> None:
    state.write(type_="issue", role="worker", issue=issue, init=True)


# ---------------------------------------------------------------------------
# Scenario: deltaspec/ 未存在時に自動作成する
#
# WHEN: auto_init=true かつ deltaspec/ ディレクトリが存在しない
# THEN: step_init が auto_init=True を返し、推奨アクションが propose になる
#
# Test target: twl.autopilot.chain.ChainRunner.step_init
# ---------------------------------------------------------------------------


class TestAutoInitWhenDeltaspecMissing:
    """Scenario: deltaspec/ 未存在時に自動作成する"""

    def test_step_init_returns_auto_init_true_when_no_deltaspec(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN deltaspec/ が存在しない THEN auto_init=True が返る。"""
        _init_issue(state, "339")

        # Project root には deltaspec/ を作らない
        project_root = tmp_path / "project"
        project_root.mkdir()

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/339"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init(issue_num="339")

        assert result.get("auto_init") is True

    def test_step_init_recommends_propose_when_no_deltaspec(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN deltaspec/ が存在しない THEN recommended_action=propose になる。"""
        _init_issue(state, "339")

        project_root = tmp_path / "project"
        project_root.mkdir()

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/339"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init(issue_num="339")

        assert result.get("recommended_action") == "propose"

    def test_step_init_returns_deltaspec_false_when_dir_missing(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN deltaspec/ が存在しない THEN deltaspec=False が返る（ディレクトリ非存在を示す）。"""
        _init_issue(state, "339")

        project_root = tmp_path / "project"
        project_root.mkdir()

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/339"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init(issue_num="339")

        assert result.get("deltaspec") is False

    def test_step_init_no_auto_init_flag_when_deltaspec_exists(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN deltaspec/ が存在する THEN auto_init フラグは含まれない（既存フロー）。"""
        _init_issue(state, "339")

        project_root = tmp_path / "project"
        deltaspec_dir = project_root / "deltaspec"
        changes_dir = deltaspec_dir / "changes" / "issue-100"
        changes_dir.mkdir(parents=True)
        (changes_dir / "proposal.md").write_text("# proposal", encoding="utf-8")

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/339"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init(issue_num="339")

        assert "auto_init" not in result

    def test_step_init_auto_init_true_regardless_of_is_quick(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN deltaspec/ が存在しない かつ is_quick=false THEN auto_init=True が返る。"""
        _init_issue(state, "339")

        project_root = tmp_path / "project"
        project_root.mkdir()

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/339"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init(issue_num="339")

        assert result.get("auto_init") is True
        assert result.get("is_quick") is False


# ---------------------------------------------------------------------------
# Scenario: 既存 change と衝突した場合に確認する
#
# WHEN: deltaspec/changes/issue-<N>/ が既に存在する
# THEN: twl spec new がエラーを返す（exit 1）
#
# Test target: twl.spec.new.cmd_new
# ---------------------------------------------------------------------------


class TestExistingChangeConflict:
    """Scenario: 既存 change と衝突した場合に確認する"""

    def test_spec_new_fails_when_change_already_exists(self, tmp_path: Path) -> None:
        """WHEN deltaspec/changes/issue-339/ が既存 THEN cmd_new が exit 1 を返す。"""
        from twl.spec.new import cmd_new

        # deltaspec ディレクトリを作成し、既存 change を用意
        deltaspec_dir = tmp_path / "deltaspec"
        change_dir = deltaspec_dir / "changes" / "issue-339"
        change_dir.mkdir(parents=True)
        (change_dir / ".deltaspec.yaml").write_text("schema: spec-driven\n", encoding="utf-8")

        original_cwd = os.getcwd()
        try:
            os.chdir(tmp_path)
            result = cmd_new("issue-339")
        finally:
            os.chdir(original_cwd)

        assert result == 1

    def test_spec_new_succeeds_when_change_not_exists(self, tmp_path: Path) -> None:
        """WHEN deltaspec/changes/issue-999/ が存在しない THEN cmd_new が exit 0 を返す。"""
        from twl.spec.new import cmd_new

        deltaspec_dir = tmp_path / "deltaspec"
        deltaspec_dir.mkdir(parents=True)

        original_cwd = os.getcwd()
        try:
            os.chdir(tmp_path)
            result = cmd_new("issue-999")
        finally:
            os.chdir(original_cwd)

        assert result == 0
        assert (tmp_path / "deltaspec" / "changes" / "issue-999").is_dir()

    def test_spec_new_conflict_via_cli(self, tmp_path: Path) -> None:
        """WHEN 既存 change に対して CLI 経由で twl spec new を実行 THEN exit code 1 かつ Error メッセージ出力。"""
        # 既存 change を作成
        change_dir = tmp_path / "deltaspec" / "changes" / "issue-339"
        change_dir.mkdir(parents=True)
        (change_dir / ".deltaspec.yaml").write_text("schema: spec-driven\n", encoding="utf-8")

        result = subprocess.run(
            [sys.executable, "-m", "twl", "spec", "new", "issue-339"],
            capture_output=True,
            text=True,
            cwd=str(tmp_path),
        )

        assert result.returncode == 1
        assert "already exists" in result.stderr.lower() or "error" in result.stderr.lower()

    def test_spec_new_conflict_error_message_includes_change_name(self, tmp_path: Path) -> None:
        """WHEN 既存 change と衝突 THEN エラーメッセージに change 名が含まれる。"""
        import io
        from contextlib import redirect_stderr

        from twl.spec.new import cmd_new

        change_dir = tmp_path / "deltaspec" / "changes" / "issue-339"
        change_dir.mkdir(parents=True)

        original_cwd = os.getcwd()
        buf = io.StringIO()
        try:
            os.chdir(tmp_path)
            with redirect_stderr(buf):
                cmd_new("issue-339")
        finally:
            os.chdir(original_cwd)

        assert "issue-339" in buf.getvalue()

    def test_spec_new_does_not_overwrite_existing_deltaspec_yaml(self, tmp_path: Path) -> None:
        """WHEN 既存 change と衝突 THEN 既存の .deltaspec.yaml は上書きされない（エッジケース）。"""
        from twl.spec.new import cmd_new

        change_dir = tmp_path / "deltaspec" / "changes" / "issue-339"
        change_dir.mkdir(parents=True)
        yaml_file = change_dir / ".deltaspec.yaml"
        original_content = "schema: spec-driven\ncreated: 2025-01-01\n"
        yaml_file.write_text(original_content, encoding="utf-8")

        original_cwd = os.getcwd()
        try:
            os.chdir(tmp_path)
            cmd_new("issue-339")
        finally:
            os.chdir(original_cwd)

        # 上書きされていないことを確認
        assert yaml_file.read_text(encoding="utf-8") == original_content


# ---------------------------------------------------------------------------
# Edge cases: deltaspec/ 未存在と既存 change の境界条件
# ---------------------------------------------------------------------------


class TestAutoInitEdgeCases:
    """Edge cases for auto_init detection in chain.step_init."""

    def test_step_init_auto_init_true_with_empty_changes_dir(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN deltaspec/ はあるが changes/ が空 THEN auto_init は含まれない（deltaspec=True, change_exists=False）。"""
        _init_issue(state, "339")

        project_root = tmp_path / "project"
        (project_root / "deltaspec" / "changes").mkdir(parents=True)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/339"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init(issue_num="339")

        # deltaspec/ 存在するが changes/ 空 → auto_init フラグなし
        assert "auto_init" not in result
        assert result.get("recommended_action") == "propose"

    def test_step_init_branch_preserved_in_result_when_no_deltaspec(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN deltaspec/ 未存在 THEN branch 情報が結果に含まれる。"""
        _init_issue(state, "339")

        project_root = tmp_path / "project"
        project_root.mkdir()

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/issue-339-auto-init"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
        ):
            result = runner.step_init(issue_num="339")

        assert result.get("branch") == "feat/issue-339-auto-init"
