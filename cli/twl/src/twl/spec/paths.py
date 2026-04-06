"""deltaspec root detection and path resolution."""

from pathlib import Path


class OpenspecNotFound(Exception):
    pass


def find_deltaspec_root(start: Path | None = None) -> Path:
    """Walk up from start (default: cwd) until deltaspec/ is found.

    Returns the project root containing deltaspec/, not the deltaspec/ dir itself.
    Raises OpenspecNotFound if not found.
    """
    current = (start or Path.cwd()).resolve()
    while True:
        if (current / "deltaspec").is_dir():
            return current
        parent = current.parent
        if parent == current:
            raise OpenspecNotFound(
                "deltaspec/ directory not found. Run from a project with deltaspec/ initialized."
            )
        current = parent


def get_changes_dir(root: Path) -> Path:
    return root / "deltaspec" / "changes"


def get_specs_dir(root: Path) -> Path:
    return root / "deltaspec" / "specs"


def get_change_dir(root: Path, name: str) -> Path:
    return get_changes_dir(root) / name
