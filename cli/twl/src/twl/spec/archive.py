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


def _integrate_specs(change_dir: Path, specs_dir: Path) -> None:
    specs_change_dir = change_dir / "specs"
    if not specs_change_dir.is_dir():
        return

    for cap_dir in sorted(specs_change_dir.iterdir()):
        if not cap_dir.is_dir():
            continue
        spec_file = cap_dir / "spec.md"
        if not spec_file.exists():
            continue

        cap_name = cap_dir.name
        text = spec_file.read_text(encoding="utf-8")
        target_dir = specs_dir / cap_name
        target_spec = target_dir / "spec.md"

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
                target_spec.write_text(new_text, encoding="utf-8")
                print(f"- Integrated MODIFIED specs for '{cap_name}'")
            else:
                print(f"Warning: MODIFIED spec for '{cap_name}' skipped: no existing spec to modify", file=sys.stderr)

        if _REMOVED_RE.search(text):
            if target_dir.exists():
                # Boundary check: ensure target_dir is within specs_dir
                resolved_target = target_dir.resolve()
                resolved_specs = specs_dir.resolve()
                if resolved_specs not in resolved_target.parents:
                    print(f"Warning: Skipping removal of '{cap_name}': path outside specs_dir", file=sys.stderr)
                    continue
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
