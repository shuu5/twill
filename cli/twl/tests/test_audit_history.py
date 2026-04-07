"""Tests for twl.autopilot.audit_history (Phase 3 / Layer 1 経験的監査)."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import pytest

from twl.autopilot import audit_history as ah


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    (d / "trace" / "session-001").mkdir(parents=True)
    return d


def _write_trace(
    autopilot_dir: Path, session: str, issue: str, events: list[dict]
) -> Path:
    sdir = autopilot_dir / "trace" / session
    sdir.mkdir(parents=True, exist_ok=True)
    p = sdir / f"issue-{issue}.jsonl"
    with open(p, "w", encoding="utf-8") as fh:
        for ev in events:
            fh.write(json.dumps(ev) + "\n")
    return p


def _start_end(step: str, exit_code: int = 0) -> list[dict]:
    return [
        {"step": step, "phase": "start", "ts": "2026-04-07T00:00:00Z", "pid": 1},
        {
            "step": step,
            "phase": "end",
            "ts": "2026-04-07T00:00:01Z",
            "pid": 1,
            "exit_code": exit_code,
        },
    ]


# ---------------------------------------------------------------------------
# parse_trace_file / parse_session
# ---------------------------------------------------------------------------


def test_parse_trace_file_skips_malformed(tmp_path: Path) -> None:
    p = tmp_path / "t.jsonl"
    p.write_text(
        '{"step":"init","phase":"start"}\n'
        "not-json\n"
        '\n'
        '{"step":"check","phase":"end","exit_code":0}\n',
        encoding="utf-8",
    )
    events = ah.parse_trace_file(p)
    assert len(events) == 2
    assert events[0]["step"] == "init"
    assert events[1]["step"] == "check"


def test_parse_trace_file_missing_returns_empty(tmp_path: Path) -> None:
    assert ah.parse_trace_file(tmp_path / "missing.jsonl") == []


def test_parse_session_counts_starts_and_failures() -> None:
    events = (
        _start_end("init")
        + _start_end("ts-preflight", exit_code=1)
        + _start_end("ts-preflight")
    )
    s = ah.parse_session(events)
    assert s["steps_called"] == {"init": 1, "ts-preflight": 2}
    assert s["steps_failed"] == {"ts-preflight": 1}
    assert s["event_count"] == 6


# ---------------------------------------------------------------------------
# mine_history
# ---------------------------------------------------------------------------


def test_mine_history_zero_sessions(tmp_path: Path) -> None:
    result = ah.mine_history(tmp_path / ".autopilot")
    assert result["session_count"] == 0
    assert result["sessions"] == []
    assert result["empirical_steps"] == {}


def test_mine_history_aggregates_multiple_sessions(autopilot_dir: Path) -> None:
    _write_trace(autopilot_dir, "s1", "10", _start_end("init") + _start_end("check"))
    _write_trace(
        autopilot_dir,
        "s2",
        "11",
        _start_end("init") + _start_end("ts-preflight", exit_code=1),
    )
    result = ah.mine_history(autopilot_dir)
    assert result["session_count"] == 2
    assert result["empirical_steps"] == {"init": 2, "check": 1, "ts-preflight": 1}
    assert result["failed_steps"] == {"ts-preflight": 1}
    issues = sorted(s["issue"] for s in result["sessions"])
    assert issues == ["10", "11"]


def test_mine_history_skips_old_files(autopilot_dir: Path) -> None:
    p = _write_trace(autopilot_dir, "old", "1", _start_end("init"))
    # backdate file mtime by 60 days
    old_ts = time.time() - 60 * 86400
    os.utime(p, (old_ts, old_ts))
    result = ah.mine_history(autopilot_dir, days=30)
    assert result["session_count"] == 0


def test_mine_history_includes_recent_files(autopilot_dir: Path) -> None:
    _write_trace(autopilot_dir, "fresh", "1", _start_end("init"))
    result = ah.mine_history(autopilot_dir, days=30)
    assert result["session_count"] == 1


# ---------------------------------------------------------------------------
# compare_with_deps
# ---------------------------------------------------------------------------


def test_compare_with_deps_detects_never_called() -> None:
    empirical = {"init": 5, "check": 2}
    declared = {"init", "check", "board-archive", "ac-verify"}
    cmp = ah.compare_with_deps(empirical, declared)
    assert cmp["declared_but_never_called"] == ["ac-verify", "board-archive"]
    assert cmp["called_but_not_declared"] == []
    assert cmp["declared_total"] == 4
    assert cmp["empirical_total"] == 2


def test_compare_with_deps_detects_orphan_executions() -> None:
    empirical = {"init": 1, "rogue-step": 1}
    declared = {"init", "check"}
    cmp = ah.compare_with_deps(empirical, declared)
    assert cmp["declared_but_never_called"] == ["check"]
    assert cmp["called_but_not_declared"] == ["rogue-step"]


def test_load_declared_steps(tmp_path: Path) -> None:
    pytest.importorskip("yaml")
    (tmp_path / "deps.yaml").write_text(
        "scripts:\n"
        "  chain-runner:\n"
        "    type: script\n"
        "    commands:\n"
        "      - init\n"
        "      - check\n"
        "      - board-archive\n",
        encoding="utf-8",
    )
    declared = ah.load_declared_steps(tmp_path)
    assert declared == {"init", "check", "board-archive"}


def test_load_declared_steps_missing_yaml(tmp_path: Path) -> None:
    assert ah.load_declared_steps(tmp_path) == set()


# ---------------------------------------------------------------------------
# reconstruct_trace_from_session_jsonl
# ---------------------------------------------------------------------------


def test_reconstruct_trace_extracts_chain_runner_calls(tmp_path: Path) -> None:
    p = tmp_path / "session.jsonl"
    msgs = [
        {
            "type": "assistant",
            "timestamp": "2026-04-07T01:00:00Z",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Bash",
                        "input": {
                            "command": 'bash "$CR/chain-runner.sh" init 42'
                        },
                    }
                ]
            },
        },
        {
            "type": "user",
            "message": {"content": []},
        },
        {
            "type": "assistant",
            "timestamp": "2026-04-07T01:01:00Z",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Bash",
                        "input": {
                            "command": "bash chain-runner.sh ts-preflight"
                        },
                    },
                    {
                        "type": "tool_use",
                        "name": "Bash",
                        "input": {
                            "command": "bash chain-runner.sh --trace /tmp/x.jsonl pr-test"
                        },
                    },
                    {
                        "type": "tool_use",
                        "name": "Read",
                        "input": {"file_path": "/etc/hosts"},
                    },
                ]
            },
        },
    ]
    with open(p, "w", encoding="utf-8") as fh:
        for m in msgs:
            fh.write(json.dumps(m) + "\n")

    events = ah.reconstruct_trace_from_session_jsonl(p)
    steps = [e["step"] for e in events]
    assert steps == ["init", "ts-preflight", "pr-test"]
    assert all(e["phase"] == "start" for e in events)
    assert all(e["source"] == "reconstructed" for e in events)


def test_reconstruct_from_directory_aggregates(tmp_path: Path) -> None:
    d = tmp_path / "sessions"
    d.mkdir()
    (d / "a.jsonl").write_text(
        json.dumps(
            {
                "type": "assistant",
                "message": {
                    "content": [
                        {
                            "type": "tool_use",
                            "name": "Bash",
                            "input": {"command": "bash chain-runner.sh init 1"},
                        }
                    ]
                },
            }
        )
        + "\n",
        encoding="utf-8",
    )
    result = ah.reconstruct_from_directory(d)
    assert result["session_count"] == 1
    assert result["empirical_steps"] == {"init": 1}


# ---------------------------------------------------------------------------
# CLI integration
# ---------------------------------------------------------------------------


def test_cli_text_output(autopilot_dir: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _write_trace(autopilot_dir, "s1", "10", _start_end("init") + _start_end("check"))
    rc = ah.main(["--autopilot-dir", str(autopilot_dir), "--days", "30"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "Sessions analyzed: 1" in out
    assert "init: 1" in out
    assert "check: 1" in out


def test_cli_json_output(autopilot_dir: Path, capsys: pytest.CaptureFixture[str]) -> None:
    _write_trace(autopilot_dir, "s1", "10", _start_end("init"))
    rc = ah.main(
        ["--autopilot-dir", str(autopilot_dir), "--format", "json"]
    )
    assert rc == 0
    out = capsys.readouterr().out
    payload = json.loads(out)
    assert payload["session_count"] == 1
    assert payload["empirical_steps"] == {"init": 1}


def test_cli_compare_deps(
    autopilot_dir: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    pytest.importorskip("yaml")
    _write_trace(autopilot_dir, "s1", "10", _start_end("init"))
    plugin_root = tmp_path / "plugin"
    plugin_root.mkdir()
    (plugin_root / "deps.yaml").write_text(
        "scripts:\n"
        "  chain-runner:\n"
        "    commands:\n"
        "      - init\n"
        "      - dead-step\n",
        encoding="utf-8",
    )
    rc = ah.main(
        [
            "--autopilot-dir",
            str(autopilot_dir),
            "--compare-deps",
            "--plugin-root",
            str(plugin_root),
            "--format",
            "json",
        ]
    )
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["compare"]["declared_but_never_called"] == ["dead-step"]
    assert payload["compare"]["called_but_not_declared"] == []


def test_cli_compare_deps_text_format(
    autopilot_dir: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    pytest.importorskip("yaml")
    _write_trace(autopilot_dir, "s1", "10", _start_end("init"))
    plugin_root = tmp_path / "plugin"
    plugin_root.mkdir()
    (plugin_root / "deps.yaml").write_text(
        "scripts:\n"
        "  chain-runner:\n"
        "    commands:\n"
        "      - init\n"
        "      - dead-step\n",
        encoding="utf-8",
    )
    rc = ah.main(
        [
            "--autopilot-dir",
            str(autopilot_dir),
            "--compare-deps",
            "--plugin-root",
            str(plugin_root),
        ]
    )
    assert rc == 0
    out = capsys.readouterr().out
    assert "Empirical vs Declared" in out
    assert "dead-step" in out


def test_cli_reconstruct_from(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    d = tmp_path / "sessions"
    d.mkdir()
    (d / "s.jsonl").write_text(
        json.dumps(
            {
                "type": "assistant",
                "message": {
                    "content": [
                        {
                            "type": "tool_use",
                            "name": "Bash",
                            "input": {
                                "command": "bash chain-runner.sh ac-extract"
                            },
                        }
                    ]
                },
            }
        )
        + "\n",
        encoding="utf-8",
    )
    rc = ah.main(["--reconstruct-from", str(d), "--format", "json"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["session_count"] == 1
    assert payload["empirical_steps"] == {"ac-extract": 1}
