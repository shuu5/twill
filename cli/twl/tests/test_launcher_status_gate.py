"""Tests for WorkerLauncher Status pre-check gate.

Issue #943: design: refined をラベルから Status field へ移行
AC5: launcher.py WorkerLauncher.launch() での Status pre-check 実装
AC6: cross-repo Issue の label fallback ロジック

Scenarios S1-S5a:
  S1: Status=Todo → LaunchError（deny）
  S2: Status=Refined → allow（cld_not_found まで進む）
  S3: Status=In Progress → allow (idempotent)
  S4: Status fetch 失敗（gh auth scope 不足）→ LaunchError + actionable message
  S5: Issue が Board 未登録 + cross-repo フラグなし → LaunchError + actionable message
  S5a: cross-repo Issue（Board 未登録）+ refined label あり → allow (label fallback)
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch, call

import pytest

# WorkerLauncher.launch() は未実装の Status gate を含むため import は成功するが
# gate 関連メソッドが存在しない → RED
from twl.autopilot.launcher import WorkerLauncher, LaunchError, LaunchDependencyError


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_gh_projectitems_result(status_name: str) -> MagicMock:
    """gh issue view --json projectItems の成功レスポンスを生成する。"""
    m = MagicMock()
    m.returncode = 0
    m.stdout = json.dumps({
        "projectItems": {
            "nodes": [
                {
                    "id": "PVTI_abc",
                    "status": {"name": status_name},
                    "project": {"number": 5},
                }
            ]
        }
    })
    m.stderr = ""
    return m


def _make_gh_projectitems_empty() -> MagicMock:
    """Issue が Board 未登録の場合（nodes 空）のレスポンスを生成する。"""
    m = MagicMock()
    m.returncode = 0
    m.stdout = json.dumps({"projectItems": {"nodes": []}})
    m.stderr = ""
    return m


def _make_gh_labels_result(labels: list[str]) -> MagicMock:
    """gh issue view --json labels のレスポンスを生成する。"""
    m = MagicMock()
    m.returncode = 0
    m.stdout = json.dumps({"labels": [{"name": lb} for lb in labels]})
    m.stderr = ""
    return m


def _make_gh_auth_error() -> MagicMock:
    """gh api の auth scope エラーレスポンスを生成する。"""
    m = MagicMock()
    m.returncode = 1
    m.stdout = ""
    m.stderr = "Your token does not have the 'project' scope"
    return m


def _make_launcher(tmp_path: Path) -> WorkerLauncher:
    return WorkerLauncher()


# ---------------------------------------------------------------------------
# S1: Status=Todo → deny
# ---------------------------------------------------------------------------


class TestS1StatusTodoDeny:
    """AC5: Status=Todo の Issue は launcher が LaunchError で deny する。"""

    def test_ac5_s1_status_todo_raises_launch_error(self, tmp_path: Path) -> None:
        # AC5: pre-check は Status=Todo を拒否する
        # RED: WorkerLauncher.launch() に Status pre-check が未実装
        launcher = _make_launcher(tmp_path)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd_str = " ".join(str(a) for a in args)
            if "projectItems" in cmd_str:
                return _make_gh_projectitems_result("Todo")
            m = MagicMock()
            m.returncode = 0
            m.stdout = "{}"
            m.stderr = ""
            return m

        with patch("subprocess.run", side_effect=fake_run):
            with pytest.raises(LaunchError, match="Refined"):
                launcher.launch(
                    issue="42",
                    project_dir=str(tmp_path),
                    autopilot_dir=str(tmp_path / ".autopilot"),
                )


# ---------------------------------------------------------------------------
# S2: Status=Refined → allow
# ---------------------------------------------------------------------------


class TestS2StatusRefinedAllow:
    """AC5: Status=Refined の Issue は Status gate を通過する。"""

    def test_ac5_s2_status_refined_passes_gate(self, tmp_path: Path) -> None:
        # AC5: pre-check は Status=Refined を許可する
        # RED: WorkerLauncher.launch() に Status pre-check が未実装
        launcher = _make_launcher(tmp_path)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd_str = " ".join(str(a) for a in args)
            if "projectItems" in cmd_str:
                return _make_gh_projectitems_result("Refined")
            # state write 等は成功させる
            m = MagicMock()
            m.returncode = 0
            m.stdout = "{}"
            m.stderr = ""
            return m

        # Status gate を通過後 cld_not_found で LaunchDependencyError になることを期待
        # gate 自体が deny していれば LaunchError("Refined") が raise される → test fail
        with patch("subprocess.run", side_effect=fake_run):
            with patch("shutil.which", return_value=None):  # cld not found
                with pytest.raises(LaunchDependencyError):
                    launcher.launch(
                        issue="43",
                        project_dir=str(tmp_path),
                        autopilot_dir=str(tmp_path / ".autopilot"),
                    )


# ---------------------------------------------------------------------------
# S3: Status=In Progress → allow (idempotent)
# ---------------------------------------------------------------------------


class TestS3StatusInProgressIdempotent:
    """AC5: Status=In Progress の Issue は冪等として allow される。"""

    def test_ac5_s3_status_in_progress_passes_gate(self, tmp_path: Path) -> None:
        # AC5: In Progress は既に遷移済みのため allow
        # RED: WorkerLauncher.launch() に idempotent ロジックが未実装
        launcher = _make_launcher(tmp_path)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd_str = " ".join(str(a) for a in args)
            if "projectItems" in cmd_str:
                return _make_gh_projectitems_result("In Progress")
            m = MagicMock()
            m.returncode = 0
            m.stdout = "{}"
            m.stderr = ""
            return m

        with patch("subprocess.run", side_effect=fake_run):
            with patch("shutil.which", return_value=None):  # cld not found
                with pytest.raises(LaunchDependencyError):
                    launcher.launch(
                        issue="44",
                        project_dir=str(tmp_path),
                        autopilot_dir=str(tmp_path / ".autopilot"),
                    )


# ---------------------------------------------------------------------------
# S4: Status fetch 失敗（gh auth scope 不足）→ deny + actionable message
# ---------------------------------------------------------------------------


class TestS4AuthScopeError:
    """AC5, W5: gh auth scope 不足でエラー → actionable message を含む LaunchError。"""

    def test_ac5_s4_auth_scope_error_includes_actionable_message(
        self, tmp_path: Path
    ) -> None:
        # RED: WorkerLauncher.launch() の auth scope エラーハンドリングが未実装
        launcher = _make_launcher(tmp_path)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd_str = " ".join(str(a) for a in args)
            if "projectItems" in cmd_str:
                return _make_gh_auth_error()
            m = MagicMock()
            m.returncode = 0
            m.stdout = "{}"
            m.stderr = ""
            return m

        with patch("subprocess.run", side_effect=fake_run):
            with pytest.raises(LaunchError) as exc_info:
                launcher.launch(
                    issue="45",
                    project_dir=str(tmp_path),
                    autopilot_dir=str(tmp_path / ".autopilot"),
                )
        # actionable message: 'gh auth refresh -s project' を含む
        assert "gh auth refresh -s project" in str(exc_info.value)


# ---------------------------------------------------------------------------
# S5: Issue が Board 未登録 + cross-repo フラグなし → deny + actionable message
# ---------------------------------------------------------------------------


class TestS5BoardNotRegisteredDeny:
    """AC5, W5: Board 未登録 Issue + non-cross-repo → deny + actionable message。"""

    def test_ac5_s5_board_not_registered_deny(self, tmp_path: Path) -> None:
        # RED: WorkerLauncher.launch() の Board 未登録チェックが未実装
        launcher = _make_launcher(tmp_path)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd_str = " ".join(str(a) for a in args)
            if "projectItems" in cmd_str:
                return _make_gh_projectitems_empty()
            m = MagicMock()
            m.returncode = 0
            m.stdout = "{}"
            m.stderr = ""
            return m

        with patch("subprocess.run", side_effect=fake_run):
            with pytest.raises(LaunchError) as exc_info:
                launcher.launch(
                    issue="46",
                    project_dir=str(tmp_path),
                    autopilot_dir=str(tmp_path / ".autopilot"),
                )
        # actionable message: 'Board に Issue を add' を含む
        assert "Board に Issue を add" in str(exc_info.value)


# ---------------------------------------------------------------------------
# S5a: cross-repo Issue（Board 未登録）+ refined label あり → allow (label fallback)
# ---------------------------------------------------------------------------


class TestS5aCrossRepoLabelFallback:
    """AC6: cross-repo + Board 未登録 + refined label → label fallback で allow。"""

    def test_ac6_s5a_cross_repo_refined_label_allow(self, tmp_path: Path) -> None:
        # AC6: label fallback ロジック
        # RED: WorkerLauncher.launch() の label fallback が未実装
        launcher = _make_launcher(tmp_path)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd_str = " ".join(str(a) for a in args)
            if "projectItems" in cmd_str:
                return _make_gh_projectitems_empty()
            if "labels" in cmd_str and "issue view" in cmd_str:
                return _make_gh_labels_result(["refined", "enhancement"])
            m = MagicMock()
            m.returncode = 0
            m.stdout = "{}"
            m.stderr = ""
            return m

        # cross-repo flag があり Board 未登録でも refined label で allow → cld_not_found まで進む
        with patch("subprocess.run", side_effect=fake_run):
            with patch("shutil.which", return_value=None):  # cld not found
                with pytest.raises(LaunchDependencyError):
                    launcher.launch(
                        issue="47",
                        project_dir=str(tmp_path),
                        autopilot_dir=str(tmp_path / ".autopilot"),
                        repo_owner="shuu5",
                        repo_name="other-repo",
                    )


# ---------------------------------------------------------------------------
# deny log: /tmp/refined-status-gate.log への記録（AC7-b）
# ---------------------------------------------------------------------------


class TestDenyEventLog:
    """AC7-b: deny 時に /tmp/refined-status-gate.log へ記録する。"""

    def test_ac7_deny_event_is_logged(self, tmp_path: Path, tmp_path_factory: pytest.TempPathFactory) -> None:
        # AC7: (b) /tmp/refined-status-gate.log への deny event log
        # RED: deny log 機能が未実装
        launcher = _make_launcher(tmp_path)

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd_str = " ".join(str(a) for a in args)
            if "projectItems" in cmd_str:
                return _make_gh_projectitems_result("Todo")
            m = MagicMock()
            m.returncode = 0
            m.stdout = "{}"
            m.stderr = ""
            return m

        import tempfile
        log_path = Path(tempfile.gettempdir()) / "refined-status-gate.log"
        log_path.unlink(missing_ok=True)

        with patch("subprocess.run", side_effect=fake_run):
            with pytest.raises(LaunchError):
                launcher.launch(
                    issue="48",
                    project_dir=str(tmp_path),
                    autopilot_dir=str(tmp_path / ".autopilot"),
                )

        # deny event が log に記録されていること
        assert log_path.exists(), "deny event log が作成されていない"
        log_content = log_path.read_text()
        assert "48" in log_content or "deny" in log_content.lower()


# ---------------------------------------------------------------------------
# GitHub API retry（AC7-c）
# ---------------------------------------------------------------------------


class TestApiRetryWithBackoff:
    """AC7-c: GitHub API retry 3 回 with exponential backoff (1s/2s/4s)。"""

    def test_ac7_github_api_retry_3_times_then_deny(self, tmp_path: Path) -> None:
        # AC7: (c) GitHub API retry 3 回 with exponential backoff、3 連続失敗で alert + deny
        # RED: retry ロジックが未実装
        launcher = _make_launcher(tmp_path)
        call_count = {"n": 0}

        def fake_run(args, **kwargs):  # type: ignore[no-untyped-def]
            cmd_str = " ".join(str(a) for a in args)
            if "projectItems" in cmd_str:
                call_count["n"] += 1
                return _make_gh_auth_error()
            m = MagicMock()
            m.returncode = 0
            m.stdout = "{}"
            m.stderr = ""
            return m

        with patch("subprocess.run", side_effect=fake_run):
            with patch("time.sleep"):  # backoff sleep をスキップ
                with pytest.raises(LaunchError):
                    launcher.launch(
                        issue="49",
                        project_dir=str(tmp_path),
                        autopilot_dir=str(tmp_path / ".autopilot"),
                    )

        # 3 回リトライ（計 3 回の gh api 呼び出し）
        assert call_count["n"] >= 3, (
            f"API retry が実装されていない: gh api 呼び出し回数 = {call_count['n']} (期待: >= 3)"
        )
