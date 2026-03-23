#!/usr/bin/env python3
"""
プラグイン共通 依存関係解析スクリプト

Usage:
    python3 analyze-deps.py                    # Graphviz出力（デフォルト）
    python3 analyze-deps.py --tree             # ASCIIツリー表示
    python3 analyze-deps.py --rich             # Rich表示（optional dependency）
    python3 analyze-deps.py --mermaid          # Mermaid形式出力
    python3 analyze-deps.py --target pr-cycle  # 特定コマンドの依存を追跡
    python3 analyze-deps.py --reverse pr-review # 逆依存（何がこれを使っているか）
    python3 analyze-deps.py --check            # ファイル存在確認
    python3 analyze-deps.py --validate         # 型ルール検証（can_spawn/spawnable_by）
    python3 analyze-deps.py --update-readme    # README.mdの依存グラフを更新
    python3 analyze-deps.py --tokens           # トークン数を表示
    python3 analyze-deps.py --deep-validate    # 深層検証（controller bloat, ref配置, tools整合性）
    python3 analyze-deps.py --complexity       # 複雑さメトリクスレポート
"""

import argparse
import difflib
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

try:
    import tiktoken
    TIKTOKEN_AVAILABLE = True
except ImportError:
    TIKTOKEN_AVAILABLE = False


# === 型ルール定数 ===
# SSOT: dev:ref-types と同期。ref-types 更新時はここも同期確認。
TYPE_RULES = {
    # === 非AT型 ===
    'controller':  {'section': 'skills',   'can_spawn': {'workflow', 'atomic', 'composite', 'specialist', 'reference'}, 'spawnable_by': {'user', 'launcher'}},
    'workflow':    {'section': 'skills',   'can_spawn': {'atomic', 'composite', 'specialist'},  'spawnable_by': {'controller', 'entry_point'}},
    # orchestrator: 廃止（step-chain パターンで代替）
    'atomic':      {'section': 'commands', 'can_spawn': {'reference'},                          'spawnable_by': {'workflow', 'controller', 'entry_point', 'team-workflow', 'team-controller', 'team-worker'}},
    'composite':   {'section': 'commands', 'can_spawn': {'specialist'},                         'spawnable_by': {'workflow', 'controller', 'entry_point'}},
    'specialist':  {'section': 'agents',   'can_spawn': set(),                                  'spawnable_by': {'workflow', 'composite', 'controller', 'entry_point', 'team-controller'}},
    'reference':   {'section': 'skills',   'can_spawn': set(),                                  'spawnable_by': {'controller', 'entry_point', 'atomic', 'agents.skills', 'team-controller', 'team-workflow', 'team-phase', 'team-worker', 'all'}},
    # === AT型 ===
    'team-controller':  {'section': 'skills',   'can_spawn': {'team-workflow', 'team-phase', 'team-worker', 'atomic', 'specialist', 'reference'}, 'spawnable_by': {'user'}},
    'team-workflow':    {'section': 'skills',   'can_spawn': {'team-phase', 'atomic'},           'spawnable_by': {'team-controller'}},
    'team-phase':       {'section': 'commands', 'can_spawn': {'team-worker'},                    'spawnable_by': {'team-workflow', 'team-controller'}},
    'team-worker':      {'section': 'agents',   'can_spawn': set(),                              'spawnable_by': {'team-phase', 'team-controller'}},
}
# entry_point は controller のエイリアス（deps.yaml 既存データ互換）
TYPE_ALIASES = {'entry_point': 'controller'}


# トークンカウント用のエンコーダー（Claude用にcl100k_baseを使用）
_encoder = None


def get_encoder():
    """tiktokenエンコーダーを取得（遅延初期化）"""
    global _encoder
    if _encoder is None and TIKTOKEN_AVAILABLE:
        _encoder = tiktoken.get_encoding("cl100k_base")
    return _encoder


def count_tokens(file_path: Path) -> int:
    """ファイルのトークン数をカウント"""
    if not file_path.exists():
        return 0

    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception:
        return 0

    encoder = get_encoder()
    if encoder:
        return len(encoder.encode(content))
    else:
        # フォールバック: CJK文字は1文字≒1トークン、それ以外は文字数/4で概算
        cjk_chars = sum(1 for c in content if ord(c) > 0x3000)
        non_cjk_chars = len(content) - cjk_chars
        return cjk_chars + non_cjk_chars // 4


def get_plugin_root() -> Path:
    """CWDから上方にdeps.yamlを探索してpluginルートを取得"""
    cwd = Path.cwd()
    current = cwd
    for _ in range(20):  # 無限ループ防止
        if (current / "deps.yaml").exists():
            return current
        parent = current.parent
        if parent == current:
            break
        current = parent
    print(f"Error: deps.yaml が見つかりません。plugin ディレクトリ内で実行してください (CWD: {cwd})", file=sys.stderr)
    sys.exit(1)


def load_deps(plugin_root: Path) -> dict:
    """deps.yamlを読み込む"""
    deps_path = plugin_root / "deps.yaml"
    if not deps_path.exists():
        print(f"Error: {deps_path} not found", file=sys.stderr)
        sys.exit(1)

    with open(deps_path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def get_plugin_name(deps: dict, plugin_root: Path) -> str:
    """プラグイン名を取得

    優先順位:
    1. deps.yaml の plugin フィールド
    2. plugin_root.name（ディレクトリ名）
    """
    return deps.get('plugin', plugin_root.name)


def build_graph(deps: dict, plugin_root: Path = None) -> Dict[str, Dict]:
    """依存グラフを構築

    Returns:
        {
            'node_id': {
                'type': 'skill' | 'command' | 'agent' | 'external',
                'name': str,
                'path': str | None,
                'description': str,
                'skill_type': str | None,  # controller, workflow, reference
                'command_type': str | None,  # launcher, atomic, composite
                'agent_type': str | None,  # orchestrator, specialist
                'calls': [(type, name), ...],
                'uses_agents': [name, ...],
                'external': [name, ...],
                'requires_mcp': [name, ...],
                'required_by': [(type, name), ...],
                'conditional': str | None,
                'tokens': int,
            }
        }
    """
    if plugin_root is None:
        plugin_root = get_plugin_root()

    graph = {}

    def parse_calls(call_list: list) -> list:
        """calls リストを (type, name) タプルのリストに変換"""
        result = []
        # キー → グラフ上のノードタイプ
        key_map = {
            'command': 'command', 'composite': 'command',
            'skill': 'skill', 'reference': 'skill',
            'agent': 'agent', 'specialist': 'agent',
            'workflow': 'skill', 'phase': 'command', 'worker': 'agent',
        }
        for c in call_list:
            for key, node_type in key_map.items():
                if c.get(key):
                    result.append((node_type, c[key]))
                    break
        return result

    # スキル
    for name, data in deps.get('skills', {}).items():
        node_id = f"skill:{name}"
        calls = parse_calls(data.get('calls', []))
        # トークン数を計算
        path = data.get('path')
        tokens = count_tokens(plugin_root / path) if path else 0
        graph[node_id] = {
            'type': 'skill',
            'skill_type': data.get('type'),  # controller / workflow / reference
            'name': name,
            'path': path,
            'description': data.get('description', ''),
            'calls': calls,
            'uses_agents': data.get('uses_agents', []),
            'external': data.get('external', []),
            'requires_mcp': data.get('requires_mcp', []),
            'required_by': [],
            'conditional': None,
            'tokens': tokens,
        }

    # コマンド
    for name, data in deps.get('commands', {}).items():
        node_id = f"command:{name}"
        # トークン数を計算
        path = data.get('path')
        tokens = count_tokens(plugin_root / path) if path else 0
        calls = parse_calls(data.get('calls', []))
        graph[node_id] = {
            'type': 'command',
            'command_type': data.get('type'),  # launcher / atomic / composite
            'name': name,
            'path': path,
            'description': data.get('description', ''),
            'calls': calls,
            'uses_agents': data.get('uses_agents', []),
            'external': data.get('external', []),
            'requires_mcp': data.get('requires_mcp', []),
            'required_by': [],
            'conditional': None,
            'tokens': tokens,
        }

    # エージェント
    for name, data in deps.get('agents', {}).items():
        node_id = f"agent:{name}"
        # トークン数を計算
        path = data.get('path')
        tokens = count_tokens(plugin_root / path) if path else 0
        calls = parse_calls(data.get('calls', []))
        graph[node_id] = {
            'type': 'agent',
            'agent_type': data.get('type'),  # orchestrator / specialist
            'name': name,
            'path': path,
            'description': data.get('description', ''),
            'calls': calls,
            'uses_agents': data.get('uses_agents', []),
            'external': data.get('external', []),
            'requires_mcp': data.get('requires_mcp', []),
            'required_by': [],
            'conditional': data.get('conditional'),
            'tokens': tokens,
        }

    # 外部依存
    for name, data in deps.get('external', {}).items():
        for cmd in data.get('commands', []):
            node_id = f"external:{name}:{cmd}"
            graph[node_id] = {
                'type': 'external',
                'name': f"{name}:{cmd}",
                'path': None,
                'description': f"{data.get('description', '')} - {cmd}",
                'calls': [],
                'uses_agents': [],
                'external': [],
                'requires_mcp': [],
                'required_by': [],
                'conditional': None,
                'tokens': 0,
            }

    # 逆依存を構築
    for node_id, node_data in graph.items():
        # calls の逆方向
        for (t, n) in node_data['calls']:
            target_id = f"{t}:{n}"
            if target_id in graph:
                graph[target_id]['required_by'].append(
                    (node_data['type'], node_data['name'])
                )

        # uses_agents の逆方向
        for agent in node_data['uses_agents']:
            target_id = f"agent:{agent}"
            if target_id in graph:
                graph[target_id]['required_by'].append(
                    (node_data['type'], node_data['name'])
                )

        # external の逆方向
        for ext in node_data['external']:
            target_id = f"external:{ext}"
            if target_id in graph:
                graph[target_id]['required_by'].append(
                    (node_data['type'], node_data['name'])
                )

    return graph


def find_node(graph: Dict, target: str) -> Optional[str]:
    """ターゲット名からノードIDを検索"""
    # 完全一致を試行
    for prefix in ['skill', 'command', 'agent', 'external']:
        node_id = f"{prefix}:{target}"
        if node_id in graph:
            return node_id

    # 部分一致を試行
    for node_id in graph:
        if node_id.endswith(f":{target}"):
            return node_id

    return None


def get_dependencies(graph: Dict, node_id: str, visited: Set[str] = None) -> List[Tuple[str, str, int]]:
    """指定ノードの依存先を再帰的に取得

    Returns: [(node_id, relation_type, depth), ...]
    """
    if visited is None:
        visited = set()

    if node_id in visited:
        return []
    visited.add(node_id)

    node = graph.get(node_id)
    if not node:
        return []

    deps = []

    # calls
    for (t, n) in node['calls']:
        target_id = f"{t}:{n}"
        deps.append((target_id, 'calls', 1))
        for (child_id, rel, depth) in get_dependencies(graph, target_id, visited):
            deps.append((child_id, rel, depth + 1))

    # uses_agents
    for agent in node['uses_agents']:
        target_id = f"agent:{agent}"
        deps.append((target_id, 'uses_agent', 1))

    # external
    for ext in node['external']:
        target_id = f"external:{ext}"
        deps.append((target_id, 'external', 1))

    return deps


def collect_reachable_nodes(graph: Dict, root_id: str) -> Set[str]:
    """root_id から到達可能な全ノードIDを収集（root自身含む）"""
    reachable = {root_id}
    deps = get_dependencies(graph, root_id)
    for (node_id, rel, depth) in deps:
        reachable.add(node_id)
    return reachable


def get_reverse_dependencies(graph: Dict, node_id: str) -> List[Tuple[str, str]]:
    """指定ノードを使用している全ノードを取得

    Returns: [(node_id, relation_type), ...]
    """
    node = graph.get(node_id)
    if not node:
        return []

    reverse = []
    for (t, n) in node['required_by']:
        reverse.append((f"{t}:{n}", 'required_by'))

    return reverse


def print_tree(graph: Dict, node_id: str, indent: int = 0, visited: Set[str] = None, is_last: bool = True):
    """ASCIIツリーを表示"""
    if visited is None:
        visited = set()

    node = graph.get(node_id)
    if not node:
        return

    # インデント
    if indent == 0:
        prefix = ""
        branch = ""
    else:
        prefix = "│   " * (indent - 1)
        branch = "└── " if is_last else "├── "

    # ノード表示
    type_label = node['type']
    name = node['name']
    skill_type = f" [{node.get('skill_type')}]" if node.get('skill_type') else ""
    conditional = f" [{node['conditional']}]" if node.get('conditional') else ""
    print(f"{prefix}{branch}{name} ({type_label}){skill_type}{conditional}")

    if node_id in visited:
        return
    visited.add(node_id)

    # 子ノードを収集
    children = []
    for (t, n) in node['calls']:
        children.append((f"{t}:{n}", 'call'))
    for agent in node['uses_agents']:
        children.append((f"agent:{agent}", 'agent'))
    for ext in node['external']:
        children.append((f"external:{ext}", 'external'))

    # 子ノードを表示
    for i, (child_id, rel_type) in enumerate(children):
        is_last_child = (i == len(children) - 1)
        print_tree(graph, child_id, indent + 1, visited, is_last_child)


def classify_layers(deps: dict, graph: Dict) -> dict:
    """ノードを層に分類する

    Returns:
        {
            'controllers': [skill_names],  # entry_point / controller
            'workflows': [skill_names],    # workflow
            'references': [skill_names],   # reference
            'launchers': [cmd_names],      # launcher type commands
            'direct_commands': [cmd_names],  # L1
            'sub_commands': [cmd_names],     # L2
            'orphan_commands': [cmd_names],  # 孤立
            'agents': [agent_names],
            'externals': [ext_names],
        }
    """
    result = {
        'controllers': [],
        'workflows': [],
        'orchestrators': [],
        'references': [],
        'launchers': [],
        'direct_commands': set(),
        'sub_commands': set(),
        'orphan_commands': [],
        'agents': list(deps.get('agents', {}).keys()),
        'externals': [],
    }

    # スキルの分類
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', 'workflow')
        if skill_type in ('entry_point', 'controller', 'team-controller'):
            result['controllers'].append(skill_name)
        elif skill_type in ('workflow', 'team-workflow'):
            result['workflows'].append(skill_name)
        elif skill_type == 'reference':
            result['references'].append(skill_name)

    # エージェントの分類（orchestrator を分離）
    for agent_name, agent_data in deps.get('agents', {}).items():
        if agent_data.get('type') == 'orchestrator':
            result['orchestrators'].append(agent_name)

    # launcher コマンドの分類
    for cmd_name, cmd_data in deps.get('commands', {}).items():
        if cmd_data.get('type') == 'launcher':
            result['launchers'].append(cmd_name)

    # コマンドの分類
    # L1: スキルまたはエージェントから直接呼ばれるコマンド
    for skill_name, skill_data in deps.get('skills', {}).items():
        for c in skill_data.get('calls', []):
            if c.get('command'):
                result['direct_commands'].add(c['command'])
            elif c.get('composite'):
                result['direct_commands'].add(c['composite'])
            elif c.get('phase'):
                result['direct_commands'].add(c['phase'])

    for agent_name, agent_data in deps.get('agents', {}).items():
        for c in agent_data.get('calls', []):
            if c.get('command'):
                result['direct_commands'].add(c['command'])
            elif c.get('composite'):
                result['direct_commands'].add(c['composite'])
            elif c.get('phase'):
                result['direct_commands'].add(c['phase'])

    # L2: L1コマンドから呼ばれるコマンド
    for cmd_name in result['direct_commands']:
        cmd_data = deps.get('commands', {}).get(cmd_name, {})
        for c in cmd_data.get('calls', []):
            if c.get('command'):
                result['sub_commands'].add(c['command'])
            elif c.get('composite'):
                result['sub_commands'].add(c['composite'])

    # 孤立コマンドの検出
    orphans = find_orphans(graph, deps)
    orphan_ids = set(orphans['unused'])
    result['orphan_commands'] = [n.split(':')[1] for n in orphan_ids if n.startswith('command:')]

    # 外部依存
    for ext_group, ext_data in deps.get('external', {}).items():
        for ext_cmd in ext_data.get('commands', []):
            result['externals'].append(f"{ext_group}:{ext_cmd}")
        for ext_skill in ext_data.get('skills', []):
            result['externals'].append(f"{ext_group}:{ext_skill}")

    return result


def generate_ordering_edges(deps: dict) -> list:
    """deps.yaml の calls 順序を invisible edges で強制"""
    def safe_id(name: str) -> str:
        return name.replace('-', '_').replace(':', '_').replace('.', '_')

    def get_node_id_from_call(call: dict) -> str | None:
        # キー → graphviz prefix のマッピング
        key_prefix = {
            'command': 'cmd', 'composite': 'cmd', 'phase': 'cmd',
            'skill': 'skill', 'reference': 'skill', 'workflow': 'skill',
            'agent': 'agent', 'specialist': 'agent', 'worker': 'agent',
        }
        for key, prefix in key_prefix.items():
            if call.get(key):
                return safe_id(f"{prefix}_{call[key]}")
        return None

    edges = []

    for skill_name, skill_data in deps.get('skills', {}).items():
        calls = skill_data.get('calls', [])
        prev_id = None
        for call in calls:
            curr_id = get_node_id_from_call(call)
            if prev_id and curr_id:
                edges.append(f"    {prev_id} -> {curr_id} [style=invis, weight=10];")
            prev_id = curr_id

    for cmd_name, cmd_data in deps.get('commands', {}).items():
        calls = cmd_data.get('calls', [])
        if not calls:
            continue
        prev_id = None
        for call in calls:
            curr_id = get_node_id_from_call(call)
            if prev_id and curr_id:
                edges.append(f"    {prev_id} -> {curr_id} [style=invis, weight=10];")
            prev_id = curr_id

    return edges


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
    lines.append("    // L0: Controller/Entry Point Skills")
    for skill_name in layers['controllers']:
        sid = safe_id(f"skill_{skill_name}")
        node_id = f"skill:{skill_name}"
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(skill_name, tokens, f"{plugin_name}:")
        skill_type = deps.get('skills', {}).get(skill_name, {}).get('type', 'controller')
        if skill_type == 'team-controller':
            lines.append(f'    {sid} [label="{label}", shape=ellipse, style=filled, fillcolor="#66bb6a", peripheries=2];')
        else:
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
            if cmd_type == 'team-phase':
                lines.append(f'    {cid} [label="{label}", shape=box, style="filled,bold", fillcolor="#c5cae9"];')
            elif cmd_type == 'composite':
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
        elif agent_type == 'team-worker':
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style=filled, fillcolor="#b39ddb"];')
        elif conditional:
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style="filled,dashed", fillcolor="#f3e5f5"];')
        else:
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style=filled, fillcolor="#ede7f6"];')
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
            elif call.get('command'):
                cmd_id = safe_id(f"cmd_{call['command']}")
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
    for cmd_data in deps.get('commands', {}).values():
        existing_types.add(cmd_data.get('type', 'atomic'))
    for agent_data in deps.get('agents', {}).values():
        existing_types.add(agent_data.get('type', 'specialist'))
    # entry_point → controller に正規化
    if 'entry_point' in existing_types:
        existing_types.add('controller')

    legend_defs = [
        ('controller',      'Controller (skill)',      'ellipse', '#c8e6c9', 'filled'),
        ('team-controller', 'Team-Controller (skill)', 'ellipse', '#66bb6a', 'filled'),
        ('workflow',        'Workflow (skill)',         'ellipse', '#e8f5e9', 'filled'),
        ('team-workflow',   'Team-Workflow (skill)',    'ellipse', '#a5d6a7', 'filled'),
        ('reference',       'Reference (skill)',       'note',    '#e1f5fe', 'filled'),
        ('atomic',          'Atomic (command)',         'box',     '#e3f2fd', 'filled'),
        ('team-phase',      'Team-Phase (command)',     'box',     '#c5cae9', '"filled,bold"'),
        ('composite',       'Composite (command)',      'box',     '#bbdefb', 'filled'),
        ('specialist',      'Specialist (agent)',       'ellipse', '#ede7f6', 'filled'),
        ('team-worker',     'Team-Worker (agent)',      'ellipse', '#b39ddb', 'filled'),
        ('orchestrator',    'Orchestrator (agent)',     'ellipse', '#f3e5f5', '"filled,bold"'),
    ]

    lines.append("    // Legend")
    lines.append("    subgraph cluster_legend {")
    lines.append('        label="Legend";')
    lines.append('        fontsize=9;')
    lines.append('        style=dashed;')
    for (type_name, label, shape, color, style) in legend_defs:
        if type_name in existing_types:
            lid = safe_id(f"legend_{type_name}")
            extra = ', peripheries=2' if type_name == 'team-controller' else ''
            lines.append(f'        {lid} [label="{label}", shape={shape}, style={style}, fillcolor="{color}"{extra}];')
    if layers.get('sub_commands'):
        lines.append('        legend_sub [label="Sub Command", shape=box, style=filled, fillcolor="#fff3e0"];')
    if layers.get('externals'):
        lines.append('        legend_ext [label="External", shape=parallelogram, style=filled, fillcolor="#eceff1"];')
    if layers.get('orphan_commands'):
        lines.append('        legend_orphan [label="Orphan", shape=box, style=filled, fillcolor="#ffcdd2"];')
    lines.append("    }")

    lines.append("}")
    return '\n'.join(lines)


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
    lines.append("    // L0: Controller/Entry Point Skills")
    for skill_name in layers['controllers']:
        node_id = f"skill:{skill_name}"
        if node_id not in allowed_nodes:
            continue
        sid = safe_id(f"skill_{skill_name}")
        tokens = graph.get(node_id, {}).get('tokens', 0)
        label = format_label(skill_name, tokens, f"{plugin_name}:")
        skill_type = deps.get('skills', {}).get(skill_name, {}).get('type', 'controller')
        if skill_type == 'team-controller':
            lines.append(f'    {sid} [label="{label}", shape=ellipse, style=filled, fillcolor="#66bb6a", peripheries=2];')
        else:
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
            if cmd_type == 'team-phase':
                lines.append(f'    {cid} [label="{label}", shape=box, style="filled,bold", fillcolor="#c5cae9"];')
            elif cmd_type == 'composite':
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
        elif agent_type == 'team-worker':
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style=filled, fillcolor="#b39ddb"];')
        elif conditional:
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style="filled,dashed", fillcolor="#f3e5f5"];')
        else:
            lines.append(f'    {aid} [label="{label}", shape=ellipse, style=filled, fillcolor="#ede7f6"];')
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
                            ('command', 'cmd'), ('composite', 'cmd'), ('phase', 'cmd'),
                            ('specialist', 'agent'), ('agent', 'agent'), ('worker', 'agent')]:
            val = call.get(key)
            if val is None:
                continue
            # ノードIDの構築
            if key in ('skill', 'reference', 'workflow'):
                target_node = f"skill:{val}"
            elif key in ('command', 'composite', 'phase'):
                target_node = f"command:{val}"
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
            elif ntype == 'external':
                allowed_gv_ids.add(safe_id(f"ext_{nname}"))

    ordering_edges = generate_ordering_edges(deps)
    if ordering_edges:
        import re
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

    # === L4: 外部依存 ===
    lines.append("    subgraph L4[\"External\"]")
    lines.append("        direction TB")
    for ext_name in layers['externals']:
        lines.append(f"        {safe_id(ext_name, 'ext_')}[/{ext_name}/]")
    lines.append("    end")
    lines.append("")

    # === 層間接続 ===
    lines.append("    %% Layer connections")
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
            elif c.get('command'):
                targets.append(c['command'])
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
            elif call.get('composite'):
                targets.append(f"◆{call['composite']}")
            elif call.get('specialist'):
                targets.append(f"●{call['specialist']}")
            elif call.get('agent'):
                targets.append(f"⟶{call['agent']}")
            elif call.get('reference'):
                targets.append(f"→{plugin_name}:{call['reference']}")
        for agent in cmd_data.get('uses_agents', []):
            targets.append(f"⟶{agent}")
        if targets:
            lines.append(f"| {cmd_name} | {', '.join(targets)} |")

    for agent_name, agent_data in deps.get('agents', {}).items():
        targets = []
        for call in agent_data.get('calls', []):
            if call.get('command'):
                targets.append(call['command'])
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
        for ref_skill in agent_data.get('skills', []):
            targets.append(f"→{plugin_name}:{ref_skill}")
        if targets:
            lines.append(f"| ⟶{agent_name} | {', '.join(targets)} |")

    lines.append("")
    lines.append("</details>")

    return '\n'.join(lines)


def print_graphviz(graph: Dict, deps: dict, plugin_name: str, show_tokens: bool = True):
    """Graphviz DOT形式でグラフを出力"""
    print(generate_graphviz(graph, deps, plugin_name, show_tokens))


def print_mermaid(graph: Dict, deps: dict, plugin_name: str):
    """Mermaid形式でグラフを出力"""
    print(generate_mermaid(graph, deps, plugin_name))


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


README_MARKER_START = "<!-- DEPS-GRAPH-START -->"
README_MARKER_END = "<!-- DEPS-GRAPH-END -->"
README_SUBGRAPH_START = "<!-- DEPS-SUBGRAPHS-START -->"
README_SUBGRAPH_END = "<!-- DEPS-SUBGRAPHS-END -->"


def update_readme(plugin_root: Path, graph: Dict, deps: dict, plugin_name: str, show_tokens: bool = True) -> bool:
    """README.mdの依存グラフセクション + サブグラフセクションを更新"""
    readme_path = plugin_root / "README.md"
    if not readme_path.exists():
        print(f"Error: {readme_path} not found", file=sys.stderr)
        return False

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

    readme_path.write_text(content, encoding='utf-8')
    print(f"Updated: {readme_path}")
    return True


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
            elif c.get('command'):
                targets.append(c['command'])
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
            elif call.get('composite'):
                targets.append(f"◆{call['composite']}")
            elif call.get('specialist'):
                targets.append(f"●{call['specialist']}")
            elif call.get('agent'):
                targets.append(f"⟶{call['agent']}")
            elif call.get('reference'):
                targets.append(f"→{plugin_name}:{call['reference']}")
        for agent in cmd_data.get('uses_agents', []):
            targets.append(f"⟶{agent}")
        if targets:
            lines.append(f"| {cmd_name} | {', '.join(targets)} |")

    for agent_name, agent_data in deps.get('agents', {}).items():
        targets = []
        for call in agent_data.get('calls', []):
            if call.get('command'):
                targets.append(call['command'])
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
        for ref_skill in agent_data.get('skills', []):
            targets.append(f"→{plugin_name}:{ref_skill}")
        if targets:
            lines.append(f"| ⟶{agent_name} | {', '.join(targets)} |")

    return '\n'.join(lines)


def print_rich_tree(graph: Dict, node_id: str):
    """Rich表示"""
    try:
        from rich.console import Console
        from rich.tree import Tree
        from rich.panel import Panel
    except ImportError:
        print("Rich not installed. Falling back to ASCII tree.")
        print("Install with: pip install rich")
        print()
        print_tree(graph, node_id)
        return

    console = Console()

    node = graph.get(node_id)
    if not node:
        console.print(f"[red]Node not found: {node_id}[/red]")
        return

    def add_children(tree: Tree, nid: str, visited: Set[str]):
        n = graph.get(nid)
        if not n or nid in visited:
            return
        visited.add(nid)

        for (t, name) in n['calls']:
            child_id = f"{t}:{name}"
            style = "blue" if t == 'command' else "green"
            label = f"[{style}]{name}[/{style}] ({t})"
            branch = tree.add(label)
            add_children(branch, child_id, visited)

        for agent in n['uses_agents']:
            child_id = f"agent:{agent}"
            child = graph.get(child_id)
            conditional = f" [{child['conditional']}]" if child and child.get('conditional') else ""
            tree.add(f"[yellow]{agent}[/yellow] (agent){conditional}")

        for ext in n['external']:
            tree.add(f"[dim]{ext}[/dim] (external)")

    root_label = f"[bold]{node['name']}[/bold] ({node['type']})"
    tree = Tree(root_label)
    add_children(tree, node_id, set())

    console.print(Panel(tree, title="Dependency Tree"))


def check_files(graph: Dict, plugin_root: Path) -> List[Tuple[str, str, str]]:
    """ファイル存在確認"""
    results = []

    for node_id, node_data in graph.items():
        if node_data['type'] == 'external':
            results.append(('external', node_id, None))
            continue

        path = node_data.get('path')
        if not path:
            results.append(('no_path', node_id, None))
            continue

        full_path = plugin_root / path
        if full_path.exists():
            results.append(('ok', node_id, path))
        else:
            results.append(('missing', node_id, path))

    return results


def find_orphans(graph: Dict, deps: dict) -> Dict[str, List[str]]:
    """孤立ノードを検出"""
    # エントリーポイント / controller を特定
    entry_points = set()
    references = set()
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', '')
        if skill_type in ('entry_point', 'controller', 'team-controller'):
            entry_points.add(f"skill:{skill_name}")
        elif skill_type == 'reference':
            references.add(f"skill:{skill_name}")

    # redirects / launcher を特定
    redirects = set()
    for cmd_name, cmd_data in deps.get('commands', {}).items():
        if cmd_data.get('redirects_to'):
            redirects.add(f"command:{cmd_name}")
        if cmd_data.get('type') == 'launcher':
            redirects.add(f"command:{cmd_name}")

    unused = []
    no_deps = []
    isolated = []

    for node_id, node_data in graph.items():
        if node_data['type'] == 'external':
            continue

        has_callers = len(node_data['required_by']) > 0
        has_deps = (
            len(node_data['calls']) > 0 or
            len(node_data['uses_agents']) > 0 or
            len(node_data['external']) > 0
        )

        is_excluded = (
            node_id in entry_points or
            node_id in references or
            node_id in redirects
        )

        if not has_callers and not is_excluded:
            unused.append(node_id)

        if not has_deps and node_data['type'] != 'agent':
            no_deps.append(node_id)

        if not has_callers and not has_deps and not is_excluded:
            isolated.append(node_id)

    return {
        'unused': sorted(unused),
        'no_deps': sorted(no_deps),
        'isolated': sorted(isolated),
    }


def resolve_type(t: str) -> str:
    """型エイリアスを解決"""
    return TYPE_ALIASES.get(t, t)


def validate_types(deps: dict, graph: Dict) -> Tuple[int, List[str]]:
    """型ルール（can_spawn/spawnable_by）の整合性を検証

    4つのチェック:
    1. セクション配置: controller は skills に、atomic は commands に等
    2. can_spawn 宣言: 宣言値が TYPE_RULES の許可範囲内か
    3. spawnable_by 宣言: 宣言値が TYPE_RULES の許可範囲内か
    4. 呼び出しエッジ: 各 calls が caller の can_spawn と callee の spawnable_by を満たすか

    Returns: (ok_count, violations_list)
    """
    ok_count = 0
    violations = []

    # セクション → コンポーネント型のマッピング
    section_map = {'skills': 'skill', 'commands': 'command', 'agents': 'agent'}

    for section in ('skills', 'commands', 'agents'):
        for name, data in deps.get(section, {}).items():
            comp_type = data.get('type')
            if not comp_type:
                continue

            resolved = resolve_type(comp_type)
            rule = TYPE_RULES.get(resolved)
            if not rule:
                violations.append(f"[unknown-type] {section}/{name}: type '{comp_type}' is not defined in TYPE_RULES")
                continue

            # Check 1: セクション配置
            if rule['section'] != section:
                violations.append(
                    f"[section] {section}/{name}: type '{comp_type}' should be in '{rule['section']}', not '{section}'"
                )
            else:
                ok_count += 1

            # Check 2: can_spawn 宣言値
            declared_can_spawn = set(data.get('can_spawn', []))
            allowed_can_spawn = rule['can_spawn']
            invalid_spawn = {resolve_type(s) for s in declared_can_spawn} - allowed_can_spawn
            if invalid_spawn:
                violations.append(
                    f"[can_spawn] {section}/{name}: declares can_spawn={sorted(invalid_spawn)} but type '{comp_type}' only allows {sorted(allowed_can_spawn)}"
                )
            else:
                ok_count += 1

            # Check 3: spawnable_by 宣言値
            declared_spawnable = set(data.get('spawnable_by', []))
            allowed_spawnable = rule['spawnable_by']
            invalid_spawnable = {resolve_type(s) for s in declared_spawnable} - {resolve_type(a) for a in allowed_spawnable}
            if invalid_spawnable:
                violations.append(
                    f"[spawnable_by] {section}/{name}: declares spawnable_by={sorted(invalid_spawnable)} but type '{comp_type}' only allows {sorted(allowed_spawnable)}"
                )
            else:
                ok_count += 1

    # Check 4: 呼び出しエッジの型整合性
    # 各 calls エントリについて、caller の can_spawn に callee の型が含まれるか、
    # callee の spawnable_by に caller の型が含まれるかを確認
    call_key_to_section = {
        'command': 'commands', 'composite': 'commands',
        'skill': 'skills', 'reference': 'skills',
        'agent': 'agents', 'specialist': 'agents',
        # Agent Teams 固有の calls キー
        'workflow': 'skills', 'phase': 'commands', 'worker': 'agents',
    }

    for section in ('skills', 'commands', 'agents'):
        for name, data in deps.get(section, {}).items():
            caller_type = resolve_type(data.get('type', ''))
            caller_rule = TYPE_RULES.get(caller_type)
            if not caller_rule:
                continue

            for call in data.get('calls', []):
                for call_key, callee_name in call.items():
                    target_section = call_key_to_section.get(call_key)
                    if not target_section:
                        continue

                    callee_data = deps.get(target_section, {}).get(callee_name, {})
                    callee_type = resolve_type(callee_data.get('type', ''))
                    callee_rule = TYPE_RULES.get(callee_type)
                    if not callee_rule:
                        continue

                    # caller の can_spawn に callee の型が含まれるか
                    if callee_type not in caller_rule['can_spawn']:
                        violations.append(
                            f"[edge] {section}/{name} ({caller_type}) -> {target_section}/{callee_name} ({callee_type}): "
                            f"'{caller_type}' cannot spawn '{callee_type}' (allowed: {sorted(caller_rule['can_spawn'])})"
                        )
                    else:
                        ok_count += 1

                    # callee の spawnable_by に caller の型が含まれるか
                    callee_spawnable = {resolve_type(s) for s in callee_rule['spawnable_by']}
                    if caller_type not in callee_spawnable:
                        violations.append(
                            f"[edge] {section}/{name} ({caller_type}) -> {target_section}/{callee_name} ({callee_type}): "
                            f"'{callee_type}' is not spawnable_by '{caller_type}' (allowed: {sorted(callee_rule['spawnable_by'])})"
                        )
                    else:
                        ok_count += 1

    # Check 5: Agent Teams 固有の検証
    # team_config の値チェック
    team_config = deps.get('team_config')
    if team_config:
        valid_lifecycles = {'persistent', 'per_phase'}
        lifecycle = team_config.get('lifecycle')
        if lifecycle and lifecycle not in valid_lifecycles:
            violations.append(
                f"[team_config] lifecycle '{lifecycle}' is invalid (allowed: {sorted(valid_lifecycles)})"
            )
        else:
            ok_count += 1

        valid_models = {'sonnet', 'opus', 'haiku'}
        default_model = team_config.get('default_model')
        if default_model and default_model not in valid_models:
            violations.append(
                f"[team_config] default_model '{default_model}' is invalid (allowed: {sorted(valid_models)})"
            )
        else:
            ok_count += 1

        max_size = team_config.get('max_size')
        if max_size is not None and (not isinstance(max_size, int) or max_size < 1):
            violations.append(
                f"[team_config] max_size must be a positive integer, got '{max_size}'"
            )
        else:
            ok_count += 1

    # team-phase の workers リストが agents セクションに存在するか
    for name, data in deps.get('commands', {}).items():
        if resolve_type(data.get('type', '')) == 'team-phase':
            workers = data.get('workers', [])
            for worker_name in workers:
                if worker_name not in deps.get('agents', {}):
                    violations.append(
                        f"[workers] commands/{name}: worker '{worker_name}' not found in agents section"
                    )
                else:
                    ok_count += 1

    # team-worker の checkpoint_ref が reference スキルとして存在するか
    for name, data in deps.get('agents', {}).items():
        if resolve_type(data.get('type', '')) == 'team-worker':
            cp_ref = data.get('checkpoint_ref')
            if cp_ref:
                ref_data = deps.get('skills', {}).get(cp_ref, {})
                if not ref_data:
                    violations.append(
                        f"[checkpoint_ref] agents/{name}: checkpoint_ref '{cp_ref}' not found in skills section"
                    )
                elif resolve_type(ref_data.get('type', '')) != 'reference':
                    violations.append(
                        f"[checkpoint_ref] agents/{name}: checkpoint_ref '{cp_ref}' is type '{ref_data.get('type')}', expected 'reference'"
                    )
                else:
                    ok_count += 1

    return ok_count, violations


def _count_body_lines(file_path: Path) -> int:
    """frontmatter を除外した本文行数を返す"""
    if not file_path.exists():
        return 0
    try:
        lines = file_path.read_text(encoding='utf-8').splitlines()
    except Exception:
        return 0
    # frontmatter 除外
    if lines and lines[0].strip() == '---':
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == '---':
                return len(lines) - i - 1
    return len(lines)


def _parse_frontmatter_tools(file_path: Path) -> Set[str]:
    """frontmatter の allowed-tools / tools を抽出"""
    if not file_path.exists():
        return set()
    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception:
        return set()
    lines = content.splitlines()
    if not lines or lines[0].strip() != '---':
        return set()
    tools = set()
    in_tools_list = False
    for line in lines[1:]:
        if line.strip() == '---':
            break
        # allowed-tools: Read, Write, Edit
        if line.startswith('allowed-tools:'):
            val = line.split(':', 1)[1].strip()
            tools.update(t.strip() for t in val.split(',') if t.strip())
            in_tools_list = False
        # tools: [Read, Write] or tools:\n  - Read
        elif line.startswith('tools:'):
            val = line.split(':', 1)[1].strip()
            if val.startswith('['):
                val = val.strip('[] ')
                tools.update(t.strip() for t in val.split(',') if t.strip())
                in_tools_list = False
            elif val:
                tools.update(t.strip() for t in val.split(',') if t.strip())
                in_tools_list = False
            else:
                in_tools_list = True
        elif in_tools_list and line.strip().startswith('- '):
            tools.add(line.strip()[2:].strip())
        elif in_tools_list and not line.startswith(' ') and not line.startswith('\t'):
            in_tools_list = False
    return tools


def _scan_body_for_mcp_tools(file_path: Path) -> Set[str]:
    """body から mcp__* パターンのツール参照をスキャン"""
    if not file_path.exists():
        return set()
    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception:
        return set()
    lines = content.splitlines()
    # skip frontmatter
    body_start = 0
    if lines and lines[0].strip() == '---':
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == '---':
                body_start = i + 1
                break
    import re
    body = '\n'.join(lines[body_start:])
    tools = set(re.findall(r'mcp__[\w-]+__[\w-]+', body))
    # Exclude placeholder patterns (e.g., mcp__xxx__yyy)
    tools = {t for t in tools if not re.fullmatch(r'mcp__x+__y+', t)}
    return tools


def deep_validate(deps: dict, plugin_root: Path) -> Tuple[List[str], List[str], List[str]]:
    """深層検証: controller bloat, ref配置, tools整合性

    Returns: (criticals, warnings, infos)
    """
    criticals_set: Set[str] = set()
    warnings_set: Set[str] = set()
    infos_set: Set[str] = set()

    criticals: List[str] = []
    warnings: List[str] = []
    infos: List[str] = []

    def add_critical(msg: str):
        if msg not in criticals_set:
            criticals_set.add(msg)
            criticals.append(msg)

    def add_warning(msg: str):
        if msg not in warnings_set:
            warnings_set.add(msg)
            warnings.append(msg)

    def add_info(msg: str):
        if msg not in infos_set:
            infos_set.add(msg)
            infos.append(msg)

    COMMON_TOOLS = {'Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Task',
                    'SendMessage', 'AskUserQuestion', 'WebSearch', 'WebFetch',
                    'Agent', 'Skill'}

    # (A) Controller 行数チェック
    for name, spec in deps.get('skills', {}).items():
        comp_type = spec.get('type', '')
        if comp_type in ('controller', 'team-controller'):
            path = plugin_root / spec.get('path', '')
            body_lines = _count_body_lines(path)
            if body_lines > 200:
                add_critical(f"[controller-bloat] {name}: {body_lines} lines (>200)")
            elif body_lines > 120:
                add_warning(f"[controller-bloat] {name}: {body_lines} lines (>120)")

    # (B) Reference 配置監査
    # 全コンポーネントの calls から reference と downstream を収集
    all_components = {}
    for section in ('skills', 'commands', 'agents'):
        for cname, cdata in deps.get(section, {}).items():
            all_components[cname] = (section, cdata)

    for parent_name, (parent_section, parent_spec) in all_components.items():
        refs_in_calls = []
        downstreams_in_calls = []
        for call in parent_spec.get('calls', []):
            for call_key, callee_name in call.items():
                callee_data = all_components.get(callee_name, (None, {}))
                callee_type = callee_data[1].get('type', '') if callee_data[0] else ''
                resolved_callee = resolve_type(callee_type)
                if call_key == 'reference' or resolved_callee == 'reference':
                    refs_in_calls.append(callee_name)
                elif resolved_callee in ('atomic', 'composite', 'specialist', 'team-worker'):
                    downstreams_in_calls.append(callee_name)

        # 各 downstream の body を読んで、ref 名が出現するか確認
        for ds_name in downstreams_in_calls:
            ds_data = all_components.get(ds_name, (None, {}))
            if not ds_data[0]:
                continue
            ds_path = plugin_root / ds_data[1].get('path', '')
            if not ds_path.exists():
                continue
            try:
                ds_body = ds_path.read_text(encoding='utf-8')
            except Exception:
                continue
            ds_calls_refs = set()
            for call in ds_data[1].get('calls', []):
                for ck, cv in call.items():
                    if ck == 'reference':
                        ds_calls_refs.add(cv)
            for ref_name in refs_in_calls:
                if ref_name in ds_body and ref_name not in ds_calls_refs:
                    add_warning(
                        f"[ref-placement] {ds_name} body references {ref_name} but doesn't declare it in calls"
                    )

    # (C) Frontmatter-Body ツール整合性
    for section in ('commands', 'agents'):
        for cname, cdata in deps.get(section, {}).items():
            path_str = cdata.get('path', '')
            if not path_str:
                continue
            path = plugin_root / path_str
            declared = _parse_frontmatter_tools(path)
            used_mcp = _scan_body_for_mcp_tools(path)
            for tool in used_mcp - declared:
                add_warning(f"[tools-mismatch] {cname}: body uses {tool} but not declared in frontmatter")
            for tool in declared - used_mcp - COMMON_TOOLS:
                add_info(f"[tools-unused] {cname}: frontmatter declares {tool} but not used in body")

    return criticals, warnings, infos


# === Complexity Metrics ===


def check_dead_components(graph: Dict, deps: dict) -> List[str]:
    """entry_point から到達不能なノード（Dead Component）を検出"""
    # entry_point / controller / team-controller を特定
    entry_points = set()
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', '')
        if skill_type in ('entry_point', 'controller', 'team-controller'):
            entry_points.add(f"skill:{skill_name}")

    # 全 entry_point から到達可能なノードを収集
    reachable = set()
    for ep in entry_points:
        reachable |= collect_reachable_nodes(graph, ep)

    # reference は entry_point から直接呼ばれなくてもよい
    references = set()
    for skill_name, skill_data in deps.get('skills', {}).items():
        if skill_data.get('type') == 'reference':
            references.add(f"skill:{skill_name}")

    # 到達不能ノードを検出（external, reference を除外）
    dead = []
    for node_id in sorted(graph):
        if graph[node_id]['type'] == 'external':
            continue
        if node_id in references:
            continue
        if node_id not in reachable:
            dead.append(node_id)

    return dead


def check_usage_frequency(graph: Dict, plugin_root: Path) -> Optional[List[Tuple[str, Optional[str]]]]:
    """3ヶ月以上変更のないコンポーネントを検出。git外ならNone"""
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--git-dir'],
            capture_output=True, text=True, cwd=str(plugin_root)
        )
        if result.returncode != 0:
            return None
    except FileNotFoundError:
        return None

    # git リポジトリルートを取得
    repo_root_result = subprocess.run(
        ['git', 'rev-parse', '--show-toplevel'],
        capture_output=True, text=True, cwd=str(plugin_root)
    )
    if repo_root_result.returncode != 0 or not repo_root_result.stdout.strip():
        return None
    repo_root = Path(repo_root_result.stdout.strip())

    # plugin_root の repo_root からの相対パスを取得
    try:
        plugin_rel = plugin_root.resolve().relative_to(repo_root.resolve())
    except ValueError:
        plugin_rel = Path('')

    # 3ヶ月以内に変更されたファイルを収集
    result = subprocess.run(
        ['git', 'log', '--since=3 months ago', '--name-only', '--pretty=format:'],
        capture_output=True, text=True, cwd=str(repo_root)
    )
    recently_changed = set()
    for line in result.stdout.splitlines():
        line = line.strip()
        if line:
            recently_changed.add(line)

    # 各ノードのパスをチェック（plugin_root相対 → repo_root相対に変換）
    stale = []
    for node_id, node_data in sorted(graph.items()):
        if node_data['type'] == 'external':
            continue
        path = node_data.get('path')
        if not path:
            continue
        # パストラバーサル防止
        resolved = (plugin_root / path).resolve()
        if not str(resolved).startswith(str(plugin_root.resolve())):
            continue
        repo_path = str(plugin_rel / path) if str(plugin_rel) != '.' else path
        if repo_path not in recently_changed:
            # 最終変更日を取得
            log_result = subprocess.run(
                ['git', 'log', '-1', '--format=%ci', '--', repo_path],
                capture_output=True, text=True, cwd=str(repo_root)
            )
            last_date = log_result.stdout.strip()[:10] if log_result.stdout.strip() else None
            stale.append((node_id, last_date))

    return stale


def calc_depth_scores(graph: Dict, deps: dict) -> List[Tuple[str, int]]:
    """各 controller の最大パス長を計測"""
    scores = []
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', '')
        if skill_type not in ('controller', 'team-controller'):
            continue
        node_id = f"skill:{skill_name}"
        all_deps = get_dependencies(graph, node_id)
        max_depth = max((d for _, _, d in all_deps), default=0)
        scores.append((skill_name, max_depth))

    scores.sort(key=lambda x: x[1], reverse=True)
    return scores


def calc_fan_out(graph: Dict) -> List[Tuple[str, int]]:
    """各ノードの Fan-out（calls 先の数）を計測"""
    results = []
    for node_id, node_data in sorted(graph.items()):
        if node_data['type'] == 'external':
            continue
        fan_out = len(node_data['calls'])
        if fan_out > 0:
            results.append((node_id, fan_out))

    results.sort(key=lambda x: x[1], reverse=True)
    return results


def calc_type_balance(graph: Dict) -> Dict[str, int]:
    """型ごとのコンポーネント数を集計"""
    balance: Dict[str, int] = {}
    for node_id, node_data in graph.items():
        if node_data['type'] == 'external':
            continue
        # skill_type / command_type / agent_type を使用
        component_type = (
            node_data.get('skill_type') or
            node_data.get('command_type') or
            node_data.get('agent_type') or
            node_data['type']
        )
        balance[component_type] = balance.get(component_type, 0) + 1

    return balance


def check_duplication(graph: Dict, plugin_root: Path) -> List[Tuple[str, str, float]]:
    """specialist 間のプロンプト類似度を検出"""
    # specialist ノードを収集
    specialists = []
    for node_id, node_data in sorted(graph.items()):
        if node_data.get('agent_type') == 'specialist' or node_data.get('skill_type') == 'specialist':
            path = node_data.get('path')
            if path:
                full_path = (plugin_root / path).resolve()
                if not str(full_path).startswith(str(plugin_root.resolve())):
                    continue  # パストラバーサル防止
                if full_path.exists():
                    try:
                        content = full_path.read_text(encoding='utf-8')
                        specialists.append((node_id, content))
                    except Exception:
                        pass

    # ペアワイズ比較
    duplicates = []
    for i in range(len(specialists)):
        for j in range(i + 1, len(specialists)):
            name_a, content_a = specialists[i]
            name_b, content_b = specialists[j]
            ratio = difflib.SequenceMatcher(None, content_a, content_b).ratio()
            if ratio >= 0.6:
                duplicates.append((name_a, name_b, ratio))

    duplicates.sort(key=lambda x: x[2], reverse=True)
    return duplicates


def calc_cost_projection(graph: Dict, deps: dict) -> List[Tuple[str, int]]:
    """各 controller の推定コンテキスト消費量を計算"""
    costs = []
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', '')
        if skill_type not in ('controller', 'team-controller'):
            continue
        node_id = f"skill:{skill_name}"
        reachable = collect_reachable_nodes(graph, node_id)
        total_tokens = sum(graph[nid].get('tokens', 0) for nid in reachable if nid in graph)
        costs.append((skill_name, total_tokens))

    costs.sort(key=lambda x: x[1], reverse=True)
    return costs


def complexity_report(graph: Dict, deps: dict, plugin_root: Path):
    """7メトリクスの複雑さレポートを出力"""
    warnings_list = []
    print("=== Complexity Report ===")
    print()

    # 1. Dead Component
    dead = check_dead_components(graph, deps)
    print("## Dead Components")
    if dead:
        print()
        print("| Component | Type |")
        print("|-----------|------|")
        for node_id in dead:
            node = graph.get(node_id, {})
            print(f"| {node_id} | {node.get('skill_type') or node.get('command_type') or node.get('agent_type') or node.get('type', '')} |")
        print()
        warnings_list.append(f"Dead Components: {len(dead)}")
    else:
        print("  No dead components found.")
    print()

    # 2. Usage Frequency
    stale = check_usage_frequency(graph, plugin_root)
    print("## Usage Frequency (stale > 3 months)")
    if stale is None:
        print("  ⚠ Skipped (not in a git repository)")
    elif stale:
        print()
        print("| Component | Last Changed |")
        print("|-----------|-------------|")
        for node_id, last_date in stale[:20]:  # 上位20件
            print(f"| {node_id} | {last_date or 'unknown'} |")
        if len(stale) > 20:
            print(f"| ... and {len(stale) - 20} more | |")
        print()
    else:
        print("  All components changed within 3 months.")
    print()

    # 3. Depth Score
    depth_scores = calc_depth_scores(graph, deps)
    print("## Depth Score")
    if depth_scores:
        print()
        print("| Controller | Max Depth | Status |")
        print("|------------|-----------|--------|")
        for name, depth in depth_scores:
            status = "WARNING" if depth > 4 else "OK"
            if depth > 4:
                warnings_list.append(f"Depth Score: {name} = {depth}")
            print(f"| {name} | {depth} | {status} |")
        print()
    else:
        print("  No controllers found.")
    print()

    # 4. Fan-out
    fan_out = calc_fan_out(graph)
    high_fan_out = [(n, f) for n, f in fan_out if f > 8]
    print("## Fan-out")
    if high_fan_out:
        print()
        print("| Component | Fan-out | Status |")
        print("|-----------|---------|--------|")
        for node_id, fo in high_fan_out:
            warnings_list.append(f"Fan-out: {node_id} = {fo}")
            print(f"| {node_id} | {fo} | WARNING |")
        print()
    else:
        print("  All components within threshold (≤ 8).")
    # 上位5件を情報として表示
    if fan_out:
        print()
        print("  Top 5 fan-out:")
        for node_id, fo in fan_out[:5]:
            print(f"    {node_id}: {fo}")
    print()

    # 5. Type Balance
    balance = calc_type_balance(graph)
    total = sum(balance.values())
    print("## Type Balance")
    print()
    print("| Type | Count | Ratio |")
    print("|------|-------|-------|")
    for comp_type, count in sorted(balance.items(), key=lambda x: x[1], reverse=True):
        ratio = f"{count / total * 100:.1f}%" if total > 0 else "0%"
        print(f"| {comp_type} | {count} | {ratio} |")
    print(f"| **Total** | **{total}** | **100%** |")
    print()

    # 6. Duplication
    duplicates = check_duplication(graph, plugin_root)
    print("## Duplication (specialist pairs ≥ 60%)")
    if duplicates:
        print()
        print("| Specialist A | Specialist B | Similarity |")
        print("|-------------|-------------|------------|")
        for name_a, name_b, ratio in duplicates:
            warnings_list.append(f"Duplication: {name_a} ↔ {name_b} = {ratio:.1%}")
            print(f"| {name_a} | {name_b} | {ratio:.1%} |")
        print()
    else:
        print("  No duplicate pairs found.")
    print()

    # 7. Cost Projection
    costs = calc_cost_projection(graph, deps)
    print("## Cost Projection (estimated context tokens)")
    if costs:
        print()
        print("| Controller | Estimated Tokens |")
        print("|------------|-----------------|")
        for name, tokens in costs:
            print(f"| {name} | {tokens:,} |")
        print()
    else:
        print("  No controllers found.")
    print()

    # Summary
    print("## Summary")
    print()
    if warnings_list:
        print(f"⚠ {len(warnings_list)} WARNING(s):")
        for w in warnings_list:
            print(f"  - {w}")
    else:
        print("All metrics within thresholds.")
    print()


def main():
    parser = argparse.ArgumentParser(description='Analyze plugin dependencies')
    parser.add_argument('--tree', action='store_true', help='ASCII tree output')
    parser.add_argument('--rich', action='store_true', help='Rich tree output (requires rich)')
    parser.add_argument('--mermaid', action='store_true', help='Mermaid graph output')
    parser.add_argument('--graphviz', action='store_true', help='Graphviz DOT output (default)')
    parser.add_argument('--target', help='Show dependencies for target')
    parser.add_argument('--reverse', help='Show reverse dependencies for target')
    parser.add_argument('--check', action='store_true', help='Check file existence')
    parser.add_argument('--validate', action='store_true', help='Validate type rules (can_spawn/spawnable_by)')
    parser.add_argument('--list', action='store_true', help='List all nodes')
    parser.add_argument('--update-readme', action='store_true', help='Update README.md with SVG graph')
    parser.add_argument('--orphans', action='store_true', help='Find orphan nodes (unused/isolated)')
    parser.add_argument('--tokens', action='store_true', help='Show token counts for all nodes')
    parser.add_argument('--no-tokens', action='store_true', help='Hide token counts in graph output')
    parser.add_argument('--deep-validate', action='store_true', help='Deep validation (controller bloat, ref placement, tools consistency)')
    parser.add_argument('--complexity', action='store_true', help='Complexity metrics report')

    args = parser.parse_args()

    plugin_root = get_plugin_root()
    deps = load_deps(plugin_root)
    graph = build_graph(deps, plugin_root)
    plugin_name = get_plugin_name(deps, plugin_root)

    # デフォルトはGraphviz
    if not any([args.tree, args.rich, args.mermaid, args.graphviz, args.target, args.reverse, args.check, args.validate, args.list, args.update_readme, args.orphans, args.tokens, args.deep_validate, args.complexity]):
        args.graphviz = True

    show_tokens = not args.no_tokens

    if args.complexity:
        complexity_report(graph, deps, plugin_root)

    if args.tokens:
        print("=== Token Counts ===")
        print()

        total_tokens = 0
        sections = [
            ('Skills', 'skill'),
            ('Commands', 'command'),
            ('Agents', 'agent'),
        ]

        for section_name, node_type in sections:
            print(f"## {section_name}")
            section_total = 0
            items = []
            for node_id, node_data in sorted(graph.items()):
                if node_data['type'] == node_type:
                    tokens = node_data.get('tokens', 0)
                    items.append((node_data['name'], tokens))
                    section_total += tokens

            items.sort(key=lambda x: x[1], reverse=True)
            for name, tokens in items:
                print(f"  {name}: {tokens:,} tokens")

            print(f"  --- subtotal: {section_total:,} tokens")
            print()
            total_tokens += section_total

        print(f"=== Total: {total_tokens:,} tokens ===")

    elif args.update_readme:
        success = update_readme(plugin_root, graph, deps, plugin_name, show_tokens)
        if not success:
            sys.exit(1)

    elif args.check:
        results = check_files(graph, plugin_root)

        ok_count = sum(1 for r in results if r[0] == 'ok')
        missing_count = sum(1 for r in results if r[0] == 'missing')
        no_path_count = sum(1 for r in results if r[0] == 'no_path')
        external_count = sum(1 for r in results if r[0] == 'external')

        print(f"=== File Check Results ===")
        print(f"OK: {ok_count}, Missing: {missing_count}, No path: {no_path_count}, External: {external_count}")
        print()

        if missing_count > 0:
            print("Missing files:")
            for status, node_id, path in results:
                if status == 'missing':
                    print(f"  - {node_id}: {path}")
            sys.exit(1)
        else:
            print("All files exist.")

    elif args.validate:
        ok_count, violations = validate_types(deps, graph)
        print(f"=== Type Validation Results ===")
        print(f"OK: {ok_count}, Violations: {len(violations)}")
        print()

        if violations:
            print("Violations:")
            for v in violations:
                print(f"  - {v}")
            sys.exit(1)
        else:
            print("All type constraints satisfied.")

    elif args.orphans:
        orphans = find_orphans(graph, deps)

        print("=== Orphan Analysis ===")
        print()

        if orphans['isolated']:
            print("## Isolated (no callers, no deps):")
            for node_id in orphans['isolated']:
                node = graph.get(node_id)
                desc = node['description'][:40] if node['description'] else ''
                print(f"  - {node_id}: {desc}...")
            print()

        if orphans['unused']:
            print("## Unused (no callers):")
            for node_id in orphans['unused']:
                if node_id not in orphans['isolated']:
                    node = graph.get(node_id)
                    desc = node['description'][:40] if node['description'] else ''
                    print(f"  - {node_id}: {desc}...")
            print()

        leaf_commands = [n for n in orphans['no_deps'] if graph[n]['type'] == 'command']
        if leaf_commands:
            print("## Leaf commands (no outgoing deps):")
            for node_id in leaf_commands:
                print(f"  - {node_id}")
            print()

        total_orphans = len(orphans['unused'])
        if total_orphans == 0:
            print("No orphan nodes found.")
        else:
            print(f"Total unused: {total_orphans}")

    elif args.deep_validate:
        # --validate の全チェックも実行
        ok_count, violations = validate_types(deps, graph)

        # deep-validate 固有チェック
        criticals, dv_warnings, dv_infos = deep_validate(deps, plugin_root)

        print("=== Deep Validation Results ===")
        print()

        # --validate 結果
        print(f"## Type Validation: OK={ok_count}, Violations={len(violations)}")
        if violations:
            for v in violations:
                print(f"  - {v}")
        print()

        # deep-validate 結果
        has_issues = False
        if criticals:
            has_issues = True
            print("## Critical:")
            for c in criticals:
                print(f"  - {c}")
            print()
        if dv_warnings:
            has_issues = True
            print("## Warning:")
            for w in dv_warnings:
                print(f"  - {w}")
            print()
        if dv_infos:
            print("## Info:")
            for i in dv_infos:
                print(f"  - {i}")
            print()

        if not has_issues and not violations:
            print("All deep validation checks passed.")
        elif violations or criticals:
            sys.exit(1)

    elif args.list:
        print("=== All Nodes ===")
        for section in ['skills', 'commands', 'agents']:
            print(f"\n## {section.upper()}")
            for node_id in sorted(graph):
                if graph[node_id]['type'] == section.rstrip('s'):
                    node = graph[node_id]
                    skill_type = f" [{node.get('skill_type')}]" if node.get('skill_type') else ""
                    desc = node['description'][:50] if node['description'] else ''
                    print(f"  {node['name']}{skill_type}: {desc}...")

        print("\n## EXTERNAL")
        for node_id in sorted(graph):
            if graph[node_id]['type'] == 'external':
                print(f"  {graph[node_id]['name']}")

    elif args.target:
        node_id = find_node(graph, args.target)
        if not node_id:
            print(f"Error: '{args.target}' not found", file=sys.stderr)
            sys.exit(1)

        if args.rich:
            print_rich_tree(graph, node_id)
        else:
            print(f"=== Dependencies of {args.target} ===")
            print()
            print_tree(graph, node_id)

    elif args.reverse:
        node_id = find_node(graph, args.reverse)
        if not node_id:
            print(f"Error: '{args.reverse}' not found", file=sys.stderr)
            sys.exit(1)

        reverse = get_reverse_dependencies(graph, node_id)
        print(f"=== What uses {args.reverse} ===")
        print()
        if reverse:
            for (nid, rel) in reverse:
                node = graph.get(nid)
                if node:
                    print(f"  {node['type']}:{node['name']}")
        else:
            print("  (nothing)")

    elif args.tree:
        # エントリポイントからツリー表示
        # entry_points から最初のスキルを取得
        entry_points = deps.get('entry_points', [])
        if entry_points:
            skill_name = Path(entry_points[0]).parent.name
        else:
            # フォールバック: entry_point タイプのスキルを検索
            skill_name = 'entry-workflow'
            for sname, sdata in deps.get('skills', {}).items():
                if sdata.get('type') in ('entry_point', 'controller'):
                    skill_name = sname
                    break
        node_id = f"skill:{skill_name}"

        print(f"=== Dependency Tree from {skill_name} ===")
        print()
        print_tree(graph, node_id)

    elif args.rich:
        entry_points = deps.get('entry_points', [])
        if entry_points:
            skill_name = Path(entry_points[0]).parent.name
        else:
            skill_name = 'entry-workflow'
            for sname, sdata in deps.get('skills', {}).items():
                if sdata.get('type') in ('entry_point', 'controller'):
                    skill_name = sname
                    break
        node_id = f"skill:{skill_name}"
        print_rich_tree(graph, node_id)

    elif args.mermaid:
        print_mermaid(graph, deps, plugin_name)

    elif args.graphviz:
        print_graphviz(graph, deps, plugin_name, show_tokens)


if __name__ == '__main__':
    main()
