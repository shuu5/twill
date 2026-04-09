"""twl spec archive <name> - Archive a change with optional spec integration."""

import re
import shutil
import sys
from pathlib import Path

from .paths import DeltaspecNotFound, find_deltaspec_root, get_changes_dir, get_specs_dir
from .new import _KEBAB_RE

_ADDED_RE = re.compile(r"^## ADDED Requirements", re.MULTILINE)
_MODIFIED_RE = re.compile(r"^## MODIFIED Requirements", re.MULTILINE)
_REMOVED_RE = re.compile(r"^## REMOVED Requirements", re.MULTILINE)
_SECTION_HDR_RE = re.compile(r"^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements", re.MULTILINE)


def _extract_block(text: str, header: str) -> str:
    """Extract content between header line and next ## section header."""
    lines = text.splitlines(keepends=True)
    in_block = False
    result = []
    for line in lines:
        if line.rstrip() == header:
            in_block = True
            continue
        if in_block:
            if _SECTION_HDR_RE.match(line):
                break
            result.append(line)
    return "".join(result)


def _resolve_change_spec(specs_change_dir: Path, entry: Path) -> tuple[str, Path] | None:
    """Return (cap_name, spec_file) for a change specs entry (flat or subdir)."""
    if entry.is_dir():
        spec_file = entry / "spec.md"
        if spec_file.exists():
            return entry.name, spec_file
    elif entry.suffix == ".md":
        return entry.stem, entry
    return None


def _resolve_target_spec(specs_dir: Path, cap_name: str) -> tuple[Path, bool]:
    """Return (target_spec_path, is_flat) for an existing baseline spec, or flat path if new."""
    flat = specs_dir / f"{cap_name}.md"
    subdir = specs_dir / cap_name / "spec.md"
    if flat.exists():
        return flat, True
    if subdir.exists():
        return subdir, False
    # New spec: prefer flat format
    return flat, True


def _integrate_specs(change_dir: Path, specs_dir: Path) -> None:
    specs_change_dir = change_dir / "specs"
    if not specs_change_dir.is_dir():
        return

    for entry in sorted(specs_change_dir.iterdir()):
        resolved = _resolve_change_spec(specs_change_dir, entry)
        if resolved is None:
            continue
        cap_name, spec_file = resolved

        text = spec_file.read_text(encoding="utf-8")
        target_spec, is_flat = _resolve_target_spec(specs_dir, cap_name)
        target_dir = target_spec.parent  # specs_dir for flat, specs_dir/cap_name for subdir

        if _ADDED_RE.search(text):
            target_dir.mkdir(parents=True, exist_ok=True)
            if target_spec.exists():
                added = _extract_block(text, "## ADDED Requirements")
                with target_spec.open("a", encoding="utf-8") as f:
                    f.write("\n" + added)
            else:
                new_text = re.sub(r"^## ADDED Requirements", "## Requirements", text, flags=re.MULTILINE)
                target_spec.write_text(new_text, encoding="utf-8")
            print(f"- Integrated ADDED specs for '{cap_name}'")

        if _MODIFIED_RE.search(text):
            if target_spec.exists():
                target_dir.mkdir(parents=True, exist_ok=True)
                modified = _extract_block(text, "## MODIFIED Requirements")
                new_text = re.sub(r"^## MODIFIED Requirements", "## Requirements", modified, flags=re.MULTILINE)
                existing = target_spec.read_text(encoding="utf-8")
                target_spec.write_text(existing + "\n" + new_text, encoding="utf-8")
                print(f"- Integrated MODIFIED specs for '{cap_name}'")
            else:
                print(f"Warning: MODIFIED spec for '{cap_name}' skipped: no existing spec to modify", file=sys.stderr)

        if _REMOVED_RE.search(text):
            if target_spec.exists():
                # Boundary check: ensure target is within specs_dir
                resolved_target = target_spec.resolve()
                resolved_specs = specs_dir.resolve()
                if resolved_specs != resolved_target.parent and resolved_specs not in resolved_target.parents:
                    print(f"Warning: Skipping removal of '{cap_name}': path outside specs_dir", file=sys.stderr)
                    continue
                if is_flat:
                    target_spec.unlink()
                else:
                    shutil.rmtree(target_dir)
                print(f"- Removed spec '{cap_name}'")


def cmd_archive(name: str, yes: bool = False, skip_specs: bool = False) -> int:
    if not _KEBAB_RE.match(name):
        print(f"Error: Change name must be kebab-case: {name}", file=sys.stderr)
        return 1

    try:
        root = find_deltaspec_root()
    except DeltaspecNotFound as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    change_dir = get_changes_dir(root) / name
    if not change_dir.is_dir():
        print(f"Error: Change '{name}' not found", file=sys.stderr)
        return 1

    if not yes:
        print(f"Archive change '{name}'?")
        if not skip_specs:
            print("This will update main specs in deltaspec/specs/.")
        answer = input("Continue? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            print("Cancelled.")
            return 0

    if not skip_specs:
        _integrate_specs(change_dir, get_specs_dir(root))

    archive_dir = get_changes_dir(root) / "archive"
    archive_dir.mkdir(parents=True, exist_ok=True)
    shutil.move(str(change_dir), str(archive_dir / name))
    print(f"✔ Archived change '{name}'")
    return 0
