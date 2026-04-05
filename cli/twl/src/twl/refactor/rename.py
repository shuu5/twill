import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

from twl.core.plugin import get_plugin_name
from twl.refactor.promote import _is_within_root


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
    print(f"\nDone. Run 'twl validate' to verify.")
    return True
