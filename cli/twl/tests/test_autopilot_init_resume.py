"""TDD RED phase tests for Issue #1208: orchestrator.pid based resume control.

AC-1: session.json 存在 + < 24h + 未完了 でも orchestrator.pid 不在なら resume 許可
AC-2: session.json 存在 + orchestrator.pid 生 PID (kill -0 成功) → InitError で block
AC-5: stale orchestrator.pid (dead PID を指す) の場合 resume 許可

現行実装 (_check_existing_session) には orchestrator.pid チェックが存在しないため、
AC-1 と AC-5 は InitError が raise される（誤った block）。
AC-2 は InitError が raise されない（誤った allow）。
全テストは RED (fail) 状態で始まる。
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import pytest

from twl.autopilot.init import AutopilotInitializer, InitError


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    (d / "archive").mkdir()
    return d


def _write_session_json(autopilot_dir: Path, hours_ago: float = 1.0) -> None:
    """Write a session.json that is hours_ago old and has no issues (= not completed)."""
    from datetime import timedelta

    started = datetime.now(timezone.utc) - timedelta(hours=hours_ago)
    data = {
        "session_id": "test-session-001",
        "started_at": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    (autopilot_dir / "session.json").write_text(
        json.dumps(data), encoding="utf-8"
    )
    # issues/ に running issue を1件置いて「未完了」状態を作る
    issue = {
        "issue": 9999,
        "status": "running",
        "branch": "feat/9999-test",
        "started_at": data["started_at"],
    }
    (autopilot_dir / "issues" / "issue-9999.json").write_text(
        json.dumps(issue), encoding="utf-8"
    )


def _write_orchestrator_pid(autopilot_dir: Path, pid: int) -> None:
    (autopilot_dir / "orchestrator.pid").write_text(str(pid), encoding="utf-8")


def _get_dead_pid() -> int:
    """Return a PID that is guaranteed to be dead."""
    # Start a short-lived process, wait for it, then return its PID.
    proc = subprocess.Popen(["true"])
    proc.wait()
    return proc.pid


# ---------------------------------------------------------------------------
# AC-1: orchestrator.pid 不在 → resume 許可 (InitError を raise しない)
# ---------------------------------------------------------------------------


def test_ac1_resume_when_orchestrator_dead(autopilot_dir: Path) -> None:
    """AC-1: session.json 存在 + < 24h + 未完了 でも orchestrator.pid 不在なら resume 許可。

    RED: 現行実装は orchestrator.pid をチェックしないため、
         session.json が < 24h + 未完了の場合は常に InitError を raise してしまう。
         このテストは InitError が raise されないことを期待するが、現行では raise される → FAIL。
    """
    _write_session_json(autopilot_dir, hours_ago=1.0)
    # orchestrator.pid を作らない（不在状態）
    assert not (autopilot_dir / "orchestrator.pid").exists()

    initializer = AutopilotInitializer(autopilot_dir=autopilot_dir)

    # 期待: orchestrator.pid がないので resume 許可 → InitError を raise しない
    # 現行実装: orchestrator.pid チェックなし → "running" 判定 → InitError を raise → FAIL
    try:
        initializer.run(check_only=True)
    except InitError as e:
        pytest.fail(
            f"AC-1 FAIL: orchestrator.pid 不在にもかかわらず InitError が raise された: {e}"
        )


# ---------------------------------------------------------------------------
# AC-2: orchestrator.pid あり + alive PID → InitError で block
# ---------------------------------------------------------------------------


def test_ac2_block_when_orchestrator_alive(autopilot_dir: Path) -> None:
    """AC-2: orchestrator.pid が存在し PID が alive (kill -0 成功) → InitError で block。

    RED: 現行実装は orchestrator.pid をチェックしないため、
         alive PID の orchestrator.pid があっても block できない。
         このテストは InitError が raise されることを期待するが、
         現行では session.json 未完了チェックで raise されるか、
         またはそもそも orchestrator.pid を参照しないため期待する理由での block ができない。

    Note: 現行実装だと session.json が < 24h + 未完了なら
          orchestrator.pid に関係なく InitError が raise される。
          しかし AC-2 の意図は「alive PID のチェックによる block」であり、
          このテストは alive PID チェックを検証するため、check_only=True で呼び出す。
    """
    _write_session_json(autopilot_dir, hours_ago=1.0)
    # 現在のプロセス自身の PID を alive PID として書き込む
    alive_pid = os.getpid()
    _write_orchestrator_pid(autopilot_dir, alive_pid)

    initializer = AutopilotInitializer(autopilot_dir=autopilot_dir)

    # 期待: orchestrator.pid の PID が alive → InitError で block
    # 現行実装: orchestrator.pid を参照しない → AC-2 の意図での block はできない
    with pytest.raises(InitError, match="orchestrator|実行中|alive"):
        # 現行実装はこの match に失敗するため FAIL
        initializer.run(check_only=True)


# ---------------------------------------------------------------------------
# AC-5: orchestrator.pid あり + stale PID (dead) → resume 許可
# ---------------------------------------------------------------------------


def test_ac5_resume_when_orchestrator_pid_stale(autopilot_dir: Path) -> None:
    """AC-5: orchestrator.pid があるが PID が dead (kill -0 失敗) → resume 許可。

    RED: 現行実装は orchestrator.pid をチェックしないため、
         stale pid ファイルがあっても session.json が < 24h + 未完了なら
         常に InitError を raise してしまう → FAIL。
    """
    _write_session_json(autopilot_dir, hours_ago=1.0)
    dead_pid = _get_dead_pid()
    _write_orchestrator_pid(autopilot_dir, dead_pid)

    # dead PID は kill -0 で失敗することを前提確認（実装のデバッグ補助）
    try:
        os.kill(dead_pid, 0)
        # もし生きていたらテストの前提が崩れるためスキップ
        pytest.skip(f"PID {dead_pid} が予期せず alive のためスキップ")
    except ProcessLookupError:
        pass  # 期待通り dead
    except PermissionError:
        # 別ユーザーのプロセスが同 PID を使っている場合は alive とみなす
        pytest.skip(f"PID {dead_pid} が別ユーザーに割り当て済みのためスキップ")

    initializer = AutopilotInitializer(autopilot_dir=autopilot_dir)

    # 期待: stale pid → resume 許可 → InitError を raise しない
    # 現行実装: orchestrator.pid チェックなし → "running" 判定 → InitError raise → FAIL
    try:
        initializer.run(check_only=True)
    except InitError as e:
        pytest.fail(
            f"AC-5 FAIL: stale orchestrator.pid にもかかわらず InitError が raise された: {e}"
        )
