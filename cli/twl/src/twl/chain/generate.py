import argparse
import difflib
import hashlib
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.plugin import get_plugin_root, load_deps, get_deps_version


CALLED_BY_PATTERN = re.compile(r'。\S+ (?:Step \d+ )?から呼び出される。$')


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
        prog='twl chain generate',
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
                print("Run 'twl chain generate --all --write' to fix.")
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
                print(f"Run 'twl chain generate {args.chain_name} --write' to fix.")
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
