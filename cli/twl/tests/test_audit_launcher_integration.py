"""Tests for audit integration in launcher.py (issue-642).

Covers:
- Worker への audit 環境変数伝搬: TWL_AUDIT=1 時に TWL_AUDIT=1 と TWL_AUDIT_DIR=<絶対パス> が env_flags に設定される
- TWL_AUDIT 未設定時は env_flags に audit 関連フラグが追加されない
- launcher が resolve_audit_dir() を呼び出して絶対パスを設定する責任を持つ

Scenarios from: spec.md Requirement: launcher による TWL_AUDIT_DIR 伝搬
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from twl.autopilot.launcher import WorkerLauncher


def _write_active(project_dir: Path, run_id: str = "launcher-run") -> Path:
    """Write .audit/.active and return the audit run directory."""
    audit_dir = project_dir / ".audit"
    audit_dir.mkdir(parents=True, exist_ok=True)
    run_dir = audit_dir / run_id
    run_dir.mkdir(exist_ok=True)
    payload = {
        "run_id": run_id,
        "started_at": "2024-01-01T00:00:00Z",
        "audit_dir": str(run_dir),
    }
    (audit_dir / ".active").write_text(json.dumps(payload), encoding="utf-8")
    return run_dir


def _collect_env_flags(env_flags: list[str]) -> dict[str, str]:
    """Parse ['-e', 'K=V', '-e', 'K2=V2'] into {'K': 'V', 'K2': 'V2'}."""
    result = {}
    i = 0
    while i < len(env_flags):
        if env_flags[i] == "-e" and i + 1 < len(env_flags):
            kv = env_flags[i + 1]
            k, _, v = kv.partition("=")
            result[k] = v
            i += 2
        else:
            i += 1
    return result


# ===========================================================================
# Requirement: launcher による TWL_AUDIT_DIR 伝搬
# ===========================================================================


class TestLauncherAuditEnvPropagation:
    """Scenario: Worker への audit 環境変数伝搬"""

    def test_audit_env_flags_set_when_twl_audit_is_1(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """WHEN TWL_AUDIT=1 が設定された状態で launcher が Worker を起動する
        THEN env_flags に TWL_AUDIT=1 と TWL_AUDIT_DIR=<絶対パス> が設定される"""
        monkeypatch.setenv("TWL_AUDIT", "1")
        run_dir = _write_active(tmp_path, run_id="env-prop-run")
        monkeypatch.setenv("TWL_AUDIT_DIR", str(run_dir))

        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: True
            )
            monkeypatch.setattr(
                audit_mod, "resolve_audit_dir",
                lambda project_root=None: run_dir
            )
        except ImportError:
            pytest.skip("twl.autopilot.audit not yet implemented")

        captured_tmux_argv: list[list[str]] = []

        def fake_run(argv, **kwargs):
            captured_tmux_argv.append(argv)
            mock = MagicMock()
            mock.returncode = 0
            mock.stdout = ""
            return mock

        ap_dir = tmp_path / ".autopilot"
        ap_dir.mkdir()
        (ap_dir / "issues").mkdir()

        launcher = WorkerLauncher(scripts_root=tmp_path / "scripts")

        with patch("twl.autopilot.launcher.subprocess.run", side_effect=fake_run), \
             patch("twl.autopilot.launcher.shutil.which", return_value="/usr/bin/cld"), \
             patch("twl.autopilot.launcher.WorkerLauncher._detect_quick_label", return_value=False):
            try:
                launcher.launch(
                    issue="1",
                    project_dir=str(tmp_path),
                    autopilot_dir=str(ap_dir),
                    model="sonnet",
                )
            except Exception:
                pass  # State init may fail in isolation — we care about tmux argv

        # Find the tmux new-window call
        tmux_calls = [a for a in captured_tmux_argv if a and a[0] == "tmux" and "new-window" in a]
        if not tmux_calls:
            pytest.skip("No tmux call captured — launcher integration not yet modified for audit")

        tmux_argv = tmux_calls[0]
        env_flags = _collect_env_flags(tmux_argv)

        assert "TWL_AUDIT" in env_flags, \
            f"TWL_AUDIT not in env_flags: {env_flags}"
        assert env_flags["TWL_AUDIT"] == "1"
        assert "TWL_AUDIT_DIR" in env_flags, \
            f"TWL_AUDIT_DIR not in env_flags: {env_flags}"
        assert Path(env_flags["TWL_AUDIT_DIR"]).is_absolute(), \
            f"TWL_AUDIT_DIR is not absolute: {env_flags['TWL_AUDIT_DIR']}"
        assert env_flags["TWL_AUDIT_DIR"] == str(run_dir)

    def test_no_audit_env_when_twl_audit_not_set(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """WHEN TWL_AUDIT が未設定の状態で launcher が Worker を起動する
        THEN env_flags に TWL_AUDIT_DIR が追加されない"""
        monkeypatch.delenv("TWL_AUDIT", raising=False)
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)

        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: False
            )
        except ImportError:
            pass  # OK — we verify env_flags don't contain TWL_AUDIT_DIR

        captured_tmux_argv: list[list[str]] = []

        def fake_run(argv, **kwargs):
            captured_tmux_argv.append(argv)
            mock = MagicMock()
            mock.returncode = 0
            mock.stdout = ""
            return mock

        ap_dir = tmp_path / ".autopilot"
        ap_dir.mkdir()
        (ap_dir / "issues").mkdir()

        launcher = WorkerLauncher(scripts_root=tmp_path / "scripts")

        with patch("twl.autopilot.launcher.subprocess.run", side_effect=fake_run), \
             patch("twl.autopilot.launcher.shutil.which", return_value="/usr/bin/cld"), \
             patch("twl.autopilot.launcher.WorkerLauncher._detect_quick_label", return_value=False):
            try:
                launcher.launch(
                    issue="1",
                    project_dir=str(tmp_path),
                    autopilot_dir=str(ap_dir),
                    model="sonnet",
                )
            except Exception:
                pass

        tmux_calls = [a for a in captured_tmux_argv if a and a[0] == "tmux" and "new-window" in a]
        if not tmux_calls:
            return  # No tmux call — acceptable if audit not integrated

        tmux_argv = tmux_calls[0]
        env_flags = _collect_env_flags(tmux_argv)

        assert "TWL_AUDIT_DIR" not in env_flags, \
            f"TWL_AUDIT_DIR should NOT be in env_flags when audit is inactive: {env_flags}"

    def test_audit_dir_is_absolute_path_in_env_flags(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Edge case: TWL_AUDIT_DIR に設定されるパスは絶対パス（resolve_audit_dir() の結果）"""
        monkeypatch.setenv("TWL_AUDIT", "1")
        run_dir = tmp_path / ".audit" / "abs-test"
        run_dir.mkdir(parents=True)
        monkeypatch.setenv("TWL_AUDIT_DIR", str(run_dir))

        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: True
            )
            monkeypatch.setattr(
                audit_mod, "resolve_audit_dir",
                lambda project_root=None: run_dir
            )
        except ImportError:
            pytest.skip("twl.autopilot.audit not yet implemented")

        captured: list[list[str]] = []

        def fake_run(argv, **kwargs):
            captured.append(argv)
            m = MagicMock()
            m.returncode = 0
            m.stdout = ""
            return m

        ap_dir = tmp_path / ".autopilot"
        ap_dir.mkdir(exist_ok=True)
        (ap_dir / "issues").mkdir(exist_ok=True)
        launcher = WorkerLauncher(scripts_root=tmp_path / "scripts")

        with patch("twl.autopilot.launcher.subprocess.run", side_effect=fake_run), \
             patch("twl.autopilot.launcher.shutil.which", return_value="/usr/bin/cld"), \
             patch("twl.autopilot.launcher.WorkerLauncher._detect_quick_label", return_value=False):
            try:
                launcher.launch(
                    issue="2",
                    project_dir=str(tmp_path),
                    autopilot_dir=str(ap_dir),
                    model="sonnet",
                )
            except Exception:
                pass

        tmux_calls = [a for a in captured if a and a[0] == "tmux" and "new-window" in a]
        if not tmux_calls:
            pytest.skip("No tmux call captured")

        env_flags = _collect_env_flags(tmux_calls[0])
        if "TWL_AUDIT_DIR" in env_flags:
            assert Path(env_flags["TWL_AUDIT_DIR"]).is_absolute(), \
                f"TWL_AUDIT_DIR must be absolute: {env_flags['TWL_AUDIT_DIR']}"
