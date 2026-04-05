import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

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

from twl.core.types import TYPE_RULES, resolve_type, _get_loom_root

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


# cross-plugin 参照の plugin 名バリデーション（英数字・ハイフン・アンダースコアのみ）
_PLUGIN_NAME_RE = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$')


def parse_cross_plugin_ref(value: str) -> Optional[Tuple[str, str]]:
    """calls 値が cross-plugin 参照かどうかを判定し、(plugin, component) を返す。

    cross-plugin 参照は 'plugin:component' 形式（コロンを1つ含む）。
    ローカル参照（コロンなし）の場合は None を返す。
    plugin 名は英数字・ハイフン・アンダースコアのみ許可（パストラバーサル防止）。
    """
    if ':' in value:
        parts = value.split(':', 1)
        if parts[0] and parts[1] and _PLUGIN_NAME_RE.match(parts[0]):
            return (parts[0], parts[1])
    return None


# cross-plugin deps.yaml のキャッシュ（キーは (plugin_name, plugin_root) タプル）
_cross_plugin_cache: Dict[Tuple[str, str], Optional[dict]] = {}


def resolve_cross_plugin(plugin_name: str, plugin_root: Optional[Path] = None) -> Optional[dict]:
    """参照先 plugin の deps.yaml を読み込んで返す。

    探索順序:
    1. plugin_root の親ディレクトリに同名ディレクトリがある場合（worktree/monorepo 構成）
    2. ~/.claude/plugins/{plugin_name}/deps.yaml

    見つからない場合は None を返す（warning は呼び出し元で出力）。
    """
    cache_key = (plugin_name, str(plugin_root) if plugin_root else '')
    if cache_key in _cross_plugin_cache:
        return _cross_plugin_cache[cache_key]

    # plugin 名の再検証（防御的プログラミング）
    if not _PLUGIN_NAME_RE.match(plugin_name):
        _cross_plugin_cache[cache_key] = None
        return None

    search_paths = []
    allowed_bases = []

    # 1. plugin_root の親ディレクトリ（同一階層の兄弟 plugin）
    if plugin_root:
        parent = plugin_root.parent.resolve()
        sibling = parent / plugin_name
        if sibling.is_dir():
            search_paths.append(sibling / "deps.yaml")
            allowed_bases.append(parent)

    # 2. ~/.claude/plugins/{plugin_name}/
    home_plugins_base = (Path.home() / ".claude" / "plugins").resolve()
    home_plugins = home_plugins_base / plugin_name
    search_paths.append(home_plugins / "deps.yaml")
    allowed_bases.append(home_plugins_base)

    for deps_path in search_paths:
        resolved = deps_path.resolve()
        # パストラバーサル防止: 解決後パスが許可ベースディレクトリ配下であることを検証
        if not any(str(resolved).startswith(str(base) + '/') for base in allowed_bases):
            continue
        if resolved.exists():
            try:
                with open(resolved, 'r', encoding='utf-8') as f:
                    deps = yaml.safe_load(f)
                _cross_plugin_cache[cache_key] = deps
                return deps
            except Exception as e:
                print(f"Warning: Failed to load cross-plugin deps.yaml '{resolved}': {e}", file=sys.stderr)

    _cross_plugin_cache[cache_key] = None
    return None


def get_cross_plugin_component(plugin_name: str, component_name: str,
                                plugin_root: Optional[Path] = None) -> Optional[Tuple[str, dict, Path]]:
    """cross-plugin 参照先のコンポーネント情報を取得する。

    Returns: (section, component_data, target_plugin_root) or None
    """
    deps = resolve_cross_plugin(plugin_name, plugin_root)
    if deps is None:
        return None

    # 参照先 plugin_root を探索
    target_root = None
    if plugin_root:
        sibling = plugin_root.parent / plugin_name
        if sibling.is_dir():
            target_root = sibling
    if target_root is None:
        home_path = Path.home() / ".claude" / "plugins" / plugin_name
        if home_path.is_dir():
            target_root = home_path

    for section in ('skills', 'commands', 'agents', 'scripts'):
        if component_name in deps.get(section, {}):
            return (section, deps[section][component_name], target_root)

    return None


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
        cross-plugin 参照（'plugin:component' 形式）は ('xref', 'plugin:component', step) として返す。
        """
        result = []
        # キー → グラフ上のノードタイプ
        # v2.0 セクション名キー + v3.0 型名キー両方サポート
        key_map = {
            # v2.0 section-name keys
            'command': 'command', 'skill': 'skill', 'agent': 'agent',
            # v3.0 type-name keys (twill type → graph node type)
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
                    value = c[key]
                    step = c.get('step')
                    # cross-plugin 参照の検出
                    xref = parse_cross_plugin_ref(value)
                    if xref:
                        result.append(('xref', value, step))
                    else:
                        result.append((node_type, value, step))
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

    # refs セクション（reference 型スキル）
    for name, data in deps.get('refs', {}).items():
        node_id = f"skill:{name}"
        if node_id in graph:
            continue  # skills セクションに同名があれば skip
        path = data.get('path')
        tokens = count_tokens(plugin_root / path) if path else 0
        graph[node_id] = {
            'type': 'skill',
            'skill_type': 'reference',
            'name': name,
            'path': path,
            'description': data.get('description', ''),
            'calls': parse_calls(data.get('calls', [])),
            'uses_agents': data.get('uses_agents', []),
            'external': data.get('external', []),
            'requires_mcp': data.get('requires_mcp', []),
            'required_by': [],
            'conditional': None,
            'tokens': tokens,
            'chain': data.get('chain'),
            'step_in': data.get('step_in'),
        }

    # cross-plugin 参照ノードを収集・生成
    xref_nodes = set()
    for node_data in graph.values():
        for (t, n, *_rest) in node_data.get('calls', []):
            if t == 'xref':
                xref_nodes.add(n)
    for xref_value in xref_nodes:
        node_id = f"xref:{xref_value}"
        if node_id not in graph:
            xref_parsed = parse_cross_plugin_ref(xref_value)
            plugin_name = xref_parsed[0] if xref_parsed else ''
            comp_name = xref_parsed[1] if xref_parsed else xref_value
            # 参照先の情報を解決
            comp_info = get_cross_plugin_component(plugin_name, comp_name, plugin_root)
            if comp_info:
                _section, comp_data, _target_root = comp_info
                desc = comp_data.get('description', '')
                comp_type = comp_data.get('type', '')
            else:
                desc = f'cross-plugin ref: {xref_value}'
                comp_type = ''
            graph[node_id] = {
                'type': 'xref',
                'xref_plugin': plugin_name,
                'xref_component': comp_name,
                'xref_type': comp_type,
                'name': xref_value,
                'path': None,
                'description': desc,
                'calls': [],
                'uses_agents': [],
                'external': [],
                'requires_mcp': [],
                'required_by': [],
                'conditional': None,
                'tokens': 0,
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

    # agent.skills の逆方向（deps から直接読む）
    for agent_name, agent_data in deps.get('agents', {}).items():
        for skill in agent_data.get('skills', []):
            target_id = f"skill:{skill}"
            if target_id in graph:
                graph[target_id]['required_by'].append(
                    ('agent', agent_name)
                )

    return graph
