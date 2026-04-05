"""Session management for autopilot session.json lifecycle.

Replaces: session-create.sh, session-archive.sh, session-add-warning.sh, session-audit.sh

CLI usage:
    python3 -m twl.autopilot.session create --plan-path P --phase-count N
    python3 -m twl.autopilot.session archive
    python3 -m twl.autopilot.session add-warning --issue N --target-issue M --file F --reason R
    python3 -m twl.autopilot.session audit <jsonl-path>
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_VALID_SESSION_ID_RE = re.compile(r"^[a-zA-Z0-9]+$")


def _autopilot_dir() -> Path:
    env = os.environ.get("AUTOPILOT_DIR", "")
    if env:
        return Path(env)
    try:
        import subprocess

        root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return Path(root) / ".autopilot"
    except Exception:
        return Path.cwd() / ".autopilot"


def _now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _atomic_write(file: Path, data: dict[str, Any]) -> None:
    file.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    fd, tmp = tempfile.mkstemp(dir=file.parent, prefix=f".{file.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, file)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


class SessionError(Exception):
    """Raised for session operation errors (exit code 1)."""


class SessionArgError(Exception):
    """Raised for argument errors (exit code 2)."""


class SessionManager:
    """Manage autopilot session.json lifecycle."""

    def __init__(self, autopilot_dir: Path | None = None) -> None:
        self.autopilot_dir = autopilot_dir or _autopilot_dir()
        self.session_file = self.autopilot_dir / "session.json"

    def create(self, plan_path: str, phase_count: int) -> str:
        """Create a new session.json."""
        if self.session_file.is_file():
            raise SessionError(
                "session.json は既に存在します。autopilot-init.sh で排他制御を確認してください"
            )
        self.autopilot_dir.mkdir(parents=True, exist_ok=True)

        session_id = _generate_session_id()
        now = _now_utc()
        data = {
            "session_id": session_id,
            "plan_path": plan_path,
            "current_phase": 1,
            "phase_count": phase_count,
            "started_at": now,
            "cross_issue_warnings": [],
            "phase_insights": [],
            "patterns": {},
            "self_improve_issues": [],
        }
        _atomic_write(self.session_file, data)
        return f"OK: session.json を作成しました (session_id={session_id})"

    def archive(self) -> str:
        """Move session.json and issues/ to archive/<session_id>/."""
        if not self.session_file.is_file():
            raise SessionError("session.json が存在しません")

        data = json.loads(self.session_file.read_text(encoding="utf-8"))
        session_id = data.get("session_id", "")

        if not _VALID_SESSION_ID_RE.match(session_id):
            raise SessionError(
                f"不正な session_id: {session_id}（英数字のみ許可）"
            )

        archive_dir = self.autopilot_dir / "archive" / session_id
        archive_dir.mkdir(parents=True, exist_ok=True)
        (archive_dir / "issues").mkdir(exist_ok=True)

        # Move session.json
        self.session_file.rename(archive_dir / "session.json")

        # Move issue-{N}.json files
        issues_dir = self.autopilot_dir / "issues"
        if issues_dir.is_dir():
            for issue_file in sorted(issues_dir.glob("issue-*.json")):
                if issue_file.is_file():
                    issue_file.rename(archive_dir / "issues" / issue_file.name)

        return f"OK: セッション {session_id} をアーカイブしました → {archive_dir}"

    def add_warning(
        self, issue: int, target_issue: int, file: str, reason: str
    ) -> str:
        """Append a cross-issue warning to session.json."""
        if not self.session_file.is_file():
            raise SessionError("session.json が存在しません")

        data = json.loads(self.session_file.read_text(encoding="utf-8"))
        warning = {
            "issue": issue,
            "target_issue": target_issue,
            "file": file,
            "reason": reason,
        }
        data.setdefault("cross_issue_warnings", []).append(warning)
        _atomic_write(self.session_file, data)
        return f"OK: cross-issue 警告を追加しました (Issue #{issue} → #{target_issue}: {file})"

    def audit(self, jsonl_path: str) -> str:
        """Analyze a Claude session JSONL file and return audit summary as JSONL."""
        path = Path(jsonl_path)
        if not path.exists():
            raise SessionError(f"File not found: {jsonl_path}")
        if not path.is_file():
            raise SessionError(f"Not a file: {jsonl_path}")
        if path.stat().st_size == 0:
            raise SessionError(f"File is empty: {jsonl_path}")

        # Path validation: ~/.claude/projects/ only (skip in test mode)
        if os.environ.get("SESSION_AUDIT_ALLOW_ANY_PATH", "0") != "1":
            real = path.resolve()
            allowed = Path.home() / ".claude" / "projects"
            try:
                real.relative_to(allowed)
            except ValueError:
                raise SessionError(f"Path must be under {allowed}")

        lines: list[dict[str, Any]] = []
        with open(path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    lines.append(json.loads(raw))
                except json.JSONDecodeError:
                    continue

        results: list[str] = []
        results.append(json.dumps(_make_metadata(path, lines), ensure_ascii=False))
        for entry in _extract_tool_calls(lines):
            results.append(json.dumps(entry, ensure_ascii=False))
        for entry in _extract_tool_results(lines):
            results.append(json.dumps(entry, ensure_ascii=False))
        for entry in _extract_ai_text(lines):
            results.append(json.dumps(entry, ensure_ascii=False))
        for entry in _extract_skill_calls(lines):
            results.append(json.dumps(entry, ensure_ascii=False))
        return "\n".join(results)


# ---------------------------------------------------------------------------
# Audit helpers
# ---------------------------------------------------------------------------

_TOOL_INPUT_LIMIT = 200
_RESULT_CONTENT_LIMIT = 150
_AI_TEXT_LIMIT = 200


def _make_metadata(path: Path, lines: list[dict[str, Any]]) -> dict[str, Any]:
    session_id = next(
        (l["sessionId"] for l in lines if "sessionId" in l), ""
    )
    timestamps = [l["timestamp"] for l in lines if "timestamp" in l]
    return {
        "entry_type": "metadata",
        "session_id": session_id,
        "source": path.name,
        "file_size_bytes": path.stat().st_size,
        "line_count": sum(1 for _ in open(path, encoding="utf-8", errors="replace")),
        "time_range": {
            "start": timestamps[0] if timestamps else "",
            "end": timestamps[-1] if timestamps else "",
        },
    }


def _truncate(s: str, limit: int) -> str:
    return s[:limit]


def _extract_tool_calls(lines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    results = []
    for line in lines:
        if line.get("type") != "assistant":
            continue
        msg = line.get("message") or {}
        ts = line.get("timestamp", "")
        for block in msg.get("content", []):
            if block.get("type") != "tool_use":
                continue
            name = block.get("name", "")
            inp = block.get("input", {}) or {}
            input_str = _format_tool_input(name, inp)
            results.append({
                "entry_type": "tool_call",
                "timestamp": ts,
                "tool_name": name,
                "tool_id": block.get("id", ""),
                "input": _truncate(input_str, _TOOL_INPUT_LIMIT),
            })
    return results


def _format_tool_input(name: str, inp: dict[str, Any]) -> str:
    if name == "Bash":
        return inp.get("command", "")
    elif name == "Skill":
        return f"{inp.get('skill', '')} {inp.get('args', '')}".strip()
    elif name in ("Read", "Write", "Edit"):
        return inp.get("file_path", "")
    elif name == "Grep":
        return inp.get("pattern", "")
    elif name == "Glob":
        return inp.get("pattern", "")
    elif name == "Agent":
        return f"{inp.get('subagent_type', '')}: {inp.get('description', '')}"
    else:
        return json.dumps(inp, ensure_ascii=False)


def _extract_tool_results(lines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    results = []
    for line in lines:
        if line.get("type") != "user":
            continue
        msg = line.get("message") or {}
        ts = line.get("timestamp", "")
        for block in msg.get("content", []):
            if block.get("type") != "tool_result":
                continue
            is_error = bool(block.get("is_error", False))
            content_raw = block.get("content", "")
            if isinstance(content_raw, list):
                content_str = "\n".join(
                    b.get("text", "") for b in content_raw if b.get("type") == "text"
                )
            elif isinstance(content_raw, str):
                content_str = content_raw
            else:
                content_str = ""
            results.append({
                "entry_type": "tool_result",
                "timestamp": ts,
                "tool_id": block.get("tool_use_id", ""),
                "status": "ERROR" if is_error else "ok",
                "content": _truncate(content_str, _RESULT_CONTENT_LIMIT),
            })
    return results


def _extract_ai_text(lines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    results = []
    for line in lines:
        if line.get("type") != "assistant":
            continue
        msg = line.get("message") or {}
        ts = line.get("timestamp", "")
        for block in msg.get("content", []):
            if block.get("type") != "text":
                continue
            text = block.get("text", "")
            if not text:
                continue
            results.append({
                "entry_type": "ai_text",
                "timestamp": ts,
                "text": _truncate(text, _AI_TEXT_LIMIT),
            })
    return results


def _extract_skill_calls(lines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    results = []
    for line in lines:
        if line.get("type") != "assistant":
            continue
        msg = line.get("message") or {}
        ts = line.get("timestamp", "")
        for block in msg.get("content", []):
            if block.get("type") != "tool_use" or block.get("name") != "Skill":
                continue
            inp = block.get("input", {}) or {}
            results.append({
                "entry_type": "skill_call",
                "timestamp": ts,
                "skill_name": inp.get("skill", ""),
                "skill_args": inp.get("args", ""),
            })
    return results


def _generate_session_id() -> str:
    return os.urandom(4).hex()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        print(
            "Usage: python3 -m twl.autopilot.session <create|archive|add-warning|audit>",
            file=sys.stderr,
        )
        return 2

    subcmd, rest = args[0], args[1:]
    mgr = SessionManager()

    try:
        if subcmd == "create":
            parsed = _parse_create_args(rest)
            msg = mgr.create(plan_path=parsed["plan_path"], phase_count=parsed["phase_count"])
            print(msg)
            return 0

        elif subcmd == "archive":
            msg = mgr.archive()
            print(msg)
            return 0

        elif subcmd == "add-warning":
            parsed = _parse_add_warning_args(rest)
            msg = mgr.add_warning(
                issue=parsed["issue"],
                target_issue=parsed["target_issue"],
                file=parsed["file"],
                reason=parsed["reason"],
            )
            print(msg)
            return 0

        elif subcmd == "audit":
            if not rest:
                print("ERROR: audit には jsonl-path 引数が必要です", file=sys.stderr)
                return 2
            output = mgr.audit(rest[0])
            print(output)
            return 0

        else:
            print(f"ERROR: 不明なサブコマンド: {subcmd}", file=sys.stderr)
            return 2

    except SessionArgError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    except SessionError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


def _parse_create_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {"plan_path": None, "phase_count": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print("Usage: python3 -m twl.autopilot.session create --plan-path P --phase-count N")
            sys.exit(0)
        elif a == "--plan-path" and i + 1 < len(argv):
            args["plan_path"] = argv[i + 1]; i += 2
        elif a == "--phase-count" and i + 1 < len(argv):
            args["phase_count"] = argv[i + 1]; i += 2
        else:
            print(f"ERROR: 不明なオプション: {a}", file=sys.stderr); sys.exit(1)
    if not args["plan_path"]:
        raise SessionArgError("--plan-path は必須です")
    if args["phase_count"] is None:
        raise SessionArgError("--phase-count は必須です")
    try:
        args["phase_count"] = int(args["phase_count"])
        if args["phase_count"] < 0:
            raise ValueError
    except (ValueError, TypeError):
        raise SessionArgError(f"--phase-count は正の整数を指定してください: {args['phase_count']}")
    return args


def _parse_add_warning_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {"issue": None, "target_issue": None, "file": None, "reason": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--issue" and i + 1 < len(argv):
            args["issue"] = argv[i + 1]; i += 2
        elif a == "--target-issue" and i + 1 < len(argv):
            args["target_issue"] = argv[i + 1]; i += 2
        elif a == "--file" and i + 1 < len(argv):
            args["file"] = argv[i + 1]; i += 2
        elif a == "--reason" and i + 1 < len(argv):
            args["reason"] = argv[i + 1]; i += 2
        else:
            print(f"ERROR: 不明なオプション: {a}", file=sys.stderr); sys.exit(1)
    for k in ("issue", "target_issue", "file", "reason"):
        if not args[k]:
            raise SessionArgError("--issue, --target-issue, --file, --reason は全て必須です")
    try:
        args["issue"] = int(args["issue"])
        args["target_issue"] = int(args["target_issue"])
    except (ValueError, TypeError):
        raise SessionArgError("--issue と --target-issue は整数を指定してください")
    return args


if __name__ == "__main__":
    sys.exit(main())
