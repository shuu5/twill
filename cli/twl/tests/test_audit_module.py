"""Tests for twl.autopilot.audit (issue-642: twl audit subcommand).

Covers:
- is_audit_active(): env var, .active file, neither
- resolve_audit_dir(): TWL_AUDIT_DIR env, .active file, neither
- audit_on(): auto-generate run-id, explicit run-id, creates dir + .active
- audit_off(): removes .active, writes index.json, error if not active
- audit_status(): active state output, inactive state output

All scenarios from deltaspec/changes/issue-642/specs/audit-subcommand/spec.md.
Edge cases: concurrent .active writes, malformed .active JSON, path edge cases.
"""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path
from typing import Generator

import pytest


# ---------------------------------------------------------------------------
# Lazy import helpers — audit.py does not exist yet, tests guard with skip
# ---------------------------------------------------------------------------

def _import_audit():
    """Import audit module, skip test if not yet implemented."""
    try:
        import twl.autopilot.audit as audit  # type: ignore[import]
        return audit
    except ImportError:
        pytest.skip("twl.autopilot.audit not yet implemented")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def project_dir(tmp_path: Path) -> Path:
    """Isolated project directory with .audit/ ready."""
    audit_dir = tmp_path / ".audit"
    audit_dir.mkdir()
    return tmp_path


@pytest.fixture
def active_file(project_dir: Path) -> Path:
    """Return the path to .audit/.active within project_dir."""
    return project_dir / ".audit" / ".active"


def _write_active(project_dir: Path, run_id: str = "test-run-001") -> dict:
    """Helper: write a valid .audit/.active file."""
    audit_dir = project_dir / ".audit"
    audit_dir.mkdir(exist_ok=True)
    run_dir = audit_dir / run_id
    run_dir.mkdir(exist_ok=True)
    payload = {
        "run_id": run_id,
        "started_at": "2024-01-01T00:00:00Z",
        "audit_dir": str(run_dir),
    }
    (audit_dir / ".active").write_text(json.dumps(payload), encoding="utf-8")
    return payload


# ===========================================================================
# Requirement: is_audit_active()
# ===========================================================================


class TestIsAuditActive:
    """Scenarios: 環境変数での有効化 / ファイルでの有効化 / 無効状態"""

    def test_env_var_twl_audit_1_returns_true(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN TWL_AUDIT=1 が設定されている THEN is_audit_active() が True を返す"""
        audit = _import_audit()
        monkeypatch.setenv("TWL_AUDIT", "1")
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)
        assert audit.is_audit_active(project_root=project_dir) is True

    def test_active_file_returns_true_without_env(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN .audit/.active が存在する THEN is_audit_active() が True を返す（環境変数なしでも）"""
        audit = _import_audit()
        monkeypatch.delenv("TWL_AUDIT", raising=False)
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)
        _write_active(project_dir)
        assert audit.is_audit_active(project_root=project_dir) is True

    def test_neither_env_nor_file_returns_false(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN TWL_AUDIT 未設定かつ .audit/.active が存在しない THEN False を返す"""
        audit = _import_audit()
        monkeypatch.delenv("TWL_AUDIT", raising=False)
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)
        # Ensure .active does not exist
        active = project_dir / ".audit" / ".active"
        active.unlink(missing_ok=True)
        assert audit.is_audit_active(project_root=project_dir) is False

    def test_env_var_zero_does_not_activate(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: TWL_AUDIT=0 は有効化しない"""
        audit = _import_audit()
        monkeypatch.setenv("TWL_AUDIT", "0")
        active = project_dir / ".audit" / ".active"
        active.unlink(missing_ok=True)
        assert audit.is_audit_active(project_root=project_dir) is False

    def test_env_var_empty_string_does_not_activate(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: TWL_AUDIT='' は有効化しない"""
        audit = _import_audit()
        monkeypatch.setenv("TWL_AUDIT", "")
        active = project_dir / ".audit" / ".active"
        active.unlink(missing_ok=True)
        assert audit.is_audit_active(project_root=project_dir) is False

    def test_both_env_and_file_returns_true(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: 両方存在しても True"""
        audit = _import_audit()
        monkeypatch.setenv("TWL_AUDIT", "1")
        _write_active(project_dir)
        assert audit.is_audit_active(project_root=project_dir) is True


# ===========================================================================
# Requirement: resolve_audit_dir()
# ===========================================================================


class TestResolveAuditDir:
    """Scenarios: 環境変数からの解決 / .active ファイルからの解決"""

    def test_env_var_twl_audit_dir_returned(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN TWL_AUDIT_DIR=<project 内パス> THEN resolve_audit_dir() が resolved Path を返す"""
        audit = _import_audit()
        expected = project_dir / "audit-session"
        expected.mkdir()
        monkeypatch.setenv("TWL_AUDIT_DIR", str(expected))
        result = audit.resolve_audit_dir(project_root=project_dir)
        assert result == expected.resolve()

    def test_env_var_outside_project_raises(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN TWL_AUDIT_DIR が project root 外 THEN ValueError を raise する"""
        audit = _import_audit()
        monkeypatch.setenv("TWL_AUDIT_DIR", "/tmp/evil-path")
        with pytest.raises(ValueError, match="TWL_AUDIT_DIR is outside project root"):
            audit.resolve_audit_dir(project_root=project_dir)

    def test_active_file_audit_dir_returned(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN TWL_AUDIT_DIR 未設定で .audit/.active が存在する THEN audit_dir フィールドを返す"""
        audit = _import_audit()
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)
        payload = _write_active(project_dir, run_id="run-20240101")
        result = audit.resolve_audit_dir(project_root=project_dir)
        assert result is not None
        assert result == Path(payload["audit_dir"])
        assert result.is_absolute()

    def test_neither_returns_none(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN TWL_AUDIT_DIR 未設定かつ .active なし THEN None を返す"""
        audit = _import_audit()
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)
        (project_dir / ".audit" / ".active").unlink(missing_ok=True)
        result = audit.resolve_audit_dir(project_root=project_dir)
        assert result is None

    def test_env_var_takes_priority_over_active_file(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: TWL_AUDIT_DIR が .active より優先される"""
        audit = _import_audit()
        env_dir = project_dir / "env-audit"
        env_dir.mkdir()
        monkeypatch.setenv("TWL_AUDIT_DIR", str(env_dir))
        _write_active(project_dir, run_id="other-run")
        result = audit.resolve_audit_dir(project_root=project_dir)
        assert result == env_dir.resolve()

    def test_active_file_relative_audit_dir_resolved_to_absolute(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: .active の audit_dir が相対パスでも絶対パスで返す"""
        audit = _import_audit()
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)
        audit_dir = project_dir / ".audit"
        run_dir = audit_dir / "rel-run"
        run_dir.mkdir(exist_ok=True)
        # Write .active with relative path
        payload = {
            "run_id": "rel-run",
            "started_at": "2024-01-01T00:00:00Z",
            "audit_dir": ".audit/rel-run",  # relative
        }
        (audit_dir / ".active").write_text(json.dumps(payload), encoding="utf-8")
        result = audit.resolve_audit_dir(project_root=project_dir)
        assert result is not None
        assert result.is_absolute()

    def test_malformed_active_file_returns_none(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: .active が不正 JSON でも例外にならず None を返す"""
        audit = _import_audit()
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)
        (project_dir / ".audit" / ".active").write_text("NOT_JSON", encoding="utf-8")
        result = audit.resolve_audit_dir(project_root=project_dir)
        assert result is None


# ===========================================================================
# Requirement: twl audit on サブコマンド
# ===========================================================================


class TestAuditOn:
    """Scenarios: run-id 自動生成で audit on / 指定 run-id で audit on"""

    def test_auto_generated_run_id_creates_dir_and_active(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN audit_on() を run_id なしで呼び出す
        THEN .audit/<timestamp>_<random>/ ディレクトリと .active が作成される"""
        audit = _import_audit()
        monkeypatch.delenv("TWL_AUDIT_DIR", raising=False)
        result = audit.audit_on(project_root=project_dir)

        run_id = result["run_id"]
        # Format: <unix_timestamp>_<4char>
        assert re.match(r"^\d+_[a-zA-Z0-9]{4}$", run_id), \
            f"Expected <timestamp>_<4char> format, got: {run_id}"

        # Directory created
        run_dir = project_dir / ".audit" / run_id
        assert run_dir.is_dir(), f"run dir not created: {run_dir}"

        # .active file created
        active = project_dir / ".audit" / ".active"
        assert active.is_file()

        # .active content
        data = json.loads(active.read_text())
        assert data["run_id"] == run_id
        assert "started_at" in data
        assert "audit_dir" in data

    def test_explicit_run_id_creates_named_dir(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN audit_on(run_id='my-run-001') THEN .audit/my-run-001/ が作成され .active の run_id が 'my-run-001'"""
        audit = _import_audit()
        result = audit.audit_on(run_id="my-run-001", project_root=project_dir)

        assert result["run_id"] == "my-run-001"

        run_dir = project_dir / ".audit" / "my-run-001"
        assert run_dir.is_dir()

        active = project_dir / ".audit" / ".active"
        data = json.loads(active.read_text())
        assert data["run_id"] == "my-run-001"

    def test_active_json_has_required_fields(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: .active の JSON に必須フィールドが全て含まれる"""
        audit = _import_audit()
        audit.audit_on(run_id="field-check", project_root=project_dir)
        data = json.loads((project_dir / ".audit" / ".active").read_text())
        assert "run_id" in data
        assert "started_at" in data
        assert "audit_dir" in data

    def test_audit_dir_field_is_absolute_path(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: .active の audit_dir は絶対パス"""
        audit = _import_audit()
        audit.audit_on(run_id="abs-path-check", project_root=project_dir)
        data = json.loads((project_dir / ".audit" / ".active").read_text())
        assert Path(data["audit_dir"]).is_absolute()

    def test_run_id_auto_unique_on_rapid_calls(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: 連続呼び出しで run-id が衝突しない"""
        audit = _import_audit()
        r1 = audit.audit_on(project_root=project_dir)
        # Remove .active to simulate second call
        (project_dir / ".audit" / ".active").unlink(missing_ok=True)
        r2 = audit.audit_on(project_root=project_dir)
        assert r1["run_id"] != r2["run_id"], "run-ids must be unique"

    def test_special_chars_in_run_id_rejected(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: run-id にパストラバーサル文字が含まれる場合は拒否する"""
        audit = _import_audit()
        with pytest.raises((ValueError, OSError, Exception)):
            audit.audit_on(run_id="../evil", project_root=project_dir)


# ===========================================================================
# Requirement: twl audit off サブコマンド
# ===========================================================================


class TestAuditOff:
    """Scenarios: 正常な audit off / audit 未開始での off"""

    def test_normal_off_removes_active_and_creates_index(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN .active が存在する状態で audit_off() を呼び出す
        THEN .active が削除され、.audit/<run-id>/index.json が作成される"""
        audit = _import_audit()
        _write_active(project_dir, run_id="off-test-001")

        audit.audit_off(project_root=project_dir)

        # .active removed
        active = project_dir / ".audit" / ".active"
        assert not active.exists(), ".active should be removed after audit off"

        # index.json created
        index_path = project_dir / ".audit" / "off-test-001" / "index.json"
        assert index_path.is_file(), f"index.json not created: {index_path}"

        data = json.loads(index_path.read_text())
        assert data["run_id"] == "off-test-001"
        assert "started_at" in data
        assert "ended_at" in data
        assert "files" in data

    def test_index_json_schema(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: index.json が {run_id, started_at, ended_at, files} を持つ"""
        audit = _import_audit()
        _write_active(project_dir, run_id="schema-check")
        audit.audit_off(project_root=project_dir)

        index_path = project_dir / ".audit" / "schema-check" / "index.json"
        data = json.loads(index_path.read_text())
        for field in ("run_id", "started_at", "ended_at", "files"):
            assert field in data, f"Missing field: {field}"
        assert isinstance(data["files"], list)

    def test_off_without_active_raises_error(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN .active が存在しない状態で audit_off() を呼び出す
        THEN 'audit is not active' を示すエラーが発生する"""
        audit = _import_audit()
        (project_dir / ".audit" / ".active").unlink(missing_ok=True)

        with pytest.raises(Exception, match="not active|not_active|audit.*inactive"):
            audit.audit_off(project_root=project_dir)

    def test_off_cleans_up_active_atomically(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: off 後に .active が残存しないことを確認"""
        audit = _import_audit()
        _write_active(project_dir, run_id="atomic-off")
        audit.audit_off(project_root=project_dir)
        assert not (project_dir / ".audit" / ".active").exists()

    def test_ended_at_is_iso8601(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: index.json の ended_at が ISO8601 形式"""
        audit = _import_audit()
        _write_active(project_dir, run_id="ts-check")
        audit.audit_off(project_root=project_dir)
        index_path = project_dir / ".audit" / "ts-check" / "index.json"
        data = json.loads(index_path.read_text())
        ended_at = data["ended_at"]
        # Should be parseable ISO8601
        assert "T" in ended_at and "Z" in ended_at, \
            f"ended_at is not ISO8601: {ended_at}"


# ===========================================================================
# Requirement: twl audit status サブコマンド
# ===========================================================================


class TestAuditStatus:
    """Scenarios: audit active 時の status / audit inactive 時の status"""

    def test_status_active_returns_true_with_run_id(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN .active が存在する状態で audit_status() を呼び出す
        THEN active: True, run_id, audit_dir を含む情報を返す"""
        audit = _import_audit()
        _write_active(project_dir, run_id="status-active-001")
        result = audit.audit_status(project_root=project_dir)

        assert result["active"] is True
        assert result["run_id"] == "status-active-001"
        assert "audit_dir" in result

    def test_status_inactive_returns_false(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """WHEN .active が存在しない状態で audit_status() を呼び出す
        THEN active: False を返す"""
        audit = _import_audit()
        monkeypatch.delenv("TWL_AUDIT", raising=False)
        (project_dir / ".audit" / ".active").unlink(missing_ok=True)
        result = audit.audit_status(project_root=project_dir)

        assert result["active"] is False

    def test_status_active_audit_dir_is_absolute(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: status の audit_dir は絶対パス"""
        audit = _import_audit()
        _write_active(project_dir, run_id="abs-status")
        result = audit.audit_status(project_root=project_dir)
        assert Path(result["audit_dir"]).is_absolute()

    def test_status_via_env_var_active(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path, tmp_path: Path
    ) -> None:
        """Edge case: .active なしでも TWL_AUDIT=1 なら is_audit_active=True"""
        audit = _import_audit()
        monkeypatch.setenv("TWL_AUDIT", "1")
        (project_dir / ".audit" / ".active").unlink(missing_ok=True)
        # audit_status may return active=True when env var is set
        result = audit.audit_status(project_root=project_dir)
        assert result["active"] is True


# ===========================================================================
# Requirement: run-id 形式バリデーション (edge cases)
# ===========================================================================


class TestRunIdFormat:
    """Auto-generated run-id が <unix-timestamp>_<4文字ランダム> 形式であることを確認"""

    def test_auto_run_id_matches_pattern(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        audit = _import_audit()
        result = audit.audit_on(project_root=project_dir)
        run_id = result["run_id"]
        pattern = re.compile(r"^\d{10,}_[a-zA-Z0-9]{4}$")
        assert pattern.match(run_id), \
            f"run_id '{run_id}' does not match <unix_timestamp>_<4char>"

    def test_auto_run_id_timestamp_is_recent(
        self, monkeypatch: pytest.MonkeyPatch, project_dir: Path
    ) -> None:
        """Edge case: 自動生成 run-id のタイムスタンプ部が現在時刻に近い"""
        audit = _import_audit()
        before = int(time.time())
        result = audit.audit_on(project_root=project_dir)
        after = int(time.time())
        run_id = result["run_id"]
        ts_part = int(run_id.split("_")[0])
        assert before <= ts_part <= after + 1, \
            f"Timestamp {ts_part} is not in range [{before}, {after}]"
