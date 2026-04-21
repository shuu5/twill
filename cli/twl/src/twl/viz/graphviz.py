import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.graph import classify_layers, collect_reachable_nodes, generate_ordering_edges


README_MARKER_START = "<!-- DEPS-GRAPH-START -->"
README_MARKER_END = "<!-- DEPS-GRAPH-END -->"
README_SUBGRAPH_START = "<!-- DEPS-SUBGRAPHS-START -->"
README_SUBGRAPH_END = "<!-- DEPS-SUBGRAPHS-END -->"
README_ENTRY_POINTS_START = "<!-- ENTRY-POINTS-START -->"
README_ENTRY_POINTS_END = "<!-- ENTRY-POINTS-END -->"

_TYPE_HEADING = {
    "controller": "Controllers",
    "supervisor": "Supervisors",
    "workflow": "Workflows",
}
_TYPE_COL = {
    "controller": "Controller",
    "supervisor": "Supervisor",
    "workflow": "Workflow",
}


def generate_entry_points_table(deps: dict, plugin_name: str) -> str:
    """deps.yaml の entry_points から Entry Points テーブルを生成"""
    entry_point_paths = deps.get("entry_points", [])
    if not entry_point_paths:
        return ""

    # パスからスキル名を抽出して skills セクションと照合
    skills = deps.get("skills", {})
    by_type: Dict[str, List[tuple]] = {}
    for path in entry_point_paths:
        # "skills/co-autopilot/SKILL.md" -> "co-autopilot"
        parts = str(path).split("/")
        if len(parts) >= 2:
            skill_name = parts[1] if parts[0] in ("skills", "refs") else parts[0]
        else:
            skill_name = parts[0].replace(".md", "").replace("SKILL", "")

        skill_data = skills.get(skill_name, {})
        skill_type = skill_data.get("type", "controller")
        description = skill_data.get("description", "")

        by_type.setdefault(skill_type, []).append((skill_name, description))

    lines = []
    for type_key in ("controller", "supervisor", "workflow"):
        entries = by_type.get(type_key)
        if not entries:
            continue
        heading = _TYPE_HEADING.get(type_key, type_key.capitalize() + "s")
        col = _TYPE_COL.get(type_key, type_key.capitalize())
        lines.append(f"### {heading}")
        lines.append("")
        lines.append(f"| {col} | 説明 |")
        lines.append("|---|---|")
        for skill_name, description in entries:
            lines.append(f"| {skill_name} | {description} |")
        lines.append("")

    # 未知タイプも出力
    for type_key, entries in by_type.items():
        if type_key in ("controller", "supervisor", "workflow"):
            continue
        heading = type_key.capitalize() + "s"
        lines.append(f"### {heading}")
        lines.append("")
        lines.append(f"| Name | 説明 |")
        lines.append("|---|---|")
        for skill_name, description in entries:
            lines.append(f"| {skill_name} | {description} |")
        lines.append("")

    return "\n".join(lines)


def generate_graphviz(graph: Dict, deps: dict, plugin_name: str, show_tokens: bool = True) -> str:
    """Graphviz DOT形式でグラフを生成"""
    lines = []
    lines.append("digraph Dependencies {")
    lines.append("    // Graph settings")
    lines.append("    rankdir=LR;")
    lines.append("    ranksep=0.8;")
    lines.append("    nodesep=0.3;")
    lines.append("    fontname=\"Helvetica\";")
    lines.append("    node [fontname=\"Helvetica\", fontsize=10];")
    lines.append("    edge [fontname=\"Helvetica\", fontsize=9];")
    lines.append("")

    def format_label(name: str, tokens: int, prefix: str = "") -> str:
        label = f"{prefix}{name}" if prefix else name
        if show_tokens and tokens > 0:
            return f"{label}\\n({tokens:,} tok)"
        return label

    def safe_id(name: str) -> str:
        return name.replace('-', '_').replace(':', '_').replace('.', '_')

    layers = classify_layers(deps, graph)

    # === ノード定義 ===
    lines.append("    // L0: Controller Skills")
    for skill_name in layers['controllers']:
        sid = safe_id(f"skill_{skill_name}")
        node_id = f"skill:{skill_name}"
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(skill_name, tokens, f"{plugin_name}:")
        lines.append(f'    {sid} [label="{label}", shape=ellipse, style=filled, fillcolor="#c8e6c9"];')
    lines.append("")

    lines.append("    // L0: Launchers")
    for cmd_name in layers['launchers']:
        cid = safe_id(f"cmd_{cmd_name}")
        node_id = f"command:{cmd_name}"
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(cmd_name, tokens)
        lines.append(f'    {cid} [label="{label}", shape=box, style="filled,rounded", fillcolor="#a5d6a7"];')
    lines.append("")

    lines.append("    // L0.5: Workflow Skills")
    for skill_name in layers['workflows']:
        sid = safe_id(f"skill_{skill_name}")
        node_id = f"skill:{skill_name}"
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(skill_name, tokens, f"{plugin_name}:")
        lines.append(f'    {sid} [label="{label}", shape=ellipse, style=filled, fillcolor="#e8f5e9"];')
    lines.append("")

    lines.append("    // Reference Skills")
    for skill_name in layers['references']:
        sid = safe_id(f"skill_{skill_name}")
        node_id = f"skill:{skill_name}"
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(skill_name, tokens, f"{plugin_name}:")
        lines.append(f'    {sid} [label="{label}", shape=note, style=filled, fillcolor="#e1f5fe"];')
    lines.append("")

    lines.append("    // L1: Direct Commands")
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        # redirects_to を持つがlauncher以外をスキップ（launcherはL0で別途描画）
        if cmd_data.get('redirects_to') and cmd_data.get('type') != 'launcher':
            continue
        # launcher は L0 で既に描画済み
        if cmd_data.get('type') == 'launcher':
            continue
        if cmd_name in layers['direct_commands']:
            cid = safe_id(f"cmd_{cmd_name}")
            node_id = f"command:{cmd_name}"
            tokens = graph.get(node_id, {}).get('tokens', 0)
            label = format_label(cmd_name, tokens)
            cmd_type = cmd_data.get('type', 'atomic')
            if cmd_type == 'composite':
                lines.append(f'    {cid} [label="{label}", shape=box, style=filled, fillcolor="#bbdefb"];')
            else:
                lines.append(f'    {cid} [label="{label}", shape=box, style=filled, fillcolor="#e3f2fd"];')
    lines.append("")

    lines.append("    // L2: Sub Commands")
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        if cmd_data.get('redirects_to'):
            continue
        is_sub = cmd_name in layers['sub_commands'] or cmd_name in layers['orphan_commands']
        if is_sub and cmd_name not in layers['direct_commands']:
            cid = safe_id(f"cmd_{cmd_name}")
            node_id = f"command:{cmd_name}"
            tokens = graph.get(node_id, {}).get('tokens', 0)
            label = format_label(cmd_name, tokens)
            if cmd_name in layers['orphan_commands']:
                lines.append(f'    {cid} [label="{label}", shape=box, style=filled, fillcolor="#ffcdd2"];')
            else:
                lines.append(f'    {cid} [label="{label}", shape=box, style=filled, fillcolor="#fff3e0"];')
    lines.append("")

    lines.append("    // L3: Agents")
    for agent_name, agent_data in deps.get('agents', {}).items():
        aid = safe_id(f"agent_{agent_name}")
        node_id = f"agent:{agent_name}"
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(agent_name, tokens)
        agent_type = agent_data.get('type', 'specialist')
        conditional = agent_data.get('conditional')
        if agent_type == 'orchestrator':
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style="filled,bold", fillcolor="#f3e5f5"];')
        elif conditional:
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style="filled,dashed", fillcolor="#f3e5f5"];')
        else:
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style=filled, fillcolor="#ede7f6"];')
    lines.append("")

    lines.append("    // L3.5: Scripts")
    for script_name in layers['scripts']:
        scid = safe_id(f"script_{script_name}")
        node_id = f"script:{script_name}"
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(script_name, tokens)
        lines.append(f'    {scid} [label="{label}", shape=hexagon, style=filled, fillcolor="#FF9800"];')
    lines.append("")

    lines.append("    // L4: External")
    for ext_name in layers['externals']:
        eid = safe_id(f"ext_{ext_name}")
        lines.append(f'    {eid} [label="{ext_name}", shape=parallelogram, style=filled, fillcolor="#eceff1"];')
    lines.append("")

    # === rank=same で層制御 ===
    lines.append("    // Layer constraints")

    # L0: launchers + controllers を同じ層に配置
    launcher_ids = [safe_id(f"cmd_{c}") for c in layers['launchers']]
    controller_ids = [safe_id(f"skill_{s}") for s in layers['controllers']]
    if launcher_ids or controller_ids:
        all_l0 = launcher_ids + controller_ids
        lines.append(f"    {{ rank=same; {'; '.join(all_l0)}; }}")

    workflow_ids = [safe_id(f"skill_{s}") for s in layers['workflows']]
    orchestrator_ids = [safe_id(f"agent_{a}") for a in layers['orchestrators']]
    if workflow_ids or orchestrator_ids:
        all_wf = workflow_ids + orchestrator_ids
        lines.append(f"    {{ rank=same; {'; '.join(all_wf)}; }}")

    if layers['references']:
        l_ids = [safe_id(f"skill_{s}") for s in layers['references']]
        lines.append(f"    {{ rank=same; {'; '.join(l_ids)}; }}")

    l1_ids = []
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        if cmd_data.get('redirects_to'):
            continue
        if cmd_name in layers['direct_commands']:
            l1_ids.append(safe_id(f"cmd_{cmd_name}"))
    if l1_ids:
        lines.append(f"    {{ rank=same; {'; '.join(l1_ids)}; }}")

    l2_ids = []
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        if cmd_data.get('redirects_to'):
            continue
        is_sub = cmd_name in layers['sub_commands'] or cmd_name in layers['orphan_commands']
        if is_sub and cmd_name not in layers['direct_commands']:
            l2_ids.append(safe_id(f"cmd_{cmd_name}"))
    if l2_ids:
        lines.append(f"    {{ rank=same; {'; '.join(l2_ids)}; }}")

    l3_ids = [safe_id(f"agent_{a}") for a in deps.get('agents', {}) if a not in layers['orchestrators']]
    if l3_ids:
        lines.append(f"    {{ rank=same; {'; '.join(l3_ids)}; }}")

    script_ids = [safe_id(f"script_{s}") for s in layers['scripts']]
    if script_ids:
        lines.append(f"    {{ rank=same; {'; '.join(script_ids)}; }}")

    l4_ids = [safe_id(f"ext_{e}") for e in layers['externals']]
    if l4_ids:
        lines.append(f"    {{ rank=same; {'; '.join(l4_ids)}; }}")

    lines.append("")

    # === エッジ定義 ===
    lines.append("    // Edges")

    # launcher -> skill (redirects_to で接続)
    for cmd_name in layers['launchers']:
        cmd_data = deps['commands'][cmd_name]
        redirects_to = cmd_data.get('redirects_to', '')
        if redirects_to.startswith('skill:'):
            target_skill = redirects_to[6:]  # "skill:" を除去
            cmd_id = safe_id(f"cmd_{cmd_name}")
            skill_id = safe_id(f"skill_{target_skill}")
            lines.append(f"    {cmd_id} -> {skill_id};")

    # skill -> skills/commands/agents
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_id = safe_id(f"skill_{skill_name}")
        for call in skill_data.get('calls', []):
            if call.get('skill'):
                target_id = safe_id(f"skill_{call['skill']}")
                lines.append(f"    {skill_id} -> {target_id};")
            elif call.get('reference'):
                target_id = safe_id(f"skill_{call['reference']}")
                lines.append(f"    {skill_id} -> {target_id};")
            elif call.get('workflow'):
                target_id = safe_id(f"skill_{call['workflow']}")
                lines.append(f"    {skill_id} -> {target_id};")
            elif call.get('controller'):
                target_id = safe_id(f"skill_{call['controller']}")
                lines.append(f"    {skill_id} -> {target_id};")
            elif call.get('command'):
                cmd_id = safe_id(f"cmd_{call['command']}")
                lines.append(f"    {skill_id} -> {cmd_id};")
            elif call.get('atomic'):
                cmd_id = safe_id(f"cmd_{call['atomic']}")
                lines.append(f"    {skill_id} -> {cmd_id};")
            elif call.get('composite'):
                cmd_id = safe_id(f"cmd_{call['composite']}")
                lines.append(f"    {skill_id} -> {cmd_id};")
            elif call.get('phase'):
                cmd_id = safe_id(f"cmd_{call['phase']}")
                lines.append(f"    {skill_id} -> {cmd_id};")
            elif call.get('specialist'):
                agent_id = safe_id(f"agent_{call['specialist']}")
                lines.append(f"    {skill_id} -> {agent_id} [style=dashed];")
            elif call.get('agent'):
                agent_id = safe_id(f"agent_{call['agent']}")
                lines.append(f"    {skill_id} -> {agent_id} [style=dashed];")
            elif call.get('worker'):
                agent_id = safe_id(f"agent_{call['worker']}")
                lines.append(f"    {skill_id} -> {agent_id} [style=dashed];")
            elif call.get('script'):
                script_id = safe_id(f"script_{call['script']}")
                lines.append(f"    {skill_id} -> {script_id};")
        for ext in skill_data.get('external', []):
            ext_id = safe_id(f"ext_{ext}")
            lines.append(f"    {skill_id} -> {ext_id} [style=dashed];")
        for agent in skill_data.get('uses_agents', []):
            agent_id = safe_id(f"agent_{agent}")
            lines.append(f"    {skill_id} -> {agent_id} [style=dashed];")

    # command -> commands/agents/skills/external
    for cmd_name, cmd_data in deps.get('commands', {}).items():
        if cmd_data.get('redirects_to'):
            continue
        cmd_id = safe_id(f"cmd_{cmd_name}")
        for call in cmd_data.get('calls', []):
            if call.get('command'):
                target_id = safe_id(f"cmd_{call['command']}")
                lines.append(f"    {cmd_id} -> {target_id};")
            elif call.get('atomic'):
                target_id = safe_id(f"cmd_{call['atomic']}")
                lines.append(f"    {cmd_id} -> {target_id};")
            elif call.get('composite'):
                target_id = safe_id(f"cmd_{call['composite']}")
                lines.append(f"    {cmd_id} -> {target_id};")
            elif call.get('phase'):
                target_id = safe_id(f"cmd_{call['phase']}")
                lines.append(f"    {cmd_id} -> {target_id};")
            elif call.get('specialist'):
                target_id = safe_id(f"agent_{call['specialist']}")
                lines.append(f"    {cmd_id} -> {target_id} [style=dashed];")
            elif call.get('agent'):
                target_id = safe_id(f"agent_{call['agent']}")
                lines.append(f"    {cmd_id} -> {target_id} [style=dashed];")
            elif call.get('worker'):
                target_id = safe_id(f"agent_{call['worker']}")
                lines.append(f"    {cmd_id} -> {target_id} [style=dashed];")
            elif call.get('reference'):
                target_id = safe_id(f"skill_{call['reference']}")
                lines.append(f"    {cmd_id} -> {target_id};")
            elif call.get('skill'):
                target_id = safe_id(f"skill_{call['skill']}")
                lines.append(f"    {cmd_id} -> {target_id};")
            elif call.get('controller'):
                target_id = safe_id(f"skill_{call['controller']}")
                lines.append(f"    {cmd_id} -> {target_id};")
            elif call.get('workflow'):
                target_id = safe_id(f"skill_{call['workflow']}")
                lines.append(f"    {cmd_id} -> {target_id};")
            elif call.get('script'):
                target_id = safe_id(f"script_{call['script']}")
                lines.append(f"    {cmd_id} -> {target_id};")
        for ext in cmd_data.get('external', []):
            ext_id = safe_id(f"ext_{ext}")
            lines.append(f"    {cmd_id} -> {ext_id} [style=dashed];")
        for agent in cmd_data.get('uses_agents', []):
            agent_id = safe_id(f"agent_{agent}")
            lines.append(f"    {cmd_id} -> {agent_id} [style=dashed];")

    # agent -> commands/skills
    for agent_name, agent_data in deps.get('agents', {}).items():
        agent_id = safe_id(f"agent_{agent_name}")
        for call in agent_data.get('calls', []):
            if call.get('command'):
                target_id = safe_id(f"cmd_{call['command']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('atomic'):
                target_id = safe_id(f"cmd_{call['atomic']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('skill'):
                target_id = safe_id(f"skill_{call['skill']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('composite'):
                target_id = safe_id(f"cmd_{call['composite']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('specialist'):
                target_id = safe_id(f"agent_{call['specialist']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('agent'):
                target_id = safe_id(f"agent_{call['agent']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('reference'):
                target_id = safe_id(f"skill_{call['reference']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('controller'):
                target_id = safe_id(f"skill_{call['controller']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('workflow'):
                target_id = safe_id(f"skill_{call['workflow']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
            elif call.get('script'):
                target_id = safe_id(f"script_{call['script']}")
                lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
        # agents.skills: で reference を参照
        for ref_skill in agent_data.get('skills', []):
            target_id = safe_id(f"skill_{ref_skill}")
            lines.append(f"    {agent_id} -> {target_id} [style=dotted];")
        for ext in agent_data.get('external', []):
            ext_id = safe_id(f"ext_{ext}")
            lines.append(f"    {agent_id} -> {ext_id} [style=dashed];")

    lines.append("")

    # === 並び順制御 ===
    ordering_edges = generate_ordering_edges(deps)
    if ordering_edges:
        lines.append("    // Ordering constraints (invisible edges)")
        lines.extend(ordering_edges)
        lines.append("")

    # === 凡例（実在する型のみ表示） ===
    existing_types = set()
    for skill_data in deps.get('skills', {}).values():
        existing_types.add(skill_data.get('type', 'controller'))
    for ref_data in deps.get('refs', {}).values():
        existing_types.add(ref_data.get('type', 'reference'))
    for cmd_data in deps.get('commands', {}).values():
        existing_types.add(cmd_data.get('type', 'atomic'))
    for agent_data in deps.get('agents', {}).values():
        existing_types.add(agent_data.get('type', 'specialist'))
    if deps.get('scripts'):
        existing_types.add('script')
    legend_defs = [
        ('controller',      'Controller (skill)',      'ellipse',  '#c8e6c9', 'filled'),
        ('workflow',        'Workflow (skill)',         'ellipse',  '#e8f5e9', 'filled'),
        ('reference',       'Reference (skill)',       'note',     '#e1f5fe', 'filled'),
        ('atomic',          'Atomic (command)',         'box',      '#e3f2fd', 'filled'),
        ('composite',       'Composite (command)',      'box',      '#bbdefb', 'filled'),
        ('specialist',      'Specialist (agent)',       'ellipse',  '#ede7f6', 'filled'),
        ('orchestrator',    'Orchestrator (agent)',     'ellipse',  '#f3e5f5', '"filled,bold"'),
        ('script',          'Script',                   'hexagon',  '#FF9800', 'filled'),
    ]

    lines.append("    // Legend")
    lines.append("    subgraph cluster_legend {")
    lines.append('        label="Legend";')
    lines.append('        fontsize=9;')
    lines.append('        style=dashed;')
    for (type_name, label, shape, color, style) in legend_defs:
        if type_name in existing_types:
            lid = safe_id(f"legend_{type_name}")
            lines.append(f'        {lid} [label="{label}", shape={shape}, style={style}, fillcolor="{color}"];')
    if layers.get('sub_commands'):
        lines.append('        legend_sub [label="Sub Command", shape=box, style=filled, fillcolor="#fff3e0"];')
    if layers.get('externals'):
        lines.append('        legend_ext [label="External", shape=parallelogram, style=filled, fillcolor="#eceff1"];')
    if layers.get('orphan_commands'):
        lines.append('        legend_orphan [label="Orphan", shape=box, style=filled, fillcolor="#ffcdd2"];')
    lines.append("    }")

    lines.append("}")
    return '\n'.join(lines)


def print_graphviz(graph: Dict, deps: dict, plugin_name: str, show_tokens: bool = True):
    """Graphviz DOT形式でグラフを出力"""
    print(generate_graphviz(graph, deps, plugin_name, show_tokens))


def generate_subgraph_graphviz(graph: Dict, deps: dict, plugin_name: str, root_name: str, allowed_nodes: Set[str], show_tokens: bool = True) -> str:
    """指定ノード集合のみで構成されるGraphviz DOTを生成（サブグラフ用）"""
    lines = []
    lines.append("digraph Dependencies {")
    lines.append("    // Graph settings")
    lines.append("    rankdir=LR;")
    lines.append("    ranksep=0.8;")
    lines.append("    nodesep=0.3;")
    lines.append('    fontname="Helvetica";')
    lines.append('    node [fontname="Helvetica", fontsize=10];')
    lines.append('    edge [fontname="Helvetica", fontsize=9];')
    lines.append(f'    label="{root_name}";')
    lines.append('    labelloc=t;')
    lines.append('    fontsize=14;')
    lines.append("")

    def format_label(name: str, tokens: int, prefix: str = "") -> str:
        label = f"{prefix}{name}" if prefix else name
        if show_tokens and tokens > 0:
            return f"{label}\\n({tokens:,} tok)"
        return label

    def safe_id(name: str) -> str:
        return name.replace('-', '_').replace(':', '_').replace('.', '_')

    layers = classify_layers(deps, graph)

    # === ノード定義（allowed_nodes に含まれるもののみ） ===
    lines.append("    // L0: Controller Skills")
    for skill_name in layers['controllers']:
        node_id = f"skill:{skill_name}"
        if node_id not in allowed_nodes:
            continue
        sid = safe_id(f"skill_{skill_name}")
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(skill_name, tokens, f"{plugin_name}:")
        lines.append(f'    {sid} [label="{label}", shape=ellipse, style=filled, fillcolor="#c8e6c9"];')
    lines.append("")

    lines.append("    // L0: Launchers")
    for cmd_name in layers['launchers']:
        node_id = f"command:{cmd_name}"
        if node_id not in allowed_nodes:
            continue
        cid = safe_id(f"cmd_{cmd_name}")
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(cmd_name, tokens)
        lines.append(f'    {cid} [label="{label}", shape=box, style="filled,rounded", fillcolor="#a5d6a7"];')
    lines.append("")

    lines.append("    // L0.5: Workflow Skills")
    for skill_name in layers['workflows']:
        node_id = f"skill:{skill_name}"
        if node_id not in allowed_nodes:
            continue
        sid = safe_id(f"skill_{skill_name}")
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(skill_name, tokens, f"{plugin_name}:")
        lines.append(f'    {sid} [label="{label}", shape=ellipse, style=filled, fillcolor="#e8f5e9"];')
    lines.append("")

    lines.append("    // Reference Skills")
    for skill_name in layers['references']:
        node_id = f"skill:{skill_name}"
        if node_id not in allowed_nodes:
            continue
        sid = safe_id(f"skill_{skill_name}")
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(skill_name, tokens, f"{plugin_name}:")
        lines.append(f'    {sid} [label="{label}", shape=note, style=filled, fillcolor="#e1f5fe"];')
    lines.append("")

    lines.append("    // L1: Direct Commands")
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        node_id = f"command:{cmd_name}"
        if node_id not in allowed_nodes:
            continue
        if cmd_data.get('redirects_to') and cmd_data.get('type') != 'launcher':
            continue
        if cmd_data.get('type') == 'launcher':
            continue
        if cmd_name in layers['direct_commands']:
            cid = safe_id(f"cmd_{cmd_name}")
            tokens = graph.get(node_id, {}).get('tokens', 0)
            label = format_label(cmd_name, tokens)
            cmd_type = cmd_data.get('type', 'atomic')
            if cmd_type == 'composite':
                lines.append(f'    {cid} [label="{label}", shape=box, style=filled, fillcolor="#bbdefb"];')
            else:
                lines.append(f'    {cid} [label="{label}", shape=box, style=filled, fillcolor="#e3f2fd"];')
    lines.append("")

    lines.append("    // L2: Sub Commands")
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        node_id = f"command:{cmd_name}"
        if node_id not in allowed_nodes:
            continue
        if cmd_data.get('redirects_to'):
            continue
        is_sub = cmd_name in layers['sub_commands'] or cmd_name in layers['orphan_commands']
        if is_sub and cmd_name not in layers['direct_commands']:
            cid = safe_id(f"cmd_{cmd_name}")
            tokens = graph.get(node_id, {}).get('tokens', 0)
            label = format_label(cmd_name, tokens)
            if cmd_name in layers['orphan_commands']:
                lines.append(f'    {cid} [label="{label}", shape=box, style=filled, fillcolor="#ffcdd2"];')
            else:
                lines.append(f'    {cid} [label="{label}", shape=box, style=filled, fillcolor="#fff3e0"];')
    lines.append("")

    lines.append("    // L3: Agents")
    for agent_name, agent_data in deps.get('agents', {}).items():
        node_id = f"agent:{agent_name}"
        if node_id not in allowed_nodes:
            continue
        aid = safe_id(f"agent_{agent_name}")
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(agent_name, tokens)
        agent_type = agent_data.get('type', 'specialist')
        conditional = agent_data.get('conditional')
        if agent_type == 'orchestrator':
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style="filled,bold", fillcolor="#f3e5f5"];')
        elif conditional:
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style="filled,dashed", fillcolor="#f3e5f5"];')
        else:
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style=filled, fillcolor="#ede7f6"];')
    lines.append("")

    lines.append("    // L3.5: Scripts")
    for script_name in layers['scripts']:
        node_id = f"script:{script_name}"
        if node_id not in allowed_nodes:
            continue
        scid = safe_id(f"script_{script_name}")
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(script_name, tokens)
        lines.append(f'    {scid} [label="{label}", shape=hexagon, style=filled, fillcolor="#FF9800"];')
    lines.append("")

    lines.append("    // L4: External")
    for ext_name in layers['externals']:
        node_id = f"external:{ext_name}"
        if node_id not in allowed_nodes:
            continue
        eid = safe_id(f"ext_{ext_name}")
        lines.append(f'    {eid} [label="{ext_name}", shape=parallelogram, style=filled, fillcolor="#eceff1"];')
    lines.append("")

    # === rank=same 制約（allowed_nodes のみ） ===
    lines.append("    // Layer constraints")

    launcher_ids = [safe_id(f"cmd_{c}") for c in layers['launchers'] if f"command:{c}" in allowed_nodes]
    controller_ids = [safe_id(f"skill_{s}") for s in layers['controllers'] if f"skill:{s}" in allowed_nodes]
    if launcher_ids or controller_ids:
        all_l0 = launcher_ids + controller_ids
        lines.append(f"    {{ rank=same; {'; '.join(all_l0)}; }}")

    workflow_ids = [safe_id(f"skill_{s}") for s in layers['workflows'] if f"skill:{s}" in allowed_nodes]
    orchestrator_ids = [safe_id(f"agent_{a}") for a in layers['orchestrators'] if f"agent:{a}" in allowed_nodes]
    if workflow_ids or orchestrator_ids:
        all_wf = workflow_ids + orchestrator_ids
        lines.append(f"    {{ rank=same; {'; '.join(all_wf)}; }}")

    ref_ids = [safe_id(f"skill_{s}") for s in layers['references'] if f"skill:{s}" in allowed_nodes]
    if ref_ids:
        lines.append(f"    {{ rank=same; {'; '.join(ref_ids)}; }}")

    l1_ids = []
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        if f"command:{cmd_name}" not in allowed_nodes:
            continue
        if cmd_data.get('redirects_to'):
            continue
        if cmd_name in layers['direct_commands']:
            l1_ids.append(safe_id(f"cmd_{cmd_name}"))
    if l1_ids:
        lines.append(f"    {{ rank=same; {'; '.join(l1_ids)}; }}")

    l2_ids = []
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        if f"command:{cmd_name}" not in allowed_nodes:
            continue
        if cmd_data.get('redirects_to'):
            continue
        is_sub = cmd_name in layers['sub_commands'] or cmd_name in layers['orphan_commands']
        if is_sub and cmd_name not in layers['direct_commands']:
            l2_ids.append(safe_id(f"cmd_{cmd_name}"))
    if l2_ids:
        lines.append(f"    {{ rank=same; {'; '.join(l2_ids)}; }}")

    l3_ids = [safe_id(f"agent_{a}") for a in deps.get('agents', {}) if a not in layers['orchestrators'] and f"agent:{a}" in allowed_nodes]
    if l3_ids:
        lines.append(f"    {{ rank=same; {'; '.join(l3_ids)}; }}")

    script_ids = [safe_id(f"script_{s}") for s in layers['scripts'] if f"script:{s}" in allowed_nodes]
    if script_ids:
        lines.append(f"    {{ rank=same; {'; '.join(script_ids)}; }}")

    l4_ids = [safe_id(f"ext_{e}") for e in layers['externals'] if f"external:{e}" in allowed_nodes]
    if l4_ids:
        lines.append(f"    {{ rank=same; {'; '.join(l4_ids)}; }}")

    lines.append("")

    # === エッジ定義（両端が allowed_nodes に含まれるもののみ） ===
    lines.append("    // Edges")

    # launcher -> skill
    for cmd_name in layers['launchers']:
        if f"command:{cmd_name}" not in allowed_nodes:
            continue
        cmd_data = deps['commands'][cmd_name]
        redirects_to = cmd_data.get('redirects_to', '')
        if redirects_to.startswith('skill:'):
            target_skill = redirects_to[6:]
            if f"skill:{target_skill}" not in allowed_nodes:
                continue
            cmd_id = safe_id(f"cmd_{cmd_name}")
            skill_id = safe_id(f"skill_{target_skill}")
            lines.append(f"    {cmd_id} -> {skill_id};")

    def _edge(src_id, call, allowed, style=""):
        """callエントリからエッジ文字列を生成。両端がallowedに含まれる場合のみ返す。"""
        attr = f" [{style}]" if style else ""
        for key, prefix in [('skill', 'skill'), ('reference', 'skill'), ('workflow', 'skill'),
                            ('controller', 'skill'),
                            ('command', 'cmd'), ('atomic', 'cmd'), ('composite', 'cmd'), ('phase', 'cmd'),
                            ('specialist', 'agent'), ('agent', 'agent'), ('worker', 'agent'),
                            ('script', 'script')]:
            val = call.get(key)
            if val is None:
                continue
            # ノードIDの構築
            if key in ('skill', 'reference', 'workflow', 'controller'):
                target_node = f"skill:{val}"
            elif key in ('command', 'atomic', 'composite', 'phase'):
                target_node = f"command:{val}"
            elif key == 'script':
                target_node = f"script:{val}"
            else:
                target_node = f"agent:{val}"
            if target_node not in allowed:
                return None
            # dashed for agent-related calls from skills/commands
            if key in ('specialist', 'agent', 'worker') and not style:
                attr = " [style=dashed]"
            target_gv_id = safe_id(f"{prefix}_{val}")
            return f"    {src_id} -> {target_gv_id}{attr};"
        return None

    # skill -> skills/commands/agents
    for skill_name, skill_data in deps.get('skills', {}).items():
        if f"skill:{skill_name}" not in allowed_nodes:
            continue
        src = safe_id(f"skill_{skill_name}")
        for call in skill_data.get('calls', []):
            edge = _edge(src, call, allowed_nodes)
            if edge:
                lines.append(edge)
        for ext in skill_data.get('external', []):
            if f"external:{ext}" in allowed_nodes:
                ext_id = safe_id(f"ext_{ext}")
                lines.append(f"    {src} -> {ext_id} [style=dashed];")
        for agent in skill_data.get('uses_agents', []):
            if f"agent:{agent}" in allowed_nodes:
                aid = safe_id(f"agent_{agent}")
                lines.append(f"    {src} -> {aid} [style=dashed];")

    # command -> commands/agents/skills/external
    for cmd_name, cmd_data in deps.get('commands', {}).items():
        if f"command:{cmd_name}" not in allowed_nodes:
            continue
        if cmd_data.get('redirects_to'):
            continue
        src = safe_id(f"cmd_{cmd_name}")
        for call in cmd_data.get('calls', []):
            edge = _edge(src, call, allowed_nodes)
            if edge:
                lines.append(edge)
        for ext in cmd_data.get('external', []):
            if f"external:{ext}" in allowed_nodes:
                ext_id = safe_id(f"ext_{ext}")
                lines.append(f"    {src} -> {ext_id} [style=dashed];")
        for agent in cmd_data.get('uses_agents', []):
            if f"agent:{agent}" in allowed_nodes:
                aid = safe_id(f"agent_{agent}")
                lines.append(f"    {src} -> {aid} [style=dashed];")

    # agent -> commands/skills
    for agent_name, agent_data in deps.get('agents', {}).items():
        if f"agent:{agent_name}" not in allowed_nodes:
            continue
        src = safe_id(f"agent_{agent_name}")
        for call in agent_data.get('calls', []):
            edge = _edge(src, call, allowed_nodes, style="style=dotted")
            if edge:
                lines.append(edge)
        for ref_skill in agent_data.get('skills', []):
            if f"skill:{ref_skill}" in allowed_nodes:
                tid = safe_id(f"skill_{ref_skill}")
                lines.append(f"    {src} -> {tid} [style=dotted];")
        for ext in agent_data.get('external', []):
            if f"external:{ext}" in allowed_nodes:
                ext_id = safe_id(f"ext_{ext}")
                lines.append(f"    {src} -> {ext_id} [style=dashed];")

    lines.append("")

    # === 並び順制御（allowed_nodes に含まれるノード間のみ） ===
    # allowed_nodes のノードIDから Graphviz ID のセットを構築
    allowed_gv_ids = set()
    for node_id in allowed_nodes:
        parts = node_id.split(':', 1)
        if len(parts) == 2:
            ntype, nname = parts
            if ntype == 'skill':
                allowed_gv_ids.add(safe_id(f"skill_{nname}"))
            elif ntype == 'command':
                allowed_gv_ids.add(safe_id(f"cmd_{nname}"))
            elif ntype == 'agent':
                allowed_gv_ids.add(safe_id(f"agent_{nname}"))
            elif ntype == 'script':
                allowed_gv_ids.add(safe_id(f"script_{nname}"))
            elif ntype == 'external':
                allowed_gv_ids.add(safe_id(f"ext_{nname}"))

    ordering_edges = generate_ordering_edges(deps)
    if ordering_edges:
        edge_pattern = re.compile(r'^\s*(\S+)\s*->\s*(\S+)\s')
        filtered_edges = []
        for edge in ordering_edges:
            m = edge_pattern.match(edge)
            if m:
                src_gv, dst_gv = m.group(1), m.group(2)
                if src_gv in allowed_gv_ids and dst_gv in allowed_gv_ids:
                    filtered_edges.append(edge)
        if filtered_edges:
            lines.append("    // Ordering constraints (invisible edges)")
            lines.extend(filtered_edges)
            lines.append("")

    lines.append("}")
    return '\n'.join(lines)


def generate_svg(plugin_root: Path, graph: Dict, deps: dict, plugin_name: str, show_tokens: bool = True) -> Optional[Path]:
    """Graphviz DOTからSVGを生成"""
    import shutil
    import subprocess

    if not shutil.which('dot'):
        print("Error: graphviz not installed. Run: apt install graphviz", file=sys.stderr)
        return None

    docs_dir = plugin_root / "docs"
    docs_dir.mkdir(exist_ok=True)

    dot_path = docs_dir / "deps.dot"
    svg_path = docs_dir / "deps.svg"

    dot_content = generate_graphviz(graph, deps, plugin_name, show_tokens)
    dot_path.write_text(dot_content, encoding='utf-8')

    try:
        result = subprocess.run(
            ['dot', '-Tsvg', str(dot_path), '-o', str(svg_path)],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"Error generating SVG: {result.stderr}", file=sys.stderr)
            return None

        print(f"Generated: {dot_path}")
        print(f"Generated: {svg_path}")
        return svg_path

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return None


def compute_subgraph_targets(deps: dict, graph: Dict) -> List[Tuple[str, str]]:
    """controller/workflow/orchestrator ノードを自動検出してサブグラフターゲットを返す

    controller が2つ以上ある場合は各 controller ごとの分離図を生成。
    workflow/orchestrator は従来通り。
    """
    layers = classify_layers(deps, graph)
    targets = []
    # controller が2つ以上の場合のみ per-controller サブグラフを生成
    if len(layers['controllers']) >= 2:
        for name in layers['controllers']:
            targets.append(('skill', name))
    for name in layers['workflows']:
        targets.append(('skill', name))
    for name in layers['orchestrators']:
        targets.append(('agent', name))
    return targets


def generate_subgraph_svgs(plugin_root: Path, graph: Dict, deps: dict, plugin_name: str, show_tokens: bool = True) -> List[Tuple[str, Path]]:
    """各 workflow/orchestrator のサブグラフ SVG を生成

    Returns: [(name, svg_path), ...]
    """
    import shutil
    import subprocess

    if not shutil.which('dot'):
        print("Error: graphviz not installed. Run: apt install graphviz", file=sys.stderr)
        return []

    docs_dir = plugin_root / "docs"
    docs_dir.mkdir(exist_ok=True)

    results = []

    targets = compute_subgraph_targets(deps, graph)
    if not targets:
        return []

    for (node_type, node_name) in targets:
        root_id = f"{node_type}:{node_name}"
        if root_id not in graph:
            print(f"Warning: {root_id} not found in graph, skipping", file=sys.stderr)
            continue

        allowed_nodes = collect_reachable_nodes(graph, root_id)
        dot_content = generate_subgraph_graphviz(graph, deps, plugin_name, node_name, allowed_nodes, show_tokens)

        dot_path = docs_dir / f"deps-{node_name}.dot"
        svg_path = docs_dir / f"deps-{node_name}.svg"

        dot_path.write_text(dot_content, encoding='utf-8')

        try:
            result = subprocess.run(
                ['dot', '-Tsvg', str(dot_path), '-o', str(svg_path)],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                print(f"Error generating SVG for {node_name}: {result.stderr}", file=sys.stderr)
                continue

            print(f"Generated: {dot_path}")
            print(f"Generated: {svg_path}")
            results.append((node_name, svg_path))

        except Exception as e:
            print(f"Error generating {node_name}: {e}", file=sys.stderr)

    return results


def update_readme(plugin_root: Path, graph: Dict, deps: dict, plugin_name: str, show_tokens: bool = True, check_only: bool = False) -> bool:
    """README.mdの依存グラフセクション + サブグラフセクション + Entry Points テーブルを更新

    check_only=True の場合はファイルを書き込まず Entry Points ドリフトの有無を返す。
    """
    from twl.viz.mermaid import generate_text_table

    readme_path = plugin_root / "README.md"
    if not readme_path.exists():
        print(f"Error: {readme_path} not found", file=sys.stderr)
        return False

    if check_only:
        original = readme_path.read_text(encoding='utf-8')
        ep_start_idx = original.find(README_ENTRY_POINTS_START)
        ep_end_idx = original.find(README_ENTRY_POINTS_END)
        if ep_start_idx == -1 or ep_end_idx == -1:
            print("✓ README.md has no ENTRY-POINTS markers, skipping check")
            return True
        entry_points_content = generate_entry_points_table(deps, plugin_name)
        expected = (
            original[:ep_start_idx + len(README_ENTRY_POINTS_START)] +
            "\n" + entry_points_content +
            original[ep_end_idx:]
        )
        if original != expected:
            print("README.md drift detected: entry points table is out of sync", file=sys.stderr)
            print("Run 'twl --update-readme' to regenerate.", file=sys.stderr)
            return False
        print("✓ README.md entry points are up to date")
        return True

    # 全体 SVG 生成
    svg_path = generate_svg(plugin_root, graph, deps, plugin_name, show_tokens)
    if not svg_path:
        print("Failed to generate SVG, falling back to text table", file=sys.stderr)
        graph_content = generate_text_table(graph, deps, plugin_name)
    else:
        graph_content = f"![Dependency Graph](./docs/deps.svg)"

    # サブグラフ SVG 生成
    subgraph_results = generate_subgraph_svgs(plugin_root, graph, deps, plugin_name, show_tokens)

    content = readme_path.read_text(encoding='utf-8')

    # === 全体グラフセクション更新 ===
    start_idx = content.find(README_MARKER_START)
    end_idx = content.find(README_MARKER_END)

    if start_idx == -1 or end_idx == -1:
        print(f"Error: DEPS-GRAPH markers not found in README.md", file=sys.stderr)
        print(f"  Add the following markers to README.md:")
        print(f"    {README_MARKER_START}")
        print(f"    {README_MARKER_END}")
        return False

    if start_idx >= end_idx:
        print(f"Error: Invalid DEPS-GRAPH marker positions", file=sys.stderr)
        return False

    content = (
        content[:start_idx + len(README_MARKER_START)] +
        "\n" + graph_content + "\n" +
        content[end_idx:]
    )

    # === サブグラフセクション更新 ===
    sub_start_idx = content.find(README_SUBGRAPH_START)
    sub_end_idx = content.find(README_SUBGRAPH_END)

    if sub_start_idx != -1 and sub_end_idx != -1 and sub_start_idx < sub_end_idx:
        # サブグラフコンテンツ生成
        subgraph_lines = []
        for (name, svg_path) in subgraph_results:
            subgraph_lines.append(f"<details>")
            subgraph_lines.append(f"<summary>{name}</summary>")
            subgraph_lines.append(f"")
            subgraph_lines.append(f"![{name}](./docs/deps-{name}.svg)")
            subgraph_lines.append(f"</details>")
            subgraph_lines.append(f"")
        subgraph_content = '\n'.join(subgraph_lines)

        content = (
            content[:sub_start_idx + len(README_SUBGRAPH_START)] +
            "\n" + subgraph_content +
            content[sub_end_idx:]
        )
    elif subgraph_results:
        # サブグラフ結果があるがマーカーが無い場合、DEPS-GRAPH-END直後に自動挿入
        graph_end_idx = content.find(README_MARKER_END)
        if graph_end_idx != -1:
            insert_pos = graph_end_idx + len(README_MARKER_END)
            subgraph_lines = []
            for (name, svg_path) in subgraph_results:
                subgraph_lines.append(f"<details>")
                subgraph_lines.append(f"<summary>{name}</summary>")
                subgraph_lines.append(f"")
                subgraph_lines.append(f"![{name}](./docs/deps-{name}.svg)")
                subgraph_lines.append(f"</details>")
                subgraph_lines.append(f"")
            subgraph_content = '\n'.join(subgraph_lines)
            insert_block = (
                f"\n\n{README_SUBGRAPH_START}\n"
                f"{subgraph_content}"
                f"{README_SUBGRAPH_END}"
            )
            content = content[:insert_pos] + insert_block + content[insert_pos:]
            print(f"Inserted DEPS-SUBGRAPHS markers into README.md")

    # === Entry Points テーブル更新 ===
    ep_start_idx = content.find(README_ENTRY_POINTS_START)
    ep_end_idx = content.find(README_ENTRY_POINTS_END)

    if ep_start_idx != -1 and ep_end_idx != -1 and ep_start_idx < ep_end_idx:
        entry_points_content = generate_entry_points_table(deps, plugin_name)
        content = (
            content[:ep_start_idx + len(README_ENTRY_POINTS_START)] +
            "\n" + entry_points_content +
            content[ep_end_idx:]
        )

    readme_path.write_text(content, encoding='utf-8')
    print(f"Updated: {readme_path}")
    return True
