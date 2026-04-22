"""State management for autopilot issue/session JSON files.

Replaces: state-read.sh, state-write.sh

CLI usage:
    python3 -m twl.autopilot.state read  --type <issue|session> [--issue N] [--repo R] [--field F]
    python3 -m twl.autopilot.state write --type <issue|session> [--issue N] [--repo R]
                                          --role <pilot|worker> [--set k=v]... [--init]
"""

from __future__ import annotations

import copy
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_VALID_SET_KEY_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)*$")
_VALID_FIELD_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_.]*$")
_VALID_REPO_RE = re.compile(r"^[a-zA-Z0-9_-]+$")

# Allowed state transitions: {current: {next, ...}}
_TRANSITIONS: dict[str, set[str]] = {
    "running": {"merge-ready", "failed"},
    "merge-ready": {"done", "failed", "conflict"},
    "failed": {"running", "done"},
    "conflict": {"merge-ready", "failed"},
}

_PILOT_ISSUE_ALLOWED_KEYS = {"status", "merged_at", "failure", "manual_override", "pr", "workflow_injected", "injected_at", "input_waiting_detected", "input_waiting_at", "escalation_requested"}


def _autopilot_dir() -> Path:
    """Resolve AUTOPILOT_DIR (env var takes priority).

    Fallback uses ``git worktree list --porcelain`` to find the main
    worktree (the entry on ``branch refs/heads/main``) and appends
    ``.autopilot``.  In bare-repo setups the ``.autopilot`` directory
    typically lives as a sibling of the main worktree (e.g.
    ``twill/.autopilot/`` next to ``twill/main/``), so we check the
    parent of the main worktree first before falling back to the
    worktree-local path.
    """
    env = os.environ.get("AUTOPILOT_DIR", "")
    if env:
        return Path(env)
    # Fallback: git worktree list → main branch worktree → .autopilot
    try:
        import subprocess

        output = subprocess.check_output(
            ["git", "worktree", "list", "--porcelain"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        # Parse worktree blocks separated by blank lines.
        # In bare-repo setups the first entry is the bare root
        # (HEAD 000...0, or path contains .bare).  We look for
        # the entry with branch refs/heads/main first, then
        # fall back to the first entry with a real HEAD.
        blocks = output.split("\n\n")
        first_real_wt = None
        for block in blocks:
            lines = block.strip().splitlines()
            wt_path = None
            head_val = None
            is_bare = False
            is_main_branch = False
            for line in lines:
                if line.startswith("worktree "):
                    wt_path = line[len("worktree "):]
                elif line.startswith("HEAD "):
                    head_val = line[len("HEAD "):]
                elif line == "bare":
                    is_bare = True
                elif line == "branch refs/heads/main":
                    is_main_branch = True
            # Skip bare entries and null-HEAD entries (bare root)
            null_head = head_val and set(head_val) <= {"0"}
            if not wt_path or is_bare or null_head:
                continue
            if first_real_wt is None:
                first_real_wt = wt_path
            if is_main_branch:
                # Prefer bare sibling: <main_wt>/../.autopilot
                bare_sibling = Path(wt_path).parent / ".autopilot"
                if bare_sibling.exists():
                    return bare_sibling
                return Path(wt_path) / ".autopilot"
        # No main branch found — use first real worktree
        if first_real_wt:
            bare_sibling = Path(first_real_wt).parent / ".autopilot"
            if bare_sibling.exists():
                return bare_sibling
            return Path(first_real_wt) / ".autopilot"
    except Exception:
        pass
    return Path.cwd() / ".autopilot"


def _resolve_file(autopilot_dir: Path, type_: str, issue: str | None, repo: str | None) -> Path:
    if type_ == "issue":
        if repo and (autopilot_dir / "repos" / repo).is_dir():
            return autopilot_dir / "repos" / repo / "issues" / f"issue-{issue}.json"
        return autopilot_dir / "issues" / f"issue-{issue}.json"
    return autopilot_dir / "session.json"


def _now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _get_nested(data: dict[str, Any], field: str) -> Any:
    """Traverse dot-separated field path."""
    parts = field.split(".")
    cur: Any = data
    for part in parts:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur


class StateError(Exception):
    """Raised for validation/transition errors (exit code 1)."""


class StateArgError(Exception):
    """Raised for argument errors (exit code 2)."""


class StateManager:
    """Read/write autopilot state files with transition validation."""

    def __init__(self, autopilot_dir: Path | None = None) -> None:
        self.autopilot_dir = autopilot_dir or _autopilot_dir()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def read(
        self,
        type_: str,
        issue: str | None = None,
        repo: str | None = None,
        field: str | None = None,
    ) -> str:
        """Return field value (or full JSON). Empty string if file absent."""
        self._validate_type(type_)
        if type_ == "issue":
            self._require_issue(issue)
            self._validate_issue_num(issue)  # type: ignore[arg-type]
        if repo:
            self._validate_repo(repo)
        if field:
            self._validate_field(field)

        file = _resolve_file(self.autopilot_dir, type_, issue, repo)
        if not file.is_file():
            return ""

        data = json.loads(file.read_text(encoding="utf-8"))

        if field is None:
            return json.dumps(data, ensure_ascii=False, indent=2)

        value = _get_nested(data, field)
        if value is None:
            return ""
        if isinstance(value, bool):
            return str(value).lower()
        return str(value)

    def write(
        self,
        type_: str,
        role: str,
        issue: str | None = None,
        repo: str | None = None,
        sets: list[str] | None = None,
        init: bool = False,
        cwd: str | None = None,
        force_done: bool = False,
        override_reason: str | None = None,
    ) -> str:
        """Write fields to state file. Returns OK message."""
        self._validate_type(type_)
        self._validate_role(role)
        if type_ == "issue":
            self._require_issue(issue)
            self._validate_issue_num(issue)  # type: ignore[arg-type]
        if repo:
            self._validate_repo(repo)
        self._check_rbac(role, type_, sets or [])
        if role == "pilot" and type_ == "issue":
            self._check_pilot_identity(sets or [], cwd)

        file = _resolve_file(self.autopilot_dir, type_, issue, repo)

        if init:
            if type_ == "issue" and role != "worker":
                raise StateArgError("issue-{N}.json の --init は worker ロールのみ許可されています")
            return self._init_issue(file, issue)  # type: ignore[arg-type]

        if not file.is_file():
            bare_sibling_dir = self.autopilot_dir.parent.parent / ".autopilot"
            bare_sibling = bare_sibling_dir / file.relative_to(self.autopilot_dir)
            hint = (
                f"\n  試したパス: {file}"
                f"\n  bare sibling 候補: {bare_sibling}"
                "\n  解決策: export AUTOPILOT_DIR=<.autopilot への絶対パス>"
            )
            raise StateError(f"ファイルが存在しません: {file}{hint}")
        if not sets:
            raise StateArgError("--set が指定されていません")

        data = json.loads(file.read_text(encoding="utf-8"))
        old_data = copy.deepcopy(data)

        for kv in sets:
            key, _, raw_value = kv.partition("=")
            if not _VALID_SET_KEY_RE.match(key):
                raise StateArgError(f"不正なフィールド名: {key}（英数字、アンダースコア、ドット区切りパスのみ許可）")

            if key == "status" and type_ == "issue":
                data = self._transition(data, raw_value, force_done=force_done, override_reason=override_reason)
            data = self._set_field(data, key, raw_value)

        if type_ == "issue":
            data["updated_at"] = _now_utc()

        # audit state-log 追記
        try:
            from twl.autopilot.audit import is_audit_active, resolve_audit_dir
            if is_audit_active():
                audit_dir = resolve_audit_dir()
                if audit_dir is not None:
                    import datetime as _dt
                    ts = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                    state_log = audit_dir / "state-log.jsonl"
                    state_log.parent.mkdir(parents=True, exist_ok=True)
                    for kv in (sets or []):
                        key, _, raw_value = kv.partition("=")
                        old_raw = _get_nested(old_data, key)
                        old_val = str(old_raw) if old_raw is not None else ""
                        new_raw = _get_nested(data, key)
                        new_val = str(new_raw) if new_raw is not None else raw_value
                        if old_val != new_val:
                            record = json.dumps({
                                "ts": ts,
                                "issue": int(issue) if issue and str(issue).isdigit() else issue,
                                "field": key,
                                "old": old_val,
                                "new": new_val,
                                "role": role,
                            }, ensure_ascii=False)
                            with open(state_log, "a", encoding="utf-8") as f:
                                f.write(record + "\n")
        except Exception:
            pass

        self._atomic_write(file, data)
        return f"OK: {file} を更新しました"

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _init_issue(self, file: Path, issue: str) -> str:
        if file.is_file():
            raise StateError(f"issue-{issue}.json は既に存在します")
        file.parent.mkdir(parents=True, exist_ok=True)
        now = _now_utc()
        data = {
            "issue": int(issue),
            "status": "running",
            "branch": "",
            "pr": None,
            "window": "",
            "started_at": now,
            "updated_at": now,
            "last_heartbeat_at": now,  # #890: chain-runner が record_current_step 時に更新する heartbeat 専用 field
            "current_step": "",
            "retry_count": 0,
            "ac_verify_call_count": 0,  # #891: step_ac_verify 呼出回数 (max retry safety net)
            "fix_instructions": None,
            "merged_at": None,
            "files_changed": [],
            "failure": None,
            "implementation_pr": None,
            "deltaspec_mode": None,
            "input_waiting_detected": None,
            "input_waiting_at": None,
        }
        self._atomic_write(file, data)
        return f"OK: issue-{issue}.json を作成しました (status=running)"

    def _transition(
        self,
        data: dict[str, Any],
        new_status: str,
        *,
        force_done: bool = False,
        override_reason: str | None = None,
    ) -> dict[str, Any]:
        current = data.get("status", "")
        if current == "done":
            raise StateError("done は終端状態です。status を変更できません")
        allowed = _TRANSITIONS.get(current, set())
        if new_status not in allowed:
            raise StateError(f"不正な状態遷移: {current} → {new_status}")
        if current == "failed" and new_status == "done":
            if not force_done:
                raise StateError(
                    "failed → done への遷移には --force-done フラグが必須です"
                )
            if not override_reason:
                raise StateArgError(
                    "--force-done 使用時は --override-reason が必須です"
                )
            data = dict(data)
            data["manual_override"] = True
            data["override_reason"] = override_reason
        if current == "failed" and new_status == "running":
            retry = data.get("retry_count", 0)
            if retry >= 1:
                raise StateError(
                    f"リトライ上限に達しています (retry_count={retry} >= 1)。"
                    "failed → running への遷移は不可"
                )
            data = dict(data)
            data["retry_count"] = retry + 1
        if current == "conflict" and new_status == "merge-ready":
            conflict_retry = data.get("conflict_retry_count", 0)
            if conflict_retry >= 1:
                raise StateError(
                    f"conflict リトライ上限に達しています (conflict_retry_count={conflict_retry} >= 1)。"
                    "conflict → merge-ready への遷移は不可"
                )
            data = dict(data)
            data["conflict_retry_count"] = conflict_retry + 1
        return data

    def _set_field(self, data: dict[str, Any], key: str, raw: str) -> dict[str, Any]:
        data = dict(data)
        if "." not in key:
            try:
                data[key] = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                data[key] = raw
            return data
        # Dot-path: navigate into nested dicts, creating missing intermediate dicts
        parts = key.split(".")
        cur = data
        for part in parts[:-1]:
            if not isinstance(cur.get(part), dict):
                cur[part] = {}
            cur = cur[part]
        last = parts[-1]
        try:
            cur[last] = json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            cur[last] = raw
        return data

    def _atomic_write(self, file: Path, data: dict[str, Any]) -> None:
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

    # ------------------------------------------------------------------
    # Validation helpers
    # ------------------------------------------------------------------

    def _validate_type(self, type_: str) -> None:
        if type_ not in ("issue", "session"):
            raise StateArgError("--type は issue または session を指定してください")

    def _validate_role(self, role: str) -> None:
        if role not in ("pilot", "worker"):
            raise StateArgError("--role は pilot または worker を指定してください")

    def _require_issue(self, issue: str | None) -> None:
        if not issue:
            raise StateArgError("type=issue の場合 --issue は必須です")

    def _validate_issue_num(self, issue: str) -> None:
        if not re.match(r"^\d+$", issue):
            raise StateArgError(f"--issue は正の整数を指定してください: {issue}")

    def _validate_field(self, field: str) -> None:
        if not _VALID_FIELD_RE.match(field):
            raise StateArgError(
                f"不正なフィールド名: {field}（英数字、アンダースコア、ドットのみ許可）"
            )

    def _validate_repo(self, repo: str) -> None:
        if not _VALID_REPO_RE.match(repo):
            raise StateArgError(
                f"不正な repo_id: {repo}（英数字、ハイフン、アンダースコアのみ許可）"
            )

    def _check_rbac(self, role: str, type_: str, sets: list[str]) -> None:
        if role == "worker" and type_ == "session":
            raise StateError("Worker は session.json への書き込み権限がありません")
        if role == "pilot" and type_ == "issue":
            for kv in sets:
                key = kv.partition("=")[0]
                if key not in _PILOT_ISSUE_ALLOWED_KEYS:
                    raise StateError(
                        f"Pilot は issue-{{N}}.json の {key} フィールドへの書き込み権限がありません"
                        f"（{', '.join(sorted(_PILOT_ISSUE_ALLOWED_KEYS))} のみ許可）"
                    )

    def _check_pilot_identity(self, sets: list[str], cwd: str | None) -> None:
        has_status = any(kv.partition("=")[0] == "status" for kv in sets)
        if not has_status:
            return
        check_cwd = cwd or os.getcwd()
        if "/worktrees/" in check_cwd:
            raise StateError(
                "worktrees/ 配下からの --role pilot の status 書き込みは禁止されています（不変条件C）"
            )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_read_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {"type": None, "issue": None, "repo": None, "field": None, "autopilot_dir": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            _print_read_usage()
            sys.exit(0)
        elif a == "--type" and i + 1 < len(argv):
            args["type"] = argv[i + 1]; i += 2
        elif a == "--issue" and i + 1 < len(argv):
            args["issue"] = argv[i + 1]; i += 2
        elif a == "--repo" and i + 1 < len(argv):
            args["repo"] = argv[i + 1]; i += 2
        elif a == "--field" and i + 1 < len(argv):
            args["field"] = argv[i + 1]; i += 2
        elif a == "--autopilot-dir" and i + 1 < len(argv):
            args["autopilot_dir"] = argv[i + 1] or None; i += 2
        else:
            print(f"ERROR: 不明なオプション: {a}", file=sys.stderr)
            sys.exit(1)
    if not args["type"]:
        print("ERROR: --type は必須です", file=sys.stderr)
        sys.exit(1)
    return args


def _parse_write_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {
        "type": None, "issue": None, "repo": None,
        "role": None, "sets": [], "init": False, "autopilot_dir": None,
        "force_done": False, "override_reason": None,
    }
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            _print_write_usage()
            sys.exit(0)
        elif a == "--type" and i + 1 < len(argv):
            args["type"] = argv[i + 1]; i += 2
        elif a == "--issue" and i + 1 < len(argv):
            args["issue"] = argv[i + 1]; i += 2
        elif a == "--repo" and i + 1 < len(argv):
            args["repo"] = argv[i + 1]; i += 2
        elif a == "--role" and i + 1 < len(argv):
            args["role"] = argv[i + 1]; i += 2
        elif a == "--set" and i + 1 < len(argv):
            args["sets"].append(argv[i + 1]); i += 2
        elif a == "--init":
            args["init"] = True; i += 1
        elif a == "--force-done":
            args["force_done"] = True; i += 1
        elif a == "--override-reason" and i + 1 < len(argv):
            args["override_reason"] = argv[i + 1]; i += 2
        elif a == "--autopilot-dir" and i + 1 < len(argv):
            args["autopilot_dir"] = argv[i + 1] or None; i += 2
        else:
            print(f"ERROR: 不明なオプション: {a}", file=sys.stderr)
            sys.exit(1)
    if not args["type"]:
        print("ERROR: --type は必須です", file=sys.stderr)
        sys.exit(1)
    if not args["role"]:
        print("ERROR: --role は必須です", file=sys.stderr)
        sys.exit(1)
    return args


def _print_read_usage() -> None:
    print(
        "Usage: python3 -m twl.autopilot.state read "
        "--type <issue|session> [--issue N] [--repo R] [--field F] [--autopilot-dir DIR]"
    )


def _print_write_usage() -> None:
    print(
        "Usage: python3 -m twl.autopilot.state write "
        "--type <issue|session> [--issue N] [--repo R] "
        "--role <pilot|worker> [--set k=v]... [--init] "
        "[--force-done --override-reason REASON] [--autopilot-dir DIR]"
    )


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        print("Usage: python3 -m twl.autopilot.state <read|write> [options]", file=sys.stderr)
        return 2

    subcmd, rest = args[0], args[1:]

    try:
        if subcmd == "read":
            parsed = _parse_read_args(rest)
            ap_dir = Path(parsed["autopilot_dir"]) if parsed.get("autopilot_dir") else None
            mgr = StateManager(autopilot_dir=ap_dir)
            result = mgr.read(
                type_=parsed["type"],
                issue=parsed["issue"],
                repo=parsed["repo"],
                field=parsed["field"],
            )
            print(result)
            return 0

        elif subcmd == "write":
            parsed = _parse_write_args(rest)
            ap_dir = Path(parsed["autopilot_dir"]) if parsed.get("autopilot_dir") else None
            mgr = StateManager(autopilot_dir=ap_dir)
            msg = mgr.write(
                type_=parsed["type"],
                role=parsed["role"],
                issue=parsed["issue"],
                repo=parsed["repo"],
                sets=parsed["sets"],
                init=parsed["init"],
                force_done=parsed["force_done"],
                override_reason=parsed["override_reason"],
            )
            print(msg)
            return 0

        else:
            print(f"ERROR: 不明なサブコマンド: {subcmd}", file=sys.stderr)
            return 2

    except StateArgError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    except StateError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
