"""twl spec validate [name] - Validate delta spec syntax."""

import json
import re
import sys
import time
from pathlib import Path

from .new import _KEBAB_RE
from .paths import OpenspecNotFound, find_deltaspec_root, get_changes_dir

_DELTA_HDR_RE = re.compile(r"^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements", re.MULTILINE)
_REQ_RE = re.compile(r"^### Requirement:", re.MULTILINE)
_SHALL_MUST_RE = re.compile(r"\b(SHALL|MUST)\b")


def _validate_change(change_dir: Path) -> list[str]:
    issues: list[str] = []
    specs_dir = change_dir / "specs"
    if not specs_dir.is_dir():
        return issues

    for spec_file in sorted(specs_dir.glob("*/spec.md")):
        cap = spec_file.parent.name
        text = spec_file.read_text(encoding="utf-8")

        if not _DELTA_HDR_RE.search(text):
            issues.append(f"{cap}: Missing delta header (ADDED/MODIFIED/REMOVED/RENAMED Requirements)")

        if not _REQ_RE.search(text):
            issues.append(f"{cap}: Missing '### Requirement:' prefix")
            continue

        # Check SHALL/MUST and Scenario per requirement block
        lines = text.splitlines()
        in_req = False
        req_name = ""
        has_keyword = False
        has_scenario = False

        for line in lines:
            if line.startswith("### Requirement:"):
                if in_req:
                    if not has_keyword:
                        issues.append(f"{cap}: Requirement '{req_name}' missing SHALL/MUST keyword")
                    if not has_scenario:
                        issues.append(f"{cap}: Requirement '{req_name}' missing #### Scenario: block")
                in_req = True
                req_name = line[len("### Requirement:"):].strip()
                has_keyword = False
                has_scenario = False
            elif in_req:
                if line.startswith("#### Scenario:"):
                    has_scenario = True
                if _SHALL_MUST_RE.search(line):
                    has_keyword = True

        if in_req:
            if not has_keyword:
                issues.append(f"{cap}: Requirement '{req_name}' missing SHALL/MUST keyword")
            if not has_scenario:
                issues.append(f"{cap}: Requirement '{req_name}' missing #### Scenario: block")

    return issues


def cmd_validate(
    name: str | None = None,
    validate_all: bool = False,
    json_mode: bool = False,
) -> int:
    if name and not _KEBAB_RE.match(name):
        print(f"Error: Change name must be kebab-case: {name}", file=sys.stderr)
        return 1

    try:
        root = find_deltaspec_root()
    except OpenspecNotFound as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    changes_dir = get_changes_dir(root)

    targets: list[str] = []
    if validate_all:
        if changes_dir.is_dir():
            for d in sorted(changes_dir.iterdir()):
                if d.is_dir() and d.name != "archive":
                    targets.append(d.name)
    elif name:
        targets.append(name)
    else:
        print("Error: Usage: twl spec validate <name> [--all]", file=sys.stderr)
        return 1

    total_items = 0
    passed = 0
    failed = 0
    json_items: list[dict] = []

    for target_name in targets:
        change_dir = changes_dir / target_name
        if not change_dir.is_dir():
            print(f"Warning: Change '{target_name}' not found, skipping.", file=sys.stderr)
            continue

        total_items += 1
        start_ms = int(time.time() * 1000)
        issues = _validate_change(change_dir)
        duration_ms = max(0, int(time.time() * 1000) - start_ms)
        valid = len(issues) == 0

        if valid:
            passed += 1
        else:
            failed += 1

        if json_mode:
            json_items.append({
                "id": target_name,
                "type": "change",
                "valid": valid,
                "issues": issues,
                "durationMs": duration_ms,
            })
        else:
            if valid:
                print(f"✔ {target_name}: valid")
            else:
                print(f"✘ {target_name}: {len(issues)} issue(s)")
                for issue in issues:
                    print(f"  - {issue}")

    if json_mode:
        out = {
            "items": json_items,
            "summary": {
                "totals": {"items": total_items, "passed": passed, "failed": failed},
                "byType": {
                    "change": {"items": total_items, "passed": passed, "failed": failed}
                },
            },
            "version": "1.0",
        }
        print(json.dumps(out, indent=2))
    else:
        print()
        print(f"Summary: {passed} passed, {failed} failed out of {total_items}")

    return 0 if failed == 0 else 1
