from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.plugin import get_cross_plugin_component


def check_files(graph: Dict, plugin_root: Path) -> Tuple[List[Tuple[str, str, str]], List[str]]:
    """ファイル存在確認

    Returns: (results, xref_warnings)
    """
    results = []
    xref_warnings = []

    for node_id, node_data in graph.items():
        if node_data['type'] == 'external':
            results.append(('external', node_id, None))
            continue

        if node_data['type'] == 'xref':
            # cross-plugin 参照のファイル存在チェック
            xref_plugin = node_data.get('xref_plugin', '')
            xref_comp = node_data.get('xref_component', '')
            comp_info = get_cross_plugin_component(xref_plugin, xref_comp, plugin_root)
            if comp_info is None:
                xref_warnings.append(
                    f"[xref-unresolved] {node_id}: cross-plugin ref could not be resolved "
                    f"(plugin '{xref_plugin}' not found)"
                )
                continue
            _section, comp_data, target_root = comp_info
            path = comp_data.get('path')
            if not path:
                results.append(('no_path', node_id, None))
                continue
            if target_root:
                full_path = target_root / path
                if full_path.exists():
                    results.append(('ok', node_id, path))
                else:
                    results.append(('missing', node_id, path))
            else:
                xref_warnings.append(
                    f"[xref-no-root] {node_id}: cannot resolve plugin root for '{xref_plugin}'"
                )
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

    return results, xref_warnings


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

    # refs セクションの reference も除外対象
    for ref_name in deps.get('refs', {}):
        references.add(f"skill:{ref_name}")

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
