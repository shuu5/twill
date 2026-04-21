"""twl chain export — regenerate computed artifacts from chain.py SSOT.

Usage:
    twl chain export --yaml [--write] [--plugin-root PATH]
    twl chain export --shell [--write] [--plugin-root PATH]

Feature flag:
    TWL_CHAIN_SSOT_MODE=chain.py   (default) — export from chain.py
    TWL_CHAIN_SSOT_MODE=deps.yaml             — fallback, print warning only
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

import yaml

from twl.autopilot.chain import export_chain_steps_sh, export_deps_chains
from twl.core.plugin import get_plugin_root, load_deps


def _get_ssot_mode() -> str:
    return os.environ.get("TWL_CHAIN_SSOT_MODE", "chain.py")


def _update_deps_yaml_chains(plugin_root: Path, deps: dict[str, Any]) -> str:
    """Return updated deps.yaml text with chains: section replaced from chain.py."""
    chains = export_deps_chains()
    deps_path = plugin_root / "deps.yaml"
    original = deps_path.read_text(encoding="utf-8")

    # Locate the chains: block start
    lines = original.splitlines(keepends=True)
    chain_start = None
    for i, line in enumerate(lines):
        if line.rstrip() == "chains:":
            chain_start = i
            break

    if chain_start is None:
        return original  # no chains section to replace

    # Find the end of the chains: block (next top-level key or EOF)
    chain_end = len(lines)
    for i in range(chain_start + 1, len(lines)):
        stripped = lines[i].rstrip()
        if stripped and not stripped.startswith(" ") and not stripped.startswith("\t") and not stripped.startswith("#"):
            chain_end = i
            break

    # Build replacement lines
    new_chains_lines: list[str] = []
    new_chains_lines.append("# チェーン（chain.py から生成 — twl chain export --yaml で再生成）\n")
    new_chains_lines.append("chains:\n")

    # Preserve workflow order from deps.yaml, then add any new ones from chain.py
    existing_order = list(deps.get("chains", {}).keys())
    chain_order = existing_order + [k for k in chains if k not in existing_order]

    for workflow in chain_order:
        if workflow not in chains:
            continue
        data = chains[workflow]
        new_chains_lines.append(f"  {workflow}:\n")
        new_chains_lines.append(f'    type: "{data["type"]}"\n')
        new_chains_lines.append(f'    description: "{data["description"]}"\n')
        new_chains_lines.append("    steps:\n")
        for step in data["steps"]:
            new_chains_lines.append(f"      - {step}\n")
        new_chains_lines.append("\n")

    updated = lines[:chain_start] + new_chains_lines + lines[chain_end:]
    return "".join(updated)


def handle_chain_export_subcommand(argv: list[str]) -> int:
    """Handle `twl chain export` subcommand. Returns exit code."""
    parser = argparse.ArgumentParser(
        prog="twl chain export",
        description="Regenerate computed artifacts from chain.py SSOT",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--yaml", action="store_true", help="Export deps.yaml chains: section")
    group.add_argument("--shell", action="store_true", help="Export chain-steps.sh bash variables")
    parser.add_argument("--write", action="store_true", help="Write output to file (default: stdout)")
    parser.add_argument(
        "--plugin-root",
        default=None,
        help="Plugin root directory (auto-detected from CWD if omitted)",
    )

    args = parser.parse_args(argv)

    mode = _get_ssot_mode()
    if mode != "chain.py":
        print(
            f"⚠️  TWL_CHAIN_SSOT_MODE={mode}: chain.py は SSoT として使用されていません。"
            " `TWL_CHAIN_SSOT_MODE=chain.py` を設定してください。",
            file=sys.stderr,
        )
        return 1

    if args.plugin_root is not None:
        plugin_root = Path(args.plugin_root)
        if not (plugin_root / "deps.yaml").exists():
            print(f"Error: deps.yaml not found in --plugin-root: {plugin_root}", file=sys.stderr)
            return 1
    else:
        plugin_root = get_plugin_root()

    deps = load_deps(plugin_root)

    if args.yaml:
        content = _update_deps_yaml_chains(plugin_root, deps)
        if args.write:
            (plugin_root / "deps.yaml").write_text(content, encoding="utf-8")
            print(f"✓ deps.yaml chains: セクションを再生成しました ({plugin_root / 'deps.yaml'})")
        else:
            print(content, end="")

    elif args.shell:
        content = export_chain_steps_sh()
        target = plugin_root / "scripts" / "chain-steps.sh"
        if args.write:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            print(f"✓ chain-steps.sh を再生成しました ({target})")
        else:
            print(content, end="")

    return 0
