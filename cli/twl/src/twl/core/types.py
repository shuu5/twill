import hashlib
import os
import re
import sys
from pathlib import Path
from typing import Dict, Optional, Tuple

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# === 型ルール定数 ===
# SSOT: types.yaml（存在すれば）。フォールバック: 以下のハードコード値。
_FALLBACK_TOKEN_THRESHOLDS: Dict[str, Tuple[int, int]] = {
    'controller': (1500, 2500),
    'workflow': (1200, 2000),
    'atomic': (1500, 2500),
    'composite': (1500, 2500),
    'specialist': (1800, 2500),
    'supervisor': (2000, 3000),
}

_FALLBACK_TYPE_RULES = {
    'controller':  {'section': 'skills',   'can_spawn': {'workflow', 'atomic', 'composite', 'specialist', 'reference'}, 'spawnable_by': {'user', 'launcher'}},
    'workflow':    {'section': 'skills',   'can_spawn': {'atomic', 'composite', 'specialist', 'reference', 'script'},  'spawnable_by': {'controller', 'user'}},
    'atomic':      {'section': 'commands', 'can_spawn': {'reference', 'script'},                  'spawnable_by': {'workflow', 'controller', 'supervisor'}},
    'composite':   {'section': 'commands', 'can_spawn': {'specialist', 'script'},               'spawnable_by': {'workflow', 'controller'}},
    'specialist':  {'section': 'agents',   'can_spawn': set(),                                  'spawnable_by': {'workflow', 'composite', 'controller', 'supervisor'}},
    'reference':   {'section': 'skills',   'can_spawn': set(),                                  'spawnable_by': {'controller', 'atomic', 'composite', 'workflow', 'supervisor', 'agents.skills', 'all'}},
    'script':      {'section': 'scripts',  'can_spawn': {'script'},                              'spawnable_by': {'atomic', 'composite', 'script'}},
    'supervisor':  {'section': 'skills',   'can_spawn': {'workflow', 'atomic', 'composite', 'specialist', 'reference', 'script'}, 'spawnable_by': {'user'}},
}
TYPE_ALIASES = {}

# specialist の model フィールド許可値
ALLOWED_MODELS = {"haiku", "sonnet", "opus"}


def _get_loom_root() -> Path:
    """twl パッケージの配置ディレクトリ（= twill リポジトリルート cli/twl）を返す

    環境変数 TWL_LOOM_ROOT が設定されている場合はその値を使用する（テスト用）。
    """
    env_root = os.environ.get('TWL_LOOM_ROOT')
    if env_root:
        return Path(env_root).resolve()
    # src/twl/core/types.py -> src/twl/core -> src/twl -> src -> cli/twl
    return Path(__file__).resolve().parent.parent.parent.parent


def load_type_rules(loom_root: Optional[Path] = None) -> dict:
    """types.yaml から TYPE_RULES を構築する。存在しなければフォールバック値を返す。"""
    if loom_root is None:
        loom_root = _get_loom_root()
    types_path = loom_root / "types.yaml"
    def _deep_copy_rules(src: dict) -> dict:
        return {k: {'section': v['section'], 'can_spawn': set(v['can_spawn']), 'spawnable_by': set(v['spawnable_by']), 'can_supervise': set(v.get('can_supervise', []))} for k, v in src.items()}

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
                'can_supervise': set(type_def.get('can_supervise', [])),
            }
        return rules
    except Exception as e:
        print(f"Warning: Failed to load types.yaml: {e}, using fallback", file=sys.stderr)
        return _deep_copy_rules(_FALLBACK_TYPE_RULES)


TYPE_RULES = load_type_rules()


def load_token_thresholds(loom_root: Optional[Path] = None) -> Dict[str, Tuple[int, int]]:
    """types.yaml から token_target を読み取り {type: (warning, critical)} を返す。

    token_target を持つ型のみ結果に含める（reference/script は意図的に除外）。
    types.yaml が読めない場合はハードコードのフォールバック値を返す。
    """
    if loom_root is None:
        loom_root = _get_loom_root()
    types_path = loom_root / "types.yaml"

    if not types_path.exists():
        return dict(_FALLBACK_TOKEN_THRESHOLDS)
    try:
        with open(types_path, encoding='utf-8') as f:
            data = yaml.safe_load(f)
        if not data or 'types' not in data:
            return dict(_FALLBACK_TOKEN_THRESHOLDS)
        result: Dict[str, Tuple[int, int]] = {}
        for type_name, type_def in data['types'].items():
            tt = type_def.get('token_target')
            if tt and isinstance(tt, dict):
                warning = int(tt.get('warning', 1500))
                critical = int(tt.get('critical', 2500))
                result[type_name] = (warning, critical)
        return result if result else dict(_FALLBACK_TOKEN_THRESHOLDS)
    except Exception as e:
        print(f"Warning: Failed to load token_target from types.yaml: {e}, using fallback", file=sys.stderr)
        return dict(_FALLBACK_TOKEN_THRESHOLDS)


def resolve_type(t: str) -> str:
    """型エイリアスを解決"""
    return TYPE_ALIASES.get(t, t)


def print_rules():
    """types.yaml の型テーブルを人間向け Markdown テーブル形式で出力する"""
    loom_root = _get_loom_root()
    types_path = loom_root / "types.yaml"
    source = str(types_path) if types_path.exists() else "fallback (hardcoded)"
    rules = load_type_rules(loom_root)

    print(f"=== TWiLL Type Rules ===")
    print(f"Source: {source}")
    print()

    # ヘッダー
    print(f"| {'Type':<12} | {'Section':<10} | {'Can Spawn':<45} | {'Spawnable By':<40} |")
    print(f"|{'-'*14}|{'-'*12}|{'-'*47}|{'-'*42}|")

    known_order = ['controller', 'supervisor', 'workflow', 'atomic', 'composite', 'specialist', 'reference']
    ordered_types = [t for t in known_order if t in rules] + sorted(set(rules.keys()) - set(known_order))
    for type_name in ordered_types:
        rule = rules[type_name]
        can_spawn = ', '.join(sorted(rule['can_spawn'])) if rule['can_spawn'] else '(none)'
        spawnable_by = ', '.join(sorted(rule['spawnable_by'])) if rule['spawnable_by'] else '(none)'
        print(f"| {type_name:<12} | {rule['section']:<10} | {can_spawn:<45} | {spawnable_by:<40} |")

    print()
    print(f"Total: {len(rules)} types defined")


def _is_within_root(file_path: Path, root: Path) -> bool:
    """file_path が root の strict subdirectory かどうかを安全に検証（シンボリックリンク解決後）"""
    try:
        resolved = file_path.resolve()
        root_resolved = root.resolve()
        # root 自身は False（strict subdirectory チェック）
        return str(resolved).startswith(str(root_resolved) + os.sep)
    except (ValueError, OSError):
        return False


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
    valid_types = set(rules.keys()) | {'controller', 'supervisor', 'workflow', 'atomic', 'composite', 'specialist', 'reference'}

    def _parse_list(raw: str) -> set:
        if not raw or raw.strip('() ') in ('none', 'なし', '-', '—', ''):
            return set()
        return {x.strip().lower() for x in raw.split(',') if x.strip() and x.strip() not in ('-', '—')}

    valid_sections = {'skills', 'commands', 'agents', 'scripts'}

    for m in table_pattern.finditer(content):
        type_name = m.group(1).strip().lower()
        # ヘッダー行やセパレータ行をスキップ
        if type_name in ('type', 'name', '---', '', '型'):
            continue
        if type_name not in valid_types:
            continue

        section = m.group(2).strip().lower()
        # 有効なセクション名を持つ行のみ型ルールテーブルとして認識（誤検出防止）
        if section not in valid_sections:
            continue
        can_spawn_raw = m.group(3).strip()
        spawnable_by_raw = m.group(4).strip()

        ref_rules[type_name] = {
            'section': section,
            'can_spawn': _parse_list(can_spawn_raw),
            'spawnable_by': _parse_list(spawnable_by_raw),
        }

    print(f"=== Sync Check: types.yaml vs {ref_path} ===")
    print()

    diffs = []

    if not ref_rules:
        print(f"  (no type rules table found in {ref_file.name}, skipping type rules check)")
        print()
    else:
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

    # === token_target テーブルチェック ===
    # パターン: | 型名 | 1,234 tok | 1,234 tok | 備考 |
    token_thresholds = load_token_thresholds(loom_root)
    token_table_pattern = re.compile(
        r'^\|\s*(\w+)\s*\|\s*([\d,]+)\s*tok\s*\|\s*([\d,]+)\s*tok\s*\|',
        re.MULTILINE
    )
    ref_token: Dict[str, Tuple[int, int]] = {}
    for m in token_table_pattern.finditer(content):
        type_name = m.group(1).strip().lower()
        if type_name in ('型', 'type', 'name', '---', ''):
            continue
        try:
            warning_val = int(m.group(2).replace(',', ''))
            critical_val = int(m.group(3).replace(',', ''))
            ref_token[type_name] = (warning_val, critical_val)
        except ValueError:
            continue

    if token_thresholds and ref_token:
        # types.yaml の token_target 型が ref テーブルに存在するかチェック
        for type_name in sorted(token_thresholds.keys()):
            if type_name not in ref_token:
                diffs.append(f"[token-missing-in-ref] '{type_name}' token_target is in types.yaml but not in {ref_file.name} table")

        # ref テーブルの型が types.yaml にあるかチェック
        for type_name in sorted(ref_token.keys()):
            if type_name not in token_thresholds:
                diffs.append(f"[token-missing-in-yaml] '{type_name}' is in {ref_file.name} token table but not in types.yaml token_target")

        # warning < critical チェック
        for type_name in sorted(ref_token.keys()):
            warn_val, crit_val = ref_token[type_name]
            if warn_val >= crit_val:
                diffs.append(f"[token-invalid] {type_name}: warning ({warn_val}) must be < critical ({crit_val})")

        # 値の一致チェック
        for type_name in sorted(set(token_thresholds.keys()) & set(ref_token.keys())):
            yaml_warn, yaml_crit = token_thresholds[type_name]
            ref_warn, ref_crit = ref_token[type_name]
            if yaml_warn != ref_warn or yaml_crit != ref_crit:
                diffs.append(
                    f"[token-mismatch] {type_name}: yaml=({yaml_warn},{yaml_crit}) vs ref=({ref_warn},{ref_crit})"
                )

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
    sync_marker = '<!-- Synced from twl docs/'
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


SYNC_COMMENT = '<!-- Synced from twl docs/ — do not edit directly -->'


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
            print("Differences found. Run 'twl sync-docs <dir>' to sync.")
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
