import difflib
import hashlib
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple


def _normalize_for_check(text: str) -> str:
    """比較用にテキストを正規化する（trailing whitespace 除去 + LF 統一）。"""
    lines = text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
    return '\n'.join(line.rstrip() for line in lines)


def meta_chain_generate(deps: dict, meta_chain_name: str, plugin_root: Path) -> dict:
    """指定メタ chain の Template D（chain 間遷移指示）を生成して辞書で返す。

    Template D はメタ chain の flow 定義から、各 workflow SKILL.md に注入する
    「完了後の遷移」セクションを生成する。

    Returns:
        {
            'template_d': {skill_name: str, ...},  # skill名 → 遷移セクション文字列
        }
    """
    meta_chains = deps.get('meta_chains', {})
    meta_data = meta_chains.get(meta_chain_name)
    if meta_data is None or not isinstance(meta_data, dict):
        return {'template_d': {}}

    flow = meta_data.get('flow')
    if not isinstance(flow, list):
        return {'template_d': {}}

    # flow id → node マップ
    flow_map = {}
    for node in flow:
        if isinstance(node, dict) and isinstance(node.get('id'), str):
            flow_map[node['id']] = node

    template_d: Dict[str, str] = {}

    for node in flow:
        if not isinstance(node, dict):
            continue
        skill_name = node.get('skill')
        if not skill_name or not isinstance(skill_name, str):
            continue

        next_entries = node.get('next', [])
        if not isinstance(next_entries, list) or not next_entries:
            continue

        # 遷移セクションを生成
        transition_lines = []

        for entry in next_entries:
            if not isinstance(entry, dict):
                continue
            condition = entry.get('condition') or ''
            goto = entry.get('goto')
            stop = entry.get('stop', False)
            message = entry.get('message', '')

            if stop:
                # stop: 案内メッセージ
                if message:
                    transition_lines.append(f"- IS_AUTOPILOT=false → 「{message}」と案内")
                else:
                    transition_lines.append("- IS_AUTOPILOT=false → ユーザーへ案内して停止")
            elif goto and goto in flow_map:
                # goto: 次のワークフローへ遷移
                target_node = flow_map[goto]
                target_skill = target_node.get('skill')
                if target_skill and isinstance(target_skill, str):
                    skill_ref = f"/twl:{target_skill}"
                    if not condition:
                        # 無条件遷移: 常に次のワークフローへ
                        transition_lines.append(
                            f"- 即座に `{skill_ref}` を Skill tool で実行（停止禁止）"
                        )
                    elif 'autopilot' in condition and '!' not in condition:
                        transition_lines.append(
                            f"- IS_AUTOPILOT=true → 即座に `{skill_ref}` を Skill tool で実行（停止禁止）"
                        )
                    elif '!autopilot' in condition:
                        transition_lines.append(
                            f"- IS_AUTOPILOT=false → 「完了。次: `{skill_ref}` を実行してください」と案内"
                        )

        if not transition_lines:
            continue  # 遷移先 skill がない場合はスキップ

        lines = ["## 完了後の遷移（meta chain 定義から自動生成）", ""]
        lines.append("```bash")
        lines.append('eval "$(bash "$CR" autopilot-detect)"')
        lines.append("```")
        lines.append("")
        lines.extend(transition_lines)

        template_d[skill_name] = '\n'.join(lines)

    return {'template_d': template_d}


def meta_chain_generate_check(result: dict, deps: dict, plugin_root: Path) -> Tuple[List[dict], List[str]]:
    """メタ chain の Template D ドリフト検出。

    Returns:
        (file_results, diffs)
    """
    template_d = result.get('template_d', {})
    if not template_d:
        return [], []

    all_components: Dict[str, Tuple[str, dict]] = {}
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            all_components[comp_name] = (section, data)

    transition_pattern = re.compile(
        r'^##\s+完了後の遷移.*$',
        re.MULTILINE | re.IGNORECASE
    )

    file_results = []
    diffs = []

    for skill_name, expected_content in template_d.items():
        comp = all_components.get(skill_name)
        if comp is None:
            continue
        path_str = comp[1].get('path')
        if not path_str:
            continue

        file_path = plugin_root / path_str
        if not file_path.resolve().is_relative_to(plugin_root.resolve()):
            continue
        if not file_path.exists():
            file_results.append({'comp': skill_name, 'path': path_str, 'status': 'DRIFT', 'template': 'D'})
            diffs.append(f"=== Diff: {path_str} (Template D) ===\n--- expected\n+++ actual (file not found)\n")
            continue

        content = file_path.read_text(encoding='utf-8')
        match = transition_pattern.search(content)
        if match is None:
            file_results.append({'comp': skill_name, 'path': path_str, 'status': 'DRIFT', 'template': 'D'})
            expected_lines = _normalize_for_check(expected_content).splitlines(keepends=True)
            diff_lines = list(difflib.unified_diff(
                expected_lines, ['(section not found)\n'],
                fromfile='expected', tofile='actual'
            ))
            diffs.append(f"=== Diff: {path_str} (Template D) ===\n" + ''.join(diff_lines))
            continue

        rest = content[match.end():]
        next_section = re.search(r'^##\s', rest, re.MULTILINE)
        if next_section:
            actual_section = content[match.start():match.end() + next_section.start()].rstrip('\n')
        else:
            actual_section = content[match.start():].rstrip('\n')

        norm_expected = _normalize_for_check(expected_content)
        norm_actual = _normalize_for_check(actual_section)

        if hashlib.sha256(norm_expected.encode('utf-8')).hexdigest() == \
           hashlib.sha256(norm_actual.encode('utf-8')).hexdigest():
            file_results.append({'comp': skill_name, 'path': path_str, 'status': 'ok', 'template': 'D'})
        else:
            file_results.append({'comp': skill_name, 'path': path_str, 'status': 'DRIFT', 'template': 'D'})
            expected_lines = norm_expected.splitlines(keepends=True)
            actual_lines = norm_actual.splitlines(keepends=True)
            diff_lines = list(difflib.unified_diff(
                expected_lines, actual_lines,
                fromfile='expected', tofile='actual'
            ))
            diffs.append(f"=== Diff: {path_str} (Template D) ===\n" + ''.join(diff_lines))

    return file_results, diffs


def meta_chain_generate_write(result: dict, deps: dict, plugin_root: Path) -> None:
    """メタ chain の Template D をプロンプトファイルに書き込む。"""
    template_d = result.get('template_d', {})
    if not template_d:
        return

    all_components: Dict[str, Tuple[str, dict]] = {}
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            all_components[comp_name] = (section, data)

    transition_pattern = re.compile(
        r'^##\s+完了後の遷移.*$',
        re.MULTILINE | re.IGNORECASE
    )

    for skill_name, new_content in template_d.items():
        comp = all_components.get(skill_name)
        if comp is None:
            continue
        path_str = comp[1].get('path')
        if not path_str:
            print(f"Warning: No path defined for {skill_name}, skipping --write", file=sys.stderr)
            continue

        file_path = plugin_root / path_str
        if not file_path.resolve().is_relative_to(plugin_root.resolve()):
            print(f"Warning: Path traversal detected for {skill_name}, skipping", file=sys.stderr)
            continue
        if not file_path.exists():
            print(f"Warning: File not found: {file_path}, skipping --write", file=sys.stderr)
            continue

        content = file_path.read_text(encoding='utf-8')
        match = transition_pattern.search(content)
        if match:
            rest = content[match.end():]
            next_section = re.search(r'^##\s', rest, re.MULTILINE)
            if next_section:
                end = match.end() + next_section.start()
            else:
                end = len(content)
            content = content[:match.start()] + new_content + '\n\n' + content[end:]
        else:
            content = content.rstrip('\n') + '\n\n' + new_content + '\n'

        file_path.write_text(content, encoding='utf-8')
        print(f"Updated (Template D): {path_str}")
