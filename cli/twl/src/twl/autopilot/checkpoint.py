"""Checkpoint management for autopilot specialist findings.

Replaces: checkpoint-write.sh, checkpoint-read.sh

CLI usage:
    python3 -m twl.autopilot.checkpoint write --step <step> --status <PASS|WARN|FAIL> [--findings <json>] [--autopilot-dir <dir>]
    python3 -m twl.autopilot.checkpoint read  --step <step> --field <field> [--autopilot-dir <dir>]
    python3 -m twl.autopilot.checkpoint read  --step <step> --critical-findings [--autopilot-dir <dir>]
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_VALID_STEP_RE = re.compile(r"^[a-z0-9-]+$")
_VALID_FIELD_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_.]*$")
_VALID_STATUSES = {"PASS", "WARN", "FAIL"}
_VALID_ISSUE_NUMBER_RE = re.compile(r"^[1-9][0-9]*$")


def _checkpoint_dir() -> Path:
    """Resolve checkpoint directory (AUTOPILOT_DIR env var takes priority)."""
    env = os.environ.get("AUTOPILOT_DIR", "")
    if env:
        return Path(env) / "checkpoints"
    try:
        root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return Path(root) / ".autopilot" / "checkpoints"
    except Exception:
        return Path.cwd() / ".autopilot" / "checkpoints"


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


class CheckpointError(Exception):
    """Runtime error (exit code 1)."""


class CheckpointArgError(Exception):
    """Argument error (exit code 2)."""


class CheckpointManager:
    """Write and read autopilot checkpoint files."""

    def __init__(self, checkpoint_dir: Path | None = None) -> None:
        self.checkpoint_dir = checkpoint_dir or _checkpoint_dir()

    def write(
        self,
        step: str,
        status: str,
        findings: list[Any] | None = None,
        issue_number: str | None = None,
    ) -> str:
        """Write checkpoint JSON and return a confirmation message.

        critical_count は severity=CRITICAL のみカウントし confidence フィルタを持たない。
        confidence フィルタは書き込み側（writer）の責務であり、ac-verify 書き込み経路
        （ac-impl-coverage-check.sh: confidence=90、LLM delegate パス: confidence=80）が
        confidence >= 80 を保証する。fix-phase はこの invariant に依存する。

        issue_number が指定された場合、{step}-{issue_number}.json に書き込み
        並列 Worker 間の checkpoint isolation を実現する（Issue #1399）。
        """
        self._validate_step(step)
        self._validate_status(status)
        if issue_number is not None:
            self._validate_issue_number(issue_number)
        findings_list: list[Any] = findings if findings is not None else []

        critical_count = sum(
            1 for f in findings_list if isinstance(f, dict) and f.get("severity") == "CRITICAL"
        )
        warning_count = sum(
            1 for f in findings_list if isinstance(f, dict) and f.get("severity") == "WARNING"
        )
        findings_summary = f"{critical_count} CRITICAL, {warning_count} WARNING"

        data: dict[str, Any] = {
            "step": step,
            "status": status,
            "findings_summary": findings_summary,
            "critical_count": critical_count,
            "findings": findings_list,
            "timestamp": _now_utc(),
        }
        if issue_number is not None:
            data["issue_number"] = issue_number

        filename = f"{step}-{issue_number}.json" if issue_number else f"{step}.json"
        file = self.checkpoint_dir / filename

        # audit 保全: 上書き前に既存ファイルをタイムスタンプ付きでコピー
        try:
            from twl.autopilot.audit import is_audit_active, resolve_audit_dir
            if is_audit_active() and file.is_file():
                audit_dir = resolve_audit_dir()
                if audit_dir is not None:
                    import shutil
                    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                    checkpoints_audit = audit_dir / "checkpoints"
                    checkpoints_audit.mkdir(parents=True, exist_ok=True)
                    dest = checkpoints_audit / f"{step}-{ts}.json"
                    if dest.exists():
                        counter = 2
                        while (checkpoints_audit / f"{step}-{ts}-{counter}.json").exists():
                            counter += 1
                        dest = checkpoints_audit / f"{step}-{ts}-{counter}.json"
                    shutil.copy2(file, dest)
        except Exception:
            pass

        _atomic_write(file, data)
        return f"checkpoint written: {file} ({status}, {findings_summary})"

    def read(
        self,
        step: str,
        field: str | None = None,
        critical_findings: bool = False,
    ) -> str:
        """Read checkpoint JSON and return a field value or filtered list."""
        self._validate_step(step)
        if not critical_findings and not field:
            raise CheckpointArgError("--field または --critical-findings が必要です")
        if field:
            self._validate_field(field)

        file = self.checkpoint_dir / f"{step}.json"
        if not file.is_file():
            raise CheckpointError(f"checkpoint not found: {file}")

        data = json.loads(file.read_text(encoding="utf-8"))

        if critical_findings:
            result = [f for f in data.get("findings", []) if isinstance(f, dict) and f.get("severity") == "CRITICAL"]
            return json.dumps(result, ensure_ascii=False)

        value = data.get(field)  # type: ignore[arg-type]
        if value is None:
            return ""
        if isinstance(value, (dict, list)):
            return json.dumps(value, ensure_ascii=False)
        return str(value)

    # ------------------------------------------------------------------
    # Validation helpers
    # ------------------------------------------------------------------

    def _validate_step(self, step: str) -> None:
        if not step:
            raise CheckpointArgError("--step は必須です")
        if not _VALID_STEP_RE.match(step):
            raise CheckpointArgError(
                f"--step に不正な文字が含まれています: {step}（小文字英数字とハイフンのみ許可）"
            )

    def _validate_status(self, status: str) -> None:
        if status not in _VALID_STATUSES:
            raise CheckpointArgError(
                f"--status は PASS, WARN, FAIL のいずれかを指定してください: {status}"
            )

    def _validate_field(self, field: str) -> None:
        if not _VALID_FIELD_RE.match(field):
            raise CheckpointArgError(
                f"不正なフィールド名: {field}（英数字、アンダースコア、ドットのみ許可）"
            )

    def _validate_issue_number(self, issue_number: str) -> None:
        if not _VALID_ISSUE_NUMBER_RE.match(issue_number):
            raise CheckpointArgError(
                f"--issue-number に不正な値: {issue_number!r}（正の整数のみ許可）"
            )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_write_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {"step": None, "status": None, "findings": None, "autopilot_dir": None, "issue_number": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print(
                "Usage: python3 -m twl.autopilot.checkpoint write "
                "--step <step> --status <PASS|WARN|FAIL> [--findings <json_array>] "
                "[--issue-number <N>] [--autopilot-dir <dir>]"
            )
            sys.exit(0)
        elif a == "--step" and i + 1 < len(argv):
            args["step"] = argv[i + 1]; i += 2
        elif a == "--status" and i + 1 < len(argv):
            args["status"] = argv[i + 1]; i += 2
        elif a == "--findings" and i + 1 < len(argv):
            args["findings"] = argv[i + 1]; i += 2
        elif a == "--issue-number" and i + 1 < len(argv):
            args["issue_number"] = argv[i + 1]; i += 2
        elif a == "--autopilot-dir" and i + 1 < len(argv):
            args["autopilot_dir"] = argv[i + 1]; i += 2
        else:
            print(f"ERROR: Unknown argument: {a}", file=sys.stderr)
            sys.exit(2)
    if not args["step"]:
        print("ERROR: --step is required", file=sys.stderr)
        sys.exit(2)
    if not args["status"]:
        print("ERROR: --status is required", file=sys.stderr)
        sys.exit(2)
    return args


def _parse_read_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {"step": None, "field": None, "critical_findings": False, "autopilot_dir": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print(
                "Usage: python3 -m twl.autopilot.checkpoint read "
                "--step <step> (--field <field> | --critical-findings) [--autopilot-dir <dir>]"
            )
            sys.exit(0)
        elif a == "--step" and i + 1 < len(argv):
            args["step"] = argv[i + 1]; i += 2
        elif a == "--field" and i + 1 < len(argv):
            args["field"] = argv[i + 1]; i += 2
        elif a == "--critical-findings":
            args["critical_findings"] = True; i += 1
        elif a == "--autopilot-dir" and i + 1 < len(argv):
            args["autopilot_dir"] = argv[i + 1]; i += 2
        else:
            print(f"ERROR: Unknown argument: {a}", file=sys.stderr)
            sys.exit(2)
    if not args["step"]:
        print("ERROR: --step is required", file=sys.stderr)
        sys.exit(2)
    return args


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        print(
            "Usage: python3 -m twl.autopilot.checkpoint <write|read> [options]",
            file=sys.stderr,
        )
        return 2

    subcmd, rest = args[0], args[1:]

    try:
        if subcmd == "write":
            parsed = _parse_write_args(rest)
            checkpoint_dir = Path(parsed["autopilot_dir"]) / "checkpoints" if parsed["autopilot_dir"] else None
            mgr = CheckpointManager(checkpoint_dir=checkpoint_dir)
            findings: list[Any] | None = None
            if parsed["findings"] is not None:
                findings = json.loads(parsed["findings"])
                if not isinstance(findings, list):
                    print("ERROR: --findings must be a valid JSON array", file=sys.stderr)
                    return 1
            msg = mgr.write(
                step=parsed["step"],
                status=parsed["status"],
                findings=findings,
                issue_number=parsed.get("issue_number"),
            )
            print(msg)
            return 0

        elif subcmd == "read":
            parsed = _parse_read_args(rest)
            checkpoint_dir = Path(parsed["autopilot_dir"]) / "checkpoints" if parsed["autopilot_dir"] else None
            mgr = CheckpointManager(checkpoint_dir=checkpoint_dir)
            result = mgr.read(
                step=parsed["step"],
                field=parsed["field"],
                critical_findings=parsed["critical_findings"],
            )
            print(result)
            return 0

        else:
            print(f"ERROR: 不明なサブコマンド: {subcmd}", file=sys.stderr)
            return 2

    except CheckpointArgError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    except CheckpointError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"ERROR: --findings は有効な JSON 配列を指定してください: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
