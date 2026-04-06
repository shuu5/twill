"""twl spec status <name> - Show artifact completion status."""

import json
import sys
from pathlib import Path

from .new import _KEBAB_RE
from .paths import OpenspecNotFound, find_deltaspec_root, get_changes_dir


def _has_specs(change_dir: Path) -> bool:
    specs_dir = change_dir / "specs"
    if not specs_dir.is_dir():
        return False
    return any(specs_dir.glob("*/spec.md"))


def _build_status(change_dir: Path) -> dict:
    proposal_done = (change_dir / "proposal.md").exists()
    design_done = (change_dir / "design.md").exists()
    specs_done = _has_specs(change_dir)
    tasks_done = (change_dir / "tasks.md").exists()

    proposal_status = "done" if proposal_done else "ready"

    if proposal_done:
        design_status = "done" if design_done else "ready"
        specs_status = "done" if specs_done else "ready"
    else:
        design_status = "done" if design_done else "blocked"
        specs_status = "done" if specs_done else "blocked"

    if design_done and specs_done:
        tasks_status = "done" if tasks_done else "ready"
    else:
        tasks_status = "done" if tasks_done else "blocked"

    is_complete = proposal_done and design_done and specs_done and tasks_done

    return {
        "proposal_done": proposal_done,
        "design_done": design_done,
        "specs_done": specs_done,
        "tasks_done": tasks_done,
        "proposal_status": proposal_status,
        "design_status": design_status,
        "specs_status": specs_status,
        "tasks_status": tasks_status,
        "is_complete": is_complete,
    }


def cmd_status(name: str, json_mode: bool = False, schema_name: str = "spec-driven") -> int:
    if not _KEBAB_RE.match(name):
        print(f"Error: Change name must be kebab-case: {name}", file=sys.stderr)
        return 1

    try:
        root = find_deltaspec_root()
    except OpenspecNotFound as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    change_dir = get_changes_dir(root) / name
    if not change_dir.is_dir():
        print(f"Error: Change '{name}' not found", file=sys.stderr)
        return 1

    # Read schema from .deltaspec.yaml if present
    deltaspec_yaml = change_dir / ".deltaspec.yaml"
    if deltaspec_yaml.exists():
        for line in deltaspec_yaml.read_text(encoding="utf-8").splitlines():
            if line.startswith("schema:"):
                schema_name = line.split(":", 1)[1].strip()
                break

    s = _build_status(change_dir)
    done_count = sum([s["proposal_done"], s["design_done"], s["specs_done"], s["tasks_done"]])

    print("- Loading change status...")

    if json_mode:
        artifacts = [
            {"id": "proposal", "outputPath": "proposal.md", "status": s["proposal_status"]},
        ]
        design_entry: dict = {"id": "design", "outputPath": "design.md", "status": s["design_status"]}
        if s["design_status"] == "blocked":
            design_entry["missingDeps"] = ["proposal"]
        artifacts.append(design_entry)

        specs_entry: dict = {"id": "specs", "outputPath": "specs/**/*.md", "status": s["specs_status"]}
        if s["specs_status"] == "blocked":
            specs_entry["missingDeps"] = ["proposal"]
        artifacts.append(specs_entry)

        tasks_entry: dict = {"id": "tasks", "outputPath": "tasks.md", "status": s["tasks_status"]}
        if s["tasks_status"] == "blocked":
            missing = []
            if not s["design_done"]:
                missing.append("design")
            if not s["specs_done"]:
                missing.append("specs")
            if missing:
                tasks_entry["missingDeps"] = missing
        artifacts.append(tasks_entry)

        out = {
            "changeName": name,
            "schemaName": schema_name,
            "isComplete": s["is_complete"],
            "applyRequires": ["tasks"],
            "artifacts": artifacts,
        }
        print(json.dumps(out, indent=2))
    else:
        print(f"Change: {name}")
        print(f"Schema: {schema_name}")
        print(f"Progress: {done_count}/4 artifacts complete")
        print()
        print(f"[{'x' if s['proposal_done'] else ' '}] proposal")
        print(f"[{'x' if s['design_done'] else ' '}] design")
        print(f"[{'x' if s['specs_done'] else ' '}] specs")
        print(f"[{'x' if s['tasks_done'] else ' '}] tasks")
        print()
        if s["is_complete"]:
            print("All artifacts complete!")
        else:
            print("Some artifacts still pending.")

    return 0
