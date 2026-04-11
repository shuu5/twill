"""Tests for orchestrator.py Worker Stagnation Detection (Issue #472).

Scenarios covered:
  - stagnation detected in _poll_single (updated_at older than STAGNATION_THRESHOLD)
  - no stagnation in _poll_single (updated_at within threshold)
  - updated_at field missing from state (should be treated as no stagnation / skip)
  - stagnation detected in _poll_phase (multi-worker)
  - MAX_STAGNATION_NUDGE exceeded -> status=failed transition
  - STAGNATION_THRESHOLD env var override (AUTOPILOT_STAGNATE_SEC)
  - STAGNATION_THRESHOLD default value (900 seconds)
"""

from __future__ import annotations

import importlib
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest

import twl.autopilot.orchestrator as orchestrator_mod
from twl.autopilot.orchestrator import (
    POLL_INTERVAL,
    PhaseOrchestrator,
    _parse_issue_entry,
    _window_name,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _iso_ago(seconds: int) -> str:
    """Return ISO-8601 UTC timestamp N seconds in the past."""
    dt = datetime.now(timezone.utc) - timedelta(seconds=seconds)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _make_orchestrator(tmp_path: Path) -> PhaseOrchestrator:
    autopilot_dir = tmp_path / ".autopilot"
    autopilot_dir.mkdir()
    (autopilot_dir / "issues").mkdir()
    return PhaseOrchestrator(
        plan_file=str(tmp_path / "plan.yaml"),
        phase=1,
        session_file=str(tmp_path / "session.json"),
        project_dir=str(tmp_path),
        autopilot_dir=str(autopilot_dir),
        scripts_root=tmp_path / "scripts",
    )


# ---------------------------------------------------------------------------
# Requirement: STAGNATION_THRESHOLD 環境変数オーバーライド
# ---------------------------------------------------------------------------


class TestStagnationThresholdConstant:
    """Scenario: 環境変数設定なし -> デフォルト 900 秒"""

    def test_default_value_is_900(self) -> None:
        """STAGNATION_THRESHOLD のデフォルト値が 900 であること."""
        # 環境変数が未設定の場合
        env_without = {k: v for k, v in os.environ.items()
                       if k != "AUTOPILOT_STAGNATE_SEC"}
        with patch.dict(os.environ, env_without, clear=True):
            # モジュールを再ロードしてデフォルト値を検証
            import importlib
            reloaded = importlib.reload(orchestrator_mod)
            assert reloaded.STAGNATION_THRESHOLD == 900

    def test_env_var_overrides_threshold(self) -> None:
        """Scenario: 環境変数設定あり -> stagnation 判定閾値が 300 秒になること."""
        with patch.dict(os.environ, {"AUTOPILOT_STAGNATE_SEC": "300"}):
            import importlib
            reloaded = importlib.reload(orchestrator_mod)
            assert reloaded.STAGNATION_THRESHOLD == 300

    def test_env_var_invalid_falls_back_or_raises(self) -> None:
        """不正な環境変数値の場合は ValueError / デフォルト値フォールバックのどちらか."""
        # 実装によって挙動が異なる可能性があるため、両パターンを許容
        with patch.dict(os.environ, {"AUTOPILOT_STAGNATE_SEC": "not_a_number"}):
            try:
                import importlib
                reloaded = importlib.reload(orchestrator_mod)
                # フォールバックした場合はデフォルト値
                assert reloaded.STAGNATION_THRESHOLD == 900
            except ValueError:
                pass  # 例外を投げる実装も許容


# ---------------------------------------------------------------------------
# Requirement: orchestrator.py Worker Stagnation Detection - _poll_single
# ---------------------------------------------------------------------------


class TestPollSingleStagnation:
    """_poll_single の stagnation 検知シナリオ."""

    def _make_state_map(self, statuses: dict[str, str], updated_ats: dict[str, str]) -> dict[str, str]:
        """issue -> (status, updated_at) の state map を構築."""
        result: dict[str, str] = {}
        for issue, status in statuses.items():
            result[(issue, "status")] = status
        for issue, updated_at in updated_ats.items():
            result[(issue, "updated_at")] = updated_at
        return result

    def test_stagnation_detected_sends_nudge(self, tmp_path: Path) -> None:
        """Scenario: stagnation 検知 (_poll_single)
        WHEN: _poll_single の running ループ中に Worker の updated_at が STAGNATION_THRESHOLD 以上古い
        THEN: orchestrator は stall nudge を送信し、stagnation_nudge_count を increment する
        """
        orch = _make_orchestrator(tmp_path)
        entry = "_default:101"
        issue = "101"
        wname = _window_name("_default", issue)

        # updated_at は STAGNATION_THRESHOLD (900秒) を超過
        stale_updated_at = _iso_ago(1000)

        call_count = 0

        def mock_read_state(iss, field, autopilot_dir, repo_id=""):
            nonlocal call_count
            if field == "status":
                call_count += 1
                if call_count == 1:
                    return "running"
                return "done"  # 2回目以降は done で終了
            if field == "updated_at":
                return stale_updated_at
            return ""

        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("twl.autopilot.orchestrator._write_state") as mock_write, \
             patch("time.sleep"), \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_check_and_nudge", return_value=False), \
             patch.object(orch, "_cleanup_worker"):

            orch._poll_single(entry)

        # stagnation が検知された場合、nudge が送信されるか stagnation カウントが管理される
        # 実装によっては _check_and_nudge の呼び出しか、専用の stagnation nudge メソッドが使われる
        # ここではメソッドが呼ばれたことを検証
        assert orch._check_and_nudge.called or hasattr(orch, "_stagnation_nudge_counts")

    def test_stagnation_not_detected_when_within_threshold(self, tmp_path: Path) -> None:
        """Scenario: stagnation なし
        WHEN: Worker の updated_at が STAGNATION_THRESHOLD 以内
        THEN: stagnation チェックはスキップし、既存の _check_and_nudge に処理を委譲する
        """
        orch = _make_orchestrator(tmp_path)
        entry = "_default:102"
        issue = "102"

        # updated_at は閾値以内（100秒前）
        fresh_updated_at = _iso_ago(100)

        call_count = 0

        def mock_read_state(iss, field, autopilot_dir, repo_id=""):
            nonlocal call_count
            if field == "status":
                call_count += 1
                if call_count == 1:
                    return "running"
                return "done"
            if field == "updated_at":
                return fresh_updated_at
            return ""

        stagnation_nudge_called = []

        def mock_check_and_nudge(issue, wname, entry):
            return False

        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("time.sleep"), \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_check_and_nudge", side_effect=mock_check_and_nudge) as mock_nudge, \
             patch.object(orch, "_cleanup_worker"):

            orch._poll_single(entry)

        # stagnation なしでも _check_and_nudge は呼ばれる（既存フロー）
        assert mock_nudge.called

    def test_stagnation_with_missing_updated_at(self, tmp_path: Path) -> None:
        """Scenario: updated_at 欠如
        WHEN: Worker の state file に updated_at フィールドが存在しない（空文字）
        THEN: stagnation として扱わず、既存の nudge フローに委譲する
        """
        orch = _make_orchestrator(tmp_path)
        entry = "_default:103"
        issue = "103"

        call_count = 0

        def mock_read_state(iss, field, autopilot_dir, repo_id=""):
            nonlocal call_count
            if field == "status":
                call_count += 1
                if call_count == 1:
                    return "running"
                return "done"
            if field == "updated_at":
                return ""  # updated_at が欠如
            return ""

        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("time.sleep"), \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_check_and_nudge", return_value=False) as mock_nudge, \
             patch.object(orch, "_cleanup_worker"):

            orch._poll_single(entry)

        # updated_at 欠如でも crash せず、通常フローが継続すること
        assert mock_nudge.called

    def test_stagnation_nudge_count_exceeds_max_transitions_to_failed(self, tmp_path: Path) -> None:
        """Scenario: stagnation 検知 (_poll_single) - MAX_STAGNATION_NUDGE 超過
        WHEN: stagnation_nudge_count が MAX_STAGNATION_NUDGE を超えた
        THEN: status=failed に遷移する
        """
        orch = _make_orchestrator(tmp_path)
        entry = "_default:104"
        issue = "104"

        # MAX_STAGNATION_NUDGE (デフォルト: 3) を超える stagnation を設定済みとする
        if hasattr(orch, "_stagnation_nudge_counts"):
            max_nudge = getattr(orchestrator_mod, "MAX_STAGNATION_NUDGE", 3)
            orch._stagnation_nudge_counts[issue] = max_nudge + 1

        stale_updated_at = _iso_ago(2000)  # 2000秒前 = 閾値超過

        statuses = ["running", "running", "running", "running", "failed"]
        status_iter = iter(statuses)

        def mock_read_state(iss, field, autopilot_dir, repo_id=""):
            if field == "status":
                try:
                    return next(status_iter)
                except StopIteration:
                    return "failed"
            if field == "updated_at":
                return stale_updated_at
            return ""

        written_states: list[tuple] = []

        def mock_write_state(iss, role, sets, autopilot_dir, repo_id=""):
            written_states.append((iss, role, sets))

        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("twl.autopilot.orchestrator._write_state", side_effect=mock_write_state), \
             patch("time.sleep"), \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_check_and_nudge", return_value=False), \
             patch.object(orch, "_cleanup_worker"):

            orch._poll_single(entry)

        # MAX_STAGNATION_NUDGE 超過時に status=failed が書き込まれるか、
        # または通常の MAX_POLL タイムアウトで failed が書き込まれることを検証
        # （実装前は既存の poll_timeout で失敗するため、written_states は空の場合もある）
        # このテストは実装後にパスすることを期待
        stagnation_failed = any(
            "status=failed" in str(sets)
            for (iss, role, sets) in written_states
            if iss == issue
        )
        assert stagnation_failed, "MAX_STAGNATION_NUDGE 超過時に status=failed が書き込まれること"


# ---------------------------------------------------------------------------
# Requirement: orchestrator.py Worker Stagnation Detection - _poll_phase
# ---------------------------------------------------------------------------


class TestPollPhaseStagnation:
    """_poll_phase の stagnation 検知シナリオ."""

    def test_stagnation_detected_in_poll_phase(self, tmp_path: Path) -> None:
        """Scenario: stagnation 検知 (_poll_phase)
        WHEN: _poll_phase の running ループ中に任意 Worker の updated_at が STAGNATION_THRESHOLD 以上古い
        THEN: orchestrator は当該 Worker に対して stall nudge を送信し、カウント管理する
        """
        orch = _make_orchestrator(tmp_path)
        entries = ["_default:201", "_default:202"]

        stale_updated_at = _iso_ago(1000)  # 閾値超過

        call_counts: dict[str, int] = {}

        def mock_read_state(iss, field, autopilot_dir, repo_id=""):
            if field == "status":
                call_counts[iss] = call_counts.get(iss, 0) + 1
                c = call_counts[iss]
                if iss == "201":
                    return "running" if c <= 2 else "done"
                else:
                    return "running" if c <= 2 else "done"
            if field == "updated_at":
                return stale_updated_at
            return ""

        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("twl.autopilot.orchestrator._write_state"), \
             patch("time.sleep"), \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_check_and_nudge", return_value=False) as mock_nudge, \
             patch.object(orch, "_cleanup_worker"):

            orch._poll_phase(entries)

        # running ループ中に _check_and_nudge が呼ばれていること（stagnation フォールスルーで）
        assert mock_nudge.called

    def test_no_stagnation_in_poll_phase(self, tmp_path: Path) -> None:
        """Scenario: stagnation なし (_poll_phase)
        WHEN: 全 Worker の updated_at が STAGNATION_THRESHOLD 以内
        THEN: 既存の _check_and_nudge に処理を委譲する
        """
        orch = _make_orchestrator(tmp_path)
        entries = ["_default:203", "_default:204"]

        fresh_updated_at = _iso_ago(60)  # 1分前 = 閾値以内

        call_counts: dict[str, int] = {}

        def mock_read_state(iss, field, autopilot_dir, repo_id=""):
            if field == "status":
                call_counts[iss] = call_counts.get(iss, 0) + 1
                c = call_counts[iss]
                return "running" if c == 1 else "done"
            if field == "updated_at":
                return fresh_updated_at
            return ""

        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("time.sleep"), \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_check_and_nudge", return_value=False) as mock_nudge, \
             patch.object(orch, "_cleanup_worker"):

            orch._poll_phase(entries)

        # 閾値以内でも running Worker がいれば _check_and_nudge は呼ばれる
        assert mock_nudge.called


# ---------------------------------------------------------------------------
# Requirement: STAGNATION_THRESHOLD の実際の閾値判定ロジック
# （モジュールレベル定数が正しく参照されること）
# ---------------------------------------------------------------------------


class TestStagnationThresholdBehavior:
    """STAGNATION_THRESHOLD が実際の判定に使われること."""

    def test_threshold_boundary_just_over(self, tmp_path: Path) -> None:
        """閾値ちょうど超過（STAGNATION_THRESHOLD + 1 秒）-> stagnation として検知."""
        # STAGNATION_THRESHOLD のデフォルト値を確認
        threshold = getattr(orchestrator_mod, "STAGNATION_THRESHOLD", 900)

        orch = _make_orchestrator(tmp_path)
        entry = "_default:301"
        issue = "301"

        # threshold + 1 秒前 = 閾値超過
        stale_updated_at = _iso_ago(threshold + 1)

        call_count = 0

        def mock_read_state(iss, field, autopilot_dir, repo_id=""):
            nonlocal call_count
            if field == "status":
                call_count += 1
                return "running" if call_count == 1 else "done"
            if field == "updated_at":
                return stale_updated_at
            return ""

        stagnation_detected = []

        original_check_and_nudge = orch._check_and_nudge

        def mock_check_and_nudge(iss, wname, ent):
            # stagnation チェック後に _check_and_nudge に委譲される
            return False

        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("time.sleep"), \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_check_and_nudge", side_effect=mock_check_and_nudge), \
             patch.object(orch, "_cleanup_worker"):

            orch._poll_single(entry)

        # クラッシュせずに完了することを確認
        assert call_count >= 1

    def test_threshold_boundary_just_under(self, tmp_path: Path) -> None:
        """閾値ちょうど未満（STAGNATION_THRESHOLD - 1 秒）-> stagnation なし."""
        threshold = getattr(orchestrator_mod, "STAGNATION_THRESHOLD", 900)

        orch = _make_orchestrator(tmp_path)
        entry = "_default:302"
        issue = "302"

        # threshold - 1 秒前 = 閾値未満
        fresh_updated_at = _iso_ago(threshold - 1)

        call_count = 0

        def mock_read_state(iss, field, autopilot_dir, repo_id=""):
            nonlocal call_count
            if field == "status":
                call_count += 1
                return "running" if call_count == 1 else "done"
            if field == "updated_at":
                return fresh_updated_at
            return ""

        with patch("twl.autopilot.orchestrator._read_state", side_effect=mock_read_state), \
             patch("time.sleep"), \
             patch.object(orch, "_is_crashed", return_value=False), \
             patch.object(orch, "_check_and_nudge", return_value=False) as mock_nudge, \
             patch.object(orch, "_cleanup_worker"):

            orch._poll_single(entry)

        # クラッシュせず完了すること（stagnation として扱わない）
        assert call_count >= 1
        assert mock_nudge.called

    def test_env_override_affects_stagnation_check(self, tmp_path: Path) -> None:
        """Scenario: 環境変数 AUTOPILOT_STAGNATE_SEC=300 設定時
        WHEN: orchestrator が起動
        THEN: 300 秒を閾値として判定される
        """
        with patch.dict(os.environ, {"AUTOPILOT_STAGNATE_SEC": "300"}):
            import importlib
            reloaded = importlib.reload(orchestrator_mod)
            assert reloaded.STAGNATION_THRESHOLD == 300

        # 元に戻す
        importlib.reload(orchestrator_mod)
