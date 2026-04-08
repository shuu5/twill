"""chain/viz.py — chain フロー可視化（Mermaid flowchart TD）。

Usage:
    twl chain viz <chain-name>
    twl chain viz --all [--update-readme]
"""
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from twl.core.plugin import get_plugin_root, load_deps


README_MARKER_START = "<!-- CHAIN-FLOW-START -->"
README_MARKER_END = "<!-- CHAIN-FLOW-END -->"

# dispatch_mode → Mermaid classDef name
_DISPATCH_CLASS: Dict[str, str] = {
    "runner": "script",
    "script": "script",
    "trigger": "script",
    "llm": "llm",
    "composite": "composite",
    "marker": "marker",
}


def _safe_mermaid_label(text: str) -> str:
    """Escape text for use inside Mermaid node labels (quoted form)."""
    return text.replace('"', "'").replace("[", "&#91;").replace("]", "&#93;")

# QUICK_SKIP_STEPS は autopilot.chain からインポート（循環回避のためローカル定義も保持）
_QUICK_SKIP_STEPS_FALLBACK: frozenset = frozenset([
    "crg-auto-build",
    "arch-ref",
    "change-propose",
    "ac-extract",
    "change-id-resolve",
    "test-scaffold",
    "check",
    "change-apply",
])


def _get_quick_skip_steps() -> frozenset:
    try:
        from twl.autopilot.chain import QUICK_SKIP_STEPS
        return QUICK_SKIP_STEPS
    except ImportError:
        return _QUICK_SKIP_STEPS_FALLBACK


def _safe_node_id(chain_name: str, step_name: str) -> str:
    """Mermaid ノード ID をサニタイズ"""
    chain_safe = re.sub(r'[^a-zA-Z0-9]', '_', chain_name)
    step_safe = re.sub(r'[^a-zA-Z0-9]', '_', step_name)
    return f"{chain_safe}__{step_safe}"


def _get_dispatch_class(step_name: str, all_components: Dict) -> str:
    """コンポーネントの dispatch_mode から classDef 名を返す。未定義は 'unknown'。"""
    comp = all_components.get(step_name)
    if comp is None:
        return "unknown"
    mode = comp[1].get("dispatch_mode")
    if mode is None:
        return "unknown"
    return _DISPATCH_CLASS.get(mode, "unknown")


def _build_all_components(deps: dict) -> Dict[str, Tuple[str, dict]]:
    all_components: Dict[str, Tuple[str, dict]] = {}
    for section in ("skills", "commands", "agents"):
        for comp_name, data in deps.get(section, {}).items():
            all_components[comp_name] = (section, data)
    return all_components


def chain_viz_single(deps: dict, chain_name: str) -> str:
    """単一 chain の Mermaid フロー図を生成して返す。"""
    chains = deps.get("chains", {})
    chain_data = chains.get(chain_name)
    if chain_data is None or not isinstance(chain_data, dict):
        return f"# Error: chain '{chain_name}' not found\n"

    steps = chain_data.get("steps", [])
    if not isinstance(steps, list):
        steps = []

    all_components = _build_all_components(deps)
    quick_skip = _get_quick_skip_steps()

    lines: List[str] = []
    lines.append("```mermaid")
    lines.append("flowchart TD")
    lines.append("")

    # subgraph
    chain_label = _safe_mermaid_label(chain_name)
    lines.append(f'    subgraph {re.sub(r"[^a-zA-Z0-9]", "_", chain_name)}["{chain_label} chain"]')

    valid_steps = [s for s in steps if isinstance(s, str)]

    for step in valid_steps:
        node_id = _safe_node_id(chain_name, step)
        step_label = _safe_mermaid_label(step)
        cls = _get_dispatch_class(step, all_components)
        if cls != "unknown":
            lines.append(f'        {node_id}["{step_label}"]:::{cls}')
        else:
            lines.append(f'        {node_id}["{step_label}"]')

    lines.append("    end")
    lines.append("")

    # 通常フロー矢印
    for i in range(len(valid_steps) - 1):
        src_id = _safe_node_id(chain_name, valid_steps[i])
        dst_id = _safe_node_id(chain_name, valid_steps[i + 1])
        lines.append(f"    {src_id} --> {dst_id}")

    # quick バイパス（破線）: quick_skip ステップを迂回する矢印
    # 先頭の非スキップ → 連続スキップ後の非スキップ への破線
    _append_quick_bypasses(lines, chain_name, valid_steps, quick_skip)

    lines.append("")
    _append_classdefs(lines)
    lines.append("```")

    return "\n".join(lines)


def _append_quick_bypasses(
    lines: List[str],
    chain_name: str,
    steps: List[str],
    quick_skip: frozenset,
) -> None:
    """quick バイパス（破線）矢印を追加する。

    連続する quick_skip ステップ群の直前→直後ノードへ破線を引く。
    """
    if not steps:
        return

    i = 0
    while i < len(steps):
        if steps[i] not in quick_skip:
            # steps[i] が非スキップ。この直後に quick_skip が始まるか確認
            j = i + 1
            while j < len(steps) and steps[j] in quick_skip:
                j += 1
            # i+1 から j-1 が全て quick_skip、j が次の非スキップ
            if j > i + 1 and j < len(steps):
                # バイパス矢印: steps[i] → steps[j]
                src_id = _safe_node_id(chain_name, steps[i])
                dst_id = _safe_node_id(chain_name, steps[j])
                lines.append(f"    {src_id} -. quick .-> {dst_id}")
            i = j
        else:
            i += 1


def chain_viz_all(deps: dict) -> str:
    """全 chain を結合した Mermaid フロー図を生成する。"""
    chains = deps.get("chains", {})
    if not chains:
        return "# No chains found\n"

    all_components = _build_all_components(deps)
    quick_skip = _get_quick_skip_steps()

    lines: List[str] = []
    lines.append("```mermaid")
    lines.append("flowchart TD")
    lines.append("")

    # 各 chain を subgraph として描画
    chain_last_steps: Dict[str, Optional[str]] = {}  # chain名 → 最後のステップ名

    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            continue
        steps = chain_data.get("steps", [])
        if not isinstance(steps, list):
            steps = []
        valid_steps = [s for s in steps if isinstance(s, str)]

        chain_label = _safe_mermaid_label(chain_name)
        chain_id = re.sub(r"[^a-zA-Z0-9]", "_", chain_name)
        lines.append(f'    subgraph {chain_id}["{chain_label} chain"]')

        for step in valid_steps:
            node_id = _safe_node_id(chain_name, step)
            step_label = _safe_mermaid_label(step)
            cls = _get_dispatch_class(step, all_components)
            if cls != "unknown":
                lines.append(f'        {node_id}["{step_label}"]:::{cls}')
            else:
                lines.append(f'        {node_id}["{step_label}"]')

        lines.append("    end")
        lines.append("")

        chain_last_steps[chain_name] = valid_steps[-1] if valid_steps else None

    # 通常フロー矢印（各 chain 内）
    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            continue
        steps = chain_data.get("steps", [])
        valid_steps = [s for s in steps if isinstance(s, str)]
        for i in range(len(valid_steps) - 1):
            src_id = _safe_node_id(chain_name, valid_steps[i])
            dst_id = _safe_node_id(chain_name, valid_steps[i + 1])
            lines.append(f"    {src_id} --> {dst_id}")

        _append_quick_bypasses(lines, chain_name, valid_steps, quick_skip)

    lines.append("")

    # ワークフロー間の遷移矢印（setup → test-ready → pr-verify → pr-fix → pr-merge）
    _chain_transition_order = ["setup", "test-ready", "pr-verify", "pr-fix", "pr-merge"]
    present_chains = [c for c in _chain_transition_order if c in chain_last_steps and chain_last_steps[c]]

    for i in range(len(present_chains) - 1):
        src_chain = present_chains[i]
        dst_chain = present_chains[i + 1]
        src_last = chain_last_steps[src_chain]
        dst_data = chains.get(dst_chain)
        if not isinstance(dst_data, dict):
            continue
        dst_steps = dst_data.get("steps", [])
        dst_valid = [s for s in dst_steps if isinstance(s, str)]
        if src_last and dst_valid:
            src_id = _safe_node_id(src_chain, src_last)
            dst_id = _safe_node_id(dst_chain, dst_valid[0])
            lines.append(f"    {src_id} --> {dst_id}")

    lines.append("")
    _append_classdefs(lines)
    lines.append("```")

    return "\n".join(lines)


def _append_classdefs(lines: List[str]) -> None:
    lines.append("    classDef script fill:#c8e6c9,stroke:#4caf50")
    lines.append("    classDef llm fill:#bbdefb,stroke:#1976d2")
    lines.append("    classDef composite fill:#e1bee7,stroke:#7b1fa2")
    lines.append("    classDef marker fill:#eeeeee,stroke:#9e9e9e")


def update_readme_chain_flow(plugin_root: Path, mermaid_content: str) -> bool:
    """README.md の CHAIN-FLOW セクションを更新する。

    Returns:
        True if updated, False if markers not found.
    """
    readme_path = plugin_root / "README.md"
    if not readme_path.exists():
        print(f"Error: README.md not found at {readme_path}", file=sys.stderr)
        return False

    content = readme_path.read_text(encoding="utf-8")
    start_idx = content.find(README_MARKER_START)
    end_idx = content.find(README_MARKER_END)

    if start_idx == -1 or end_idx == -1:
        print(f"Error: CHAIN-FLOW markers not found in README.md", file=sys.stderr)
        print(f"  Add the following markers to README.md:")
        print(f"    {README_MARKER_START}")
        print(f"    {README_MARKER_END}")
        return False

    if start_idx >= end_idx:
        print(f"Error: Invalid CHAIN-FLOW marker positions", file=sys.stderr)
        return False

    new_content = (
        content[: start_idx + len(README_MARKER_START)]
        + "\n\n"
        + mermaid_content
        + "\n\n"
        + content[end_idx:]
    )
    readme_path.write_text(new_content, encoding="utf-8")
    print(f"Updated README.md CHAIN-FLOW section")
    return True


def handle_chain_viz_subcommand(argv: list) -> None:
    """twl chain viz サブコマンドを処理する。"""
    import argparse

    parser = argparse.ArgumentParser(
        prog="twl chain viz",
        description="Generate Mermaid flowchart for chain(s) from deps.yaml",
    )
    parser.add_argument(
        "chain_name",
        nargs="?",
        default=None,
        help="Name of the chain to visualize",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        dest="all_chains",
        help="Visualize all chains in one combined flowchart",
    )
    parser.add_argument(
        "--update-readme",
        action="store_true",
        help="Embed flowchart into README.md between CHAIN-FLOW markers",
    )

    args = parser.parse_args(argv)

    if args.all_chains and args.chain_name:
        print("Error: --all and chain name are mutually exclusive", file=sys.stderr)
        sys.exit(1)

    if not args.all_chains and not args.chain_name:
        parser.print_usage(sys.stderr)
        print("Error: either chain name or --all is required", file=sys.stderr)
        sys.exit(1)

    plugin_root = get_plugin_root()
    deps = load_deps(plugin_root)

    if args.all_chains:
        output = chain_viz_all(deps)
    else:
        chains = deps.get("chains", {})
        if args.chain_name not in chains:
            print(f"Error: Chain '{args.chain_name}' not found in deps.yaml", file=sys.stderr)
            sys.exit(1)
        output = chain_viz_single(deps, args.chain_name)

    print(output)

    if args.update_readme:
        if not update_readme_chain_flow(plugin_root, output):
            sys.exit(1)
