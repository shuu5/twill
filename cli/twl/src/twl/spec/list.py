"""twl spec list - List all changes."""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from .paths import OpenspecNotFound, find_openspec_root, get_changes_dir

_TASK_RE = re.compile(r"^- \[[ x]\]")
_TASK_DONE_RE = re.compile(r"^- \[x\]")


def _parse_tasks(tasks_file: Path) -> tuple[int, int]:
    """Return (total, complete) task counts."""
    if not tasks_file.exists():
        return 0, 0
    text = tasks_file.read_text(encoding="utf-8")
    total = sum(1 for line in text.splitlines() if _TASK_RE.match(line))
    complete = sum(1 for line in text.splitlines() if _TASK_DONE_RE.match(line))
    return total, complete


def _get_status(total: int, complete: int) -> str:
    if total > 0 and complete == total:
        return "complete"
    if complete > 0:
        return "in-progress"
    return "pending"


def _rel_time(mtime: float) -> str:
    ago = int(datetime.now(timezone.utc).timestamp() - mtime)
    if ago < 60:
        return "just now"
    if ago < 3600:
        return f"{ago // 60}m ago"
    if ago < 86400:
        return f"{ago // 3600}h ago"
    return f"{ago // 86400}d ago"


def cmd_list(json_mode: bool = False, sort_order: str = "recent") -> int:
    try:
        root = find_openspec_root()
    except OpenspecNotFound as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    changes_dir = get_changes_dir(root)
    if not changes_dir.is_dir():
        if json_mode:
            print('{"changes": []}')
        else:
            print("No changes found.")
        return 0

    entries = []
    for d in sorted(changes_dir.iterdir()):
        if not d.is_dir() or d.name == "archive":
            continue
        total, complete = _parse_tasks(d / "tasks.md")
        mtime = d.stat().st_mtime
        entries.append({
            "name": d.name,
            "total": total,
            "complete": complete,
            "status": _get_status(total, complete),
            "mtime": mtime,
        })

    if not entries:
        if json_mode:
            print('{"changes": []}')
        else:
            print("No changes found.")
        return 0

    if sort_order == "name":
        entries.sort(key=lambda e: e["name"])
    else:
        entries.sort(key=lambda e: e["mtime"], reverse=True)

    if json_mode:
        changes = []
        for e in entries:
            iso = datetime.fromtimestamp(e["mtime"], tz=timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%S.000Z"
            )
            changes.append({
                "name": e["name"],
                "completedTasks": e["complete"],
                "totalTasks": e["total"],
                "lastModified": iso,
                "status": e["status"],
            })
        print(json.dumps({"changes": changes}, indent=2))
    else:
        print("Changes:")
        for e in entries:
            if e["status"] == "complete":
                display = "✓ Complete"
            else:
                display = f"{e['complete']}/{e['total']} tasks"
            rel = _rel_time(e["mtime"])
            print(f"  {e['name']:<45} {display:<18} {rel}")

    return 0
