"""
tests/scenarios/test_issue_485_auto_init_suppression.py

Issue #485: auto-init 抑制ガード + offline フォールバック
Source: deltaspec/changes/issue-485/specs/auto-init-suppression/spec.md

Coverage:
  Requirement: auto-init 抑制ガード（Phase 1）
    Scenario: nested root 存在時に auto-init を発動しない
    Scenario: TWL_SPEC_ALLOW_AUTO_INIT=1 で従来動作を維持
  Requirement: origin/main アクセス失敗時のフォールバック
    Scenario: offline 環境でのフォールバック
  Requirement: unit test — nested root 存在時の auto-init 抑制
    Scenario: test_new_auto_init_suppressed_when_nested_root_exists
    Scenario: test_new_auto_init_allowed_with_env_var

TDD: これらのテストは実装前に書かれており、最初は失敗する。
"""

from __future__ import annotations

import io
import subprocess
import sys
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from twl.spec.new import cmd_new


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_no_deltaspec_dir(tmp_path: Path) -> Path:
    """Return tmp_path with no deltaspec/ (triggers DeltaspecNotFound)."""
    return tmp_path


def _git_ls_tree_output_with_nested(nested_path: str) -> str:
    """Return fake git ls-tree output that contains a nested config.yaml."""
    return f"100644 blob abc123\t{nested_path}/deltaspec/config.yaml\n"


def _git_ls_tree_output_empty() -> str:
    """Return fake git ls-tree output with no deltaspec/config.yaml."""
    return ""


# ---------------------------------------------------------------------------
# Requirement: auto-init 抑制ガード（Phase 1）
# ---------------------------------------------------------------------------


class TestAutoInitSuppressedWhenNestedRootExists:
    """
    Scenario: nested root 存在時に auto-init を発動しない

    WHEN: find_deltaspec_root() が DeltaspecNotFound を raise し、
          git ls-tree origin/main 出力に */deltaspec/config.yaml が含まれ、
          かつ TWL_SPEC_ALLOW_AUTO_INIT 未設定
    THEN: deltaspec/ ディレクトリが作成されず、エラーメッセージを stderr に出力し、
          exit code 1 で終了する
    """

    def test_cmd_new_returns_exit_1_when_nested_root_detected(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        WHEN git ls-tree origin/main が nested config.yaml を含む出力を返す
        THEN cmd_new が exit code 1 を返す
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = _git_ls_tree_output_with_nested("plugins/twl")

        with patch("subprocess.run", return_value=ls_tree_result):
            rc = cmd_new("issue-485")

        assert rc == 1

    def test_deltaspec_dir_not_created_when_nested_root_detected(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        WHEN nested root が検出される
        THEN deltaspec/ ディレクトリが cwd に作成されていない
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = _git_ls_tree_output_with_nested("plugins/twl")

        with patch("subprocess.run", return_value=ls_tree_result):
            cmd_new("issue-485")

        assert not (tmp_path / "deltaspec").exists(), (
            "deltaspec/ must NOT be created when nested root is detected"
        )

    def test_error_message_includes_nested_root_hint(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        WHEN nested root が検出される
        THEN stderr に「nested deltaspec root が origin/main に存在しますが cwd から参照できません」が含まれる
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = _git_ls_tree_output_with_nested("plugins/twl")

        buf = io.StringIO()
        with patch("subprocess.run", return_value=ls_tree_result):
            with redirect_stderr(buf):
                cmd_new("issue-485")

        err = buf.getvalue()
        assert "nested" in err.lower() or "origin/main" in err, (
            f"Expected nested root hint in stderr, got: {err!r}"
        )

    def test_error_message_includes_cd_hint(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        WHEN nested root が検出される
        THEN stderr に cd <nested-root-parent> または git rebase の案内が含まれる
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = _git_ls_tree_output_with_nested("plugins/twl")

        buf = io.StringIO()
        with patch("subprocess.run", return_value=ls_tree_result):
            with redirect_stderr(buf):
                cmd_new("issue-485")

        err = buf.getvalue()
        has_cd_hint = "cd " in err
        has_rebase_hint = "git rebase" in err or "rebase" in err.lower()
        assert has_cd_hint or has_rebase_hint, (
            f"Expected cd or rebase hint in stderr, got: {err!r}"
        )

    def test_spec_new_auto_init_suppressed_when_nested_root_exists(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        Scenario: test_new_auto_init_suppressed_when_nested_root_exists

        WHEN git ls-tree origin/main が plugins/twl/deltaspec/config.yaml を含む出力を返すようモック化され、
             find_deltaspec_root() が DeltaspecNotFound を raise する
        THEN cmd_new("issue-xxx") が exit code 1 を返し、
             deltaspec/ ディレクトリが作成されていない
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = (
            "100644 blob deadbeef\tplugins/twl/deltaspec/config.yaml\n"
        )

        with patch("subprocess.run", return_value=ls_tree_result):
            rc = cmd_new("issue-xxx")

        assert rc == 1, "cmd_new must return exit code 1"
        assert not (tmp_path / "deltaspec").exists(), (
            "deltaspec/ must not be created"
        )


# ---------------------------------------------------------------------------
# Requirement: auto-init 抑制ガード（Phase 1）— TWL_SPEC_ALLOW_AUTO_INIT=1 で従来動作
# ---------------------------------------------------------------------------


class TestAutoInitAllowedWithEnvVar:
    """
    Scenario: TWL_SPEC_ALLOW_AUTO_INIT=1 で従来動作を維持

    WHEN find_deltaspec_root() が DeltaspecNotFound を raise し、
         TWL_SPEC_ALLOW_AUTO_INIT=1 が設定されている
    THEN 従来の auto-init フローが実行され、deltaspec/ が cwd に作成される
    """

    def test_cmd_new_returns_exit_0_when_env_var_set(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        TWL_SPEC_ALLOW_AUTO_INIT=1 設定時に cmd_new が exit code 0 を返す
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.setenv("TWL_SPEC_ALLOW_AUTO_INIT", "1")

        # git ls-tree が nested root を検出してもフォールバック許可
        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = _git_ls_tree_output_with_nested("plugins/twl")

        with patch("subprocess.run", return_value=ls_tree_result):
            rc = cmd_new("issue-485-allow")

        assert rc == 0, "cmd_new must return 0 when TWL_SPEC_ALLOW_AUTO_INIT=1"

    def test_deltaspec_dir_created_when_env_var_set(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        TWL_SPEC_ALLOW_AUTO_INIT=1 設定時に deltaspec/ が cwd に作成される
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.setenv("TWL_SPEC_ALLOW_AUTO_INIT", "1")

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = _git_ls_tree_output_with_nested("plugins/twl")

        with patch("subprocess.run", return_value=ls_tree_result):
            cmd_new("issue-485-allow")

        assert (tmp_path / "deltaspec").exists(), (
            "deltaspec/ must be created when TWL_SPEC_ALLOW_AUTO_INIT=1"
        )
        assert (tmp_path / "deltaspec" / "changes" / "issue-485-allow").is_dir()

    def test_spec_new_auto_init_allowed_with_env_var(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        Scenario: test_new_auto_init_allowed_with_env_var

        WHEN TWL_SPEC_ALLOW_AUTO_INIT=1 が設定され、
             find_deltaspec_root() が DeltaspecNotFound を raise する
        THEN cmd_new("issue-xxx") が exit code 0 を返し、
             deltaspec/changes/issue-xxx/ が作成される
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.setenv("TWL_SPEC_ALLOW_AUTO_INIT", "1")

        # git ls-tree が nested root を返してもフォールバック許可
        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = (
            "100644 blob deadbeef\tplugins/twl/deltaspec/config.yaml\n"
        )

        with patch("subprocess.run", return_value=ls_tree_result):
            rc = cmd_new("issue-xxx")

        assert rc == 0, "cmd_new must return exit code 0 when env var is set"
        assert (tmp_path / "deltaspec" / "changes" / "issue-xxx").is_dir()


# ---------------------------------------------------------------------------
# Requirement: origin/main アクセス失敗時のフォールバック
# ---------------------------------------------------------------------------


class TestOfflineFallback:
    """
    Scenario: offline 環境でのフォールバック

    WHEN git ls-tree origin/main が非ゼロ exit code を返す
    THEN stderr に [WARN] origin/main へのアクセスに失敗しました。auto-init を続行します。 を出力し、
         従来の auto-init を実行する
    """

    def test_auto_init_continues_when_git_ls_tree_fails(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        git ls-tree が非ゼロを返す場合、cmd_new が exit 0 を返す（auto-init 継続）
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 128  # git ls-tree 失敗（offline など）
        ls_tree_result.stdout = ""

        with patch("subprocess.run", return_value=ls_tree_result):
            rc = cmd_new("issue-485-offline")

        assert rc == 0, (
            "cmd_new must return 0 and fall back to auto-init when git ls-tree fails"
        )

    def test_warn_message_output_when_git_ls_tree_fails(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        git ls-tree が失敗した場合、stderr に WARN メッセージが出力される
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 1
        ls_tree_result.stdout = ""

        buf = io.StringIO()
        with patch("subprocess.run", return_value=ls_tree_result):
            with redirect_stderr(buf):
                cmd_new("issue-485-offline")

        err = buf.getvalue()
        assert "WARN" in err or "warn" in err.lower(), (
            f"Expected WARN in stderr when git ls-tree fails, got: {err!r}"
        )

    def test_warn_message_mentions_origin_main(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        WARN メッセージに 'origin/main' が含まれる
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 1
        ls_tree_result.stdout = ""

        buf = io.StringIO()
        with patch("subprocess.run", return_value=ls_tree_result):
            with redirect_stderr(buf):
                cmd_new("issue-485-offline")

        err = buf.getvalue()
        assert "origin/main" in err, (
            f"Expected 'origin/main' in WARN message, got: {err!r}"
        )

    def test_deltaspec_created_after_offline_fallback(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        offline フォールバック後、deltaspec/ が正常に作成される
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 1
        ls_tree_result.stdout = ""

        with patch("subprocess.run", return_value=ls_tree_result):
            rc = cmd_new("offline-change")

        assert rc == 0
        assert (tmp_path / "deltaspec" / "changes" / "offline-change").is_dir()

    def test_no_nested_root_no_suppress_no_env_var(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """
        git ls-tree が成功し、nested config.yaml を含まない場合は auto-init を実行する
        """
        monkeypatch.chdir(tmp_path)
        monkeypatch.delenv("TWL_SPEC_ALLOW_AUTO_INIT", raising=False)

        ls_tree_result = MagicMock()
        ls_tree_result.returncode = 0
        ls_tree_result.stdout = _git_ls_tree_output_empty()

        with patch("subprocess.run", return_value=ls_tree_result):
            rc = cmd_new("plain-change")

        assert rc == 0
        assert (tmp_path / "deltaspec" / "changes" / "plain-change").is_dir()
