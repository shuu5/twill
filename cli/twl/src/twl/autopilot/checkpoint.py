"""Checkpoint management for autopilot specialist findings.

Replaces: checkpoint-write.sh, checkpoint-read.sh

CLI usage:
    python3 -m twl.autopilot.checkpoint write --step <step> --status <PASS|WARN|FAIL> [--findings <json>]
    python3 -m twl.autopilot.checkpoint read  --step <step> --field <field>
    python3 -m twl.autopilot.checkpoint read  --step <step> --critical-findings
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
    ) -> str:
        """Write checkpoint JSON and return a confirmation message."""
        self._validate_step(step)
        self._validate_status(status)
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
        file = self.checkpoint_dir / f"{step}.json"
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


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_write_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {"step": None, "status": None, "findings": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print(
                "Usage: python3 -m twl.autopilot.checkpoint write "
                "--step <step> --status <PASS|WARN|FAIL> [--findings <json_array>]"
            )
            sys.exit(0)
        elif a == "--step" and i + 1 < len(argv):
            args["step"] = argv[i + 1]; i += 2
        elif a == "--status" and i + 1 < len(argv):
            args["status"] = argv[i + 1]; i += 2
        elif a == "--findings" and i + 1 < len(argv):
            args["findings"] = argv[i + 1]; i += 2
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
    args: dict[str, Any] = {"step": None, "field": None, "critical_findings": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print(
                "Usage: python3 -m twl.autopilot.checkpoint read "
                "--step <step> (--field <field> | --critical-findings)"
            )
            sys.exit(0)
        elif a == "--step" and i + 1 < len(argv):
            args["step"] = argv[i + 1]; i += 2
        elif a == "--field" and i + 1 < len(argv):
            args["field"] = argv[i + 1]; i += 2
        elif a == "--critical-findings":
            args["critical_findings"] = True; i += 1
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
    mgr = CheckpointManager()

    try:
        if subcmd == "write":
            parsed = _parse_write_args(rest)
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
            )
            print(msg)
            return 0

        elif subcmd == "read":
            parsed = _parse_read_args(rest)
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
