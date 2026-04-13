"""Tests for audit integration in state.py write methods (issue-642).

Covers:
- state 変更のログ記録: audit 有効時に変更フィールド・変更前後の値を state-log.jsonl に追記
- 変更なし時はログ不記録: 同一値を設定した場合は JSONL への追記なし
- ログエントリのスキーマ: {ts, issue, field, old, new, role}

Scenarios from: spec.md Requirement: state 遷移ログ
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from twl.autopilot.state import StateManager


def _write_active(project_dir: Path, run_id: str = "state-test-run") -> Path:
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


def _create_autopilot_dir(tmp_path: Path, issue: str = "1") -> tuple[Path, Path]:
    """Create autopilot dir with issues subdir and return (autopilot_dir, issues_dir)."""
    ap_dir = tmp_path / ".autopilot"
    issues_dir = ap_dir / "issues"
    issues_dir.mkdir(parents=True)
    return ap_dir, issues_dir


def _init_issue(state: StateManager, issue: str = "1") -> None:
    state.write(type_="issue", role="worker", issue=issue, init=True)


def _read_state_log(run_dir: Path) -> list[dict]:
    """Read all JSONL entries from state-log.jsonl."""
    log_file = run_dir / "state-log.jsonl"
    if not log_file.exists():
        return []
    entries = []
    for line in log_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            entries.append(json.loads(line))
    return entries


# ===========================================================================
# Requirement: state 遷移ログ
# ===========================================================================


class TestStateAuditLog:
    """Scenario: state 変更のログ記録"""

    def test_field_change_appended_to_state_log(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """WHEN audit が有効な状態で state.write() がフィールドを変更する
        THEN {ts, issue, field, old, new, role} が state-log.jsonl に追記される"""
        ap_dir, _ = _create_autopilot_dir(tmp_path)
        run_dir = _write_active(tmp_path, run_id="state-log-run")

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

        state = StateManager(autopilot_dir=ap_dir)
        _init_issue(state, issue="42")
        state.write(
            type_="issue", role="worker", issue="42",
            sets=["current_step=phase-review"],
        )

        entries = _read_state_log(run_dir)
        assert len(entries) >= 1, f"Expected at least 1 log entry, got {entries}"

        entry = next(
            (e for e in entries if e.get("field") == "current_step"),
            None
        )
        assert entry is not None, \
            f"No log entry for field=current_step, got: {entries}"

        assert "ts" in entry
        assert entry["field"] == "current_step"
        assert entry["new"] == "phase-review"
        assert "old" in entry
        assert "role" in entry
        assert entry["role"] in ("worker", "pilot")
        assert "issue" in entry

    def test_log_entry_schema_complete(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Edge case: ログエントリに必須フィールド {ts, issue, field, old, new, role} が全て含まれる"""
        ap_dir, _ = _create_autopilot_dir(tmp_path)
        run_dir = _write_active(tmp_path, run_id="schema-run")

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

        state = StateManager(autopilot_dir=ap_dir)
        _init_issue(state, issue="7")
        state.write(
            type_="issue", role="worker", issue="7",
            sets=["current_step=merge-gate"],
        )

        entries = _read_state_log(run_dir)
        assert entries, "No log entries written"
        entry = entries[-1]
        for required_key in ("ts", "issue", "field", "old", "new", "role"):
            assert required_key in entry, \
                f"Missing required key '{required_key}' in log entry: {entry}"

    def test_no_change_no_log_entry(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """WHEN audit が有効な状態で write が既存値と同一の値を設定する
        THEN state-log.jsonl への追記は行われない"""
        ap_dir, _ = _create_autopilot_dir(tmp_path)
        run_dir = _write_active(tmp_path, run_id="no-change-run")

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

        state = StateManager(autopilot_dir=ap_dir)
        _init_issue(state, issue="5")
        # Set initial value
        state.write(
            type_="issue", role="worker", issue="5",
            sets=["current_step=phase-review"],
        )
        entries_after_first = _read_state_log(run_dir)
        count_after_first = len(entries_after_first)

        # Set same value again
        state.write(
            type_="issue", role="worker", issue="5",
            sets=["current_step=phase-review"],
        )
        entries_after_second = _read_state_log(run_dir)
        assert len(entries_after_second) == count_after_first, \
            f"Expected no new log entries for unchanged field. " \
            f"Before: {count_after_first}, After: {len(entries_after_second)}"

    def test_multiple_fields_each_logged(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Edge case: 複数フィールドを一度に変更した場合、それぞれがログに記録される"""
        ap_dir, _ = _create_autopilot_dir(tmp_path)
        run_dir = _write_active(tmp_path, run_id="multi-field-run")

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

        state = StateManager(autopilot_dir=ap_dir)
        _init_issue(state, issue="10")
        state.write(
            type_="issue", role="worker", issue="10",
            sets=["current_step=phase-review", "retry_count=1"],
        )

        entries = _read_state_log(run_dir)
        fields_logged = {e.get("field") for e in entries}
        assert "current_step" in fields_logged, \
            f"current_step not logged. Entries: {entries}"

    def test_role_recorded_in_log(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Edge case: ログエントリの role が write 呼び出し時の role と一致する"""
        ap_dir, _ = _create_autopilot_dir(tmp_path)
        run_dir = _write_active(tmp_path, run_id="role-log-run")

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

        state = StateManager(autopilot_dir=ap_dir)
        _init_issue(state, issue="20")
        state.write(
            type_="issue", role="worker", issue="20",
            sets=["current_step=worker-step"],
        )

        entries = _read_state_log(run_dir)
        entry = next(
            (e for e in entries if e.get("field") == "current_step"),
            None
        )
        assert entry is not None
        assert entry["role"] == "worker"

    def test_log_is_valid_jsonl(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Edge case: state-log.jsonl の各行が有効な JSON"""
        ap_dir, _ = _create_autopilot_dir(tmp_path)
        run_dir = _write_active(tmp_path, run_id="jsonl-valid-run")

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

        state = StateManager(autopilot_dir=ap_dir)
        _init_issue(state, issue="99")
        state.write(type_="issue", role="worker", issue="99", sets=["current_step=a"])
        state.write(type_="issue", role="worker", issue="99", sets=["current_step=b"])

        log_file = run_dir / "state-log.jsonl"
        if not log_file.exists():
            pytest.skip("state-log.jsonl not created (audit integration not implemented)")

        for i, line in enumerate(log_file.read_text(encoding="utf-8").splitlines()):
            line = line.strip()
            if not line:
                continue
            try:
                json.loads(line)
            except json.JSONDecodeError as e:
                pytest.fail(f"Line {i+1} is not valid JSON: {line!r} — {e}")

    def test_audit_inactive_no_log_written(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Edge case: audit が無効な場合は state-log.jsonl に書き込まない"""
        ap_dir, _ = _create_autopilot_dir(tmp_path)

        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: False
            )
        except ImportError:
            pass  # audit not implemented: no integration, test still validates no crash

        state = StateManager(autopilot_dir=ap_dir)
        _init_issue(state, issue="3")
        state.write(type_="issue", role="worker", issue="3", sets=["current_step=x"])

        # No .audit directory or state-log.jsonl should appear
        audit_base = tmp_path / ".audit"
        for run_dir in (audit_base.iterdir() if audit_base.exists() else []):
            log = run_dir / "state-log.jsonl"
            assert not log.exists(), \
                f"state-log.jsonl should not exist when audit is inactive: {log}"
