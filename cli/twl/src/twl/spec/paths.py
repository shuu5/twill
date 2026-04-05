"""openspec root detection and path resolution."""

from pathlib import Path


class OpenspecNotFound(Exception):
    pass


def find_openspec_root(start: Path | None = None) -> Path:
    """Walk up from start (default: cwd) until openspec/ is found.

    Returns the project root containing openspec/, not the openspec/ dir itself.
    Raises OpenspecNotFound if not found.
    """
    current = (start or Path.cwd()).resolve()
    while True:
        if (current / "openspec").is_dir():
            return current
        parent = current.parent
        if parent == current:
            raise OpenspecNotFound(
                "openspec/ directory not found. Run from a project with openspec/ initialized."
            )
        current = parent


def get_changes_dir(root: Path) -> Path:
    return root / "openspec" / "changes"


def get_specs_dir(root: Path) -> Path:
    return root / "openspec" / "specs"


def get_change_dir(root: Path, name: str) -> Path:
    return get_changes_dir(root) / name
