from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.graph import classify_layers


def generate_mermaid(graph: Dict, deps: dict, plugin_name: str) -> str:
    """Mermaid形式でグラフを生成"""
    lines = []
    lines.append("```mermaid")
    lines.append("%%{init:{'flowchart':{'nodeSpacing': 8, 'rankSpacing': 50}}}%%")
    lines.append("flowchart LR")
    lines.append("")

    def safe_id(name: str, prefix: str = "") -> str:
        safe = name.replace('-', '_').replace(':', '_')
        return f"{prefix}{safe}" if prefix else safe

    layers = classify_layers(deps, graph)

    # === L0: スキル + Launchers ===
    lines.append("    subgraph L0[\" \"]")
    lines.append("        direction TB")
    for cmd_name in layers['launchers']:
        lines.append(f"        {safe_id(cmd_name, 'cmd_')}[{cmd_name}]:::launcher")
    for skill_name in layers['controllers']:
        lines.append(f"        {safe_id(skill_name, 'skill_')}([{plugin_name}:{skill_name}]):::controller")
    for skill_name in layers['workflows']:
        lines.append(f"        {safe_id(skill_name, 'skill_')}([{plugin_name}:{skill_name}]):::workflow")
    lines.append("    end")
    lines.append("")

    # === L1: 直接コマンド ===
    lines.append("    subgraph L1[\"Commands\"]")
    lines.append("        direction TB")
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        # redirects_to を持つがlauncher以外をスキップ（launcherはL0で別途描画）
        if cmd_data.get('redirects_to') and cmd_data.get('type') != 'launcher':
            continue
        # launcher は L0 で既に描画済み
        if cmd_data.get('type') == 'launcher':
            continue
        if cmd_name in layers['direct_commands']:
            lines.append(f"        {safe_id(cmd_name, 'cmd_')}[{cmd_name}]")
    lines.append("    end")
    lines.append("")

    # === L2: サブコマンド ===
    lines.append("    subgraph L2[\"Sub\"]")
    lines.append("        direction TB")
    for cmd_name in deps.get('commands', {}):
        cmd_data = deps['commands'][cmd_name]
        if cmd_data.get('redirects_to'):
            continue
        is_sub = cmd_name in layers['sub_commands'] or cmd_name in layers['orphan_commands']
        if is_sub and cmd_name not in layers['direct_commands']:
            cid = safe_id(cmd_name, 'cmd_')
            if cmd_name in layers['orphan_commands']:
                lines.append(f"        {cid}[{cmd_name}]:::orphan")
            else:
                lines.append(f"        {cid}[{cmd_name}]")
    lines.append("    end")
    lines.append("")

    # === L3: エージェント ===
    lines.append("    subgraph L3[\"Agents\"]")
    lines.append("        direction TB")
    for agent_name, agent_data in deps.get('agents', {}).items():
        aid = safe_id(agent_name, 'agent_')
        conditional = agent_data.get('conditional')
        if conditional:
            lines.append(f"        {aid}([{agent_name}]):::conditional")
        else:
            lines.append(f"        {aid}([{agent_name}])")
    lines.append("    end")
    lines.append("")

    # === L3.5: スクリプト ===
    if layers['scripts']:
        lines.append("    subgraph L3_5[\"Scripts\"]")
        lines.append("        direction TB")
        for script_name in layers['scripts']:
            scid = safe_id(script_name, 'script_')
            lines.append(f"        {scid}{{{{{script_name}}}}}")
        lines.append("    end")
        lines.append("")

    # === L4: 外部依存 ===
    lines.append("    subgraph L4[\"External\"]")
    lines.append("        direction TB")
    for ext_name in layers['externals']:
        lines.append(f"        {safe_id(ext_name, 'ext_')}[/{ext_name}/]")
    lines.append("    end")
    lines.append("")

    # === 層間接続 ===
    lines.append("    %% Layer connections")
    if layers['scripts']:
        lines.append("    L0 --> L1 --> L2 -.-> L3")
        lines.append("    L2 --> L3_5")
        lines.append("    L0 -.-> L4")
        lines.append("    L1 -.-> L4")
    else:
        lines.append("    L0 --> L1 --> L2 -.-> L3")
        lines.append("    L0 -.-> L4")
        lines.append("    L1 -.-> L4")
    lines.append("")

    # === launcher → skill エッジ ===
    for cmd_name in layers['launchers']:
        cmd_data = deps['commands'][cmd_name]
        redirects_to = cmd_data.get('redirects_to', '')
        if redirects_to.startswith('skill:'):
            target_skill = redirects_to[6:]  # "skill:" を除去
            cmd_id = safe_id(cmd_name, 'cmd_')
            skill_id = safe_id(target_skill, 'skill_')
            lines.append(f"    {cmd_id} --> {skill_id}")
    lines.append("")

    # === スタイル定義 ===
    lines.append("    classDef controller fill:#c8e6c9,stroke:#2e7d32")
    lines.append("    classDef workflow fill:#e8f5e9,stroke:#43a047")
    lines.append("    classDef orphan fill:#ffcdd2,stroke:#c62828")
    lines.append("    classDef conditional fill:#e3f2fd,stroke:#1976d2")
    lines.append("    classDef scriptStyle fill:#FF9800,stroke:#E65100")

    # Apply script class
    for script_name in layers['scripts']:
        scid = safe_id(script_name, 'script_')
        lines.append(f"    class {scid} scriptStyle")

    lines.append("```")

    # === 詳細テーブル ===
    lines.append("")
    lines.append("<details>")
    lines.append("<summary>詳細な依存関係</summary>")
    lines.append("")
    lines.append("| From | To |")
    lines.append("|------|-----|")

    for skill_name, skill_data in deps.get('skills', {}).items():
        targets = []
        for c in skill_data.get('calls', []):
            if c.get('skill'):
                targets.append(f"→{plugin_name}:{c['skill']}")
            elif c.get('reference'):
                targets.append(f"→{plugin_name}:{c['reference']}")
            elif c.get('controller'):
                targets.append(f"→{plugin_name}:{c['controller']}")
            elif c.get('workflow'):
                targets.append(f"→{plugin_name}:{c['workflow']}")
            elif c.get('command'):
                targets.append(c['command'])
            elif c.get('atomic'):
                targets.append(c['atomic'])
            elif c.get('composite'):
                targets.append(f"◆{c['composite']}")
            elif c.get('specialist'):
                targets.append(f"●{c['specialist']}")
            elif c.get('agent'):
                targets.append(f"⟶{c['agent']}")
            elif c.get('script'):
                targets.append(f"⬡{c['script']}")
        for agent in skill_data.get('uses_agents', []):
            targets.append(f"⟶{agent}")
        if targets:
            lines.append(f"| {plugin_name}:{skill_name} | {', '.join(targets)} |")

    # launcher コマンド（redirects_to を持つ）
    for cmd_name in layers['launchers']:
        cmd_data = deps['commands'][cmd_name]
        redirects_to = cmd_data.get('redirects_to', '')
        if redirects_to.startswith('skill:'):
            target_skill = redirects_to[6:]
            lines.append(f"| ▸{cmd_name} | →{plugin_name}:{target_skill} |")

    for cmd_name, cmd_data in deps.get('commands', {}).items():
        # redirects_to を持つがlauncher以外をスキップ
        if cmd_data.get('redirects_to') and cmd_data.get('type') != 'launcher':
            continue
        # launcher は上で処理済み
        if cmd_data.get('type') == 'launcher':
            continue
        targets = []
        for call in cmd_data.get('calls', []):
            if call.get('command'):
                targets.append(call['command'])
            elif call.get('atomic'):
                targets.append(call['atomic'])
            elif call.get('composite'):
                targets.append(f"◆{call['composite']}")
            elif call.get('specialist'):
                targets.append(f"●{call['specialist']}")
            elif call.get('agent'):
                targets.append(f"⟶{call['agent']}")
            elif call.get('reference'):
                targets.append(f"→{plugin_name}:{call['reference']}")
            elif call.get('controller'):
                targets.append(f"→{plugin_name}:{call['controller']}")
            elif call.get('workflow'):
                targets.append(f"→{plugin_name}:{call['workflow']}")
            elif call.get('script'):
                targets.append(f"⬡{call['script']}")
        for agent in cmd_data.get('uses_agents', []):
            targets.append(f"⟶{agent}")
        if targets:
            lines.append(f"| {cmd_name} | {', '.join(targets)} |")

    for agent_name, agent_data in deps.get('agents', {}).items():
        targets = []
        for call in agent_data.get('calls', []):
            if call.get('command'):
                targets.append(call['command'])
            elif call.get('atomic'):
                targets.append(call['atomic'])
            elif call.get('skill'):
                targets.append(f"→{plugin_name}:{call['skill']}")
            elif call.get('composite'):
                targets.append(f"◆{call['composite']}")
            elif call.get('specialist'):
                targets.append(f"●{call['specialist']}")
            elif call.get('agent'):
                targets.append(f"⟶{call['agent']}")
            elif call.get('reference'):
                targets.append(f"→{plugin_name}:{call['reference']}")
            elif call.get('controller'):
                targets.append(f"→{plugin_name}:{call['controller']}")
            elif call.get('workflow'):
                targets.append(f"→{plugin_name}:{call['workflow']}")
        for ref_skill in agent_data.get('skills', []):
            targets.append(f"→{plugin_name}:{ref_skill}")
        if targets:
            lines.append(f"| ⟶{agent_name} | {', '.join(targets)} |")

    lines.append("")
    lines.append("</details>")

    return '\n'.join(lines)


def print_mermaid(graph: Dict, deps: dict, plugin_name: str):
    """Mermaid形式でグラフを出力"""
    print(generate_mermaid(graph, deps, plugin_name))


def generate_text_table(graph: Dict, deps: dict, plugin_name: str) -> str:
    """テキストテーブル形式で依存関係を出力"""
    lines = []
    lines.append("| From | To |")
    lines.append("|------|-----|")

    for skill_name, skill_data in deps.get('skills', {}).items():
        targets = []
        for c in skill_data.get('calls', []):
            if c.get('skill'):
                targets.append(f"→{plugin_name}:{c['skill']}")
            elif c.get('reference'):
                targets.append(f"→{plugin_name}:{c['reference']}")
            elif c.get('controller'):
                targets.append(f"→{plugin_name}:{c['controller']}")
            elif c.get('workflow'):
                targets.append(f"→{plugin_name}:{c['workflow']}")
            elif c.get('command'):
                targets.append(c['command'])
            elif c.get('atomic'):
                targets.append(c['atomic'])
            elif c.get('composite'):
                targets.append(f"◆{c['composite']}")
            elif c.get('specialist'):
                targets.append(f"●{c['specialist']}")
            elif c.get('agent'):
                targets.append(f"⟶{c['agent']}")
        for agent in skill_data.get('uses_agents', []):
            targets.append(f"⟶{agent}")
        if targets:
            lines.append(f"| {plugin_name}:{skill_name} | {', '.join(targets)} |")

    for cmd_name, cmd_data in deps.get('commands', {}).items():
        if cmd_data.get('redirects_to'):
            continue
        targets = []
        for call in cmd_data.get('calls', []):
            if call.get('command'):
                targets.append(call['command'])
            elif call.get('atomic'):
                targets.append(call['atomic'])
            elif call.get('composite'):
                targets.append(f"◆{call['composite']}")
            elif call.get('specialist'):
                targets.append(f"●{call['specialist']}")
            elif call.get('agent'):
                targets.append(f"⟶{call['agent']}")
            elif call.get('reference'):
                targets.append(f"→{plugin_name}:{call['reference']}")
            elif call.get('controller'):
                targets.append(f"→{plugin_name}:{call['controller']}")
            elif call.get('workflow'):
                targets.append(f"→{plugin_name}:{call['workflow']}")
        for agent in cmd_data.get('uses_agents', []):
            targets.append(f"⟶{agent}")
        if targets:
            lines.append(f"| {cmd_name} | {', '.join(targets)} |")

    for agent_name, agent_data in deps.get('agents', {}).items():
        targets = []
        for call in agent_data.get('calls', []):
            if call.get('command'):
                targets.append(call['command'])
            elif call.get('atomic'):
                targets.append(call['atomic'])
            elif call.get('skill'):
                targets.append(f"→{plugin_name}:{call['skill']}")
            elif call.get('composite'):
                targets.append(f"◆{call['composite']}")
            elif call.get('specialist'):
                targets.append(f"●{call['specialist']}")
            elif call.get('agent'):
                targets.append(f"⟶{call['agent']}")
            elif call.get('reference'):
                targets.append(f"→{plugin_name}:{call['reference']}")
            elif call.get('controller'):
                targets.append(f"→{plugin_name}:{call['controller']}")
            elif call.get('workflow'):
                targets.append(f"→{plugin_name}:{call['workflow']}")
        for ref_skill in agent_data.get('skills', []):
            targets.append(f"→{plugin_name}:{ref_skill}")
        if targets:
            lines.append(f"| ⟶{agent_name} | {', '.join(targets)} |")

    return '\n'.join(lines)
