"""twl spec new <name> - Create a new change directory."""

import re
import sys
from datetime import date
from pathlib import Path

from .paths import DeltaspecNotFound, find_deltaspec_root, get_changes_dir

_KEBAB_RE = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$")


def cmd_new(name: str) -> int:
    if not _KEBAB_RE.match(name):
        print(
            f"Error: Change name must be kebab-case (lowercase letters, numbers, hyphens): {name}",
            file=sys.stderr,
        )
        return 1

    try:
        root = find_deltaspec_root()
    except DeltaspecNotFound as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    change_dir = get_changes_dir(root) / name
    if change_dir.exists():
        print(f"Error: Change '{name}' already exists at {change_dir}/", file=sys.stderr)
        return 1

    change_dir.mkdir(parents=True)
    deltaspec_yaml = change_dir / ".deltaspec.yaml"
    deltaspec_yaml.write_text(
        f"schema: spec-driven\ncreated: {date.today().isoformat()}\n",
        encoding="utf-8",
    )

    print(f"- Creating change '{name}'...")
    print(f"✔ Created change '{name}' at deltaspec/changes/{name}/ (schema: spec-driven)")
    return 0
