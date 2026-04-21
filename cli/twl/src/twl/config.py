"""Loader for project-links.yaml — centralised external link config.

CLI usage:
    python3 -m twl config get <key>    # e.g. project-board.number
    twl config get project-board.number
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

_FILENAME = "project-links.yaml"


def _find_project_links(start: Path | None = None) -> Path | None:
    """Walk up from start (default: CWD) to find project-links.yaml."""
    current = (start or Path.cwd()).resolve()
    for _ in range(20):
        candidate = current / _FILENAME
        if candidate.is_file():
            return candidate
        parent = current.parent
        if parent == current:
            break
        current = parent
    return None


def load() -> dict[str, Any]:
    """Load project-links.yaml, returning empty dict if not found."""
    path = _find_project_links()
    if path is None:
        return {}
    with path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    return data


def get(key: str) -> Any:
    """Return the value at dot-separated key path.

    Keys use hyphens as written in YAML (project_board.number), but also
    accept hyphenated form (project-board.number) by normalising to underscores.

    Raises:
        KeyError: If key is not found.
    """
    data = load()
    parts = [p.replace("-", "_") for p in key.split(".")]
    node: Any = data
    for part in parts:
        if not isinstance(node, dict) or part not in node:
            raise KeyError(f"Key not found in {_FILENAME}: {key!r}")
        node = node[part]
    return node


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    if not args or args[0] in ("-h", "--help"):
        print("Usage: twl config get <key>")
        print("       key: dot-separated path, e.g. project-board.number")
        return 0

    if args[0] == "get":
        if len(args) < 2:
            print("Error: key argument required", file=sys.stderr)
            print("Usage: twl config get <key>", file=sys.stderr)
            return 1
        key = args[1]
        try:
            value = get(key)
        except KeyError as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1
        print(value)
        return 0

    print(f"Error: unknown subcommand '{args[0]}'", file=sys.stderr)
    print("Usage: twl config get <key>", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
