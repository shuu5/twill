from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.plugin import get_plugin_root, load_deps, build_graph
from twl.core.types import resolve_type


def find_node(graph: Dict, target: str) -> Optional[str]:
    """ターゲット名からノードIDを検索"""
    # 完全一致を試行
    for prefix in ['skill', 'command', 'agent', 'script', 'external', 'xref']:
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
    for (t, n, *_rest) in node['calls']:
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
    for (t, n, *_rest) in node['calls']:
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
            'controllers': [skill_names],  # controller
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
    from twl.validation.check import find_orphans

    result = {
        'controllers': [],
        'observers': [],
        'workflows': [],
        'orchestrators': [],
        'references': [],
        'launchers': [],
        'direct_commands': set(),
        'sub_commands': set(),
        'orphan_commands': [],
        'agents': list(deps.get('agents', {}).keys()),
        'scripts': list(deps.get('scripts', {}).keys()),
        'externals': [],
    }

    # スキルの分類
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', 'workflow')
        if skill_type == 'controller':
            result['controllers'].append(skill_name)
        elif skill_type == 'observer':
            result['observers'].append(skill_name)
        elif skill_type == 'workflow':
            result['workflows'].append(skill_name)
        elif skill_type == 'reference':
            result['references'].append(skill_name)

    # refs セクション（reference 型スキル）
    for ref_name in deps.get('refs', {}):
        if ref_name not in result['references']:
            result['references'].append(ref_name)

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
            elif c.get('atomic'):
                result['direct_commands'].add(c['atomic'])

    for agent_name, agent_data in deps.get('agents', {}).items():
        for c in agent_data.get('calls', []):
            if c.get('command'):
                result['direct_commands'].add(c['command'])
            elif c.get('composite'):
                result['direct_commands'].add(c['composite'])
            elif c.get('phase'):
                result['direct_commands'].add(c['phase'])
            elif c.get('atomic'):
                result['direct_commands'].add(c['atomic'])

    # L2+: コマンドから再帰的に呼ばれるコマンド（BFS）
    visited = set(result['direct_commands'])
    frontier = set(result['direct_commands'])
    while frontier:
        next_frontier = set()
        for cmd_name in frontier:
            cmd_data = deps.get('commands', {}).get(cmd_name, {})
            for c in cmd_data.get('calls', []):
                child = c.get('command') or c.get('composite') or c.get('atomic') or c.get('phase')
                if child and child not in visited:
                    result['sub_commands'].add(child)
                    visited.add(child)
                    next_frontier.add(child)
        frontier = next_frontier

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
            'atomic': 'cmd', 'script': 'script',
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
