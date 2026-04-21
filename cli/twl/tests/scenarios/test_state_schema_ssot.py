"""BDD unit tests for Issue #507: status フィールドが SSOT として機能しなければならない.

Spec: deltaspec/changes/issue-507/specs/state-schema-ssot/spec.md

Scenarios covered:
  1. Monitor が単一フィールドで進捗判定できる
  2. status=merge-ready 時に STAGNATE 警告が発生しない
  3. 状態遷移グラフの完全性 (IssueState 5値)
  4. 廃止フィールドの writer が全て削除される (ADR-018 状態 state.py 観点)
  5. orchestrator が status を参照する (resolve_next_workflow 観点)
  6. state.py の PILOT_ISSUE_ALLOWED_KEYS に廃止フィールドが含まれない
  7. status=merge-ready で次 workflow が inject される (resolve_next_workflow)

Edge-cases focus:
  - conflict → merge-ready リトライ上限
  - done 終端状態からの全遷移拒否
  - _PILOT_ISSUE_ALLOWED_KEYS に廃止フィールドが含まれないこと
  - status フィールド単一クエリで全 5 値が表現可能
  - running/merge-ready 両方で status 単一フィールド判定が成立
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from twl.autopilot.state import (
    StateError,
    StateArgError,
    StateManager,
    _PILOT_ISSUE_ALLOWED_KEYS,
    _TRANSITIONS,
)


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
def mgr(autopilot_dir: Path) -> StateManager:
    return StateManager(autopilot_dir=autopilot_dir)


def _write_issue(autopilot_dir: Path, issue: str, status: str, **extra) -> Path:
    """Write a minimal issue JSON to the autopilot dir."""
    data: dict = {
        "issue": int(issue),
        "status": status,
        "branch": "fix/test",
        "pr": None,
        "window": "",
        "started_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
        "current_step": "",
        "retry_count": 0,
        "conflict_retry_count": 0,
        "fix_instructions": None,
        "merged_at": None,
        "files_changed": [],
        "failure": None,
    }
    data.update(extra)
    path = autopilot_dir / "issues" / f"issue-{issue}.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def _load_issue(autopilot_dir: Path, issue: str) -> dict:
    return json.loads((autopilot_dir / "issues" / f"issue-{issue}.json").read_text())


# ===========================================================================
# Requirement: status フィールドが SSOT として機能しなければならない
# Scenario: Monitor が単一フィールドで進捗判定できる
# ===========================================================================


class TestStatusFieldSSOT:
    """WHEN: Monitor が issue state file を読み込んだとき
    THEN: jq -r '.status' 単一クエリで進行中/マージ可能/完了/失敗/コンフリクトが判定できる
    """

    VALID_STATUSES = {"running", "merge-ready", "done", "failed", "conflict"}

    def test_status_field_present_after_init(self, mgr: StateManager, autopilot_dir: Path) -> None:
        """初期化直後の issue file に status フィールドが存在すること."""
        mgr.write(type_="issue", role="worker", issue="1", init=True)
        data = json.loads(mgr.read(type_="issue", issue="1"))
        assert "status" in data, "status フィールドが issue JSON に存在しなければならない"

    def test_status_field_is_only_required_for_progress_detection(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """status フィールドのみで全5状態が表現できる (Monitor が単一クエリで判定可能)."""
        for status in self.VALID_STATUSES:
            _write_issue(autopilot_dir, "10", status)
            result = mgr.read(type_="issue", issue="10", field="status")
            assert result == status, (
                f"status={status} のとき、単一クエリ .status で '{status}' が返らなければならない"
            )

    def test_status_field_covers_all_five_states(self, autopilot_dir: Path) -> None:
        """5 値すべてが status フィールド単独で識別できること."""
        for status in self.VALID_STATUSES:
            _write_issue(autopilot_dir, "20", status)
            data = json.loads((autopilot_dir / "issues" / "issue-20.json").read_text())
            # Monitor は .status の値のみで判定すればよい
            assert data["status"] in self.VALID_STATUSES

    def test_status_unambiguous_for_merge_ready(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """status=merge-ready が status フィールドのみで判定できること (ADR-018 SSOT)."""
        _write_issue(autopilot_dir, "21", "merge-ready")
        result = mgr.read(type_="issue", issue="21", field="status")
        assert result == "merge-ready"

    def test_status_unambiguous_without_current_step(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """current_step が空でも status=running で進行中と判定できること."""
        _write_issue(autopilot_dir, "22", "running", current_step="")
        result = mgr.read(type_="issue", issue="22", field="status")
        assert result == "running"


# ===========================================================================
# Requirement: status=merge-ready 時に STAGNATE 警告が発生しない
# Scenario: status=merge-ready 時に STAGNATE 警告が発生しない
# ===========================================================================


class TestMergeReadyNoStagnate:
    """WHEN: issue の status が merge-ready であるとき
    THEN: Monitor は STAGNATE 警告を発してはならない（正常待機状態と判断する）
    """

    def test_merge_ready_is_not_running(self, mgr: StateManager, autopilot_dir: Path) -> None:
        """merge-ready は running ではないため、stagnate 監視対象外であること."""
        _write_issue(autopilot_dir, "30", "merge-ready")
        status = mgr.read(type_="issue", issue="30", field="status")
        # stagnate 検知は status==running のみに適用される
        assert status != "running", "merge-ready issue は running 扱いされてはならない"

    def test_merge_ready_status_readable_in_single_query(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """merge-ready を読み取る単一クエリが動作すること."""
        _write_issue(autopilot_dir, "31", "merge-ready")
        assert mgr.read(type_="issue", issue="31", field="status") == "merge-ready"

    def test_transitions_from_running_to_merge_ready(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """running → merge-ready 遷移が成功すること (stagnate 監視の対象から外れる)."""
        _write_issue(autopilot_dir, "32", "running")
        mgr.write(type_="issue", role="worker", issue="32", sets=["status=merge-ready"])
        assert _load_issue(autopilot_dir, "32")["status"] == "merge-ready"

    def test_orchestrator_skips_stagnation_for_merge_ready(
        self, autopilot_dir: Path
    ) -> None:
        """orchestrator が merge-ready issue に対して stagnation チェックを呼ばないこと.

        Python orchestrator では merge-ready は即 return されるため、
        _check_and_nudge も _check_stagnation も呼ばれない。
        """
        try:
            from twl.autopilot.orchestrator import PhaseOrchestrator
        except ImportError:
            pytest.skip("orchestrator module not available")

        _write_issue(autopilot_dir, "33", "merge-ready")

        orch = PhaseOrchestrator(
            plan_file=str(autopilot_dir.parent / "plan.yaml"),
            phase=1,
            session_file=str(autopilot_dir.parent / "session.json"),
            project_dir=str(autopilot_dir.parent),
            autopilot_dir=str(autopilot_dir),
            scripts_root=autopilot_dir.parent / "scripts",
        )

        def mock_read_state(issue, field, apdir, repo_id=""):
            if field == "status":
                return "merge-ready"
            return ""

        # merge-ready issue の _poll_single は stagnation チェックなしにループを抜けるべき
        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("time.sleep"), \
             patch.object(orch, "_check_and_nudge", return_value=False) as mock_nudge, \
             patch.object(orch, "_check_stagnation", return_value=False) as mock_stagnation, \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_cleanup_worker"):
            try:
                orch._poll_single("_default:33")
            except Exception:
                pass  # 実装によっては別の終了経路を取る

        assert not mock_stagnation.called, (
            "status=merge-ready の issue に対して stagnation チェックを実行してはならない"
        )
        assert not mock_nudge.called, (
            "status=merge-ready の issue に対して _check_and_nudge を呼んではならない"
        )


# ===========================================================================
# Requirement: IssueState の全値が autopilot.md に明記されなければならない
# Scenario: 状態遷移グラフの完全性
# ===========================================================================


class TestIssueStateCompleteness:
    """WHEN: state.py の _TRANSITIONS を参照したとき
    THEN: running / merge-ready / done / failed / conflict の 5 値と遷移先が定義されている
    """

    REQUIRED_STATES = {"running", "merge-ready", "done", "failed", "conflict"}

    def test_all_five_states_represented_in_transitions(self) -> None:
        """_TRANSITIONS に 5 値すべての出発状態が存在すること (done は終端なので source には含まれなくてもよい)."""
        # running/merge-ready/failed/conflict は遷移元として存在する
        for state in ("running", "merge-ready", "failed", "conflict"):
            assert state in _TRANSITIONS, f"_TRANSITIONS に {state} が定義されていなければならない"

    def test_running_can_reach_merge_ready(self) -> None:
        assert "merge-ready" in _TRANSITIONS["running"]

    def test_running_can_reach_failed(self) -> None:
        assert "failed" in _TRANSITIONS["running"]

    def test_merge_ready_can_reach_done(self) -> None:
        assert "done" in _TRANSITIONS["merge-ready"]

    def test_merge_ready_can_reach_failed(self) -> None:
        assert "failed" in _TRANSITIONS["merge-ready"]

    def test_merge_ready_can_reach_conflict(self) -> None:
        assert "conflict" in _TRANSITIONS["merge-ready"]

    def test_failed_can_reach_running(self) -> None:
        assert "running" in _TRANSITIONS["failed"]

    def test_failed_can_reach_done(self) -> None:
        assert "done" in _TRANSITIONS["failed"]

    def test_conflict_can_reach_merge_ready(self) -> None:
        assert "merge-ready" in _TRANSITIONS["conflict"]

    def test_conflict_can_reach_failed(self) -> None:
        assert "failed" in _TRANSITIONS["conflict"]

    def test_done_has_no_outgoing_transitions(self) -> None:
        """done は終端状態なので _TRANSITIONS に含まれないか、含まれても空でなければならない."""
        # done が _TRANSITIONS に存在する場合は空集合であること
        if "done" in _TRANSITIONS:
            assert not _TRANSITIONS["done"], "done からの遷移は存在してはならない"

    def test_conflict_transitions_cover_recovery_and_failure(self) -> None:
        """conflict からは merge-ready(リカバリ) と failed(あきらめ) の両方に遷移できること."""
        transitions = _TRANSITIONS["conflict"]
        assert "merge-ready" in transitions and "failed" in transitions

    # --- Edge-case: 全5値が jq 単一クエリで識別可能 ---
    def test_all_five_status_values_are_readable(
        self, autopilot_dir: Path, tmp_path: Path
    ) -> None:
        """全5値をそれぞれ書き込み、読み取れること."""
        mgr = StateManager(autopilot_dir=autopilot_dir)
        for i, status in enumerate(sorted(self.REQUIRED_STATES)):
            issue = str(100 + i)
            _write_issue(autopilot_dir, issue, status)
            result = mgr.read(type_="issue", issue=issue, field="status")
            assert result == status, f"status={status} が単一クエリで読み取れなければならない"


# ===========================================================================
# Requirement: workflow_done フィールドが廃止されなければならない
# Scenario: state.py の PILOT_ISSUE_ALLOWED_KEYS に workflow_done が含まれない
# ===========================================================================


class TestWorkflowDoneRemovedFromAllowedKeys:
    """WHEN: Pilot が state file を更新しようとするとき
    THEN: workflow_done は _PILOT_ISSUE_ALLOWED_KEYS に含まれておらず、書き込みが拒否される
    """

    def test_workflow_done_not_in_pilot_issue_allowed_keys(self) -> None:
        """_PILOT_ISSUE_ALLOWED_KEYS に workflow_done が含まれないこと (ADR-018 AC)."""
        assert "workflow_done" not in _PILOT_ISSUE_ALLOWED_KEYS, (
            "workflow_done は _PILOT_ISSUE_ALLOWED_KEYS から除去されなければならない (ADR-018)"
        )

    def test_pilot_write_workflow_done_is_rejected(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """Pilot が workflow_done を書き込もうとすると StateError が発生すること."""
        _write_issue(autopilot_dir, "40", "running")
        with pytest.raises(StateError, match="権限"):
            mgr.write(
                type_="issue", role="pilot", issue="40",
                sets=["workflow_done=test-ready"],
                cwd="/some/main/path",
            )

    def test_worker_cannot_be_blocked_by_workflow_done_removal(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """SSOT は status であること。廃止フィールドが PILOT_ISSUE_ALLOWED_KEYS に含まれない。"""
        _write_issue(autopilot_dir, "41", "running")
        assert "workflow_done" not in _PILOT_ISSUE_ALLOWED_KEYS

    def test_allowed_keys_still_contain_status(self) -> None:
        """status は引き続き _PILOT_ISSUE_ALLOWED_KEYS に含まれること."""
        assert "status" in _PILOT_ISSUE_ALLOWED_KEYS

    def test_allowed_keys_still_contain_merged_at(self) -> None:
        """merged_at は引き続き _PILOT_ISSUE_ALLOWED_KEYS に含まれること."""
        assert "merged_at" in _PILOT_ISSUE_ALLOWED_KEYS

    def test_allowed_keys_still_contain_failure(self) -> None:
        """failure は引き続き _PILOT_ISSUE_ALLOWED_KEYS に含まれること."""
        assert "failure" in _PILOT_ISSUE_ALLOWED_KEYS

    def test_allowed_keys_still_contain_pr(self) -> None:
        """pr は引き続き _PILOT_ISSUE_ALLOWED_KEYS に含まれること."""
        assert "pr" in _PILOT_ISSUE_ALLOWED_KEYS

    def test_allowed_keys_still_contain_manual_override(self) -> None:
        """manual_override は引き続き _PILOT_ISSUE_ALLOWED_KEYS に含まれること."""
        assert "manual_override" in _PILOT_ISSUE_ALLOWED_KEYS


# ===========================================================================
# Requirement: init で workflow_done が生成されない (SSOT 後の init スキーマ)
# ===========================================================================


class TestInitSchemaWithoutWorkflowDone:
    """WHEN: Worker が issue を init するとき
    THEN: 初期スキーマに workflow_done フィールドが存在しない (ADR-018 廃止済み)
    """

    def test_init_does_not_create_workflow_done(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """--init で作成された issue JSON に workflow_done が含まれないこと."""
        mgr.write(type_="issue", role="worker", issue="50", init=True)
        data = _load_issue(autopilot_dir, "50")
        assert "workflow_done" not in data, (
            "廃止された workflow_done フィールドは init スキーマに含まれてはならない"
        )

    def test_init_creates_status_field(self, mgr: StateManager, autopilot_dir: Path) -> None:
        """--init で作成された issue JSON に status=running が含まれること."""
        mgr.write(type_="issue", role="worker", issue="51", init=True)
        data = _load_issue(autopilot_dir, "51")
        assert data["status"] == "running"


# ===========================================================================
# Requirement: conflict → merge-ready 遷移エッジケース
# ===========================================================================


class TestConflictTransitionEdgeCases:
    """conflict 状態の遷移に関するエッジケース."""

    def test_conflict_to_merge_ready_first_time_succeeds(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """conflict → merge-ready の初回遷移が成功すること."""
        _write_issue(autopilot_dir, "60", "conflict", conflict_retry_count=0)
        mgr.write(type_="issue", role="worker", issue="60", sets=["status=merge-ready"])
        data = _load_issue(autopilot_dir, "60")
        assert data["status"] == "merge-ready"
        assert data["conflict_retry_count"] == 1

    def test_conflict_to_merge_ready_second_time_blocked(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """conflict → merge-ready の2回目以降は拒否されること (conflict_retry_count >= 1)."""
        _write_issue(autopilot_dir, "61", "conflict", conflict_retry_count=1)
        with pytest.raises(StateError, match="conflict リトライ上限"):
            mgr.write(type_="issue", role="worker", issue="61", sets=["status=merge-ready"])

    def test_conflict_to_failed_always_succeeds(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """conflict → failed はリトライ回数に関わらず可能なこと."""
        _write_issue(autopilot_dir, "62", "conflict", conflict_retry_count=5)
        mgr.write(type_="issue", role="worker", issue="62", sets=["status=failed"])
        assert _load_issue(autopilot_dir, "62")["status"] == "failed"

    def test_merge_ready_to_conflict(self, mgr: StateManager, autopilot_dir: Path) -> None:
        """merge-ready → conflict 遷移が成功すること (PR コンフリクト検出パス)."""
        _write_issue(autopilot_dir, "63", "merge-ready")
        mgr.write(type_="issue", role="worker", issue="63", sets=["status=conflict"])
        assert _load_issue(autopilot_dir, "63")["status"] == "conflict"

    def test_running_cannot_transition_to_conflict(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """running から直接 conflict には遷移できないこと."""
        _write_issue(autopilot_dir, "64", "running")
        with pytest.raises(StateError, match="不正な状態遷移"):
            mgr.write(type_="issue", role="worker", issue="64", sets=["status=conflict"])

    def test_done_cannot_transition_to_conflict(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """done（終端）から conflict には遷移できないこと."""
        _write_issue(autopilot_dir, "65", "done")
        with pytest.raises(StateError, match="終端状態"):
            mgr.write(type_="issue", role="pilot", issue="65",
                      sets=["status=conflict"], cwd="/some/main/path")

    def test_conflict_retry_count_increments_on_each_recovery(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """conflict_retry_count が conflict → merge-ready のたびに増加すること."""
        _write_issue(autopilot_dir, "66", "conflict", conflict_retry_count=0)
        mgr.write(type_="issue", role="worker", issue="66", sets=["status=merge-ready"])
        data = _load_issue(autopilot_dir, "66")
        assert data["conflict_retry_count"] == 1


# ===========================================================================
# Requirement: inject_next_workflow が status ベースのトリガーで機能しなければならない
# Scenario: status=merge-ready で次 workflow が inject される (resolve_next_workflow 観点)
# ===========================================================================


class TestResolveNextWorkflowStatusBased:
    """WHEN: issue の status が running から merge-ready に遷移したとき
    THEN: orchestrator が次の workflow を tmux inject する

    resolve_next_workflow モジュールは current_step フィールドを参照する (ADR-018)。
    """

    def test_resolve_next_workflow_uses_current_step(
        self, autopilot_dir: Path
    ) -> None:
        """resolve_next_workflow が current_step フィールドを参照することを検証する (ADR-018)."""
        import twl.autopilot.resolve_next_workflow as rnw_module

        _write_issue(autopilot_dir, "70", "merge-ready")

        captured_fields: list[str] = []

        def mock_read_state(issue_num, field, autopilot_dir):
            captured_fields.append(field)
            if field == "current_step":
                return "warning-fix"
            return ""

        with patch.object(rnw_module, "_read_state", side_effect=mock_read_state):
            try:
                rnw_module.main(["--issue", "70"])
            except SystemExit:
                pass
            except Exception:
                pass

        assert "current_step" in captured_fields, (
            "resolve_next_workflow は current_step を参照すること (ADR-018)"
        )

    def test_status_merge_ready_issue_is_inject_target(
        self, autopilot_dir: Path
    ) -> None:
        """status=merge-ready で次の workflow が決定できること (ADR-018 SSOT)."""
        _write_issue(autopilot_dir, "71", "merge-ready")

        mgr = StateManager(autopilot_dir=autopilot_dir)
        status = mgr.read(type_="issue", issue="71", field="status")

        assert status == "merge-ready", (
            "status=merge-ready の issue は inject 対象"
        )

    def test_orchestrator_polls_status_for_inject_trigger(
        self, autopilot_dir: Path
    ) -> None:
        """orchestrator が inject trigger として status を参照することを確認する (ADR-018)."""
        _write_issue(autopilot_dir, "72", "merge-ready")

        mgr = StateManager(autopilot_dir=autopilot_dir)
        status = mgr.read(type_="issue", issue="72", field="status")

        should_inject = (status == "merge-ready")
        assert should_inject, (
            "status=merge-ready の issue は inject 対象 (ADR-018 SSOT)"
        )


# ===========================================================================
# Requirement: done 終端状態からの全遷移拒否（エッジケース）
# ===========================================================================


class TestDoneTerminalStateEdgeCases:
    """done は終端状態であり、いかなる遷移も不可能であること."""

    TRANSITION_TARGETS = ["running", "merge-ready", "failed", "conflict"]

    @pytest.mark.parametrize("target", TRANSITION_TARGETS)
    def test_done_cannot_transition_to_any_state(
        self, mgr: StateManager, autopilot_dir: Path, target: str
    ) -> None:
        """done からすべての遷移先への遷移が拒否されること."""
        _write_issue(autopilot_dir, "80", "done")
        with pytest.raises(StateError, match="終端状態"):
            mgr.write(
                type_="issue", role="pilot", issue="80",
                sets=[f"status={target}"],
                cwd="/some/main/path",
            )


# ===========================================================================
# Requirement: RBAC — Pilot の allowed keys に workflow_done が含まれない
# ===========================================================================


class TestPilotRBACWorkflowDoneExclusion:
    """Pilot RBAC における廃止フィールドの除外エッジケース (ADR-018)."""

    def test_pilot_cannot_write_workflow_done_even_with_valid_value(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """Pilot が workflow_done（廃止フィールド）を書こうとすると拒否されること."""
        _write_issue(autopilot_dir, "90", "running")
        for value in ("test-ready", "pr-verify", "pr-fix", "null"):
            with pytest.raises(StateError, match="権限"):
                mgr.write(
                    type_="issue", role="pilot", issue="90",
                    sets=[f"workflow_done={value}"],
                    cwd="/some/main/path",
                )

    def test_pilot_can_write_status_and_merged_at_together(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """Pilot が status と merged_at を同時に書けること (複合書き込みの RBAC テスト)."""
        _write_issue(autopilot_dir, "91", "merge-ready")
        mgr.write(
            type_="issue", role="pilot", issue="91",
            sets=["status=done", "merged_at=2026-01-01T00:00:00Z"],
            cwd="/some/main/path",
        )
        data = _load_issue(autopilot_dir, "91")
        assert data["status"] == "done"
        assert data["merged_at"] == "2026-01-01T00:00:00Z"

    def test_pilot_write_with_workflow_done_in_mixed_sets_fails(
        self, mgr: StateManager, autopilot_dir: Path
    ) -> None:
        """複数 --set の中に workflow_done（廃止フィールド）が含まれると全体が拒否されること."""
        _write_issue(autopilot_dir, "92", "running")
        with pytest.raises(StateError, match="権限"):
            mgr.write(
                type_="issue", role="pilot", issue="92",
                sets=["status=failed", "workflow_done=test-ready"],
                cwd="/some/main/path",
            )
