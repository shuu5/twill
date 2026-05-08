"""Audit session management for autopilot execution history persistence.

CLI usage:
    python3 -m twl.autopilot.audit on [--run-id ID]
    python3 -m twl.autopilot.audit off
    python3 -m twl.autopilot.audit status

Files:
    .audit/.active        — active session marker (JSON)
    .audit/<run-id>/      — session directory
    .audit/<run-id>/index.json — session summary (written on off)
"""

from __future__ import annotations

import json
import os
import re
import random
import string
import sys
from datetime import datetime, timezone
from pathlib import Path

# run_id は英数字・ハイフン・アンダースコアのみ許可（path traversal 防止）
_VALID_RUN_ID_RE = re.compile(r"^[a-zA-Z0-9_-]+$")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _project_root() -> Path:
    """Resolve project root via git rev-parse --show-toplevel."""
    import subprocess
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(result.stdout.strip())


def _resolve_root(project_root: Path | None) -> Path:
    """Return project_root if provided, otherwise resolve via git."""
    return project_root if project_root is not None else _project_root()


def _active_file(project_root: Path | None = None) -> Path:
    return _resolve_root(project_root) / ".audit" / ".active"


def _now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _gen_run_id() -> str:
    ts = int(datetime.now(timezone.utc).timestamp())
    suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=4))
    return f"{ts}_{suffix}"


def _validate_run_id(run_id: str) -> None:
    """Raise ValueError if run_id contains path-traversal characters."""
    if not _VALID_RUN_ID_RE.match(run_id):
        raise ValueError(
            f"Invalid run_id {run_id!r}: only alphanumeric characters, hyphens, and underscores are allowed"
        )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def is_audit_active(project_root: Path | None = None) -> bool:
    """Return True if audit is active (TWL_AUDIT=1 env OR .audit/.active exists)."""
    if os.environ.get("TWL_AUDIT") == "1":
        return True
    try:
        return _active_file(project_root).is_file()
    except Exception:
        return False


def resolve_audit_dir(project_root: Path | None = None) -> Path | None:
    """Resolve audit directory: TWL_AUDIT_DIR env → .audit/.active → None."""
    env = os.environ.get("TWL_AUDIT_DIR")
    if env:
        root = _resolve_root(project_root)
        resolved = Path(env).resolve()
        root_resolved = root.resolve()
        if not resolved.is_relative_to(root_resolved):
            raise ValueError(f"TWL_AUDIT_DIR is outside project root: {resolved}")
        return resolved
    try:
        active = _active_file(project_root)
        if active.is_file():
            data = json.loads(active.read_text(encoding="utf-8"))
            audit_dir = data.get("audit_dir")
            if audit_dir:
                root = _resolve_root(project_root)
                resolved = root / audit_dir
                resolved = resolved.resolve()
                # Enforce path containment: audit_dir must stay within project root
                root_resolved = root.resolve()
                if not resolved.is_relative_to(root_resolved):
                    raise ValueError(f"audit_dir is outside project root: {resolved}")
                return resolved
    except ValueError:
        raise
    except Exception:
        pass
    return None


def audit_on(run_id: str | None = None, project_root: Path | None = None) -> dict:
    """Start an audit session. Create .audit/<run-id>/ and .audit/.active."""
    if run_id is None:
        run_id = _gen_run_id()

    _validate_run_id(run_id)

    root = _resolve_root(project_root)
    audit_dir = root / ".audit" / run_id
    audit_dir.mkdir(parents=True, exist_ok=True)

    started_at = _now_utc()
    active_data = {
        "run_id": run_id,
        "started_at": started_at,
        "audit_dir": str(audit_dir),
    }
    active_file = root / ".audit" / ".active"
    active_file.write_text(json.dumps(active_data, ensure_ascii=False) + "\n", encoding="utf-8")

    return active_data


def audit_off(project_root: Path | None = None) -> dict:
    """Stop an audit session. Remove .audit/.active and write index.json."""
    active = _active_file(project_root)
    if not active.is_file():
        raise RuntimeError("audit is not active")

    data = json.loads(active.read_text(encoding="utf-8"))
    run_id = data["run_id"]
    _validate_run_id(run_id)
    root = _resolve_root(project_root)
    audit_dir = root / ".audit" / run_id

    ended_at = _now_utc()

    # Collect files as a flat list of relative paths
    files: list[str] = []
    specialists_dir = audit_dir / "specialists"
    if specialists_dir.is_dir():
        for p in sorted(specialists_dir.iterdir()):
            files.append(str(p.relative_to(audit_dir)))
    checkpoints_dir = audit_dir / "checkpoints"
    if checkpoints_dir.is_dir():
        for p in sorted(checkpoints_dir.iterdir()):
            files.append(str(p.relative_to(audit_dir)))
    state_log = audit_dir / "state-log.jsonl"
    if state_log.is_file():
        files.append("state-log.jsonl")

    index = {
        "run_id": run_id,
        "started_at": data.get("started_at", ""),
        "ended_at": ended_at,
        "files": files,
    }
    index_file = audit_dir / "index.json"
    index_file.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    active.unlink()
    return index


def audit_status(project_root: Path | None = None) -> dict:
    """Return current audit status as dict."""
    active = _active_file(project_root)
    if not active.is_file() and os.environ.get("TWL_AUDIT") != "1":
        return {"active": False}

    if active.is_file():
        try:
            data = json.loads(active.read_text(encoding="utf-8"))
            return {
                "active": True,
                "run_id": data.get("run_id", ""),
                "started_at": data.get("started_at", ""),
                "audit_dir": data.get("audit_dir", ""),
            }
        except Exception:
            pass

    # TWL_AUDIT=1 but no .active file
    audit_dir = resolve_audit_dir(project_root)
    return {
        "active": True,
        "run_id": None,
        "audit_dir": str(audit_dir) if audit_dir else None,
        "source": "TWL_AUDIT env",
    }


def audit_snapshot(
    source_dir: Path | str,
    label: str,
    project_root: Path | None = None,
) -> Path | None:
    """Copy source_dir to .audit/<run-id>/<label>/ for persistence.

    Returns the destination path, or None if audit is not active (no-op).
    D1 compliant: audit.py does not know the internal structure of source_dir.
    """
    if not is_audit_active(project_root):
        return None

    audit_dir = resolve_audit_dir(project_root)
    if audit_dir is None:
        return None

    source = Path(source_dir)
    if not source.is_dir():
        return None

    # Validate label (same rules as run_id)
    if not _VALID_RUN_ID_RE.match(label.replace("/", "_")):
        raise ValueError(f"Invalid label {label!r}: use alphanumeric, hyphens, underscores, or slashes")

    dest = audit_dir / label
    dest.mkdir(parents=True, exist_ok=True)

    import shutil
    shutil.copytree(source, dest, dirs_exist_ok=True)
    return dest


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# stuck-patterns lint (#1582)
# ---------------------------------------------------------------------------

def _cmd_stuck_patterns_lint(args: "argparse.Namespace") -> int:
    """Lint stuck-patterns.yaml against consumer scripts for drift detection."""
    import subprocess
    import glob

    project_root = _project_root()

    # stuck-patterns.yaml の解決
    yaml_path_arg = getattr(args, "yaml_path", None)
    if yaml_path_arg:
        yaml_path = Path(yaml_path_arg)
    else:
        yaml_path = project_root / "plugins" / "twl" / "refs" / "stuck-patterns.yaml"

    if not yaml_path.exists():
        print(f"error: stuck-patterns.yaml not found: {yaml_path}", file=sys.stderr)
        return 1

    # YAML からパターン ID を抽出
    pattern_ids: list[str] = []
    with open(yaml_path) as f:
        for line in f:
            m = re.match(r"\s*-\s*id:\s*(\S+)", line)
            if m:
                pattern_ids.append(m.group(1))

    if not pattern_ids:
        print("error: stuck-patterns.yaml にパターンが見つかりません", file=sys.stderr)
        return 1

    print(f"stuck-patterns.yaml: {len(pattern_ids)} patterns found")

    # consumer スクリプトのデフォルトリスト
    consumer_paths_arg = getattr(args, "consumers", None)
    if consumer_paths_arg:
        consumer_files = [Path(p) for p in consumer_paths_arg]
    else:
        consumer_files = [
            project_root / "plugins" / "twl" / "scripts" / "autopilot-orchestrator.sh",
            project_root / "plugins" / "session" / "scripts" / "lib" / "observer-auto-inject.sh",
            project_root / "plugins" / "session" / "scripts" / "cld-observe-any",
            project_root / "plugins" / "twl" / "skills" / "su-observer" / "scripts" / "step0-monitor-bootstrap.sh",
        ]

    # 各 consumer が stuck-patterns-lib.sh を参照しているか確認
    errors: list[str] = []
    warnings: list[str] = []

    for consumer in consumer_files:
        if not consumer.exists():
            warnings.append(f"WARN: consumer not found: {consumer}")
            continue
        try:
            result = subprocess.run(
                ["grep", "-qF", "stuck-patterns-lib.sh"],
                input=consumer.read_text(),
                capture_output=True,
                text=True,
            )
        except Exception:
            result = subprocess.CompletedProcess([], returncode=1)

        if result.returncode != 0:
            # grep で直接確認
            with open(consumer) as cf:
                text = cf.read()
            if "stuck-patterns-lib.sh" not in text and "_load_stuck_patterns" not in text:
                errors.append(f"DRIFT: {consumer.name} does not reference stuck-patterns-lib.sh")
            else:
                print(f"  ✓ {consumer.name}: references stuck-patterns-lib.sh")
        else:
            print(f"  ✓ {consumer.name}: references stuck-patterns-lib.sh")

    for w in warnings:
        print(w)
    for e in errors:
        print(e, file=sys.stderr)

    if errors:
        return 1

    print("stuck-patterns lint: OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    import argparse
    parser = argparse.ArgumentParser(description="twl audit — autopilot execution history")
    sub = parser.add_subparsers(dest="cmd", metavar="<command>")

    on_p = sub.add_parser("on", help="Start audit session")
    on_p.add_argument("--run-id", dest="run_id", default=None, help="Custom run ID")

    sub.add_parser("off", help="Stop audit session and write index.json")
    sub.add_parser("status", help="Show current audit status")

    snap_p = sub.add_parser("snapshot", help="Copy directory to audit for persistence")
    snap_p.add_argument("--source-dir", dest="source_dir", required=True, help="Directory to snapshot")
    snap_p.add_argument("--label", required=True, help="Label for the snapshot (e.g. co-issue/1)")

    sp = sub.add_parser("stuck-patterns", help="Lint stuck-patterns.yaml against consumer scripts")
    sp.add_argument("--yaml", dest="yaml_path", default=None, help="Path to stuck-patterns.yaml (default: auto-detect)")
    sp.add_argument("--consumer", dest="consumers", action="append", default=None,
                    metavar="PATH", help="Consumer script path to check (repeatable)")

    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    if args.cmd == "on":
        try:
            result = audit_on(args.run_id)
        except ValueError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
        print(f"audit started: run_id={result['run_id']}, dir={result['audit_dir']}")
        return 0

    if args.cmd == "off":
        try:
            result = audit_off()
            print(f"audit stopped: run_id={result['run_id']}, ended_at={result['ended_at']}")
            return 0
        except RuntimeError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1

    if args.cmd == "status":
        result = audit_status()
        if result["active"]:
            print(f"active: true")
            if result.get("run_id"):
                print(f"run_id: {result['run_id']}")
            if result.get("audit_dir"):
                print(f"audit_dir: {result['audit_dir']}")
        else:
            print("active: false")
        return 0

    if args.cmd == "snapshot":
        try:
            dest = audit_snapshot(args.source_dir, args.label)
            if dest:
                print(f"snapshot saved: {dest}")
            else:
                print("audit not active — snapshot skipped")
            return 0
        except ValueError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1

    if args.cmd == "stuck-patterns":
        return _cmd_stuck_patterns_lint(args)

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
