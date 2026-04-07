"""twl audit-history - Layer 1 経験的監査.

過去の autopilot session trace ファイル
(``${AUTOPILOT_DIR}/trace/<session>/issue-*.jsonl``) を mining し、
実際に呼ばれた step 群を集計する。``--compare-deps`` モードでは
``deps.yaml`` の宣言された chain-runner commands と突き合わせ、
F4 (No-op 化) や F1/F2 と相補的な dead code 候補を検出する。

CLI usage:
    python3 -m twl.autopilot.audit_history [--days 30] [--compare-deps] [...]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Trace file parsing
# ---------------------------------------------------------------------------


def parse_trace_file(path: Path) -> list[dict[str, Any]]:
    """Parse a JSON Lines trace file. Skip malformed lines silently."""
    events: list[dict[str, Any]] = []
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    events.append(json.loads(raw))
                except json.JSONDecodeError:
                    continue
    except OSError:
        return []
    return events


def file_age_days(path: Path) -> float:
    """Return age of *path* in days based on mtime, or +inf on error."""
    try:
        mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    except OSError:
        return float("inf")
    return (datetime.now(tz=timezone.utc) - mtime).total_seconds() / 86400.0


def parse_session(events: list[dict[str, Any]]) -> dict[str, Any]:
    """Aggregate per-session step statistics from raw events.

    Returns a dict with::

        steps_called: {step: count}        # number of "start" events per step
        steps_failed: {step: count}        # number of non-zero "end" events
        event_count: int
    """
    steps_called: Counter[str] = Counter()
    steps_failed: Counter[str] = Counter()
    for ev in events:
        step = ev.get("step")
        phase = ev.get("phase")
        if not step or not isinstance(step, str):
            continue
        if phase == "start":
            steps_called[step] += 1
        elif phase == "end":
            ec = ev.get("exit_code")
            if isinstance(ec, int) and ec != 0:
                steps_failed[step] += 1
    return {
        "steps_called": dict(steps_called),
        "steps_failed": dict(steps_failed),
        "event_count": len(events),
    }


# ---------------------------------------------------------------------------
# History mining
# ---------------------------------------------------------------------------


def mine_history(autopilot_dir: Path, days: int = 30) -> dict[str, Any]:
    """Mine all trace files under ``<autopilot_dir>/trace/`` younger than *days*."""
    sessions: list[dict[str, Any]] = []
    trace_root = autopilot_dir / "trace"
    if trace_root.is_dir():
        for trace_file in sorted(trace_root.glob("*/issue-*.jsonl")):
            if file_age_days(trace_file) > days:
                continue
            events = parse_trace_file(trace_file)
            if not events:
                continue
            session = parse_session(events)
            session["file"] = str(trace_file)
            session["session_id"] = trace_file.parent.name
            issue_stem = trace_file.stem  # e.g. "issue-123"
            session["issue"] = (
                issue_stem[len("issue-"):] if issue_stem.startswith("issue-") else issue_stem
            )
            sessions.append(session)

    empirical: Counter[str] = Counter()
    failures: Counter[str] = Counter()
    for s in sessions:
        for step, count in s.get("steps_called", {}).items():
            empirical[step] += count
        for step, count in s.get("steps_failed", {}).items():
            failures[step] += count

    return {
        "sessions": sessions,
        "session_count": len(sessions),
        "empirical_steps": dict(empirical),
        "failed_steps": dict(failures),
    }


# ---------------------------------------------------------------------------
# Reconstructing trace from past Claude Code session jsonl
# ---------------------------------------------------------------------------


_CHAIN_RUNNER_PATTERN = re.compile(
    r"""chain-runner\.sh        # script name
        ["']?                    # optional closing quote
        \s+                      # whitespace
        (?:--trace(?:=\S+|\s+\S+)\s+)?   # optional --trace flag
        ([a-z][a-z0-9-]*)        # step name
    """,
    re.VERBOSE,
)


def reconstruct_trace_from_session_jsonl(jsonl_path: Path) -> list[dict[str, Any]]:
    """Reconstruct trace events from a Claude Code session jsonl.

    Walks ``assistant`` messages, picks up Bash ``tool_use`` calls invoking
    ``chain-runner.sh <step>`` and produces synthetic ``start`` events.
    Used for retroactive analysis of sessions recorded before the trace
    mechanism was introduced.
    """
    events: list[dict[str, Any]] = []
    try:
        with open(jsonl_path, encoding="utf-8") as fh:
            for raw in fh:
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if msg.get("type") != "assistant":
                    continue
                content = msg.get("message", {}).get("content", [])
                if not isinstance(content, list):
                    continue
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    if item.get("type") != "tool_use" or item.get("name") != "Bash":
                        continue
                    cmd = item.get("input", {}).get("command", "") or ""
                    m = _CHAIN_RUNNER_PATTERN.search(cmd)
                    if m:
                        events.append(
                            {
                                "step": m.group(1),
                                "phase": "start",
                                "ts": msg.get("timestamp"),
                                "source": "reconstructed",
                            }
                        )
    except OSError:
        return []
    return events


def reconstruct_from_directory(directory: Path, days: int | None = None) -> dict[str, Any]:
    """Walk a directory of Claude Code session jsonl files and aggregate."""
    sessions: list[dict[str, Any]] = []
    if directory.is_dir():
        for jsonl_path in sorted(directory.glob("*.jsonl")):
            if days is not None and file_age_days(jsonl_path) > days:
                continue
            events = reconstruct_trace_from_session_jsonl(jsonl_path)
            if not events:
                continue
            session = parse_session(events)
            session["file"] = str(jsonl_path)
            session["source"] = "reconstructed"
            sessions.append(session)

    empirical: Counter[str] = Counter()
    for s in sessions:
        for step, count in s.get("steps_called", {}).items():
            empirical[step] += count
    return {
        "sessions": sessions,
        "session_count": len(sessions),
        "empirical_steps": dict(empirical),
        "failed_steps": {},
    }


# ---------------------------------------------------------------------------
# deps.yaml comparison
# ---------------------------------------------------------------------------


def load_declared_steps(plugin_root: Path) -> set[str]:
    """Return the set of declared chain-runner commands from deps.yaml."""
    deps_path = plugin_root / "deps.yaml"
    if not deps_path.is_file():
        return set()
    try:
        import yaml  # type: ignore
    except ImportError:
        return set()
    try:
        deps = yaml.safe_load(deps_path.read_text(encoding="utf-8")) or {}
    except Exception:
        return set()
    scripts = deps.get("scripts") or {}
    cr = scripts.get("chain-runner") or {}
    cmds = cr.get("commands") or []
    return {c for c in cmds if isinstance(c, str)}


def compare_with_deps(
    empirical_steps: dict[str, int], declared: set[str]
) -> dict[str, Any]:
    """Compute set difference between empirical and declared call graphs."""
    empirical_set = set(empirical_steps)
    return {
        "declared_total": len(declared),
        "empirical_total": len(empirical_set),
        "declared_but_never_called": sorted(declared - empirical_set),
        "called_but_not_declared": sorted(empirical_set - declared),
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _format_text_report(
    result: dict[str, Any], compare: dict[str, Any] | None
) -> list[str]:
    lines: list[str] = []
    lines.append("=== Audit History (Layer 1 Empirical) ===")
    lines.append(f"Sessions analyzed: {result['session_count']}")
    lines.append("")
    lines.append(f"Empirical steps ({len(result['empirical_steps'])}):")
    for step, count in sorted(result["empirical_steps"].items(), key=lambda x: (-x[1], x[0])):
        lines.append(f"  {step}: {count}")
    if result.get("failed_steps"):
        lines.append("")
        lines.append("Failed steps (non-zero exit_code):")
        for step, count in sorted(result["failed_steps"].items(), key=lambda x: (-x[1], x[0])):
            lines.append(f"  {step}: {count}")
    if compare is not None:
        lines.append("")
        lines.append("=== Empirical vs Declared ===")
        lines.append(
            f"Declared but never called (potential dead code) "
            f"[{len(compare['declared_but_never_called'])}]:"
        )
        if compare["declared_but_never_called"]:
            for s in compare["declared_but_never_called"]:
                lines.append(f"  - {s}")
        else:
            lines.append("  (none)")
        lines.append("")
        lines.append(
            f"Called but not declared (orphan executions) "
            f"[{len(compare['called_but_not_declared'])}]:"
        )
        if compare["called_but_not_declared"]:
            for s in compare["called_but_not_declared"]:
                lines.append(f"  - {s}")
        else:
            lines.append("  (none)")
    return lines


def cli_audit_history(args: argparse.Namespace) -> int:
    if args.reconstruct_from:
        directory = Path(args.reconstruct_from).expanduser()
        result = reconstruct_from_directory(directory, days=args.days)
    else:
        autopilot_dir = Path(args.autopilot_dir).expanduser()
        result = mine_history(autopilot_dir, days=args.days)

    compare: dict[str, Any] | None = None
    if args.compare_deps:
        plugin_root = (
            Path(args.plugin_root).expanduser() if args.plugin_root else Path.cwd()
        )
        declared = load_declared_steps(plugin_root)
        compare = compare_with_deps(result["empirical_steps"], declared)
        result["compare"] = compare

    if args.format == "json":
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0

    for line in _format_text_report(result, compare):
        print(line)
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="twl audit-history",
        description="Layer 1 empirical audit (mine trace files; compare with deps.yaml)",
    )
    p.add_argument(
        "--autopilot-dir",
        default=".autopilot",
        help="Autopilot directory containing trace/ subdir (default: .autopilot)",
    )
    p.add_argument(
        "--days",
        type=int,
        default=30,
        help="Only consider trace files modified within N days (default: 30)",
    )
    p.add_argument(
        "--compare-deps",
        action="store_true",
        help="Compare empirical call graph with deps.yaml declared chain-runner commands",
    )
    p.add_argument(
        "--plugin-root",
        default=None,
        help="Plugin root for deps.yaml (default: cwd)",
    )
    p.add_argument(
        "--reconstruct-from",
        default=None,
        help="Reconstruct trace from a directory of Claude Code session jsonl files",
    )
    p.add_argument("--format", choices=["text", "json"], default="text")
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return cli_audit_history(args)


if __name__ == "__main__":
    sys.exit(main())
