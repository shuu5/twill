"""twl spec instructions <artifact> <name> - Get artifact build instructions."""

import json
import re
import sys
from pathlib import Path

from .paths import OpenspecNotFound, find_openspec_root, get_changes_dir

_TASK_RE = re.compile(r"^- \[(?P<done>[x ])\] (?P<desc>.+)$")

_ARTIFACTS = {
    "proposal": {
        "description": "Initial proposal document outlining the change",
        "outputPath": "proposal.md",
        "instruction": (
            "Create the proposal document that establishes WHY this change is needed.\n\n"
            "Sections:\n"
            "- **Why**: 1-2 sentences on the problem or opportunity.\n"
            "- **What Changes**: Bullet list of changes.\n"
            "- **Capabilities**: New and Modified capabilities.\n"
            "- **Impact**: Affected code, APIs, dependencies.\n\n"
            "Keep it concise (1-2 pages). Focus on the \"why\" not the \"how\"."
        ),
        "template": (
            "## Why\n\n## What Changes\n\n## Capabilities\n\n"
            "### New Capabilities\n\n### Modified Capabilities\n\n## Impact\n"
        ),
        "deps": [],
        "unlocks": ["design", "specs"],
    },
    "design": {
        "description": "Technical design document with implementation details",
        "outputPath": "design.md",
        "instruction": (
            "Create the design document that explains HOW to implement the change.\n\n"
            "Sections:\n"
            "- **Context**: Background and constraints\n"
            "- **Goals / Non-Goals**: Scope boundaries\n"
            "- **Decisions**: Key technical choices with rationale\n"
            "- **Risks / Trade-offs**: Known limitations"
        ),
        "template": (
            "## Context\n\n## Goals / Non-Goals\n\n"
            "**Goals:**\n\n**Non-Goals:**\n\n## Decisions\n\n## Risks / Trade-offs\n"
        ),
        "deps": ["proposal"],
        "unlocks": ["tasks"],
    },
    "specs": {
        "description": "Detailed specifications for the change",
        "outputPath": "specs/**/*.md",
        "instruction": (
            "Create specification files that define WHAT the system should do.\n\n"
            "Create one spec file per capability listed in the proposal.\n\n"
            "Format:\n"
            "- Delta headers: ## ADDED/MODIFIED/REMOVED/RENAMED Requirements\n"
            "- Each requirement: ### Requirement: <name>\n"
            "- Use SHALL/MUST for normative requirements\n"
            "- Each scenario: #### Scenario: <name> with WHEN/THEN format"
        ),
        "template": (
            "## ADDED Requirements\n\n"
            "### Requirement: <!-- name -->\n<!-- description -->\n\n"
            "#### Scenario: <!-- name -->\n"
            "- **WHEN** <!-- condition -->\n"
            "- **THEN** <!-- expected outcome -->\n"
        ),
        "deps": ["proposal"],
        "unlocks": ["tasks"],
    },
    "tasks": {
        "description": "Implementation checklist with trackable tasks",
        "outputPath": "tasks.md",
        "instruction": (
            "Create the task list that breaks down the implementation work.\n\n"
            "Guidelines:\n"
            "- Group related tasks under ## numbered headings\n"
            "- Each task MUST be a checkbox: - [ ] X.Y Task description\n"
            "- Tasks should be small enough to complete in one session\n"
            "- Order tasks by dependency"
        ),
        "template": (
            "## 1. <!-- Group -->\n\n- [ ] 1.1 <!-- Task -->\n\n"
            "## 2. <!-- Group -->\n\n- [ ] 2.1 <!-- Task -->\n"
        ),
        "deps": ["design", "specs"],
        "unlocks": [],
    },
}


def _dep_done(change_dir: Path, dep: str) -> bool:
    if dep == "proposal":
        return (change_dir / "proposal.md").exists()
    if dep == "design":
        return (change_dir / "design.md").exists()
    if dep == "specs":
        return any((change_dir / "specs").glob("*/spec.md")) if (change_dir / "specs").is_dir() else False
    return False


def _apply_instructions(name: str, change_dir: Path, schema_name: str, json_mode: bool) -> int:
    tasks_file = change_dir / "tasks.md"
    if not tasks_file.exists():
        if json_mode:
            print(json.dumps({"state": "blocked", "message": "tasks.md not found"}))
        else:
            print("tasks.md not found. Create artifacts first.")
        return 0

    tasks = []
    for line in tasks_file.read_text(encoding="utf-8").splitlines():
        m = _TASK_RE.match(line)
        if m:
            tasks.append({"description": m.group("desc"), "done": m.group("done") == "x"})

    total = len(tasks)
    complete = sum(1 for t in tasks if t["done"])
    remaining = total - complete
    state = "all_done" if remaining == 0 else "ready"

    print("- Generating apply instructions...")

    if json_mode:
        tasks_json = [
            {"id": i + 1, "description": t["description"], "done": t["done"]}
            for i, t in enumerate(tasks)
        ]
        out = {
            "changeName": name,
            "changeDir": str(change_dir),
            "schemaName": schema_name,
            "contextFiles": {
                "proposal": str(change_dir / "proposal.md"),
                "specs": str(change_dir / "specs/**/*.md"),
                "design": str(change_dir / "design.md"),
                "tasks": str(change_dir / "tasks.md"),
            },
            "progress": {"total": total, "complete": complete, "remaining": remaining},
            "tasks": tasks_json,
            "state": state,
            "instruction": (
                "Read context files, work through pending tasks, mark complete as you go.\n"
                "Pause if you hit blockers or need clarification."
            ),
        }
        print(json.dumps(out, indent=2))
    else:
        print(f"Change: {name}")
        print(f"Progress: {complete}/{total} tasks complete ({remaining} remaining)")
        print()
        for t in tasks:
            mark = "x" if t["done"] else " "
            print(f"[{mark}] {t['description']}")

    return 0


def cmd_instructions(artifact: str, name: str, json_mode: bool = False) -> int:
    try:
        root = find_openspec_root()
    except OpenspecNotFound as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    change_dir = get_changes_dir(root) / name
    if not change_dir.is_dir():
        print(f"Error: Change '{name}' not found", file=sys.stderr)
        return 1

    schema_name = "spec-driven"
    openspec_yaml = change_dir / ".openspec.yaml"
    if openspec_yaml.exists():
        for line in openspec_yaml.read_text(encoding="utf-8").splitlines():
            if line.startswith("schema:"):
                schema_name = line.split(":", 1)[1].strip()
                break

    if artifact == "apply":
        return _apply_instructions(name, change_dir, schema_name, json_mode)

    if artifact not in _ARTIFACTS:
        print(
            f"Error: Unknown artifact: {artifact}. Available: proposal, design, specs, tasks, apply",
            file=sys.stderr,
        )
        return 1

    art = _ARTIFACTS[artifact]

    if json_mode:
        print("- Generating instructions...")
        deps_list = []
        for dep in art["deps"]:
            done = _dep_done(change_dir, dep)
            path_map = {
                "proposal": "proposal.md",
                "design": "design.md",
                "specs": "specs/**/*.md",
            }
            deps_list.append({"id": dep, "done": done, "path": path_map[dep]})

        out = {
            "changeName": name,
            "artifactId": artifact,
            "schemaName": schema_name,
            "changeDir": str(change_dir),
            "outputPath": art["outputPath"],
            "description": art["description"],
            "instruction": art["instruction"],
            "template": art["template"],
            "dependencies": deps_list,
            "unlocks": art["unlocks"],
        }
        print(json.dumps(out, indent=2))
    else:
        print(f"Artifact: {artifact}")
        print(f"Output: {art['outputPath']}")
        print(f"Description: {art['description']}")
        print()
        print(art["instruction"])

    return 0
