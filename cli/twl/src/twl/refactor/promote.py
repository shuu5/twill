import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

from twl.core.types import TYPE_RULES, resolve_type


def _is_within_root(file_path: Path, root: Path) -> bool:
    """file_path が root の strict subdirectory かどうかを安全に検証（シンボリックリンク解決後）"""
    try:
        resolved = file_path.resolve()
        root_resolved = root.resolve()
        # root 自身は False（strict subdirectory チェック）
        return str(resolved).startswith(str(root_resolved) + os.sep)
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
    print(f"\nDone. Run 'twl validate' to verify.")
    return True
