"""twl spec archive <name> - Archive a change with optional spec integration.

Follows Fission-AI/OpenSpec semantics:
- Operation order: REMOVED → MODIFIED → ADDED
- MODIFIED: requirement-level replacement (not append)
- ADDED on new file: ADDED block only (not full text)
- Atomicity: validate all → write all (any failure aborts)
- Scope: .deltaspec.yaml scope field → deltaspec/specs/<scope>/
"""

import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

from .paths import DeltaspecNotFound, find_deltaspec_root, get_changes_dir, get_specs_dir
from .new import _KEBAB_RE

_ADDED_RE = re.compile(r"^## ADDED Requirements", re.MULTILINE)
_MODIFIED_RE = re.compile(r"^## MODIFIED Requirements", re.MULTILINE)
_REMOVED_RE = re.compile(r"^## REMOVED Requirements", re.MULTILINE)
_SECTION_HDR_RE = re.compile(r"^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements", re.MULTILINE)
_REQ_HDR_RE = re.compile(r"^### Requirement:\s*(.+)", re.MULTILINE)


class SpecIntegrationError(Exception):
    """Raised when spec integration fails validation (aborts entire archive)."""


@dataclass
class _SpecOp:
    cap_name: str
    text: str
    target_spec: Path
    is_flat: bool
    specs_dir: Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _extract_block(text: str, header: str) -> str:
    """Extract content between header line and next ## section header."""
    lines = text.splitlines(keepends=True)
    in_block = False
    result: list[str] = []
    for line in lines:
        if line.rstrip() == header:
            in_block = True
            continue
        if in_block:
            if _SECTION_HDR_RE.match(line):
                break
            result.append(line)
    return "".join(result)


def _parse_requirements(text: str) -> list[tuple[str, str]]:
    """Parse text into (requirement_name, full_block_text) tuples."""
    lines = text.splitlines(keepends=True)
    reqs: list[tuple[str, str]] = []
    current_name = ""
    current_lines: list[str] = []

    for line in lines:
        m = _REQ_HDR_RE.match(line)
        if m:
            if current_name:
                reqs.append((current_name.strip(), "".join(current_lines)))
            current_name = m.group(1)
            current_lines = [line]
        elif current_name:
            current_lines.append(line)

    if current_name:
        reqs.append((current_name.strip(), "".join(current_lines)))
    return reqs


def _replace_requirements(existing_text: str, modified_block: str, cap_name: str) -> str:
    """Replace matching requirement blocks. Raises SpecIntegrationError if not found."""
    modified_reqs = _parse_requirements(modified_block)
    result = existing_text

    for req_name, new_block in modified_reqs:
        existing_reqs = _parse_requirements(result)
        found = False
        for ename, eblock in existing_reqs:
            if ename == req_name:
                result = result.replace(eblock, new_block)
                found = True
                break
        if not found:
            raise SpecIntegrationError(
                f"'{cap_name}' MODIFIED: requirement '{req_name}' not found in target spec"
            )
    return result


def _validate_no_duplicate_adds(existing_text: str, added_block: str, cap_name: str) -> None:
    """Ensure ADDED requirements don't duplicate existing ones."""
    existing_reqs = {name for name, _ in _parse_requirements(existing_text)}
    added_reqs = _parse_requirements(added_block)
    for req_name, _ in added_reqs:
        if req_name in existing_reqs:
            raise SpecIntegrationError(
                f"'{cap_name}' ADDED: requirement '{req_name}' already exists in target spec"
            )


def _read_scope(change_dir: Path) -> str | None:
    """Read scope field from .deltaspec.yaml."""
    yaml_path = change_dir / ".deltaspec.yaml"
    if not yaml_path.exists():
        return None
    try:
        import yaml
        data = yaml.safe_load(yaml_path.read_text(encoding="utf-8")) or {}
        return data.get("scope")
    except Exception:
        return None


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
    return flat, True


# ---------------------------------------------------------------------------
# Core: 2-pass spec integration (OpenSpec semantics)
# ---------------------------------------------------------------------------

def _integrate_specs(change_dir: Path, specs_dir: Path) -> None:
    """Integrate change specs into baseline specs directory.

    2-pass architecture for atomicity:
      Pass 1 (validate): read all specs, check for errors, collect operations
      Pass 2 (apply): REMOVED → MODIFIED → ADDED
    """
    scope = _read_scope(change_dir)
    if scope:
        specs_dir = specs_dir / scope

    specs_change_dir = change_dir / "specs"
    if not specs_change_dir.is_dir():
        return

    # === Pass 1: Validate (no writes) ===
    operations: list[_SpecOp] = []
    for entry in sorted(specs_change_dir.iterdir()):
        resolved = _resolve_change_spec(specs_change_dir, entry)
        if resolved is None:
            continue
        cap_name, spec_file = resolved
        text = spec_file.read_text(encoding="utf-8")
        target_spec, is_flat = _resolve_target_spec(specs_dir, cap_name)

        # Validate MODIFIED/ADDED constraints
        if not target_spec.exists():
            if _MODIFIED_RE.search(text):
                raise SpecIntegrationError(
                    f"'{cap_name}': target spec does not exist; "
                    "only ADDED requirements are allowed for new specs. "
                    "MODIFIED requires an existing spec."
                )
        else:
            existing_text = target_spec.read_text(encoding="utf-8")
            if _ADDED_RE.search(text):
                added_block = _extract_block(text, "## ADDED Requirements")
                _validate_no_duplicate_adds(existing_text, added_block, cap_name)
            if _MODIFIED_RE.search(text):
                modified_block = _extract_block(text, "## MODIFIED Requirements")
                # Dry-run replacement to validate requirement names exist
                _replace_requirements(existing_text, modified_block, cap_name)

        operations.append(_SpecOp(cap_name, text, target_spec, is_flat, specs_dir))

    # === Pass 2: Apply in order (REMOVED → MODIFIED → ADDED) ===

    # REMOVED first
    for op in operations:
        if _REMOVED_RE.search(op.text):
            if op.target_spec.exists():
                resolved_target = op.target_spec.resolve()
                resolved_specs = op.specs_dir.resolve()
                if resolved_specs != resolved_target.parent and resolved_specs not in resolved_target.parents:
                    print(f"Warning: Skipping removal of '{op.cap_name}': path outside specs_dir", file=sys.stderr)
                    continue
                if op.is_flat:
                    op.target_spec.unlink()
                else:
                    shutil.rmtree(op.target_spec.parent)
                print(f"- Removed spec '{op.cap_name}'")

    # MODIFIED second
    for op in operations:
        if _MODIFIED_RE.search(op.text):
            if op.target_spec.exists():
                modified_block = _extract_block(op.text, "## MODIFIED Requirements")
                existing = op.target_spec.read_text(encoding="utf-8")
                updated = _replace_requirements(existing, modified_block, op.cap_name)
                op.target_spec.write_text(updated, encoding="utf-8")
                print(f"- Integrated MODIFIED specs for '{op.cap_name}'")

    # ADDED last
    for op in operations:
        if _ADDED_RE.search(op.text):
            target_dir = op.target_spec.parent
            target_dir.mkdir(parents=True, exist_ok=True)
            added_block = _extract_block(op.text, "## ADDED Requirements")
            if op.target_spec.exists():
                with op.target_spec.open("a", encoding="utf-8") as f:
                    f.write("\n" + added_block)
            else:
                new_text = "## Requirements\n" + added_block
                op.target_spec.write_text(new_text, encoding="utf-8")
            print(f"- Integrated ADDED specs for '{op.cap_name}'")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

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
        try:
            _integrate_specs(change_dir, get_specs_dir(root))
        except SpecIntegrationError as e:
            print(f"Error: Spec integration failed: {e}", file=sys.stderr)
            print("Aborted. No files were changed.", file=sys.stderr)
            return 1

    archive_dir = get_changes_dir(root) / "archive"
    archive_dir.mkdir(parents=True, exist_ok=True)
    shutil.move(str(change_dir), str(archive_dir / name))
    print(f"✔ Archived change '{name}'")
    return 0
