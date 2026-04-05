import difflib
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from twl.core.graph import get_dependencies, collect_reachable_nodes
from twl.core.types import _is_within_root
from twl.validation.check import find_orphans


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
