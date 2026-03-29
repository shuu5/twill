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
import hashlib
import json
import os
import re
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
# SSOT: types.yaml（存在すれば）。フォールバック: 以下のハードコード値。
_FALLBACK_TYPE_RULES = {
    'controller':  {'section': 'skills',   'can_spawn': {'workflow', 'atomic', 'composite', 'specialist', 'reference'}, 'spawnable_by': {'user', 'launcher'}},
    'workflow':    {'section': 'skills',   'can_spawn': {'atomic', 'composite', 'specialist'},  'spawnable_by': {'controller', 'user'}},
    'atomic':      {'section': 'commands', 'can_spawn': {'reference', 'script'},                  'spawnable_by': {'workflow', 'controller'}},
    'composite':   {'section': 'commands', 'can_spawn': {'specialist', 'script'},               'spawnable_by': {'workflow', 'controller'}},
    'specialist':  {'section': 'agents',   'can_spawn': set(),                                  'spawnable_by': {'workflow', 'composite', 'controller'}},
    'reference':   {'section': 'skills',   'can_spawn': set(),                                  'spawnable_by': {'controller', 'atomic', 'agents.skills', 'all'}},
    'script':      {'section': 'scripts',  'can_spawn': set(),                                  'spawnable_by': {'atomic', 'composite'}},
}
TYPE_ALIASES = {}

# specialist の model フィールド許可値
ALLOWED_MODELS = {"haiku", "sonnet", "opus"}


def _get_loom_root() -> Path:
    """loom-engine.py の配置ディレクトリ（= loom リポジトリルート）を返す"""
    return Path(__file__).resolve().parent


def load_type_rules(loom_root: Optional[Path] = None) -> dict:
    """types.yaml から TYPE_RULES を構築する。存在しなければフォールバック値を返す。"""
    if loom_root is None:
        loom_root = _get_loom_root()
    types_path = loom_root / "types.yaml"
    def _deep_copy_rules(src: dict) -> dict:
        return {k: {'section': v['section'], 'can_spawn': set(v['can_spawn']), 'spawnable_by': set(v['spawnable_by'])} for k, v in src.items()}

    if not types_path.exists():
        return _deep_copy_rules(_FALLBACK_TYPE_RULES)
    try:
        with open(types_path, encoding='utf-8') as f:
            data = yaml.safe_load(f)
        if not data or 'types' not in data:
            print(f"Warning: types.yaml has no 'types' key, using fallback", file=sys.stderr)
            return _deep_copy_rules(_FALLBACK_TYPE_RULES)
        rules = {}
        for type_name, type_def in data['types'].items():
            rules[type_name] = {
                'section': type_def.get('section', ''),
                'can_spawn': set(type_def.get('can_spawn', [])),
                'spawnable_by': set(type_def.get('spawnable_by', [])),
            }
        return rules
    except Exception as e:
        print(f"Warning: Failed to load types.yaml: {e}, using fallback", file=sys.stderr)
        return _deep_copy_rules(_FALLBACK_TYPE_RULES)


TYPE_RULES = load_type_rules()


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


def get_deps_version(deps: dict) -> str:
    """deps.yaml の version を返す。未指定時は "2.0" として扱う。"""
    return str(deps.get('version', '2.0'))


def get_plugin_name(deps: dict, plugin_root: Path) -> str:
    """プラグイン名を取得

    優先順位:
    1. deps.yaml の plugin フィールド
    2. plugin_root.name（ディレクトリ名）
    """
    return deps.get('plugin', plugin_root.name)


def build_envelope(command: str, version: str, plugin: str, items: list, exit_code: int) -> dict:
    """JSON 出力用の共通エンベロープを構築"""
    summary = {"critical": 0, "warning": 0, "info": 0, "ok": 0}
    for item in items:
        sev = item.get("severity", "info")
        if sev in summary:
            summary[sev] += 1
    summary["total"] = len(items)
    return {
        "command": command,
        "version": version,
        "plugin": plugin,
        "items": items,
        "summary": summary,
        "exit_code": exit_code,
    }


def output_json(envelope: dict):
    """エンベロープを stdout に JSON 出力"""
    print(json.dumps(envelope, ensure_ascii=False, indent=2))


def _parse_violation_to_item(violation: str, default_severity: str = "critical") -> dict:
    """violation 文字列を items 形式に変換

    パターン: [code] section/component: message
    """
    item = {"severity": default_severity, "component": "", "message": violation, "code": ""}
    m = re.match(r'\[([^\]]+)\]\s+(\S+?)/([\w-]+):\s*(.*)', violation)
    if m:
        item["code"] = m.group(1)
        item["component"] = m.group(3)
        item["message"] = m.group(4)
    else:
        m2 = re.match(r'\[([^\]]+)\]\s+([\w-]+):\s*(.*)', violation)
        if m2:
            item["code"] = m2.group(1)
            item["component"] = m2.group(2)
            item["message"] = m2.group(3)
    return item


def _violations_to_items(violations: List[str], severity: str = "critical") -> List[dict]:
    """violation 文字列リストを items リストに変換"""
    return [_parse_violation_to_item(v, severity) for v in violations]


def _check_results_to_items(results: List[Tuple[str, str, str]]) -> List[dict]:
    """check_files() の結果を items 形式に変換"""
    severity_map = {"missing": "critical", "no_path": "warning", "ok": "ok", "external": "info"}
    message_map = {"missing": "File missing", "no_path": "No path defined", "ok": "File exists", "external": "External component"}
    items = []
    for status, node_id, path in results:
        items.append({
            "severity": severity_map.get(status, "info"),
            "component": node_id,
            "message": message_map.get(status, status),
            "path": path or "",
            "status": status,
        })
    return items


def _deep_validate_to_items(criticals: List[str], warnings: List[str], infos: List[str]) -> List[dict]:
    """deep_validate() の結果を items 形式に変換"""
    items = []
    for msg in criticals:
        item = _parse_violation_to_item(msg, "critical")
        item["check"] = _extract_check_label(msg)
        items.append(item)
    for msg in warnings:
        item = _parse_violation_to_item(msg, "warning")
        item["check"] = _extract_check_label(msg)
        items.append(item)
    for msg in infos:
        item = _parse_violation_to_item(msg, "info")
        item["check"] = _extract_check_label(msg)
        items.append(item)
    return items


def _extract_check_label(msg: str) -> str:
    """deep-validate メッセージからチェックラベルを抽出

    [controller-bloat] → A, [ref-placement] → B, [tools-mismatch]/[tools-unused] → C,
    [chain-*] → chain, その他 → code そのまま
    """
    m = re.match(r'\[([^\]]+)\]', msg)
    if not m:
        return ""
    code = m.group(1)
    label_map = {
        "controller-bloat": "A",
        "ref-placement": "B",
        "tools-mismatch": "C",
        "tools-unused": "C",
    }
    if code in label_map:
        return label_map[code]
    if code.startswith("chain-"):
        return "chain"
    return code


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
                'calls': [(type, name, step), ...],
                'uses_agents': [name, ...],
                'external': [name, ...],
                'requires_mcp': [name, ...],
                'required_by': [(type, name), ...],
                'conditional': str | None,
                'tokens': int,
                'chain': str | None,       # v3.0: 所属チェーン名
                'step_in': dict | None,    # v3.0: {parent: str, step: str|None}
            }
        }
    """
    if plugin_root is None:
        plugin_root = get_plugin_root()

    graph = {}

    def parse_calls(call_list: list) -> list:
        """calls リストを (type, name, step) タプルのリストに変換

        step は calls エントリの 'step' フィールド値（v3.0）。なければ None。
        """
        result = []
        # キー → グラフ上のノードタイプ
        # v2.0 セクション名キー + v3.0 型名キー両方サポート
        key_map = {
            # v2.0 section-name keys
            'command': 'command', 'skill': 'skill', 'agent': 'agent',
            # v3.0 type-name keys (loom type → graph node type)
            'atomic': 'command', 'composite': 'command',
            'controller': 'skill', 'workflow': 'skill', 'reference': 'skill',
            'specialist': 'agent',
            # Agent Teams 固有キー
            'phase': 'command', 'worker': 'agent',
            # script 型
            'script': 'script',
        }
        for c in call_list:
            for key, node_type in key_map.items():
                if c.get(key):
                    step = c.get('step')
                    result.append((node_type, c[key], step))
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
            'chain': data.get('chain'),
            'step_in': data.get('step_in'),
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
            'chain': data.get('chain'),
            'step_in': data.get('step_in'),
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
            'chain': data.get('chain'),
            'step_in': data.get('step_in'),
        }

    # スクリプト
    for name, data in deps.get('scripts', {}).items():
        node_id = f"script:{name}"
        path = data.get('path')
        tokens = count_tokens(plugin_root / path) if path else 0
        calls = parse_calls(data.get('calls', []))
        graph[node_id] = {
            'type': 'script',
            'name': name,
            'path': path,
            'description': data.get('description', ''),
            'calls': calls,
            'uses_agents': [],
            'external': [],
            'requires_mcp': [],
            'required_by': [],
            'conditional': None,
            'tokens': tokens,
            'chain': data.get('chain'),
            'step_in': data.get('step_in'),
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
        for (t, n, *_rest) in node_data['calls']:
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
    for prefix in ['skill', 'command', 'agent', 'script', 'external']:
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
        'scripts': list(deps.get('scripts', {}).keys()),
        'externals': [],
    }

    # スキルの分類
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', 'workflow')
        if skill_type == 'controller':
            result['controllers'].append(skill_name)
        elif skill_type == 'workflow':
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

        for (t, name, *_rest) in n['calls']:
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
    # controller を特定
    entry_points = set()
    references = set()
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', '')
        if skill_type == 'controller':
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

        if not has_deps and node_data['type'] not in ('agent', 'script'):
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
    section_map = {'skills': 'skill', 'commands': 'command', 'agents': 'agent', 'scripts': 'script'}

    for section in ('skills', 'commands', 'agents', 'scripts'):
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
        # v2.0 section-name keys
        'command': 'commands', 'skill': 'skills', 'agent': 'agents',
        # v3.0 type-name keys
        'atomic': 'commands', 'composite': 'commands',
        'controller': 'skills', 'workflow': 'skills', 'reference': 'skills',
        'specialist': 'agents',
        # Agent Teams 固有の calls キー
        'phase': 'commands', 'worker': 'agents',
        # script 型
        'script': 'scripts',
    }

    for section in ('skills', 'commands', 'agents', 'scripts'):
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

    return ok_count, violations


def validate_body_refs(deps: dict, plugin_root: Path) -> Tuple[int, List[str]]:
    """body 内の /{plugin}:{name} 参照が deps.yaml に存在するか検証

    Returns: (ok_count, violations_list)
    """
    ok_count = 0
    violations = []

    plugin_name = get_plugin_name(deps, plugin_root)

    # deps.yaml の全コンポーネント名集合を構築
    all_names: Set[str] = set()
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for name in deps.get(section, {}).keys():
            all_names.add(name)

    # 参照パターン: /{plugin}:{name} or /{plugin}:[\w-]+
    ref_pattern = re.compile(r'/(' + re.escape(plugin_name) + r'):([\w-]+)')

    # 全 .md ファイルの body をスキャン
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            path = data.get('path')
            if not path:
                continue
            file_path = plugin_root / path
            if not _is_within_root(file_path, plugin_root):
                continue
            body = _get_body_text(file_path)
            if not body:
                continue

            matches = ref_pattern.findall(body)
            seen = set()
            for _plugin, ref_name in matches:
                if ref_name in seen:
                    continue
                seen.add(ref_name)
                if ref_name in all_names:
                    ok_count += 1
                else:
                    violations.append(
                        f"[body-ref] {section}/{comp_name}: reference '/{plugin_name}:{ref_name}' not found in deps.yaml"
                    )

    return ok_count, violations


def validate_v3_schema(deps: dict) -> Tuple[int, List[str]]:
    """v3.0 スキーマ固有の構文検証

    v2.0 では呼ばれない。v3.0 時のみ以下を検証:
    1. calls キーが型名（atomic/composite/workflow/controller/specialist/reference）であること
    2. step フィールドが文字列であること
    3. step_in 構造が {parent: str} であること
    4. chain フィールド値が chains セクションに存在すること
    5. chains セクションの steps 内コンポーネントが存在すること

    Returns: (ok_count, violations_list)
    """
    ok_count = 0
    violations = []

    version = get_deps_version(deps)
    if not version.startswith('3'):
        return ok_count, violations

    # 許可される v3.0 型名キー
    v3_type_keys = {'atomic', 'composite', 'workflow', 'controller', 'specialist', 'reference', 'script'}
    # v2.0 セクション名キー（v3.0 では非推奨）
    v2_section_keys = {'command', 'skill', 'agent'}

    # 全コンポーネント名集合
    all_components: Set[str] = set()
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for name in deps.get(section, {}).keys():
            all_components.add(name)

    chains = deps.get('chains', {})

    # Check 1: calls キーが型名であること
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for comp_name, data in deps.get(section, {}).items():
            for i, call in enumerate(data.get('calls', [])):
                call_keys = [k for k in call.keys() if k != 'step']
                for key in call_keys:
                    if key in v2_section_keys:
                        violations.append(
                            f"[v3-calls-key] {section}/{comp_name}/calls[{i}]: "
                            f"section-name key '{key}' is not allowed in v3.0, use type-name key "
                            f"(atomic/composite/workflow/controller/specialist/reference)"
                        )
                    elif key not in v3_type_keys:
                        violations.append(
                            f"[v3-calls-key] {section}/{comp_name}/calls[{i}]: "
                            f"unknown key '{key}'"
                        )
                    else:
                        ok_count += 1

                # Check 2: step フィールドが文字列であること
                step = call.get('step')
                if step is not None:
                    if not isinstance(step, str):
                        violations.append(
                            f"[v3-step-type] {section}/{comp_name}/calls[{i}]: "
                            f"step must be a string, got {type(step).__name__}"
                        )
                    else:
                        ok_count += 1

            # Check 3: step_in 構造
            step_in = data.get('step_in')
            if step_in is not None:
                if not isinstance(step_in, dict):
                    violations.append(
                        f"[v3-step_in-type] {section}/{comp_name}: "
                        f"step_in must be a dict, got {type(step_in).__name__}"
                    )
                elif 'parent' not in step_in:
                    violations.append(
                        f"[v3-step_in-parent] {section}/{comp_name}: "
                        f"step_in must have 'parent' key"
                    )
                elif not isinstance(step_in['parent'], str):
                    violations.append(
                        f"[v3-step_in-parent] {section}/{comp_name}: "
                        f"step_in.parent must be a string"
                    )
                else:
                    if step_in['parent'] not in all_components:
                        violations.append(
                            f"[v3-step_in-ref] {section}/{comp_name}: "
                            f"step_in.parent '{step_in['parent']}' not found in deps.yaml"
                        )
                    else:
                        ok_count += 1

            # Check 4: chain フィールド値が chains セクションに存在すること
            chain = data.get('chain')
            if chain is not None:
                if not isinstance(chain, str):
                    violations.append(
                        f"[v3-chain-type] {section}/{comp_name}: "
                        f"chain must be a string, got {type(chain).__name__}"
                    )
                elif chain not in chains:
                    violations.append(
                        f"[v3-chain-ref] {section}/{comp_name}: "
                        f"chain '{chain}' not found in chains section"
                    )
                else:
                    ok_count += 1

    # Check 5: chains セクションの構造と steps 内コンポーネント存在確認
    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            violations.append(
                f"[v3-chains-type] chains/{chain_name}: must be a dict"
            )
            continue

        steps = chain_data.get('steps', [])
        if not isinstance(steps, list):
            violations.append(
                f"[v3-chains-steps] chains/{chain_name}: steps must be a list"
            )
            continue

        for i, step_entry in enumerate(steps):
            if isinstance(step_entry, str):
                if step_entry not in all_components:
                    violations.append(
                        f"[v3-chains-ref] chains/{chain_name}/steps[{i}]: "
                        f"component '{step_entry}' not found in deps.yaml"
                    )
                else:
                    ok_count += 1
            else:
                violations.append(
                    f"[v3-chains-step-type] chains/{chain_name}/steps[{i}]: "
                    f"step entry must be a string, got {type(step_entry).__name__}"
                )

    # Check 6: 旧形式 scripts フィールド WARNING
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            legacy_scripts = data.get('scripts')
            if legacy_scripts is not None and isinstance(legacy_scripts, list):
                violations.append(
                    f"[v3-legacy-scripts] {section}/{comp_name}: "
                    f"component-level 'scripts' field is deprecated in v3.0, "
                    f"use top-level 'scripts' section with 'calls' references instead"
                )

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
        if comp_type == 'controller':
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
                elif resolved_callee in ('atomic', 'composite', 'specialist'):
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

    # (D) Model Declaration: specialist の model フィールド検証
    for section in ('skills', 'commands', 'agents'):
        for cname, cdata in deps.get(section, {}).items():
            comp_type = cdata.get('type', '')
            if resolve_type(comp_type) != 'specialist':
                continue
            model = cdata.get('model')
            if model is None:
                add_warning(f"[model-required] {cname}: specialist で model 未宣言")
            elif model == 'opus':
                add_warning(f"[model-required] {cname}: specialist に opus は推奨されません")
            elif model not in ALLOWED_MODELS:
                add_info(f"[model-required] {cname}: model '{model}' は許可リストにありません")

    # (E) Specialist 出力スキーマ検証
    for section in ('skills', 'commands', 'agents'):
        for cname, cdata in deps.get(section, {}).items():
            resolved = resolve_type(cdata.get('type', ''))
            if resolved != 'specialist':
                continue

            output_schema = cdata.get('output_schema', None)
            if output_schema == 'custom':
                continue
            if output_schema is not None and output_schema != '':
                add_warning(f"[specialist-output-schema] {cname}: invalid output_schema value '{output_schema}' (expected 'custom' or omit)")
                continue

            path_str = cdata.get('path', '')
            if not path_str:
                continue
            path = plugin_root / path_str
            if not path.exists():
                continue

            schema_kw = _check_output_schema_keywords(path)
            missing = [cat for cat, present in schema_kw.items() if not present]
            if missing:
                add_warning(f"[specialist-output-schema] {cname}: missing output schema keywords: {', '.join(missing)}")

    return criticals, warnings, infos


def chain_validate(deps: dict, plugin_root: Path) -> Tuple[List[str], List[str], List[str]]:
    """Chain/Step 双方向整合性検証

    v3.0 deps.yaml のみ対象。以下を検証:
    1. chain-bidirectional: chains.steps ⟺ component.chain の双方向一致
    2. step-bidirectional: parent.calls[].step ⟺ child.step_in の双方向一致
    3. chain-type-guard: Chain 種別ごとの参加者型制約
    4. step-ordering: calls 内 step 番号の昇順
    5. prompt-consistency: body 内の chain/step 参照と deps.yaml の整合性

    Returns: (criticals, warnings, infos)
    """
    criticals: List[str] = []
    warnings: List[str] = []
    infos: List[str] = []
    ok_count = 0

    version = get_deps_version(deps)
    if not version.startswith('3'):
        return criticals, warnings, infos

    chains = deps.get('chains', {})

    # 全コンポーネントの名前→(section, data) マップ
    all_components: Dict[str, Tuple[str, dict]] = {}
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            all_components[comp_name] = (section, data)

    # --- 1. chain-bidirectional ---
    # 1a. 順方向: chains.steps の各コンポーネントが component.chain を持つか
    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            continue
        steps = chain_data.get('steps', [])
        if not isinstance(steps, list):
            continue
        for step_entry in steps:
            if not isinstance(step_entry, str):
                continue
            comp = all_components.get(step_entry)
            if comp is None:
                # コンポーネント自体が存在しない（validate_v3_schema で検出済み）
                continue
            comp_chain = comp[1].get('chain')
            if comp_chain is None:
                criticals.append(
                    f"[chain-bidir] {step_entry}: "
                    f"listed in chains/{chain_name}/steps but has no chain field"
                )
            elif comp_chain != chain_name:
                criticals.append(
                    f"[chain-bidir] {step_entry}: "
                    f"listed in chains/{chain_name}/steps but chain='{comp_chain}'"
                )
            else:
                ok_count += 1

    # 1b. 逆方向: component.chain を持つコンポーネントが chains.steps に含まれるか
    for comp_name, (section, data) in all_components.items():
        chain = data.get('chain')
        if chain is None:
            continue
        if not isinstance(chain, str):
            continue
        chain_data = chains.get(chain)
        if chain_data is None:
            # chain 自体が不在（validate_v3_schema で検出済み）
            continue
        steps = chain_data.get('steps', [])
        if not isinstance(steps, list):
            continue
        if comp_name not in steps:
            criticals.append(
                f"[chain-bidir] {comp_name}: "
                f"chain='{chain}' but not listed in chains/{chain}/steps"
            )
        else:
            ok_count += 1

    # --- 2. step-bidirectional ---
    # 2a. 順方向: parent.calls[].step を持つ呼び出しに対し、child が step_in を持つか
    for comp_name, (section, data) in all_components.items():
        for call in data.get('calls', []):
            step = call.get('step')
            if step is None:
                continue
            # call のターゲット名を取得
            callee_name = None
            for key, val in call.items():
                if key != 'step' and isinstance(val, str):
                    callee_name = val
                    break
            if callee_name is None:
                continue
            callee = all_components.get(callee_name)
            if callee is None:
                continue
            callee_step_in = callee[1].get('step_in')
            if callee_step_in is None:
                criticals.append(
                    f"[step-bidir] {callee_name}: "
                    f"called with step='{step}' from {comp_name} but has no step_in"
                )
            elif not isinstance(callee_step_in, dict):
                continue  # 型エラーは validate_v3_schema で検出
            elif callee_step_in.get('parent') != comp_name:
                criticals.append(
                    f"[step-bidir] {callee_name}: "
                    f"called with step='{step}' from {comp_name} "
                    f"but step_in.parent='{callee_step_in.get('parent')}'"
                )
            else:
                ok_count += 1

    # 2b. 逆方向: child.step_in.parent を持つコンポーネントに対し、parent の calls に step があるか
    for comp_name, (section, data) in all_components.items():
        step_in = data.get('step_in')
        if step_in is None or not isinstance(step_in, dict):
            continue
        parent_name = step_in.get('parent')
        if parent_name is None or not isinstance(parent_name, str):
            continue
        parent = all_components.get(parent_name)
        if parent is None:
            continue  # 不在は validate_v3_schema で検出
        # parent の calls から comp_name への step 指定を探す
        found_step_call = False
        for call in parent[1].get('calls', []):
            if call.get('step') is None:
                continue
            callee_name = None
            for key, val in call.items():
                if key != 'step' and isinstance(val, str):
                    callee_name = val
                    break
            if callee_name == comp_name:
                found_step_call = True
                break
        if not found_step_call:
            criticals.append(
                f"[step-bidir] {comp_name}: "
                f"step_in.parent='{parent_name}' but {parent_name} has no step call to {comp_name}"
            )
        else:
            ok_count += 1

    # --- 3. chain-type-guard ---
    CHAIN_TYPE_ALLOWED = {
        'A': {'workflow', 'atomic'},
        'B': {'atomic', 'composite'},
    }
    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            continue
        chain_type = chain_data.get('type')
        if chain_type is None:
            continue  # type フィールドなし → スキップ
        allowed = CHAIN_TYPE_ALLOWED.get(chain_type)
        if allowed is None:
            warnings.append(
                f"[chain-type] chains/{chain_name}: unknown chain type '{chain_type}'"
            )
            continue
        steps = chain_data.get('steps', [])
        if not isinstance(steps, list):
            continue
        for step_entry in steps:
            if not isinstance(step_entry, str):
                continue
            comp = all_components.get(step_entry)
            if comp is None:
                continue
            comp_type = resolve_type(comp[1].get('type', ''))
            if comp_type not in allowed:
                allowed_str = ', '.join(sorted(allowed))
                warnings.append(
                    f"[chain-type] chains/{chain_name}: "
                    f"{comp_type} '{step_entry}' not allowed in Chain {chain_type} "
                    f"(allowed: {allowed_str})"
                )
            else:
                ok_count += 1

    # --- 4. step-ordering ---
    for comp_name, (section, data) in all_components.items():
        calls = data.get('calls', [])
        step_values: List[Tuple[str, float]] = []
        for call in calls:
            step = call.get('step')
            if step is None:
                continue
            try:
                step_num = float(step)
            except (ValueError, TypeError):
                warnings.append(
                    f"[step-order] {comp_name}: step '{step}' is not a valid number"
                )
                continue
            step_values.append((step, step_num))

        for i in range(1, len(step_values)):
            if step_values[i][1] < step_values[i - 1][1]:
                warnings.append(
                    f"[step-order] {comp_name}: "
                    f"step '{step_values[i][0]}' appears after '{step_values[i - 1][0]}' (not ascending)"
                )
            elif step_values[i][1] == step_values[i - 1][1]:
                warnings.append(
                    f"[step-order] {comp_name}: "
                    f"duplicate step '{step_values[i][0]}'"
                )
            else:
                ok_count += 1

    # --- 5. prompt-consistency ---
    # body 内の step 参照パターン（日本語対応）
    step_ref_pattern = re.compile(
        r'(\S+?)(?:\s+の)?\s*Step\s+(\S+)\s*から呼び出される',
        re.IGNORECASE
    )

    for comp_name, (section, data) in all_components.items():
        path_str = data.get('path', '')
        if not path_str:
            continue
        path = plugin_root / path_str
        body = _get_body_text(path)
        if not body:
            continue

        for match in step_ref_pattern.finditer(body):
            ref_parent = match.group(1)
            ref_step = match.group(2)
            # step_in の確認
            step_in = data.get('step_in')
            if step_in is None or not isinstance(step_in, dict):
                warnings.append(
                    f"[prompt-chain] {comp_name}: "
                    f"body mentions '{ref_parent} Step {ref_step}' but no matching step_in in deps.yaml"
                )
            elif step_in.get('parent') != ref_parent:
                warnings.append(
                    f"[prompt-chain] {comp_name}: "
                    f"body mentions '{ref_parent} Step {ref_step}' "
                    f"but step_in.parent='{step_in.get('parent')}'"
                )
            else:
                ok_count += 1

    return criticals, warnings, infos


# === Chain Generate ===


def chain_generate(deps: dict, chain_name: str, plugin_root: Path) -> dict:
    """指定チェーンの Template A/B/C を生成して辞書で返す。

    Returns:
        {
            'template_a': {comp_name: str, ...},  # チェックポイント出力テンプレート
            'template_b': {comp_name: str, ...},  # called-by 宣言行
            'template_c': str,                     # SKILL.md 向けスターター指示
            'template_c_target': str | None,       # Template C 注入先の SKILL.md パス
        }
    """
    chains = deps.get('chains', {})
    chain_data = chains.get(chain_name)
    if chain_data is None or not isinstance(chain_data, dict):
        return {'template_a': {}, 'template_b': {}, 'template_c': '', 'template_c_target': None}

    steps = chain_data.get('steps', [])
    if not isinstance(steps, list):
        return {'template_a': {}, 'template_b': {}, 'template_c': '', 'template_c_target': None}

    # 全コンポーネントの名前→(section, data) マップ
    all_components: Dict[str, Tuple[str, dict]] = {}
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            all_components[comp_name] = (section, data)

    def _sanitize_name(name: str) -> str:
        """テンプレート埋め込み用に名前をサニタイズ（改行・Markdown特殊文字除去）"""
        return name.replace('\n', '').replace('\r', '').replace('`', '').strip()

    # --- Template A: チェックポイント ---
    template_a: Dict[str, str] = {}
    for i, step_name in enumerate(steps):
        if not isinstance(step_name, str):
            continue
        if i < len(steps) - 1:
            next_name = _sanitize_name(steps[i + 1])
            template_a[step_name] = (
                f"## チェックポイント（MUST）\n\n"
                f"`/dev:{next_name}` を Skill tool で自動実行。"
            )
        else:
            template_a[step_name] = (
                f"## チェックポイント（MUST）\n\n"
                f"チェーン完了。"
            )

    # --- Template B: called-by 宣言行 ---
    template_b: Dict[str, str] = {}
    for step_name in steps:
        if not isinstance(step_name, str):
            continue
        comp = all_components.get(step_name)
        if comp is None:
            continue
        step_in = comp[1].get('step_in')
        if step_in is None or not isinstance(step_in, dict):
            continue
        parent = step_in.get('parent')
        if parent is None:
            continue
        safe_parent = _sanitize_name(parent)
        step_val = step_in.get('step')
        if step_val and isinstance(step_val, str) and step_val.strip():
            safe_step = _sanitize_name(step_val)
            template_b[step_name] = f"{safe_parent} Step {safe_step} から呼び出される。"
        else:
            template_b[step_name] = f"{safe_parent} から呼び出される。"

    # --- Template C: SKILL.md 向けスターター指示 ---
    # ライフサイクルテーブル
    table_lines = ["| # | 型 | コンポーネント | 説明 |", "|---|---|---|---|"]
    for i, step_name in enumerate(steps):
        if not isinstance(step_name, str):
            continue
        comp = all_components.get(step_name)
        if comp is None:
            comp_type = ''
            desc = ''
        else:
            comp_type = comp[1].get('type', '')
            desc = comp[1].get('description', '')
        safe_desc = desc.replace('|', '\\|').replace('\n', ' ') if desc else ''
        safe_type = comp_type.replace('|', '\\|').replace('\n', ' ') if comp_type else ''
        table_lines.append(f"| {i + 1} | {safe_type} | {step_name} | {safe_desc} |")
    lifecycle_table = '\n'.join(table_lines)

    # 最初のステップを特定
    first_step = None
    for s in steps:
        if isinstance(s, str):
            first_step = _sanitize_name(s)
            break

    # 親 SKILL.md を特定（step_in.parent から）
    template_c_target = None
    for s in steps:
        if not isinstance(s, str):
            continue
        comp = all_components.get(s)
        if comp is None:
            continue
        step_in = comp[1].get('step_in')
        if step_in and isinstance(step_in, dict):
            parent_name = step_in.get('parent')
            if parent_name and isinstance(parent_name, str):
                parent_comp = all_components.get(parent_name)
                if parent_comp:
                    parent_path = parent_comp[1].get('path')
                    if parent_path:
                        template_c_target = parent_path
                        break

    # スターター指示を生成
    if first_step:
        template_c = (
            f"## chain 実行指示（MUST）\n\n"
            f"以下の順序でステップを実行する。各ステップの COMMAND.md を Read し、Skill tool で自動実行すること。\n\n"
            f"Step 1: `/dev:{first_step}` を Skill tool で実行\n"
            f"→ 以降は各 COMMAND.md のチェックポイントに従い自動進行\n\n"
            f"### ライフサイクル\n\n"
            f"{lifecycle_table}"
        )
    else:
        template_c = ''

    return {
        'template_a': template_a,
        'template_b': template_b,
        'template_c': template_c,
        'template_c_target': template_c_target,
    }


def chain_generate_print(result: dict, chain_name: str, chain_type: Optional[str] = None) -> None:
    """chain_generate の結果を stdout に出力する。"""
    template_a = result['template_a']
    template_b = result['template_b']
    template_c = result['template_c']
    template_c_target = result.get('template_c_target')

    # chain type による出力分岐
    show_a = chain_type in (None, 'A')
    show_b = chain_type in (None, 'B') or any(template_b.values())
    show_c = True

    if show_a and template_a:
        print(f"=== Template A: チェックポイント ({chain_name}) ===")
        print()
        for comp_name, content in template_a.items():
            print(f"--- {comp_name} ---")
            print(content)
            print()

    if show_b and template_b:
        print(f"=== Template B: called-by ({chain_name}) ===")
        print()
        for comp_name, content in template_b.items():
            print(f"--- {comp_name} ---")
            print(content)
            print()

    if show_c and template_c:
        target_info = f" → {template_c_target}" if template_c_target else ""
        print(f"=== Template C: chain starter ({chain_name}){target_info} ===")
        print()
        print(template_c)
        print()


# called-by パターン: description 末尾の「。XXX (Step N )から呼び出される。」を検出
CALLED_BY_PATTERN = re.compile(r'。\S+ (?:Step \d+ )?から呼び出される。$')


def chain_generate_write(result: dict, deps: dict, plugin_root: Path) -> None:
    """chain_generate の結果をプロンプトファイルに書き込む。"""
    all_components: Dict[str, Tuple[str, dict]] = {}
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            all_components[comp_name] = (section, data)

    template_a = result['template_a']
    template_b = result['template_b']

    # チェックポイントセクション検出パターン
    checkpoint_pattern = re.compile(
        r'^##\s+(?:チェックポイント|Checkpoint).*$',
        re.MULTILINE | re.IGNORECASE
    )

    all_comps = set(template_a.keys()) | set(template_b.keys())

    for comp_name in all_comps:
        comp = all_components.get(comp_name)
        if comp is None:
            continue
        path_str = comp[1].get('path')
        if not path_str:
            print(f"Warning: No path defined for {comp_name}, skipping --write", file=sys.stderr)
            continue

        file_path = plugin_root / path_str
        # パストラバーサル防御
        if not str(file_path.resolve()).startswith(str(plugin_root.resolve())):
            print(f"Warning: Path traversal detected for {comp_name}, skipping", file=sys.stderr)
            continue
        if not file_path.exists():
            print(f"Warning: File not found: {file_path}, skipping --write", file=sys.stderr)
            continue

        content = file_path.read_text(encoding='utf-8')
        modified = False

        # Template A: チェックポイントセクション置換
        if comp_name in template_a:
            match = checkpoint_pattern.search(content)
            if match:
                # セクションの開始位置から次のセクション（## で始まる行）または EOF まで置換
                start = match.start()
                # 次の ## セクションを検索（同レベル以上）
                rest = content[match.end():]
                next_section = re.search(r'^##\s', rest, re.MULTILINE)
                if next_section:
                    end = match.end() + next_section.start()
                else:
                    end = len(content)
                content = content[:start] + template_a[comp_name] + '\n\n' + content[end:]
                modified = True
            else:
                print(f"Warning: Section marker not found in {path_str}, skipping", file=sys.stderr)

        # Template B: frontmatter description 内の called-by 更新
        if comp_name in template_b:
            called_by_text = template_b[comp_name]
            lines = content.splitlines()
            in_frontmatter = False
            desc_line_idx = None
            for i, line in enumerate(lines):
                if i == 0 and line.strip() == '---':
                    in_frontmatter = True
                    continue
                if in_frontmatter and line.strip() == '---':
                    in_frontmatter = False
                    continue
                if in_frontmatter and 'description:' in line:
                    desc_line_idx = i
                    break
            if desc_line_idx is None:
                print(f"Warning: No description field in {path_str}, skipping Template B", file=sys.stderr)
            else:
                desc_line = lines[desc_line_idx]
                # description: の値部分を取得
                prefix, _, value = desc_line.partition('description:')
                value = value.strip()
                # クォートを除去して処理
                quote_char = ''
                if value and value[0] in ('"', "'"):
                    quote_char = value[0]
                    value = value[1:]
                    if value.endswith(quote_char):
                        value = value[:-1]
                # called-by パターンで置換または追記
                if CALLED_BY_PATTERN.search(value):
                    new_value = CALLED_BY_PATTERN.sub(f'。{called_by_text}', value)
                else:
                    if value and not value.endswith('。'):
                        new_value = f'{value}。{called_by_text}'
                    elif value:
                        new_value = f'{value}{called_by_text}'
                    else:
                        new_value = called_by_text
                # クォートを復元
                if quote_char:
                    new_value = f'{quote_char}{new_value}{quote_char}'
                lines[desc_line_idx] = f'{prefix}description: {new_value}'
                content = '\n'.join(lines)
                modified = True

        if modified:
            file_path.write_text(content, encoding='utf-8')
            print(f"Updated: {path_str}")

    # Template C: SKILL.md へのスターター指示注入
    template_c = result['template_c']
    template_c_target = result.get('template_c_target')
    if template_c and template_c_target:
        target_path = plugin_root / template_c_target
        if not str(target_path.resolve()).startswith(str(plugin_root.resolve())):
            print(f"Warning: Path traversal detected for Template C target, skipping", file=sys.stderr)
        elif not target_path.exists():
            print(f"Warning: Template C target not found: {target_path}, skipping", file=sys.stderr)
        else:
            target_content = target_path.read_text(encoding='utf-8')
            starter_pattern = re.compile(
                r'^##\s+chain\s+実行指示.*$',
                re.MULTILINE | re.IGNORECASE
            )
            match = starter_pattern.search(target_content)
            if match:
                # 既存セクションを置換
                rest = target_content[match.end():]
                next_section = re.search(r'^##\s', rest, re.MULTILINE)
                if next_section:
                    end = match.end() + next_section.start()
                else:
                    end = len(target_content)
                target_content = target_content[:match.start()] + template_c + '\n\n' + target_content[end:]
            else:
                # セクションが存在しない場合、ファイル末尾に追加
                target_content = target_content.rstrip('\n') + '\n\n' + template_c + '\n'
            target_path.write_text(target_content, encoding='utf-8')
            print(f"Updated (Template C): {template_c_target}")


def _extract_called_by(content: str) -> Optional[str]:
    """ファイル内容の frontmatter description から called-by 部分を抽出する。

    Returns:
        called-by 文字列（例: "workflow-pr-cycle Step 3 から呼び出される。"）。
        description が存在しない、または called-by パターンが見つからない場合は None。
    """
    lines = content.splitlines()
    in_frontmatter = False
    for i, line in enumerate(lines):
        if i == 0 and line.strip() == '---':
            in_frontmatter = True
            continue
        if in_frontmatter and line.strip() == '---':
            break
        if in_frontmatter and 'description:' in line:
            _, _, value = line.partition('description:')
            value = value.strip()
            # クォート除去
            if value and value[0] in ('"', "'"):
                quote_char = value[0]
                value = value[1:]
                if value.endswith(quote_char):
                    value = value[:-1]
            match = CALLED_BY_PATTERN.search(value)
            if match:
                # 先頭の「。」を除いた called-by 文を返す
                return match.group(0).lstrip('。')
            return None
    return None


def _normalize_for_check(text: str) -> str:
    """比較用にテキストを正規化する（trailing whitespace 除去 + LF 統一）。"""
    lines = text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
    return '\n'.join(line.rstrip() for line in lines)


def _extract_checkpoint_section(content: str) -> Optional[str]:
    """ファイル内容からチェックポイントセクションを抽出する。

    Returns:
        セクション文字列。セクションが存在しない場合は None。
    """
    pattern = re.compile(
        r'^##\s+(?:チェックポイント|Checkpoint).*$',
        re.MULTILINE | re.IGNORECASE
    )
    match = pattern.search(content)
    if not match:
        return None

    rest = content[match.end():]
    next_section = re.search(r'^##\s', rest, re.MULTILINE)
    if next_section:
        section = content[match.start():match.end() + next_section.start()]
    else:
        section = content[match.start():]

    return section.rstrip('\n')


def _extract_starter_section(content: str) -> Optional[str]:
    """ファイル内容から chain 実行指示セクションを抽出する。

    Returns:
        セクション文字列。セクションが存在しない場合は None。
    """
    pattern = re.compile(
        r'^##\s+chain\s+実行指示.*$',
        re.MULTILINE | re.IGNORECASE
    )
    match = pattern.search(content)
    if not match:
        return None

    rest = content[match.end():]
    next_section = re.search(r'^##\s', rest, re.MULTILINE)
    if next_section:
        section = content[match.start():match.end() + next_section.start()]
    else:
        section = content[match.start():]

    return section.rstrip('\n')


def chain_generate_check(result: dict, deps: dict, plugin_root: Path) -> Tuple[List[dict], List[str]]:
    """単一 chain の Template A + Template B + Template C ドリフト検出。

    Returns:
        (file_results, diffs)
        file_results: [{'comp': str, 'path': str, 'status': 'ok'|'DRIFT', 'template': 'A'|'B'|'C'}, ...]
        diffs: unified diff テキストのリスト
    """
    all_components: Dict[str, Tuple[str, dict]] = {}
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            all_components[comp_name] = (section, data)

    template_a = result['template_a']
    template_b = result['template_b']
    file_results = []
    diffs = []

    # --- Template A チェック ---
    for comp_name, expected_content in template_a.items():
        comp = all_components.get(comp_name)
        if comp is None:
            continue
        path_str = comp[1].get('path')
        if not path_str:
            continue

        file_path = plugin_root / path_str
        if not str(file_path.resolve()).startswith(str(plugin_root.resolve())):
            continue
        if not file_path.exists():
            file_results.append({'comp': comp_name, 'path': path_str, 'status': 'DRIFT', 'template': 'A'})
            diff_text = f"=== Diff: {path_str} (Template A) ===\n--- expected\n+++ actual (file not found)\n"
            diffs.append(diff_text)
            continue

        content = file_path.read_text(encoding='utf-8')
        actual_section = _extract_checkpoint_section(content)

        if actual_section is None:
            file_results.append({'comp': comp_name, 'path': path_str, 'status': 'DRIFT', 'template': 'A'})
            expected_lines = _normalize_for_check(expected_content).splitlines(keepends=True)
            diff_lines = list(difflib.unified_diff(
                expected_lines, ['(section not found)\n'],
                fromfile='expected', tofile='actual'
            ))
            diff_text = f"=== Diff: {path_str} (Template A) ===\n" + ''.join(diff_lines)
            diffs.append(diff_text)
            continue

        norm_expected = _normalize_for_check(expected_content)
        norm_actual = _normalize_for_check(actual_section)

        if hashlib.sha256(norm_expected.encode('utf-8')).hexdigest() == \
           hashlib.sha256(norm_actual.encode('utf-8')).hexdigest():
            file_results.append({'comp': comp_name, 'path': path_str, 'status': 'ok', 'template': 'A'})
        else:
            file_results.append({'comp': comp_name, 'path': path_str, 'status': 'DRIFT', 'template': 'A'})
            expected_lines = norm_expected.splitlines(keepends=True)
            actual_lines = norm_actual.splitlines(keepends=True)
            diff_lines = list(difflib.unified_diff(
                expected_lines, actual_lines,
                fromfile='expected', tofile='actual'
            ))
            diff_text = f"=== Diff: {path_str} (Template A) ===\n" + ''.join(diff_lines)
            diffs.append(diff_text)

    # --- Template B チェック ---
    for comp_name, expected_called_by in template_b.items():
        comp = all_components.get(comp_name)
        if comp is None:
            continue
        path_str = comp[1].get('path')
        if not path_str:
            continue

        file_path = plugin_root / path_str
        if not str(file_path.resolve()).startswith(str(plugin_root.resolve())):
            continue
        if not file_path.exists():
            file_results.append({'comp': comp_name, 'path': path_str, 'status': 'DRIFT', 'template': 'B'})
            diff_text = f"=== Diff: {path_str} (Template B) ===\n--- expected\n+++ actual (file not found)\n"
            diffs.append(diff_text)
            continue

        content = file_path.read_text(encoding='utf-8')
        actual_called_by = _extract_called_by(content)

        if actual_called_by is None:
            file_results.append({'comp': comp_name, 'path': path_str, 'status': 'DRIFT', 'template': 'B'})
            diff_lines = list(difflib.unified_diff(
                [expected_called_by + '\n'], ['(called-by not found)\n'],
                fromfile='expected', tofile='actual'
            ))
            diff_text = f"=== Diff: {path_str} (Template B) ===\n" + ''.join(diff_lines)
            diffs.append(diff_text)
            continue

        norm_expected = _normalize_for_check(expected_called_by)
        norm_actual = _normalize_for_check(actual_called_by)

        if norm_expected == norm_actual:
            file_results.append({'comp': comp_name, 'path': path_str, 'status': 'ok', 'template': 'B'})
        else:
            file_results.append({'comp': comp_name, 'path': path_str, 'status': 'DRIFT', 'template': 'B'})
            diff_lines = list(difflib.unified_diff(
                [norm_expected + '\n'], [norm_actual + '\n'],
                fromfile='expected', tofile='actual'
            ))
            diff_text = f"=== Diff: {path_str} (Template B) ===\n" + ''.join(diff_lines)
            diffs.append(diff_text)

    # --- Template C チェック ---
    template_c = result['template_c']
    template_c_target = result.get('template_c_target')
    if template_c and template_c_target:
        target_path = plugin_root / template_c_target
        if str(target_path.resolve()).startswith(str(plugin_root.resolve())):
            if not target_path.exists():
                file_results.append({'comp': '(SKILL.md)', 'path': template_c_target, 'status': 'DRIFT', 'template': 'C'})
                diffs.append(f"=== Diff: {template_c_target} (Template C) ===\n--- expected\n+++ actual (file not found)\n")
            else:
                content = target_path.read_text(encoding='utf-8')
                actual_section = _extract_starter_section(content)

                if actual_section is None:
                    file_results.append({'comp': '(SKILL.md)', 'path': template_c_target, 'status': 'DRIFT', 'template': 'C'})
                    expected_lines = _normalize_for_check(template_c).splitlines(keepends=True)
                    diff_lines = list(difflib.unified_diff(
                        expected_lines, ['(section not found)\n'],
                        fromfile='expected', tofile='actual'
                    ))
                    diffs.append(f"=== Diff: {template_c_target} (Template C) ===\n" + ''.join(diff_lines))
                else:
                    norm_expected = _normalize_for_check(template_c)
                    norm_actual = _normalize_for_check(actual_section)

                    if hashlib.sha256(norm_expected.encode('utf-8')).hexdigest() == \
                       hashlib.sha256(norm_actual.encode('utf-8')).hexdigest():
                        file_results.append({'comp': '(SKILL.md)', 'path': template_c_target, 'status': 'ok', 'template': 'C'})
                    else:
                        file_results.append({'comp': '(SKILL.md)', 'path': template_c_target, 'status': 'DRIFT', 'template': 'C'})
                        expected_lines = norm_expected.splitlines(keepends=True)
                        actual_lines = norm_actual.splitlines(keepends=True)
                        diff_lines = list(difflib.unified_diff(
                            expected_lines, actual_lines,
                            fromfile='expected', tofile='actual'
                        ))
                        diffs.append(f"=== Diff: {template_c_target} (Template C) ===\n" + ''.join(diff_lines))

    return file_results, diffs


def handle_chain_subcommand(argv: list) -> None:
    """chain サブコマンドを処理する。sys.exit() で終了。"""
    parser = argparse.ArgumentParser(
        prog='loom chain generate',
        description='Generate step chain templates from deps.yaml'
    )
    parser.add_argument('chain_name', nargs='?', default=None,
                        help='Name of the chain to generate templates for')
    parser.add_argument('--write', action='store_true', help='Write templates to prompt files')
    parser.add_argument('--check', action='store_true', help='Check for drift in generated templates')
    parser.add_argument('--all', action='store_true', dest='all_chains',
                        help='Process all chains in deps.yaml')

    args = parser.parse_args(argv)

    # 排他バリデーション
    if args.all_chains and args.chain_name:
        print("Error: --all and chain name are mutually exclusive", file=sys.stderr)
        sys.exit(1)

    if not args.all_chains and not args.chain_name:
        parser.print_usage(sys.stderr)
        print("Error: either chain name or --all is required", file=sys.stderr)
        sys.exit(1)

    if args.check and args.write:
        print("Error: --check and --write are mutually exclusive", file=sys.stderr)
        sys.exit(1)

    plugin_root = get_plugin_root()
    deps = load_deps(plugin_root)

    # v3.0 バージョンチェック
    version = get_deps_version(deps)
    if not version.startswith('3'):
        print("Error: chain generate requires deps.yaml v3.0+", file=sys.stderr)
        sys.exit(1)

    chains = deps.get('chains', {})

    if args.all_chains:
        # --all モード
        if not chains:
            print("0 chains found")
            sys.exit(0)

        if args.check:
            # --all --check: サマリー + 末尾 diff
            all_diffs: List[str] = []
            chains_ok = 0
            chains_total = 0
            total_drifted = 0

            for cname, cdata in chains.items():
                chains_total += 1
                chain_type = cdata.get('type') if isinstance(cdata, dict) else None
                result = chain_generate(deps, cname, plugin_root)
                file_results, diffs = chain_generate_check(result, deps, plugin_root)

                has_drift = any(r['status'] == 'DRIFT' for r in file_results)
                if not has_drift:
                    chains_ok += 1

                print(f"chain: {cname}")
                for r in file_results:
                    status = "ok" if r['status'] == 'ok' else "DRIFT"
                    print(f"  {r['path']:<40s} ... {status}")
                print()

                if diffs:
                    total_drifted += len([r for r in file_results if r['status'] == 'DRIFT'])
                    all_diffs.extend(diffs)

            drifted_chains = chains_total - chains_ok
            print(f"Summary: {chains_ok}/{chains_total} chains ok"
                  + (f", {total_drifted} files drifted in {drifted_chains} chain{'s' if drifted_chains != 1 else ''}."
                     if total_drifted > 0 else "."))

            if all_diffs:
                print("Run 'loom chain generate --all --write' to fix.")
                print()
                for d in all_diffs:
                    print(d)
                sys.exit(1)
            else:
                sys.exit(0)
        else:
            # --all stdout / --all --write
            for cname, cdata in chains.items():
                chain_type = cdata.get('type') if isinstance(cdata, dict) else None
                result = chain_generate(deps, cname, plugin_root)
                chain_generate_print(result, cname, chain_type)
                if args.write:
                    chain_generate_write(result, deps, plugin_root)
            sys.exit(0)
    else:
        # 単一 chain モード
        if args.chain_name not in chains:
            print(f"Error: Chain '{args.chain_name}' not found in deps.yaml", file=sys.stderr)
            sys.exit(1)

        chain_data = chains[args.chain_name]
        chain_type = chain_data.get('type') if isinstance(chain_data, dict) else None

        result = chain_generate(deps, args.chain_name, plugin_root)

        if args.check:
            file_results, diffs = chain_generate_check(result, deps, plugin_root)
            for r in file_results:
                status = "ok" if r['status'] == 'ok' else "DRIFT"
                print(f"  {r['path']:<40s} ... {status}")

            if diffs:
                print()
                print(f"Run 'loom chain generate {args.chain_name} --write' to fix.")
                print()
                for d in diffs:
                    print(d)
                sys.exit(1)
            else:
                print()
                print("All files are in sync.")
                sys.exit(0)
        else:
            chain_generate_print(result, args.chain_name, chain_type)
            if args.write:
                chain_generate_write(result, deps, plugin_root)


# === Audit Report ===


def _get_body_text(file_path: Path) -> str:
    """frontmatter を除外した本文テキストを返す"""
    if not file_path.exists():
        return ''
    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception:
        return ''
    lines = content.splitlines()
    if lines and lines[0].strip() == '---':
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == '---':
                return '\n'.join(lines[i + 1:])
    return '\n'.join(lines)


def _count_inline_bash_lines(file_path: Path) -> Tuple[int, int]:
    """bash/shell/sh コードブロックの行数と非空本文行数を返す

    Returns: (inline_lines, total_non_empty_lines)
    """
    body = _get_body_text(file_path)
    if not body:
        return 0, 0

    lines = body.splitlines()
    total_non_empty = sum(1 for l in lines if l.strip())

    inline_lines = 0
    in_bash_block = False
    for line in lines:
        stripped = line.strip()
        if re.match(r'^```(?:bash|shell|sh)\s*$', stripped):
            in_bash_block = True
            continue
        if stripped == '```' and in_bash_block:
            in_bash_block = False
            continue
        if in_bash_block and stripped:
            inline_lines += 1

    return inline_lines, total_non_empty


def _check_step0_routing(file_path: Path) -> Tuple[bool, bool]:
    """Step 0 の存在と IF/ELIF ルーティングパターンを検出

    Returns: (has_step0, has_routing)
    """
    body = _get_body_text(file_path)
    if not body:
        return False, False

    has_step0 = bool(re.search(r'(?:###?\s+)?Step\s*0', body))
    has_routing = bool(re.search(r'\b(?:IF|ELIF|ELSE)\b', body))

    return has_step0, has_routing


REQUIRED_OUTPUT_KEYWORDS = {
    "result_values": {"PASS", "FAIL"},        # いずれか1つ以上
    "structure": {"findings"},                 # 必須
    "severity": {"severity"},                  # 必須
    "confidence": {"confidence"},              # 必須
}


def _check_self_contained_keywords(file_path: Path) -> Dict[str, bool]:
    """Self-Contained キーワードの存在確認

    Returns: dict with keyword presence
    """
    body = _get_body_text(file_path)
    keywords = {
        'purpose': bool(re.search(r'##\s*(?:目的|Purpose)', body)) if body else False,
        'output': bool(re.search(r'##\s*(?:出力|Output|返却)', body)) if body else False,
        'constraint': bool(re.search(r'##\s*(?:制約|禁止|MUST NOT|Constraint)', body)) if body else False,
    }
    return keywords


def _check_output_schema_keywords(file_path: Path) -> Dict[str, bool]:
    """出力スキーマキーワードのカテゴリ別存在確認

    Returns: dict with category presence (result_values, structure, severity, confidence)
    """
    body = _get_body_text(file_path)
    if not body:
        return {cat: False for cat in REQUIRED_OUTPUT_KEYWORDS}

    result = {}
    for category, keywords in REQUIRED_OUTPUT_KEYWORDS.items():
        result[category] = any(kw in body for kw in keywords)
    return result


def audit_collect(deps: dict, plugin_root: Path) -> List[dict]:
    """5セクションの Loom 準拠度データを収集（print なし）

    Returns: items リスト（severity, component, message, section, value, threshold）
    """
    COMMON_TOOLS = {'Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Task',
                    'SendMessage', 'AskUserQuestion', 'WebSearch', 'WebFetch',
                    'Agent', 'Skill'}

    items = []

    all_components = {}
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for name, spec in deps.get(section, {}).items():
            all_components[name] = {
                'section': section,
                'type': spec.get('type', ''),
                'path': spec.get('path', ''),
                'calls': spec.get('calls', []),
                'model': spec.get('model'),
            }

    # Section 1: Controller Size
    for name, comp in sorted(all_components.items()):
        resolved = resolve_type(comp['type'])
        if resolved != 'controller':
            continue
        path = plugin_root / comp['path']
        lines = _count_body_lines(path)
        if lines > 200:
            severity = 'critical'
        elif lines > 120:
            severity = 'warning'
        else:
            severity = 'ok'
        items.append({
            "severity": severity,
            "component": name,
            "message": f"Controller size {lines} lines" + (f" (threshold: {200 if lines > 200 else 120})" if severity != 'ok' else ""),
            "section": "controller_size",
            "value": lines,
            "threshold": 200 if lines > 200 else 120,
        })

    # Section 2: Inline Implementation
    for name, comp in sorted(all_components.items()):
        if resolve_type(comp['type']) == 'script':
            continue
        path = plugin_root / comp['path']
        inline, total = _count_inline_bash_lines(path)
        if inline == 0:
            continue
        ratio = inline / total * 100 if total > 0 else 0.0
        if ratio > 50:
            severity = 'warning'
        elif ratio > 30:
            severity = 'info'
        else:
            severity = 'ok'
        items.append({
            "severity": severity,
            "component": name,
            "message": f"Inline ratio {ratio:.1f}% ({inline}/{total} lines)",
            "section": "inline_implementation",
            "value": round(ratio, 1),
            "threshold": 50,
        })

    # Section 3: 1C=1W (Step 0 Routing)
    for name, comp in sorted(all_components.items()):
        resolved = resolve_type(comp['type'])
        if resolved != 'controller':
            continue
        path = plugin_root / comp['path']
        has_step0, has_routing = _check_step0_routing(path)
        if has_step0 and has_routing:
            severity = 'ok'
        else:
            severity = 'warning'
        items.append({
            "severity": severity,
            "component": name,
            "message": f"Step 0: {'Yes' if has_step0 else 'No'}, Routing: {'Yes' if has_routing else 'No'}",
            "section": "step0_routing",
            "value": 1 if (has_step0 and has_routing) else 0,
            "threshold": 1,
        })

    # Section 4: Tools Accuracy
    for name, comp in sorted(all_components.items()):
        if comp['section'] not in ('commands', 'agents'):
            continue
        path = plugin_root / comp['path']
        declared = _parse_frontmatter_tools(path)
        used_mcp = _scan_body_for_mcp_tools(path)
        missing = used_mcp - declared
        extra = declared - used_mcp - COMMON_TOOLS
        if missing:
            severity = 'warning'
        elif extra:
            severity = 'info'
        else:
            severity = 'ok'
        items.append({
            "severity": severity,
            "component": name,
            "message": f"Declared: {len(declared)}, Used: {len(used_mcp)}, Missing: {', '.join(sorted(missing)) if missing else '-'}, Extra: {', '.join(sorted(extra)) if extra else '-'}",
            "section": "tools_accuracy",
            "value": len(missing),
            "threshold": 0,
        })

    # Section 5: Self-Contained
    for name, comp in sorted(all_components.items()):
        resolved = resolve_type(comp['type'])
        if resolved != 'specialist':
            continue
        path = plugin_root / comp['path']
        keywords = _check_self_contained_keywords(path)

        # Schema check (same logic as audit_report)
        output_schema_val = None
        for section in ('skills', 'commands', 'agents'):
            if name in deps.get(section, {}):
                output_schema_val = deps[section][name].get('output_schema', None)
                break
        if output_schema_val == 'custom':
            schema_str = 'Skip'
            schema_ok = True
        else:
            schema_kw = _check_output_schema_keywords(path)
            schema_ok = all(schema_kw.values())
            schema_str = 'Yes' if schema_ok else 'No'

        has_required = keywords['purpose'] and keywords['output'] and schema_ok
        severity = 'ok' if has_required else 'warning'
        items.append({
            "severity": severity,
            "component": name,
            "message": f"Purpose: {'Yes' if keywords['purpose'] else 'No'}, Output: {'Yes' if keywords['output'] else 'No'}, Constraint: {'Yes' if keywords['constraint'] else 'No'}, Schema: {schema_str}",
            "section": "self_contained",
            "value": 1 if has_required else 0,
            "threshold": 1,
        })

    return items


def audit_report(deps: dict, plugin_root: Path) -> Tuple[int, int, int]:
    """5セクションの Loom 準拠度レポートを出力

    Returns: (critical_count, warning_count, ok_count)
    """
    items = audit_collect(deps, plugin_root)

    criticals = sum(1 for i in items if i['severity'] == 'critical')
    warnings = sum(1 for i in items if i['severity'] == 'warning')
    oks = sum(1 for i in items if i['severity'] in ('ok', 'info'))

    # Collect all components for display
    all_components = {}
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for name, spec in deps.get(section, {}).items():
            all_components[name] = {
                'section': section,
                'type': spec.get('type', ''),
                'path': spec.get('path', ''),
                'calls': spec.get('calls', []),
                'model': spec.get('model'),
            }

    COMMON_TOOLS = {'Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Task',
                    'SendMessage', 'AskUserQuestion', 'WebSearch', 'WebFetch',
                    'Agent', 'Skill'}

    # === Section 1: Controller Size ===
    print("## 1. Controller Size")
    print()
    print("| Component | Lines | Severity |")
    print("|-----------|-------|----------|")

    for name, comp in sorted(all_components.items()):
        resolved = resolve_type(comp['type'])
        if resolved != 'controller':
            continue
        path = plugin_root / comp['path']
        lines = _count_body_lines(path)
        if lines > 200:
            severity = 'CRITICAL'
        elif lines > 120:
            severity = 'WARNING'
        elif lines > 80:
            severity = 'OK (near limit)'
        else:
            severity = 'OK'
        print(f"| {name} | {lines} | {severity} |")
    print()

    # === Section 2: Inline Implementation ===
    print("## 2. Inline Implementation")
    print()
    print("| Component | Type | Inline | Total | Ratio | Severity |")
    print("|-----------|------|--------|-------|-------|----------|")

    for name, comp in sorted(all_components.items()):
        if resolve_type(comp['type']) == 'script':
            continue
        path = plugin_root / comp['path']
        inline, total = _count_inline_bash_lines(path)
        if inline == 0:
            continue
        ratio = inline / total * 100 if total > 0 else 0.0

        if ratio > 50:
            severity = 'WARNING'
        elif ratio > 30:
            severity = 'INFO'
        else:
            severity = 'OK'

        print(f"| {name} | {comp['type']} | {inline} | {total} | {ratio:.1f}% | {severity} |")
    print()

    # === Section 3: 1C=1W (Step 0 Routing) ===
    print("## 3. 1C=1W (Step 0 Routing)")
    print()
    print("| Component | Has Step 0 | Has Routing | Severity |")
    print("|-----------|-----------|-------------|----------|")

    for name, comp in sorted(all_components.items()):
        resolved = resolve_type(comp['type'])
        if resolved != 'controller':
            continue
        path = plugin_root / comp['path']
        has_step0, has_routing = _check_step0_routing(path)

        if has_step0 and has_routing:
            severity = 'OK'
        elif has_step0:
            severity = 'WARNING'
        else:
            severity = 'WARNING'

        s0 = 'Yes' if has_step0 else 'No'
        rt = 'Yes' if has_routing else 'No'
        print(f"| {name} | {s0} | {rt} | {severity} |")
    print()

    # === Section 4: Tools Accuracy ===
    print("## 4. Tools Accuracy")
    print()
    print("| Component | Declared | Used (MCP) | Missing | Extra | Severity |")
    print("|-----------|----------|------------|---------|-------|----------|")

    for name, comp in sorted(all_components.items()):
        if comp['section'] not in ('commands', 'agents'):
            continue
        path = plugin_root / comp['path']
        declared = _parse_frontmatter_tools(path)
        used_mcp = _scan_body_for_mcp_tools(path)

        missing = used_mcp - declared
        extra = declared - used_mcp - COMMON_TOOLS

        if missing:
            severity = 'WARNING'
        elif extra:
            severity = 'INFO'
        else:
            severity = 'OK'

        missing_str = ', '.join(sorted(missing)) if missing else '-'
        extra_str = ', '.join(sorted(extra)) if extra else '-'

        print(f"| {name} | {len(declared)} | {len(used_mcp)} | {missing_str} | {extra_str} | {severity} |")
    print()

    # === Section 5: Self-Contained ===
    print("## 5. Self-Contained")
    print()
    print("| Component | Type | Purpose | Output | Constraint | Schema | Severity |")
    print("|-----------|------|---------|--------|------------|--------|----------|")

    for name, comp in sorted(all_components.items()):
        resolved = resolve_type(comp['type'])
        if resolved != 'specialist':
            continue
        path = plugin_root / comp['path']
        keywords = _check_self_contained_keywords(path)

        # 出力スキーマ準拠チェック
        output_schema_val = None
        for section in ('skills', 'commands', 'agents'):
            if name in deps.get(section, {}):
                output_schema_val = deps[section][name].get('output_schema', None)
                break

        if output_schema_val == 'custom':
            schema_str = 'Skip'
            schema_ok = True
        else:
            schema_kw = _check_output_schema_keywords(path)
            schema_ok = all(schema_kw.values())
            schema_str = 'Yes' if schema_ok else 'No'

        has_required = keywords['purpose'] and keywords['output'] and schema_ok
        if has_required:
            severity = 'OK'
        else:
            severity = 'WARNING'

        p = 'Yes' if keywords['purpose'] else 'No'
        o = 'Yes' if keywords['output'] else 'No'
        c = 'Yes' if keywords['constraint'] else 'No'
        print(f"| {name} | {comp['type']} | {p} | {o} | {c} | {schema_str} | {severity} |")
    print()

    # === Section 6: Model Declaration ===
    print("## 6. Model Declaration")
    print()
    print("| Name | Type | Model | Severity |")
    print("|------|------|-------|----------|")

    for name, comp in sorted(all_components.items()):
        resolved = resolve_type(comp['type'])
        if resolved != 'specialist':
            continue
        model = comp.get('model')
        if model is None:
            model_str = '(none)'
            severity = 'WARNING'
            warnings += 1
        elif model == 'opus':
            model_str = model
            severity = 'WARNING'
            warnings += 1
        elif model not in ALLOWED_MODELS:
            model_str = model
            severity = 'INFO'
            oks += 1
        else:
            model_str = model
            severity = 'OK'
            oks += 1
        print(f"| {name} | {comp['type']} | {model_str} | {severity} |")
    print()

    # === Summary ===
    print("## Summary")
    print()
    print("| Severity | Count |")
    print("|----------|-------|")
    print(f"| CRITICAL | {criticals} |")
    print(f"| WARNING  | {warnings} |")
    print(f"| OK       | {oks} |")

    return criticals, warnings, oks


# === Complexity Metrics ===


def check_dead_components(graph: Dict, deps: dict) -> List[str]:
    """controller から到達不能なノード（Dead Component）を検出"""
    # controller を特定
    entry_points = set()
    for skill_name, skill_data in deps.get('skills', {}).items():
        skill_type = skill_data.get('type', '')
        if skill_type == 'controller':
            entry_points.add(f"skill:{skill_name}")

    # 全 controller から到達可能なノードを収集
    reachable = set()
    for ep in entry_points:
        reachable |= collect_reachable_nodes(graph, ep)

    # reference は controller から直接呼ばれなくてもよい
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
        if skill_type != 'controller':
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
        if skill_type != 'controller':
            continue
        node_id = f"skill:{skill_name}"
        reachable = collect_reachable_nodes(graph, node_id)
        total_tokens = sum(graph[nid].get('tokens', 0) for nid in reachable if nid in graph)
        costs.append((skill_name, total_tokens))

    costs.sort(key=lambda x: x[1], reverse=True)
    return costs


def complexity_collect(graph: Dict, deps: dict, plugin_root: Path) -> List[dict]:
    """7メトリクスの複雑さデータを収集（print なし）

    Returns: items リスト（severity, component, message, metric, value, threshold）
    """
    items = []

    # 1. Dead Component
    dead = check_dead_components(graph, deps)
    for node_id in dead:
        node = graph.get(node_id, {})
        node_type = node.get('skill_type') or node.get('command_type') or node.get('agent_type') or node.get('type', '')
        items.append({
            "severity": "warning",
            "component": node_id,
            "message": f"Dead component ({node_type})",
            "metric": "dead_component",
            "value": 1,
            "threshold": 0,
        })

    # 2. Usage Frequency
    stale = check_usage_frequency(graph, plugin_root)
    if stale:
        for node_id, last_date in stale:
            items.append({
                "severity": "info",
                "component": node_id,
                "message": f"Stale component (last changed: {last_date or 'unknown'})",
                "metric": "usage_frequency",
                "value": 0,
                "threshold": 0,
            })

    # 3. Depth Score
    depth_scores = calc_depth_scores(graph, deps)
    for name, depth in depth_scores:
        severity = "warning" if depth > 4 else "ok"
        items.append({
            "severity": severity,
            "component": name,
            "message": f"Depth score {depth}" + (f" (threshold: 4)" if depth > 4 else ""),
            "metric": "depth_score",
            "value": depth,
            "threshold": 4,
        })

    # 4. Fan-out
    fan_out = calc_fan_out(graph)
    for node_id, fo in fan_out:
        if fo > 8:
            items.append({
                "severity": "warning",
                "component": node_id,
                "message": f"Fan-out {fo} (threshold: 8)",
                "metric": "fan_out",
                "value": fo,
                "threshold": 8,
            })

    # 5. Type Balance
    balance = calc_type_balance(graph)
    total = sum(balance.values())
    for comp_type, count in sorted(balance.items(), key=lambda x: x[1], reverse=True):
        ratio = count / total * 100 if total > 0 else 0
        items.append({
            "severity": "info",
            "component": comp_type,
            "message": f"Type balance: {count} ({ratio:.1f}%)",
            "metric": "type_balance",
            "value": count,
            "threshold": 0,
        })

    # 6. Duplication
    duplicates = check_duplication(graph, plugin_root)
    for name_a, name_b, ratio in duplicates:
        items.append({
            "severity": "warning",
            "component": f"{name_a}/{name_b}",
            "message": f"Duplication {ratio:.1%}",
            "metric": "duplication",
            "value": round(ratio * 100, 1),
            "threshold": 60,
        })

    # 7. Cost Projection
    costs = calc_cost_projection(graph, deps)
    for name, tokens in costs:
        items.append({
            "severity": "info",
            "component": name,
            "message": f"Estimated context tokens: {tokens:,}",
            "metric": "cost_projection",
            "value": tokens,
            "threshold": 0,
        })

    return items


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
        for node_id, last_date in stale[:20]:
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


def _is_within_root(file_path: Path, root: Path) -> bool:
    """file_path が root 配下にあるか安全に検証（シンボリックリンク解決後）"""
    try:
        resolved = file_path.resolve()
        root_resolved = root.resolve()
        # commonpath で厳密に判定（prefix 一致の誤判定を防止）
        return os.path.commonpath([resolved, root_resolved]) == str(root_resolved)
    except (ValueError, OSError):
        return False


def _compute_new_path(name: str, new_section: str) -> str:
    """セクションに応じた新しいファイルパスを生成"""
    if new_section == 'skills':
        return f"skills/{name}/SKILL.md"
    elif new_section == 'commands':
        return f"commands/{name}.md"
    elif new_section == 'agents':
        return f"agents/{name}.md"
    return f"{new_section}/{name}.md"


# 型変更時のデフォルト値（TYPE_RULES の許可範囲内で実用的なデフォルト）
_PROMOTE_DEFAULTS = {
    'controller':  {'can_spawn': ['atomic', 'composite', 'reference', 'specialist', 'workflow'], 'spawnable_by': ['user']},
    'workflow':    {'can_spawn': ['atomic', 'composite', 'specialist'], 'spawnable_by': ['controller', 'user']},
    'composite':   {'can_spawn': ['specialist'], 'spawnable_by': ['controller', 'workflow']},
    'atomic':      {'can_spawn': ['reference'], 'spawnable_by': ['controller', 'workflow']},
    'specialist':  {'can_spawn': [], 'spawnable_by': ['composite', 'controller', 'workflow']},
    'reference':   {'can_spawn': [], 'spawnable_by': ['all']},
}


def promote_component(plugin_root: Path, deps: dict, name: str, new_type: str, dry_run: bool) -> bool:
    """コンポーネントの型を変更（昇格/降格）

    TYPE_RULES に基づいて:
    1. deps.yaml の type を更新
    2. deps.yaml のセクション間移動（必要時）
    3. ファイルの移動（セクション変更時）
    4. can_spawn/spawnable_by を新しい型のデフォルトに調整
    5. path を新しいセクションの規約に合わせて更新

    Returns: True if changes were made (or would be made in dry_run)
    """
    # 入力バリデーション: rename_component と同じルール
    _valid_name = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]*$')
    if not _valid_name.match(name):
        print("Error: component name must match [A-Za-z0-9][A-Za-z0-9_-]*", file=sys.stderr)
        return False

    resolved_new = resolve_type(new_type)
    if resolved_new not in TYPE_RULES:
        print(f"Error: unknown type '{new_type}'. Valid types: {sorted(TYPE_RULES.keys())}", file=sys.stderr)
        return False

    # コンポーネントを検索
    found_section = None
    found_data = None
    for section in ('skills', 'commands', 'agents'):
        section_dict = deps.get(section, {})
        if name in section_dict:
            found_section = section
            found_data = section_dict[name]
            break

    if not found_section:
        print(f"Error: '{name}' not found in deps.yaml (skills/commands/agents)", file=sys.stderr)
        return False

    old_type = found_data.get('type', '')
    resolved_old = resolve_type(old_type)

    if resolved_old == resolved_new:
        print(f"'{name}' is already type '{new_type}'.")
        return False

    new_rule = TYPE_RULES[resolved_new]
    new_section = new_rule['section']

    # 移動先セクションに同名が存在しないか確認
    if new_section != found_section:
        if name in deps.get(new_section, {}):
            print(f"Error: '{name}' already exists in '{new_section}'", file=sys.stderr)
            return False

    changes = []

    # 1. type 変更
    changes.append(f"  type: '{old_type}' → '{new_type}'")

    # 2. セクション移動
    if new_section != found_section:
        changes.append(f"  section: {found_section}/{name} → {new_section}/{name}")

    # 3. can_spawn/spawnable_by 調整（None 安全）
    defaults = _PROMOTE_DEFAULTS.get(resolved_new, {})
    old_can_spawn = sorted(found_data.get('can_spawn') or [])
    new_can_spawn = defaults.get('can_spawn', [])
    old_spawnable_by = sorted(found_data.get('spawnable_by') or [])
    new_spawnable_by = defaults.get('spawnable_by', [])

    if old_can_spawn != new_can_spawn:
        changes.append(f"  can_spawn: {old_can_spawn} → {new_can_spawn}")
    if old_spawnable_by != new_spawnable_by:
        changes.append(f"  spawnable_by: {old_spawnable_by} → {new_spawnable_by}")

    # 4. ファイルパス更新（セクション変更時は常に新規約のパスを算出）
    old_path = found_data.get('path')
    new_path = None
    if new_section != found_section:
        new_path = _compute_new_path(name, new_section)
        # 移動先パスの安全性検証
        new_file_candidate = plugin_root / new_path
        if not _is_within_root(new_file_candidate, plugin_root):
            print(f"Error: computed path '{new_path}' escapes plugin root", file=sys.stderr)
            return False
        if old_path and new_path != old_path:
            changes.append(f"  file: {old_path} → {new_path}")
        elif not old_path:
            changes.append(f"  path: (none) → {new_path}")

    if not changes:
        print(f"No changes needed for promoting '{name}' to '{new_type}'.")
        return False

    if dry_run:
        print(f"[dry-run] Would promote '{name}' to '{new_type}':")
        for c in changes:
            print(c)
        return True

    # --- 実際の変更を適用 ---
    print(f"Promoting '{name}': '{old_type}' → '{new_type}':")

    deps_path = plugin_root / "deps.yaml"
    deps_backup = deps_path.read_text(encoding='utf-8')
    file_moved = False
    old_file_for_rollback = None
    new_file_for_rollback = None

    try:
        raw_deps = yaml.safe_load(deps_backup)
        comp_data = raw_deps[found_section][name]

        # type 更新
        comp_data['type'] = new_type

        # can_spawn 更新
        if new_can_spawn:
            comp_data['can_spawn'] = list(new_can_spawn)
        elif 'can_spawn' in comp_data:
            del comp_data['can_spawn']

        # spawnable_by 更新
        if new_spawnable_by:
            comp_data['spawnable_by'] = list(new_spawnable_by)
        elif 'spawnable_by' in comp_data:
            del comp_data['spawnable_by']

        # セクション移動
        if new_section != found_section:
            del raw_deps[found_section][name]
            if new_section not in raw_deps:
                raw_deps[new_section] = {}

            # ファイル移動（old_path ありかつパスが変わる場合）
            if old_path and new_path and new_path != old_path:
                old_file = plugin_root / old_path
                new_file = plugin_root / new_path
                if old_file.exists() and _is_within_root(old_file, plugin_root) and _is_within_root(new_file, plugin_root):
                    new_file.parent.mkdir(parents=True, exist_ok=True)
                    old_file.rename(new_file)
                    file_moved = True
                    old_file_for_rollback = old_file
                    new_file_for_rollback = new_file
                    # 空ディレクトリを削除
                    old_dir = old_file.parent
                    if old_dir != plugin_root and old_dir.exists() and not any(old_dir.iterdir()):
                        old_dir.rmdir()

            # path は常に新セクション規約に更新
            comp_data['path'] = new_path

            raw_deps[new_section][name] = comp_data

        # deps.yaml 書き戻し
        deps_path.write_text(
            yaml.dump(raw_deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding='utf-8'
        )
    except Exception as e:
        print(f"Error: promote failed: {e}", file=sys.stderr)
        # ファイル移動のロールバック
        if file_moved and new_file_for_rollback and old_file_for_rollback:
            try:
                old_file_for_rollback.parent.mkdir(parents=True, exist_ok=True)
                new_file_for_rollback.rename(old_file_for_rollback)
            except Exception:
                print("Warning: ファイル移動のロールバックに失敗しました。", file=sys.stderr)
        # deps.yaml のロールバック
        try:
            deps_path.write_text(deps_backup, encoding='utf-8')
            print("deps.yaml をロールバックしました。", file=sys.stderr)
        except Exception:
            print("Warning: ロールバックにも失敗しました。", file=sys.stderr)
        return False

    for c in changes:
        print(c)
    print(f"\nDone. Run 'loom validate' to verify.")
    return True


def _update_frontmatter_name(file_path: Path, new_name: str, dry_run: bool) -> Optional[str]:
    """frontmatter の name フィールドを更新

    Returns: 変更内容の説明文字列、変更なしなら None
    """
    if not file_path.exists():
        return None
    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception:
        return None
    lines = content.splitlines(keepends=True)
    if not lines or lines[0].strip() != '---':
        return None

    for i, line in enumerate(lines[1:], 1):
        if line.strip() == '---':
            break
        m = re.match(r'^(name:\s*)(.+)$', line.rstrip('\n\r'))
        if m:
            old_val = m.group(2).strip().strip('"').strip("'")
            if old_val == new_name:
                return None
            new_line = f"{m.group(1)}{new_name}\n"
            desc = f"  frontmatter name: '{old_val}' → '{new_name}' in {file_path.name}"
            if not dry_run:
                lines[i] = new_line
                file_path.write_text(''.join(lines), encoding='utf-8')
            return desc
    return None


def rename_component(plugin_root: Path, deps: dict, old_name: str, new_name: str, dry_run: bool) -> bool:
    """コンポーネント名を8箇所（+ v3.0 chain 関連）で原子的に更新

    更新対象:
    1. deps.yaml キー名
    2. deps.yaml 内の全 calls 参照
    3. deps.yaml の v3.0 フィールド (chains.*.steps, step_in.parent, chain)
    4. 対象コンポーネントの frontmatter name フィールド
    5. プラグイン内全 .md ファイルの body 内 /{plugin}:{old} → /{plugin}:{new}
    6. path フィールド（パスコンポーネント境界マッチ）
    7. entry_points リスト内のパス
    8. ディレクトリ/ファイルの実 rename

    Returns: True if changes were made (or would be made in dry_run)
    """
    # 入力バリデーション: 英数字・ハイフン・アンダースコアのみ許可
    _valid_name = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]*$')
    if not _valid_name.match(old_name) or not _valid_name.match(new_name):
        print("Error: component name must match [A-Za-z0-9][A-Za-z0-9_-]*", file=sys.stderr)
        return False

    plugin_name = get_plugin_name(deps, plugin_root)
    deps_path = plugin_root / "deps.yaml"
    changes = []

    # --- 1. deps.yaml キー名の変更 ---
    found_section = None
    found_data = None
    for section in ('skills', 'commands', 'agents', 'scripts'):
        section_dict = deps.get(section, {})
        if old_name in section_dict:
            if new_name in section_dict:
                print(f"Error: '{new_name}' already exists in {section}", file=sys.stderr)
                return False
            found_section = section
            found_data = section_dict[old_name]
            changes.append(f"  deps.yaml key: {section}/{old_name} → {section}/{new_name}")
            break

    # チェーン名のみの rename かチェック
    is_chain_only_rename = False
    if not found_section:
        chains = deps.get('chains', {})
        if old_name in chains:
            is_chain_only_rename = True
            if new_name in chains:
                print(f"Error: chain '{new_name}' already exists", file=sys.stderr)
                return False
        else:
            print(f"Error: '{old_name}' not found in deps.yaml (skills/commands/agents/chains)", file=sys.stderr)
            return False

    if found_section:
        # new_name が他セクションに存在しないか確認
        for section in ('skills', 'commands', 'agents', 'scripts'):
            if section != found_section and new_name in deps.get(section, {}):
                print(f"Error: '{new_name}' already exists in {section}", file=sys.stderr)
                return False
        # new_name が chain 名と衝突しないか確認
        if new_name in deps.get('chains', {}):
            print(f"Error: '{new_name}' conflicts with existing chain name", file=sys.stderr)
            return False

    # --- 2. deps.yaml 内の全 calls 参照の更新 ---
    call_keys = {'command', 'composite', 'skill', 'reference', 'agent', 'specialist',
                 'workflow', 'phase', 'worker', 'script'}
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for comp_name, data in deps.get(section, {}).items():
            for call in data.get('calls', []):
                for key in call_keys:
                    if call.get(key) == old_name:
                        changes.append(f"  deps.yaml calls: {section}/{comp_name} → {key}: {old_name} → {new_name}")

    # --- 3. v3.0 フィールド (chains, step_in, chain) ---
    # chains.*.steps 内のコンポーネント名
    chains = deps.get('chains', {})
    for chain_name, chain_data in chains.items():
        if isinstance(chain_data, dict):
            steps = chain_data.get('steps', [])
            for i, step in enumerate(steps):
                if step == old_name:
                    changes.append(f"  deps.yaml chains: chains/{chain_name}/steps[{i}]: {old_name} → {new_name}")

    # step_in.parent の更新
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for comp_name, data in deps.get(section, {}).items():
            step_in = data.get('step_in', {})
            if isinstance(step_in, dict) and step_in.get('parent') == old_name:
                changes.append(f"  deps.yaml step_in: {section}/{comp_name}/step_in.parent: {old_name} → {new_name}")

    # chain フィールドの更新（チェーン名 rename 時）
    if old_name in chains:
        changes.append(f"  deps.yaml chains: chains/{old_name} → chains/{new_name}")
        # 全コンポーネントの chain フィールドも更新
        for section in ('skills', 'commands', 'agents', 'scripts'):
            for comp_name, data in deps.get(section, {}).items():
                if data.get('chain') == old_name:
                    changes.append(f"  deps.yaml chain: {section}/{comp_name}/chain: {old_name} → {new_name}")

    # --- 4. frontmatter name ---
    component_path = found_data.get('path') if found_data else None
    if component_path:
        file_path = plugin_root / component_path
        if _is_within_root(file_path, plugin_root):
            fm_change = _update_frontmatter_name(file_path, new_name, dry_run=True)  # always preview first
            if fm_change:
                changes.append(fm_change)

    # --- 5. body 参照 /{plugin}:{old} → /{plugin}:{new} ---
    old_ref = f"/{plugin_name}:{old_name}"
    new_ref = f"/{plugin_name}:{new_name}"
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            comp_path = data.get('path')
            if not comp_path:
                continue
            file_path = plugin_root / comp_path
            if not file_path.exists():
                continue
            if not _is_within_root(file_path, plugin_root):
                continue
            try:
                content = file_path.read_text(encoding='utf-8')
            except Exception:
                continue
            if old_ref in content:
                count = content.count(old_ref)
                changes.append(f"  body ref: {comp_path} ({count} occurrence{'s' if count > 1 else ''}): {old_ref} → {new_ref}")

    # --- 6. path フィールド更新 ---
    new_component_path = None
    if found_data and component_path:
        path_parts = component_path.split('/')
        if old_name in path_parts:
            new_path_parts = [new_name if p == old_name else p for p in path_parts]
            new_component_path = '/'.join(new_path_parts)
            changes.append(f"  path: {component_path} → {new_component_path}")

    # --- 7. entry_points 更新 ---
    entry_points_changes = []
    for ep in deps.get('entry_points', []):
        # パストラバーサル防止: entry_points パスが plugin_root 内か検証
        if not _is_within_root(plugin_root / ep, plugin_root):
            continue
        ep_parts = ep.split('/')
        if old_name in ep_parts:
            new_ep_parts = [new_name if p == old_name else p for p in ep_parts]
            new_ep = '/'.join(new_ep_parts)
            if not _is_within_root(plugin_root / new_ep, plugin_root):
                continue
            entry_points_changes.append((ep, new_ep))
            changes.append(f"  entry_points: {ep} → {new_ep}")

    # --- 8. ディレクトリ rename ---
    dir_rename_needed = False
    old_dir = None
    new_dir = None
    if found_data and component_path:
        comp_file = plugin_root / component_path
        old_dir = comp_file.parent
        if old_dir != plugin_root and old_dir.name == old_name:
            new_dir = old_dir.parent / new_name
            # パストラバーサル防止: 両ディレクトリが plugin_root 内か検証
            if not _is_within_root(old_dir, plugin_root) or not _is_within_root(new_dir, plugin_root):
                print(f"Error: directory path escapes plugin root", file=sys.stderr)
                return False
            if new_dir.exists():
                print(f"Error: destination directory '{new_dir.relative_to(plugin_root)}/' already exists", file=sys.stderr)
                return False
            if old_dir.exists():
                dir_rename_needed = True
                changes.append(f"  directory: {old_dir.relative_to(plugin_root)}/ → {new_dir.relative_to(plugin_root)}/")

    # --- 結果表示 ---
    if not changes:
        print(f"No changes needed for renaming '{old_name}' to '{new_name}'.")
        return False

    if dry_run:
        print(f"[dry-run] Would rename '{old_name}' → '{new_name}':")
        for c in changes:
            print(c)
        return True

    # --- 実際の変更を適用 ---
    print(f"Renaming '{old_name}' → '{new_name}':")

    # deps.yaml をテキストベースではなく YAML パース → 書き戻しで更新
    raw_deps = yaml.safe_load(deps_path.read_text(encoding='utf-8'))

    # 1. キー名変更 (順序保持) — コンポーネント rename の場合のみ
    if found_section:
        section_dict = raw_deps[found_section]
        new_section = {}
        for k, v in section_dict.items():
            if k == old_name:
                new_section[new_name] = v
            else:
                new_section[k] = v
        raw_deps[found_section] = new_section

    # 2. calls 参照更新
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for comp_name, data in raw_deps.get(section, {}).items():
            for call in data.get('calls', []):
                for key in call_keys:
                    if call.get(key) == old_name:
                        call[key] = new_name

    # 3. v3.0 フィールド更新
    raw_chains = raw_deps.get('chains', {})
    for chain_name, chain_data in raw_chains.items():
        if isinstance(chain_data, dict):
            steps = chain_data.get('steps', [])
            for i, step in enumerate(steps):
                if step == old_name:
                    steps[i] = new_name

    for section in ('skills', 'commands', 'agents', 'scripts'):
        for comp_name, data in raw_deps.get(section, {}).items():
            step_in = data.get('step_in', {})
            if isinstance(step_in, dict) and step_in.get('parent') == old_name:
                step_in['parent'] = new_name

    if old_name in raw_chains:
        raw_chains[new_name] = raw_chains.pop(old_name)
        for section in ('skills', 'commands', 'agents', 'scripts'):
            for comp_name, data in raw_deps.get(section, {}).items():
                if data.get('chain') == old_name:
                    data['chain'] = new_name

    # 4. path フィールド更新
    if found_section and new_component_path:
        raw_deps[found_section][new_name]['path'] = new_component_path

    # 5. entry_points 更新
    if entry_points_changes:
        raw_ep = raw_deps.get('entry_points', [])
        for old_ep, new_ep in entry_points_changes:
            for i, ep in enumerate(raw_ep):
                if ep == old_ep:
                    raw_ep[i] = new_ep

    # 6. ディレクトリ rename（deps.yaml 書き戻し前に実行）
    dir_moved = False
    if dir_rename_needed and old_dir and new_dir:
        try:
            if not _is_within_root(new_dir, plugin_root):
                print(f"Error: new directory path escapes plugin root", file=sys.stderr)
                return False
            new_dir.parent.mkdir(parents=True, exist_ok=True)
            old_dir.rename(new_dir)
            dir_moved = True
        except Exception as e:
            print(f"Error: ディレクトリ rename に失敗しました: {e}", file=sys.stderr)
            return False

    # deps.yaml 書き戻し（バックアップ付きロールバック）
    deps_backup = deps_path.read_text(encoding='utf-8')
    try:
        deps_path.write_text(
            yaml.dump(raw_deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
            encoding='utf-8'
        )
    except Exception as e:
        print(f"Error: deps.yaml 書き戻しに失敗しました: {e}", file=sys.stderr)
        # ディレクトリ rename のロールバック
        if dir_moved and new_dir and old_dir:
            try:
                new_dir.rename(old_dir)
                print("ディレクトリ rename をロールバックしました。", file=sys.stderr)
            except Exception:
                print("Warning: ディレクトリ rename のロールバックにも失敗しました。", file=sys.stderr)
        try:
            deps_path.write_text(deps_backup, encoding='utf-8')
            print("deps.yaml をロールバックしました。", file=sys.stderr)
        except Exception:
            print("Warning: ロールバックにも失敗しました。", file=sys.stderr)
        return False

    # 7. ディレクトリ rename 後の空ディレクトリ削除
    if dir_moved and old_dir and old_dir.parent != plugin_root:
        old_parent = old_dir.parent
        if old_parent.exists() and not any(old_parent.iterdir()):
            old_parent.rmdir()

    # 8. frontmatter name 更新（rename 後のパスを使用）
    actual_path = new_component_path if new_component_path else component_path
    if actual_path:
        file_path = plugin_root / actual_path
        if _is_within_root(file_path, plugin_root):
            _update_frontmatter_name(file_path, new_name, dry_run=False)

    # 9. body 参照更新
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in raw_deps.get(section, {}).items():
            comp_path = data.get('path')
            if not comp_path:
                continue
            file_path = plugin_root / comp_path
            if not file_path.exists():
                continue
            if not str(file_path.resolve()).startswith(str(plugin_root.resolve())):
                continue
            try:
                content = file_path.read_text(encoding='utf-8')
            except Exception:
                continue
            if old_ref in content:
                new_content = content.replace(old_ref, new_ref)
                file_path.write_text(new_content, encoding='utf-8')

    for c in changes:
        print(c)
    print(f"\nDone. Run 'loom validate' to verify.")
    return True


def print_rules():
    """types.yaml の型テーブルを人間向け Markdown テーブル形式で出力する"""
    loom_root = _get_loom_root()
    types_path = loom_root / "types.yaml"
    source = str(types_path) if types_path.exists() else "fallback (hardcoded)"
    rules = load_type_rules(loom_root)

    print(f"=== Loom Type Rules ===")
    print(f"Source: {source}")
    print()

    # ヘッダー
    print(f"| {'Type':<12} | {'Section':<10} | {'Can Spawn':<45} | {'Spawnable By':<40} |")
    print(f"|{'-'*14}|{'-'*12}|{'-'*47}|{'-'*42}|")

    known_order = ['controller', 'workflow', 'atomic', 'composite', 'specialist', 'reference']
    ordered_types = [t for t in known_order if t in rules] + sorted(set(rules.keys()) - set(known_order))
    for type_name in ordered_types:
        rule = rules[type_name]
        can_spawn = ', '.join(sorted(rule['can_spawn'])) if rule['can_spawn'] else '(none)'
        spawnable_by = ', '.join(sorted(rule['spawnable_by'])) if rule['spawnable_by'] else '(none)'
        print(f"| {type_name:<12} | {rule['section']:<10} | {can_spawn:<45} | {spawnable_by:<40} |")

    print()
    print(f"Total: {len(rules)} types defined")


def sync_check(ref_path: str):
    """types.yaml と指定ドキュメントの型テーブル部分を比較し差分を報告する"""
    loom_root = _get_loom_root()
    rules = load_type_rules(loom_root)

    ref_file = Path(ref_path).resolve()
    if not ref_file.exists():
        print(f"Error: Reference file not found: {ref_path}", file=sys.stderr)
        sys.exit(1)
    # パス境界検証: loom_root 配下のファイルのみ許可
    if not _is_within_root(ref_file, loom_root):
        print(f"Error: Reference file must be within {loom_root}: {ref_path}", file=sys.stderr)
        sys.exit(1)

    content = ref_file.read_text(encoding='utf-8')

    # Markdown テーブルから型情報を抽出
    # パターン: | type | section | can_spawn | spawnable_by | 形式のテーブル行
    # 型名は **bold** マーカー付きの場合がある
    ref_rules: Dict[str, dict] = {}
    table_pattern = re.compile(
        r'^\|\s*\*{0,2}(\w+)\*{0,2}\s*\|\s*(\w+)\s*\|\s*([^|]*)\s*\|\s*([^|]*)\s*\|',
        re.MULTILINE
    )
    valid_types = set(rules.keys()) | {'controller', 'workflow', 'atomic', 'composite', 'specialist', 'reference'}

    def _parse_list(raw: str) -> set:
        if not raw or raw.strip('() ') in ('none', 'なし', '-', '—', ''):
            return set()
        return {x.strip().lower() for x in raw.split(',') if x.strip() and x.strip() not in ('-', '—')}

    for m in table_pattern.finditer(content):
        type_name = m.group(1).strip().lower()
        # ヘッダー行やセパレータ行をスキップ
        if type_name in ('type', 'name', '---', '', '型'):
            continue
        if type_name not in valid_types:
            continue

        section = m.group(2).strip().lower()
        can_spawn_raw = m.group(3).strip()
        spawnable_by_raw = m.group(4).strip()

        ref_rules[type_name] = {
            'section': section,
            'can_spawn': _parse_list(can_spawn_raw),
            'spawnable_by': _parse_list(spawnable_by_raw),
        }

    if not ref_rules:
        print(f"Warning: No type table found in {ref_path}", file=sys.stderr)
        print("Expected format: | type | section | can_spawn | spawnable_by |")
        sys.exit(1)

    print(f"=== Sync Check: types.yaml vs {ref_path} ===")
    print()

    diffs = []
    # types.yaml にあって ref にない
    for type_name in sorted(rules.keys()):
        if type_name not in ref_rules:
            diffs.append(f"[missing-in-ref] '{type_name}' is in types.yaml but not in {ref_file.name}")

    # ref にあって types.yaml にない
    for type_name in sorted(ref_rules.keys()):
        if type_name not in rules:
            diffs.append(f"[missing-in-yaml] '{type_name}' is in {ref_file.name} but not in types.yaml")

    # 両方にある型のフィールド差分
    for type_name in sorted(set(rules.keys()) & set(ref_rules.keys())):
        yaml_rule = rules[type_name]
        ref_rule = ref_rules[type_name]

        if yaml_rule['section'] != ref_rule['section']:
            diffs.append(f"[section-mismatch] {type_name}: yaml='{yaml_rule['section']}' vs ref='{ref_rule['section']}'")

        yaml_cs = yaml_rule['can_spawn']
        ref_cs = ref_rule['can_spawn']
        if yaml_cs != ref_cs:
            only_yaml = yaml_cs - ref_cs
            only_ref = ref_cs - yaml_cs
            parts = []
            if only_yaml:
                parts.append(f"only in yaml: {sorted(only_yaml)}")
            if only_ref:
                parts.append(f"only in ref: {sorted(only_ref)}")
            diffs.append(f"[can_spawn-mismatch] {type_name}: {', '.join(parts)}")

        yaml_sb = yaml_rule['spawnable_by']
        ref_sb = ref_rule['spawnable_by']
        if yaml_sb != ref_sb:
            only_yaml = yaml_sb - ref_sb
            only_ref = ref_sb - yaml_sb
            parts = []
            if only_yaml:
                parts.append(f"only in yaml: {sorted(only_yaml)}")
            if only_ref:
                parts.append(f"only in ref: {sorted(only_ref)}")
            diffs.append(f"[spawnable_by-mismatch] {type_name}: {', '.join(parts)}")

    if diffs:
        print(f"Found {len(diffs)} difference(s):")
        for d in diffs:
            print(f"  - {d}")
        sys.exit(1)
    else:
        print("No differences found. types.yaml and reference document are in sync.")


def _extract_body(content: str) -> str:
    """frontmatter と sync コメントを除いた本文部分を抽出する"""
    text = content
    # frontmatter 除去（行単位で閉じ --- を検出）
    if text.startswith('---'):
        # 最初の改行以降で、行頭の --- を探す
        end = text.find('\n---', 3)
        if end != -1:
            text = text[end + 4:].lstrip('\n')
    # sync コメント除去
    sync_marker = '<!-- Synced from loom docs/'
    if text.startswith(sync_marker):
        newline = text.find('\n')
        if newline != -1:
            text = text[newline + 1:].lstrip('\n')
    return text


def _body_hash(content: str) -> str:
    """本文部分の SHA256 ハッシュを返す"""
    body = _extract_body(content)
    return hashlib.sha256(body.encode('utf-8')).hexdigest()


def _build_frontmatter(filename: str, deps: dict) -> str:
    """deps.yaml の reference 定義から frontmatter を構築する。

    deps.yaml の skills/commands/agents セクションからファイル名に一致する reference を検索し、
    一致すれば name, type, spawnable_by, description, disable-model-invocation を付与。
    一致しなければ最小限の frontmatter (type: reference) を返す。
    """
    matched = None
    for section in ('skills', 'commands', 'agents'):
        section_data = deps.get(section, {})
        if not isinstance(section_data, dict):
            continue
        for comp_name, comp_def in section_data.items():
            if not isinstance(comp_def, dict):
                continue
            if comp_def.get('type') != 'reference':
                continue
            comp_path = comp_def.get('path', '')
            if Path(comp_path).name == filename:
                matched = (comp_name, comp_def)
                break
        if matched:
            break

    if matched is None:
        return '---\ntype: reference\n---'

    comp_name, comp_def = matched
    fm = {}
    # name フィールド: deps.yaml の plugin prefix + component name
    plugin_name = deps.get('plugin', '')
    if plugin_name:
        fm['name'] = f'{plugin_name}:{comp_name}'
    else:
        fm['name'] = comp_name
    # description
    if comp_def.get('description'):
        fm['description'] = str(comp_def['description'])
    # type
    fm['type'] = 'reference'
    # spawnable_by
    sb = comp_def.get('spawnable_by', [])
    if sb:
        fm['spawnable_by'] = list(sb) if isinstance(sb, list) else [sb]
    # disable-model-invocation
    if comp_def.get('disable-model-invocation') is not None:
        fm['disable-model-invocation'] = bool(comp_def['disable-model-invocation'])
    # yaml.dump で安全にシリアライズ
    body = yaml.dump(fm, default_flow_style=False, allow_unicode=True, sort_keys=False).rstrip('\n')
    return f'---\n{body}\n---'


SYNC_COMMENT = '<!-- Synced from loom docs/ — do not edit directly -->'


def sync_docs(target_dir: str, check_only: bool = False):
    """docs/ の ref-*.md を対象ディレクトリにコピー同期する。

    --check 時は本文ハッシュ比較のみ行い、差分ありで非ゼロ exit。
    """
    loom_root = _get_loom_root()
    docs_dir = loom_root / 'docs'

    if not docs_dir.exists():
        print(f"Error: docs/ directory not found at {docs_dir}", file=sys.stderr)
        sys.exit(1)

    target = Path(target_dir).resolve()
    if not target.is_dir():
        print(f"Error: Target directory does not exist: {target_dir}", file=sys.stderr)
        sys.exit(1)

    # 対象ディレクトリの deps.yaml を読み込み
    # target 自体か、その親ディレクトリから deps.yaml を探索
    deps = {}
    deps_search = target
    for _ in range(10):
        deps_path = deps_search / 'deps.yaml'
        if deps_path.exists():
            try:
                with open(deps_path, encoding='utf-8') as f:
                    deps = yaml.safe_load(f) or {}
            except yaml.YAMLError as e:
                print(f"Warning: Failed to parse {deps_path}: {e}", file=sys.stderr)
            break
        parent = deps_search.parent
        if parent == deps_search:
            break
        deps_search = parent

    # docs/ から ref-*.md を glob
    source_files = sorted(docs_dir.glob('ref-*.md'))
    if not source_files:
        print("Warning: No ref-*.md files found in docs/", file=sys.stderr)
        sys.exit(0)

    if check_only:
        # --check モード: ハッシュ比較
        has_diff = False
        for src in source_files:
            dest = target / src.name
            if not dest.exists():
                print(f"  [missing] {src.name}")
                has_diff = True
                continue

            src_hash = _body_hash(src.read_text(encoding='utf-8'))
            dest_hash = _body_hash(dest.read_text(encoding='utf-8'))

            if src_hash != dest_hash:
                print(f"  [changed] {src.name}")
                has_diff = True
            else:
                print(f"  [ok]      {src.name}")

        if has_diff:
            print()
            print("Differences found. Run 'loom sync-docs <dir>' to sync.")
            sys.exit(1)
        else:
            print()
            print("All files are in sync.")
            sys.exit(0)
    else:
        # 同期モード
        synced = 0
        for src in source_files:
            dest = target / src.name
            source_body = _extract_body(src.read_text(encoding='utf-8'))
            frontmatter = _build_frontmatter(src.name, deps)

            output = f"{frontmatter}\n\n{SYNC_COMMENT}\n\n{source_body}"
            dest.write_text(output, encoding='utf-8')
            synced += 1
            print(f"  [synced] {src.name}")

        print()
        print(f"Synced {synced} file(s) to {target_dir}")


def main():
    # chain サブコマンドの前処理（sys.argv を先に検査）
    if len(sys.argv) >= 2 and sys.argv[1] == 'chain':
        if len(sys.argv) >= 3 and sys.argv[2] == 'generate':
            handle_chain_subcommand(sys.argv[3:])
            sys.exit(0)
        else:
            print(f"Error: unknown chain subcommand '{sys.argv[2] if len(sys.argv) >= 3 else ''}'", file=sys.stderr)
            print("Usage: loom chain generate <chain-name> [--write]", file=sys.stderr)
            sys.exit(1)

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
    parser.add_argument('--audit', action='store_true', help='Loom compliance audit (5-section markdown report)')
    parser.add_argument('--complexity', action='store_true', help='Complexity metrics report')
    parser.add_argument('--rename', nargs=2, metavar=('OLD', 'NEW'), help='Rename a component (updates deps.yaml, frontmatter, body refs)')
    parser.add_argument('--promote', nargs=2, metavar=('NAME', 'NEW_TYPE'), help='Change component type (promote/demote with section move, file move, can_spawn/spawnable_by adjustment)')
    parser.add_argument('--dry-run', action='store_true', help='Preview changes without applying (use with --rename or --promote)')
    parser.add_argument('--rules', action='store_true', help='Print type rules table from types.yaml')
    parser.add_argument('--sync-check', metavar='REF_PATH', help='Compare types.yaml with a reference Markdown document')
    parser.add_argument('--sync-docs', metavar='TARGET_DIR', help='Sync docs/ref-*.md to target directory with frontmatter from deps.yaml')
    parser.add_argument('--format', choices=['json'], help='Output format (default: text)')

    args = parser.parse_args()

    # rules / sync-check / sync-docs は deps.yaml 不要の独立コマンド
    if args.rules:
        print_rules()
        sys.exit(0)

    if args.sync_check:
        sync_check(args.sync_check)
        sys.exit(0)

    if args.sync_docs:
        sync_docs(args.sync_docs, check_only=args.check)
        sys.exit(0)

    plugin_root = get_plugin_root()
    deps = load_deps(plugin_root)
    graph = build_graph(deps, plugin_root)
    plugin_name = get_plugin_name(deps, plugin_root)

    # rename は独立コマンド
    if args.rename:
        old_name, new_name = args.rename
        success = rename_component(plugin_root, deps, old_name, new_name, args.dry_run)
        sys.exit(0 if success else 1)

    # promote は独立コマンド
    if args.promote:
        comp_name, new_type = args.promote
        success = promote_component(plugin_root, deps, comp_name, new_type, args.dry_run)
        sys.exit(0 if success else 1)

    # デフォルトはGraphviz
    if not any([args.tree, args.rich, args.mermaid, args.graphviz, args.target, args.reverse, args.check, args.validate, args.list, args.update_readme, args.orphans, args.tokens, args.deep_validate, args.audit, args.complexity]):
        args.graphviz = True

    show_tokens = not args.no_tokens

    if args.complexity:
        if args.format == 'json':
            items = complexity_collect(graph, deps, plugin_root)
            exit_code = 0  # complexity は warning でも exit 0
            envelope = build_envelope("complexity", get_deps_version(deps), plugin_name, items, exit_code)
            output_json(envelope)
            sys.exit(exit_code)

        complexity_report(graph, deps, plugin_root)

    if args.tokens:
        print("=== Token Counts ===")
        print()

        total_tokens = 0
        sections = [
            ('Skills', 'skill'),
            ('Commands', 'command'),
            ('Agents', 'agent'),
            ('Scripts', 'script'),
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

    if args.update_readme:
        success = update_readme(plugin_root, graph, deps, plugin_name, show_tokens)
        if not success:
            sys.exit(1)

    if args.check:
        results = check_files(graph, plugin_root)

        ok_count = sum(1 for r in results if r[0] == 'ok')
        missing_count = sum(1 for r in results if r[0] == 'missing')
        no_path_count = sum(1 for r in results if r[0] == 'no_path')
        external_count = sum(1 for r in results if r[0] == 'external')

        # v3.0 chain 検証（JSON/テキスト共通で実行）
        chain_items = []
        cv_criticals_check = []
        cv_warnings_check = []
        if get_deps_version(deps).startswith('3'):
            cv_criticals_check, cv_warnings_check, cv_infos_check = chain_validate(deps, plugin_root)
            chain_items = _deep_validate_to_items(cv_criticals_check, cv_warnings_check, cv_infos_check)

        exit_code = 1 if (missing_count > 0 or cv_criticals_check) else 0

        if args.format == 'json':
            items = _check_results_to_items(results)
            items.extend(chain_items)
            envelope = build_envelope("check", get_deps_version(deps), plugin_name, items, exit_code)
            output_json(envelope)
            sys.exit(exit_code)

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

        # v3.0 chain 検証結果のテキスト出力
        if chain_items and (cv_criticals_check or cv_warnings_check):
            print()
            print("=== Chain Validation Results ===")
            if cv_criticals_check:
                print("Critical:")
                for c in cv_criticals_check:
                    print(f"  - {c}")
            if cv_warnings_check:
                print("Warning:")
                for w in cv_warnings_check:
                    print(f"  - {w}")
            if cv_criticals_check:
                sys.exit(1)

    if args.validate:
        ok_count, violations = validate_types(deps, graph)
        # body 参照チェック
        body_ok, body_violations = validate_body_refs(deps, plugin_root)
        ok_count += body_ok
        violations.extend(body_violations)
        # v3.0 スキーマ検証
        v3_ok, v3_violations = validate_v3_schema(deps)
        ok_count += v3_ok
        violations.extend(v3_violations)
        # chain 双方向整合性検証
        cv_criticals, cv_warnings, _cv_infos = chain_validate(deps, plugin_root)
        violations.extend(cv_criticals)
        violations.extend(cv_warnings)

        exit_code = 1 if violations else 0

        if args.format == 'json':
            items = _violations_to_items(violations)
            envelope = build_envelope("validate", get_deps_version(deps), plugin_name, items, exit_code)
            output_json(envelope)
            sys.exit(exit_code)

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

    if args.orphans:
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

    if args.deep_validate:
        # --validate の全チェックも実行
        ok_count, violations = validate_types(deps, graph)
        # body 参照チェック
        body_ok, body_violations = validate_body_refs(deps, plugin_root)
        ok_count += body_ok
        violations.extend(body_violations)
        # v3.0 スキーマ検証
        v3_ok, v3_violations = validate_v3_schema(deps)
        ok_count += v3_ok
        violations.extend(v3_violations)

        # deep-validate 固有チェック
        criticals, dv_warnings, dv_infos = deep_validate(deps, plugin_root)
        # chain 双方向整合性検証
        cv_criticals, cv_warnings, cv_infos = chain_validate(deps, plugin_root)
        criticals.extend(cv_criticals)
        dv_warnings.extend(cv_warnings)
        dv_infos.extend(cv_infos)

        exit_code = 1 if (violations or criticals) else 0

        if args.format == 'json':
            items = _violations_to_items(violations)
            items.extend(_deep_validate_to_items(criticals, dv_warnings, dv_infos))
            envelope = build_envelope("deep-validate", get_deps_version(deps), plugin_name, items, exit_code)
            output_json(envelope)
            sys.exit(exit_code)

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

    elif args.audit:
        if args.format == 'json':
            items = audit_collect(deps, plugin_root)
            exit_code = 1 if any(i['severity'] == 'critical' for i in items) else 0
            envelope = build_envelope("audit", get_deps_version(deps), plugin_name, items, exit_code)
            output_json(envelope)
            sys.exit(exit_code)

        print("=== Loom Compliance Audit ===")
        print()
        audit_criticals, audit_warnings, audit_oks = audit_report(deps, plugin_root)
        if audit_criticals > 0:
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

        print("\n## SCRIPTS")
        for node_id in sorted(graph):
            if graph[node_id]['type'] == 'script':
                node = graph[node_id]
                desc = node['description'][:50] if node['description'] else ''
                print(f"  {node['name']}: {desc}...")

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
            # フォールバック: controller タイプのスキルを検索
            skill_name = 'entry-workflow'
            for sname, sdata in deps.get('skills', {}).items():
                if sdata.get('type') == 'controller':
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
                if sdata.get('type') == 'controller':
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
