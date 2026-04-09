"""twl refine — deps.yaml の refined_by / refined_at を更新する。

Usage:
    twl refine --component <name>
    twl refine --batch <file.json>
"""

from __future__ import annotations

import hashlib
import json
import sys
from datetime import date
from pathlib import Path
from typing import Optional

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

from twl.core.plugin import get_plugin_root, load_deps


def _compute_ref_prompt_guide_hash(plugin_root: Path) -> Optional[str]:
    ref_path = plugin_root / "refs" / "ref-prompt-guide.md"
    if not ref_path.exists():
        return None
    return hashlib.sha1(ref_path.read_bytes()).hexdigest()[:8]


def _find_component_section(deps: dict, name: str) -> Optional[str]:
    for section in ("skills", "commands", "agents"):
        if name in deps.get(section, {}):
            return section
    return None


def _update_refined_fields(deps_path: Path, deps: dict, name: str, current_hash: str) -> bool:
    """deps.yaml の refined_by / refined_at を更新。成功なら True。"""
    section = _find_component_section(deps, name)
    if section is None:
        print(f"WARNING: コンポーネント '{name}' が deps.yaml に見つかりません — スキップ", file=sys.stderr)
        return False

    # deps.yaml をテキストとして読み込み、対象フィールドを置換
    content = deps_path.read_text(encoding="utf-8")
    today = date.today().strftime("%Y-%m-%d")
    new_refined_by = f"ref-prompt-guide@{current_hash}"

    # 現在の refined_by / refined_at を更新（存在する場合）
    # 存在しない場合は追加は行わない（deps.yaml 構造は SSOT のため直接追加しない）
    import re
    # コンポーネントブロック内の refined_by を対象ハッシュに更新
    pattern_by = re.compile(
        r'(^  ' + re.escape(name) + r':.*?(?:\n  \S|\Z))',
        re.MULTILINE | re.DOTALL,
    )

    def replace_fields(m: re.Match) -> str:
        block = m.group(0)
        block = re.sub(
            r'(    refined_by:\s*")[^"]*(")',
            rf'\g<1>{new_refined_by}\g<2>',
            block,
        )
        block = re.sub(
            r"(    refined_by:\s*')[^']*(')",
            rf"\g<1>{new_refined_by}\g<2>",
            block,
        )
        block = re.sub(
            r'(    refined_by:\s*)(?![\"\'])(\S+)',
            rf'\g<1>"{new_refined_by}"',
            block,
        )
        block = re.sub(
            r'(    refined_at:\s*")[^"]*(")',
            rf'\g<1>{today}\g<2>',
            block,
        )
        block = re.sub(
            r"(    refined_at:\s*')[^']*(')",
            rf"\g<1>{today}\g<2>",
            block,
        )
        block = re.sub(
            r'(    refined_at:\s*)(?![\"\'])(\S+)',
            rf'\g<1>"{today}"',
            block,
        )
        return block

    new_content, count = pattern_by.subn(replace_fields, content)
    if count == 0:
        print(f"WARNING: '{name}' のブロックが deps.yaml で見つかりませんでした — スキップ", file=sys.stderr)
        return False

    deps_path.write_text(new_content, encoding="utf-8")
    print(f"✓ {name}: refined_by={new_refined_by}, refined_at={today}")
    return True


def handle_refine(argv: list[str]) -> int:
    import argparse
    parser = argparse.ArgumentParser(
        prog="twl refine",
        description="deps.yaml の refined_by / refined_at を更新する",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--component", metavar="NAME", help="単一コンポーネントを更新")
    group.add_argument("--batch", metavar="FILE", help="JSON 配列から一括更新")
    args = parser.parse_args(argv)

    plugin_root = get_plugin_root()
    deps = load_deps(plugin_root)
    deps_path = plugin_root / "deps.yaml"

    current_hash = _compute_ref_prompt_guide_hash(plugin_root)
    if current_hash is None:
        print("ERROR: refs/ref-prompt-guide.md が見つかりません", file=sys.stderr)
        return 1

    if args.component:
        names = [args.component]
    else:
        batch_path = Path(args.batch)
        if not batch_path.exists():
            print(f"ERROR: {args.batch} が見つかりません", file=sys.stderr)
            return 1
        try:
            raw = json.loads(batch_path.read_text(encoding="utf-8"))
            if not isinstance(raw, list):
                print("ERROR: JSON ファイルは文字列配列でなければなりません", file=sys.stderr)
                return 1
            names = list(dict.fromkeys(str(n) for n in raw))  # 重複除去
        except json.JSONDecodeError as e:
            print(f"ERROR: JSON パース失敗: {e}", file=sys.stderr)
            return 1

    success = skip = error = 0
    for name in names:
        # deps を再ロード（前のループで更新済みのため）
        deps = load_deps(plugin_root)
        section = _find_component_section(deps, name)
        if section is None:
            print(f"WARNING: '{name}' は deps.yaml に存在しません — スキップ", file=sys.stderr)
            skip += 1
            continue
        ok = _update_refined_fields(deps_path, deps, name, current_hash)
        if ok:
            success += 1
        else:
            error += 1

    if len(names) > 1:
        print(f"\n完了: 成功={success}, スキップ={skip}, エラー={error}")

    return 0 if error == 0 else 1
