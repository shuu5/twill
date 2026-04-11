"""deltaspec root detection and path resolution."""

import os
from pathlib import Path


class DeltaspecNotFound(Exception):
    pass


def _find_git_root(start: Path) -> Path | None:
    """Walk up from start to find the .git directory."""
    current = start.resolve()
    while True:
        if (current / ".git").exists():
            return current
        parent = current.parent
        if parent == current:
            return None
        current = parent


def _walk_down_find_deltaspec_roots(git_top: Path, max_depth: int = 3) -> list[Path]:
    """Find all project roots with deltaspec/config.yaml within max_depth from git_top.

    Excludes .git, node_modules, __pycache__ directories.
    """
    exclude = {".git", "node_modules", "__pycache__"}
    results: list[Path] = []

    def _recurse(current: Path, depth: int) -> None:
        if depth > max_depth:
            return
        if (current / "deltaspec" / "config.yaml").is_file():
            results.append(current)
        try:
            for child in sorted(current.iterdir()):
                if child.is_dir() and child.name not in exclude:
                    _recurse(child, depth + 1)
        except PermissionError:
            pass

    _recurse(git_top, 0)
    return results


def find_deltaspec_root(start: Path | None = None) -> Path:
    """Find the project root containing deltaspec/config.yaml.

    Strategy:
    1. Walk-up from start: find deltaspec/config.yaml
       (deltaspec/ directories without config.yaml are skipped)
    2. Walk-down fallback: from git toplevel, search **/deltaspec/config.yaml (maxdepth=3)
    3. Multiple hits: select closest to cwd (longest common path prefix)
    4. Not found: raise DeltaspecNotFound

    Returns the project root (parent of deltaspec/), not deltaspec/ itself.
    """
    current = (start or Path.cwd()).resolve()

    # Phase 1: Walk-up looking for deltaspec/config.yaml
    probe = current
    while True:
        if (probe / "deltaspec" / "config.yaml").is_file():
            return probe
        parent = probe.parent
        if parent == probe:
            break
        probe = parent

    # Phase 2: Walk-down fallback from git toplevel
    git_top = _find_git_root(current)
    if git_top is not None:
        candidates = _walk_down_find_deltaspec_roots(git_top, max_depth=3)
        if candidates:
            if len(candidates) == 1:
                return candidates[0]
            # Multiple hits: select root with longest common path with current
            def _common_len(root: Path) -> int:
                try:
                    return len(Path(os.path.commonpath([str(current), str(root)])).parts)
                except ValueError:
                    return 0

            return max(candidates, key=_common_len)

    raise DeltaspecNotFound(
        "deltaspec/config.yaml not found. Run from a project with deltaspec/ initialized."
    )


def get_changes_dir(root: Path) -> Path:
    return root / "deltaspec" / "changes"


def get_specs_dir(root: Path) -> Path:
    return root / "deltaspec" / "specs"


def get_change_dir(root: Path, name: str) -> Path:
    return get_changes_dir(root) / name
