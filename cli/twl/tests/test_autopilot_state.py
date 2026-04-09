"""Tests for twl.autopilot.state and twl.autopilot.session.

Covers state transition rules (happy path, error path, invalid transitions),
role-based access control, field validation, and session lifecycle.
"""

import json
import os
import tempfile
from pathlib import Path

import pytest

from twl.autopilot.state import StateManager, StateError, StateArgError
from twl.autopilot.session import SessionManager, SessionError, SessionArgError


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
def session(autopilot_dir: Path) -> SessionManager:
    return SessionManager(autopilot_dir=autopilot_dir)


def _init_issue(state: StateManager, issue: str = "1") -> None:
    state.write(type_="issue", role="worker", issue=issue, init=True)


def _load_issue(autopilot_dir: Path, issue: str = "1") -> dict:
    return json.loads((autopilot_dir / "issues" / f"issue-{issue}.json").read_text())


def _create_issue_with_status(
    autopilot_dir: Path, issue: str, status: str, retry_count: int = 0
) -> None:
    data = {
        "issue": int(issue),
        "status": status,
        "branch": "",
        "pr": None,
        "window": "",
        "started_at": "2024-01-01T00:00:00Z",
        "updated_at": "2024-01-01T00:00:00Z",
        "current_step": "",
        "retry_count": retry_count,
        "fix_instructions": None,
        "merged_at": None,
        "files_changed": [],
        "failure": None,
    }
    file = autopilot_dir / "issues" / f"issue-{issue}.json"
    file.write_text(json.dumps(data))


# ===========================================================================
# StateManager — read
# ===========================================================================


class TestStateRead:
    def test_missing_file_returns_empty(self, state: StateManager) -> None:
        assert state.read(type_="issue", issue="99") == ""

    def test_read_full_json(self, state: StateManager, autopilot_dir: Path) -> None:
        _init_issue(state, "1")
        result = state.read(type_="issue", issue="1")
        data = json.loads(result)
        assert data["status"] == "running"
        assert data["issue"] == 1

    def test_read_field(self, state: StateManager) -> None:
        _init_issue(state, "2")
        assert state.read(type_="issue", issue="2", field="status") == "running"

    def test_read_missing_field_returns_empty(self, state: StateManager) -> None:
        _init_issue(state, "3")
        assert state.read(type_="issue", issue="3", field="nonexistent_field") == ""

    def test_read_nested_field(self, state: StateManager, autopilot_dir: Path) -> None:
        file = autopilot_dir / "issues" / "issue-5.json"
        file.write_text(json.dumps({"failure": {"reason": "timeout"}, "status": "failed"}))
        assert state.read(type_="issue", issue="5", field="failure.reason") == "timeout"

    def test_invalid_type(self, state: StateManager) -> None:
        with pytest.raises(StateArgError):
            state.read(type_="bad", issue="1")

    def test_missing_issue_for_type_issue(self, state: StateManager) -> None:
        with pytest.raises(StateArgError):
            state.read(type_="issue")

    def test_invalid_issue_num(self, state: StateManager) -> None:
        with pytest.raises(StateArgError):
            state.read(type_="issue", issue="abc")

    def test_invalid_field_name(self, state: StateManager) -> None:
        _init_issue(state, "4")
        with pytest.raises(StateArgError):
            state.read(type_="issue", issue="4", field="../etc/passwd")

    def test_read_boolean_field_false(self, state: StateManager, autopilot_dir: Path) -> None:
        file = autopilot_dir / "issues" / "issue-6.json"
        file.write_text(json.dumps({"is_quick": False, "status": "running"}))
        # false should return "false", not empty string
        assert state.read(type_="issue", issue="6", field="is_quick") == "false"


# ===========================================================================
# StateManager — write / init
# ===========================================================================


class TestStateWriteInit:
    def test_init_creates_file(self, state: StateManager, autopilot_dir: Path) -> None:
        state.write(type_="issue", role="worker", issue="1", init=True)
        data = _load_issue(autopilot_dir, "1")
        assert data["status"] == "running"
        assert data["retry_count"] == 0

    def test_init_duplicate_fails(self, state: StateManager) -> None:
        _init_issue(state, "1")
        with pytest.raises(StateError, match="既に存在"):
            state.write(type_="issue", role="worker", issue="1", init=True)

    def test_init_requires_worker_role(self, state: StateManager) -> None:
        with pytest.raises(StateArgError):
            state.write(type_="issue", role="pilot", issue="1", init=True)


class TestStateWriteFields:
    def test_set_string_field(self, state: StateManager, autopilot_dir: Path) -> None:
        _init_issue(state, "1")
        state.write(type_="issue", role="worker", issue="1", sets=["current_step=check"])
        data = _load_issue(autopilot_dir, "1")
        assert data["current_step"] == "check"

    def test_set_json_null_field(self, state: StateManager, autopilot_dir: Path) -> None:
        _init_issue(state, "1")
        state.write(type_="issue", role="worker", issue="1", sets=["pr=null"])
        data = _load_issue(autopilot_dir, "1")
        assert data["pr"] is None

    def test_set_bool_field(self, state: StateManager, autopilot_dir: Path) -> None:
        _init_issue(state, "1")
        state.write(type_="issue", role="worker", issue="1", sets=["is_quick=true"])
        data = _load_issue(autopilot_dir, "1")
        assert data["is_quick"] is True

    def test_updated_at_auto_set(self, state: StateManager, autopilot_dir: Path) -> None:
        _init_issue(state, "1")
        state.write(type_="issue", role="worker", issue="1", sets=["current_step=test"])
        data = _load_issue(autopilot_dir, "1")
        import re
        assert "updated_at" in data
        assert re.match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", data["updated_at"])

    def test_invalid_key_name(self, state: StateManager) -> None:
        _init_issue(state, "1")
        with pytest.raises(StateArgError, match="不正なフィールド名"):
            state.write(type_="issue", role="worker", issue="1", sets=["../etc=bad"])

    def test_no_sets_raises(self, state: StateManager) -> None:
        _init_issue(state, "1")
        with pytest.raises(StateArgError, match="--set"):
            state.write(type_="issue", role="worker", issue="1", sets=[])


# ===========================================================================
# StateManager — transition validation
# ===========================================================================


class TestStateTransitions:
    def test_running_to_merge_ready(self, state: StateManager, autopilot_dir: Path) -> None:
        _create_issue_with_status(autopilot_dir, "1", "running")
        state.write(type_="issue", role="worker", issue="1", sets=["status=merge-ready"])
        assert _load_issue(autopilot_dir, "1")["status"] == "merge-ready"

    def test_running_to_failed(self, state: StateManager, autopilot_dir: Path) -> None:
        _create_issue_with_status(autopilot_dir, "1", "running")
        state.write(type_="issue", role="worker", issue="1", sets=["status=failed"])
        assert _load_issue(autopilot_dir, "1")["status"] == "failed"

    def test_merge_ready_to_done(self, state: StateManager, autopilot_dir: Path) -> None:
        _create_issue_with_status(autopilot_dir, "1", "merge-ready")
        state.write(type_="issue", role="pilot", issue="1",
                    sets=["status=done"], cwd="/some/main/path")
        assert _load_issue(autopilot_dir, "1")["status"] == "done"

    def test_merge_ready_to_failed(self, state: StateManager, autopilot_dir: Path) -> None:
        _create_issue_with_status(autopilot_dir, "1", "merge-ready")
        state.write(type_="issue", role="pilot", issue="1",
                    sets=["status=failed"], cwd="/some/main/path")
        assert _load_issue(autopilot_dir, "1")["status"] == "failed"

    def test_failed_to_running_increments_retry(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "failed", retry_count=0)
        state.write(type_="issue", role="worker", issue="1", sets=["status=running"])
        data = _load_issue(autopilot_dir, "1")
        assert data["status"] == "running"
        assert data["retry_count"] == 1

    def test_failed_to_running_blocked_at_retry_limit(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "failed", retry_count=1)
        with pytest.raises(StateError, match="リトライ上限"):
            state.write(type_="issue", role="worker", issue="1", sets=["status=running"])

    def test_done_is_terminal(self, state: StateManager, autopilot_dir: Path) -> None:
        _create_issue_with_status(autopilot_dir, "1", "done")
        with pytest.raises(StateError, match="終端状態"):
            state.write(type_="issue", role="pilot", issue="1",
                        sets=["status=running"], cwd="/some/main/path")

    def test_invalid_transition_running_to_done(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "running")
        with pytest.raises(StateError, match="不正な状態遷移"):
            state.write(type_="issue", role="worker", issue="1", sets=["status=done"])

    def test_invalid_transition_merge_ready_to_running(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "merge-ready")
        with pytest.raises(StateError, match="不正な状態遷移"):
            state.write(type_="issue", role="worker", issue="1", sets=["status=running"])

    def test_failed_to_done_with_force_done(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "failed")
        state.write(
            type_="issue", role="worker", issue="1",
            sets=["status=done"],
            force_done=True, override_reason="Emergency bypass merge completed",
        )
        data = _load_issue(autopilot_dir, "1")
        assert data["status"] == "done"
        assert data["manual_override"] is True
        assert data["override_reason"] == "Emergency bypass merge completed"

    def test_failed_to_done_without_force_done_rejected(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "failed")
        with pytest.raises(StateError, match="--force-done フラグが必須"):
            state.write(type_="issue", role="worker", issue="1", sets=["status=done"])

    def test_failed_to_done_force_done_without_reason_rejected(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "failed")
        with pytest.raises(StateArgError, match="--override-reason が必須"):
            state.write(
                type_="issue", role="worker", issue="1",
                sets=["status=done"], force_done=True,
            )

    def test_failed_to_running_unaffected_by_force_done(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "failed", retry_count=0)
        state.write(type_="issue", role="worker", issue="1", sets=["status=running"])
        data = _load_issue(autopilot_dir, "1")
        assert data["status"] == "running"
        assert data["retry_count"] == 1
        assert "manual_override" not in data


# ===========================================================================
# StateManager — RBAC
# ===========================================================================


class TestStateRBAC:
    def test_worker_cannot_write_session(self, state: StateManager, autopilot_dir: Path) -> None:
        (autopilot_dir / "session.json").write_text(json.dumps({"session_id": "abc"}))
        with pytest.raises(StateError, match="Worker"):
            state.write(type_="session", role="worker", sets=["current_phase=2"])

    def test_pilot_cannot_write_arbitrary_issue_field(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _init_issue(state, "1")
        with pytest.raises(StateError, match="権限"):
            state.write(type_="issue", role="pilot", issue="1",
                        sets=["current_step=bad"], cwd="/some/main/path")

    def test_pilot_can_write_status(self, state: StateManager, autopilot_dir: Path) -> None:
        _create_issue_with_status(autopilot_dir, "1", "running")
        state.write(type_="issue", role="pilot", issue="1",
                    sets=["status=failed"], cwd="/some/main/path")
        assert _load_issue(autopilot_dir, "1")["status"] == "failed"

    def test_pilot_cannot_write_from_worktrees(
        self, state: StateManager, autopilot_dir: Path
    ) -> None:
        _create_issue_with_status(autopilot_dir, "1", "running")
        with pytest.raises(StateError, match="不変条件C"):
            state.write(
                type_="issue", role="pilot", issue="1",
                sets=["status=failed"],
                cwd="/home/user/projects/twill/worktrees/feat/1-foo",
            )


# ===========================================================================
# SessionManager — create
# ===========================================================================


class TestSessionCreate:
    def test_create_writes_file(self, session: SessionManager, autopilot_dir: Path) -> None:
        session.create(plan_path="plan.yaml", phase_count=3)
        data = json.loads((autopilot_dir / "session.json").read_text())
        assert data["phase_count"] == 3
        assert data["current_phase"] == 1
        assert len(data["session_id"]) == 8  # 4 bytes → 8 hex chars

    def test_create_fails_if_exists(self, session: SessionManager, autopilot_dir: Path) -> None:
        session.create(plan_path="plan.yaml", phase_count=2)
        with pytest.raises(SessionError, match="既に存在"):
            session.create(plan_path="plan.yaml", phase_count=2)


# ===========================================================================
# SessionManager — archive
# ===========================================================================


class TestSessionArchive:
    def test_archive_moves_files(self, session: SessionManager, autopilot_dir: Path) -> None:
        session.create(plan_path="plan.yaml", phase_count=1)
        sid = json.loads((autopilot_dir / "session.json").read_text())["session_id"]

        # create a fake issue file
        issue_file = autopilot_dir / "issues" / "issue-1.json"
        issue_file.write_text(json.dumps({"issue": 1, "status": "done"}))

        session.archive()

        assert not (autopilot_dir / "session.json").exists()
        archive = autopilot_dir / "archive" / sid
        assert (archive / "session.json").exists()
        assert (archive / "issues" / "issue-1.json").exists()

    def test_archive_fails_without_session(self, session: SessionManager) -> None:
        with pytest.raises(SessionError, match="session.json が存在しません"):
            session.archive()


# ===========================================================================
# SessionManager — add_warning
# ===========================================================================


class TestSessionAddWarning:
    def test_add_warning_appends(self, session: SessionManager, autopilot_dir: Path) -> None:
        session.create(plan_path="plan.yaml", phase_count=1)
        session.add_warning(issue=1, target_issue=2, file="src/foo.py", reason="conflict")
        data = json.loads((autopilot_dir / "session.json").read_text())
        assert len(data["cross_issue_warnings"]) == 1
        w = data["cross_issue_warnings"][0]
        assert w["issue"] == 1
        assert w["target_issue"] == 2

    def test_add_warning_multiple(self, session: SessionManager, autopilot_dir: Path) -> None:
        session.create(plan_path="plan.yaml", phase_count=1)
        session.add_warning(1, 2, "a.py", "r1")
        session.add_warning(3, 4, "b.py", "r2")
        data = json.loads((autopilot_dir / "session.json").read_text())
        assert len(data["cross_issue_warnings"]) == 2

    def test_add_warning_fails_without_session(self, session: SessionManager) -> None:
        with pytest.raises(SessionError):
            session.add_warning(1, 2, "f.py", "reason")


# ===========================================================================
# SessionManager — audit
# ===========================================================================


class TestSessionAudit:
    def _make_jsonl(self, tmp_path: Path, lines: list[dict]) -> Path:
        f = tmp_path / "session.jsonl"
        f.write_text("\n".join(json.dumps(l) for l in lines))
        return f

    def test_audit_extracts_tool_calls(self, session: SessionManager, tmp_path: Path) -> None:
        os.environ["SESSION_AUDIT_ALLOW_ANY_PATH"] = "1"
        try:
            lines = [
                {
                    "type": "assistant",
                    "timestamp": "2024-01-01T00:00:00Z",
                    "message": {
                        "content": [
                            {"type": "tool_use", "id": "t1", "name": "Bash",
                             "input": {"command": "echo hello"}}
                        ]
                    },
                }
            ]
            path = self._make_jsonl(tmp_path, lines)
            output = session.audit(str(path))
            entries = [json.loads(l) for l in output.strip().split("\n") if l.strip()]
            tool_calls = [e for e in entries if e["entry_type"] == "tool_call"]
            assert len(tool_calls) == 1
            assert tool_calls[0]["tool_name"] == "Bash"
            assert "echo hello" in tool_calls[0]["input"]
        finally:
            os.environ.pop("SESSION_AUDIT_ALLOW_ANY_PATH", None)

    def test_audit_extracts_skill_calls(self, session: SessionManager, tmp_path: Path) -> None:
        os.environ["SESSION_AUDIT_ALLOW_ANY_PATH"] = "1"
        try:
            lines = [
                {
                    "type": "assistant",
                    "timestamp": "2024-01-01T00:00:00Z",
                    "message": {
                        "content": [
                            {"type": "tool_use", "id": "s1", "name": "Skill",
                             "input": {"skill": "twl:check", "args": ""}}
                        ]
                    },
                }
            ]
            path = self._make_jsonl(tmp_path, lines)
            output = session.audit(str(path))
            entries = [json.loads(l) for l in output.strip().split("\n") if l.strip()]
            skill_calls = [e for e in entries if e["entry_type"] == "skill_call"]
            assert len(skill_calls) == 1
            assert skill_calls[0]["skill_name"] == "twl:check"
        finally:
            os.environ.pop("SESSION_AUDIT_ALLOW_ANY_PATH", None)

    def test_audit_missing_file_raises(self, session: SessionManager) -> None:
        os.environ["SESSION_AUDIT_ALLOW_ANY_PATH"] = "1"
        try:
            with pytest.raises(SessionError, match="not found"):
                session.audit("/nonexistent/path.jsonl")
        finally:
            os.environ.pop("SESSION_AUDIT_ALLOW_ANY_PATH", None)

    def test_audit_skips_invalid_json_lines(
        self, session: SessionManager, tmp_path: Path
    ) -> None:
        os.environ["SESSION_AUDIT_ALLOW_ANY_PATH"] = "1"
        try:
            f = tmp_path / "mixed.jsonl"
            f.write_text('{"type":"user"}\nINVALID LINE\n{"type":"assistant","message":{}}\n')
            output = session.audit(str(f))
            entries = [json.loads(l) for l in output.strip().split("\n") if l.strip()]
            assert any(e["entry_type"] == "metadata" for e in entries)
        finally:
            os.environ.pop("SESSION_AUDIT_ALLOW_ANY_PATH", None)

    def test_audit_path_restricted_without_env_override(
        self, session: SessionManager, tmp_path: Path
    ) -> None:
        """audit() rejects paths outside ~/.claude/projects/ in normal mode."""
        os.environ.pop("SESSION_AUDIT_ALLOW_ANY_PATH", None)
        f = tmp_path / "session.jsonl"
        f.write_text('{"type":"user"}\n')
        with pytest.raises(Exception, match="Path must be under"):
            session.audit(str(f))


# ===========================================================================
# CLI integration via main()
# ===========================================================================


class TestStateCLI:
    def test_read_subcommand(self, autopilot_dir: Path) -> None:
        from twl.autopilot.state import main

        mgr = StateManager(autopilot_dir=autopilot_dir)
        _init_issue(mgr, "1")

        # Patch AUTOPILOT_DIR so main() can find the file
        os.environ["AUTOPILOT_DIR"] = str(autopilot_dir)
        try:
            import io
            from contextlib import redirect_stdout

            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = main(["read", "--type", "issue", "--issue", "1", "--field", "status"])
            assert rc == 0
            assert buf.getvalue().strip() == "running"
        finally:
            os.environ.pop("AUTOPILOT_DIR", None)

    def test_write_subcommand(self, autopilot_dir: Path) -> None:
        from twl.autopilot.state import main

        mgr = StateManager(autopilot_dir=autopilot_dir)
        _init_issue(mgr, "1")

        os.environ["AUTOPILOT_DIR"] = str(autopilot_dir)
        try:
            rc = main(["write", "--type", "issue", "--issue", "1",
                       "--role", "worker", "--set", "current_step=apply"])
            assert rc == 0
            assert mgr.read(type_="issue", issue="1", field="current_step") == "apply"
        finally:
            os.environ.pop("AUTOPILOT_DIR", None)

    def test_unknown_subcommand(self) -> None:
        from twl.autopilot.state import main

        rc = main(["unknown"])
        assert rc == 2

    def test_missing_subcommand(self) -> None:
        from twl.autopilot.state import main

        rc = main([])
        assert rc == 2

    def test_force_done_cli(self, autopilot_dir: Path) -> None:
        from twl.autopilot.state import main

        _create_issue_with_status(autopilot_dir, "1", "failed")

        os.environ["AUTOPILOT_DIR"] = str(autopilot_dir)
        try:
            rc = main([
                "write", "--type", "issue", "--issue", "1",
                "--role", "worker", "--set", "status=done",
                "--force-done", "--override-reason", "Emergency bypass merge completed",
            ])
            assert rc == 0
            data = _load_issue(autopilot_dir, "1")
            assert data["status"] == "done"
            assert data["manual_override"] is True
            assert data["override_reason"] == "Emergency bypass merge completed"
        finally:
            os.environ.pop("AUTOPILOT_DIR", None)
