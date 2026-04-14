"""twl spec new <name> - Create a new change directory."""

import os
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

from .paths import DeltaspecNotFound, find_deltaspec_root, get_changes_dir

_KEBAB_RE = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$")
_ISSUE_RE = re.compile(r"^issue-(\d+)$")


def _has_nested_deltaspec_in_remote() -> bool | None:
    """Check if origin/main contains nested deltaspec/config.yaml files.

    Returns:
        True  — nested roots found (auto-init should be suppressed)
        False — no nested roots in origin/main (safe to auto-init)
        None  — git ls-tree failed (offline/no origin; caller should warn and proceed)
    """
    try:
        result = subprocess.run(
            ["git", "ls-tree", "-r", "--name-only", "origin/main"],
            capture_output=True,
            text=True,
            cwd=Path.cwd(),
            timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None  # git not found or timed out

    if result.returncode != 0:
        return None  # git ls-tree failed (offline, no origin, etc.)

    for line in result.stdout.splitlines():
        # Detect nested deltaspec/config.yaml (not at repo root level)
        # e.g. "plugins/twl/deltaspec/config.yaml" or "cli/twl/deltaspec/config.yaml"
        if line.endswith("deltaspec/config.yaml") and "/" in line:
            return True

    return False


def _init_deltaspec_config(deltaspec_dir: Path) -> None:
    """Create deltaspec/config.yaml if deltaspec/ is being initialized."""
    config_path = deltaspec_dir / "config.yaml"
    if not config_path.exists():
        config_path.write_text(
            "schema: spec-driven\ncontext: {}\n",
            encoding="utf-8",
        )


def cmd_new(name: str, scope: str | None = None) -> int:
    if not _KEBAB_RE.match(name):
        print(
            f"Error: Change name must be kebab-case (lowercase letters, numbers, hyphens): {name}",
            file=sys.stderr,
        )
        return 1

    try:
        root = find_deltaspec_root()
    except DeltaspecNotFound:
        cwd = Path.cwd()

        # Phase 1 guard: detect nested roots via origin/main
        # If TWL_SPEC_ALLOW_AUTO_INIT is set, skip the guard (Phase 2 opt-in)
        if not os.environ.get("TWL_SPEC_ALLOW_AUTO_INIT"):
            has_nested = _has_nested_deltaspec_in_remote()
            if has_nested is True:
                print(
                    "Error: nested deltaspec root が origin/main に存在しますが、"
                    "現在の cwd から参照できません。\n"
                    "  次のいずれかを実行してください:\n"
                    "    1. `git rebase origin/main` — feat branch を最新 main に rebase する\n"
                    "    2. `cd <nested-root-parent>` — 対象モジュールのディレクトリから実行する\n"
                    "  移行期間中に従来の動作が必要な場合: TWL_SPEC_ALLOW_AUTO_INIT=1 twl spec new ...",
                    file=sys.stderr,
                )
                return 1
            elif has_nested is None:
                # git ls-tree failed (offline or no origin) — warn and fall through
                print(
                    "[WARN] origin/main へのアクセスに失敗しました。auto-init を続行します。",
                    file=sys.stderr,
                )

        # Auto-init: create deltaspec/config.yaml in cwd
        deltaspec_dir = cwd / "deltaspec"
        deltaspec_dir.mkdir(parents=True, exist_ok=True)
        _init_deltaspec_config(deltaspec_dir)
        print(f"Initialized deltaspec/ in {cwd}")
        root = cwd

    change_dir = get_changes_dir(root) / name
    if change_dir.exists():
        print(f"Error: Change '{name}' already exists at {change_dir}/", file=sys.stderr)
        return 1

    m = _ISSUE_RE.match(name)
    issue_line = f"issue: {m.group(1)}\n" if m else ""
    scope_line = f"scope: {scope}\n" if scope else ""

    change_dir.mkdir(parents=True)
    deltaspec_yaml = change_dir / ".deltaspec.yaml"
    deltaspec_yaml.write_text(
        f"schema: spec-driven\ncreated: {date.today().isoformat()}\n"
        f"{issue_line}{scope_line}name: {name}\nstatus: pending\n",
        encoding="utf-8",
    )

    print(f"- Creating change '{name}'...")
    print(f"✔ Created change '{name}' at deltaspec/changes/{name}/ (schema: spec-driven)")
    return 0
