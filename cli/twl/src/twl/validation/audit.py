import hashlib
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.types import resolve_type, ALLOWED_MODELS
from twl.validation.utils import _get_body_text, _count_body_lines


REQUIRED_OUTPUT_KEYWORDS = {
    "result_values": {"PASS", "FAIL"},        # いずれか1つ以上
    "structure": {"findings"},                 # 必須
    "severity": {"severity"},                  # 必須
    "confidence": {"confidence"},              # 必須
}

# controller_size: コンポーネント別の critical 行数閾値（デフォルト 200）
# Issue #1082: co-autopilot は inline 化により 231 行になるため 280 に緩和
_CONTROLLER_SIZE_OVERRIDES: Dict[str, int] = {
    'co-autopilot': 280,
}


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


def _compute_ref_prompt_guide_hash(plugin_root: Path) -> Optional[str]:
    """ref-prompt-guide.md の SHA-1 ハッシュ先頭8文字を返す（ファイル不在は None）"""
    ref_path = plugin_root / "refs" / "ref-prompt-guide.md"
    if not ref_path.exists():
        return None
    return hashlib.sha1(ref_path.read_bytes()).hexdigest()[:8]


def _parse_dispatch_table(runner_text: str) -> Set[str]:
    """chain-runner.sh の case "$STEP" in ... esac から step 名を抽出する

    認識パターン:
        <step-name>)   step_<func> "$@" ;;
        <step-name>)   record_current_step "..."; ok "..." "..." ;;
    """
    if not runner_text:
        return set()
    pattern = re.compile(
        r'^\s*([a-z][a-z0-9-]*)\)\s*(?:record_current_step|step_[a-z_]+)',
        re.M,
    )
    return set(pattern.findall(runner_text))


def _read_skill_text(skills_root: Path, workflow_name: str) -> str:
    """workflow の SKILL.md を読み込む（フロントマター含む全文）"""
    skill_path = skills_root / workflow_name / "SKILL.md"
    if not skill_path.exists():
        return ""
    try:
        return skill_path.read_text(encoding="utf-8")
    except Exception:
        return ""


def _skill_has_invocation(skill_text: str, target: str) -> bool:
    """SKILL.md text 内に target component への明示的実行指示があるかを判定

    Phase 1: 厳密マッチ（false positive 抑制）
        - commands/<target>.md / agents/<target>.md / skills/<target>/ の Read 指示
        - chain-runner.sh <target> / "$CR" <target> 等の実行指示
        - bash chain-runner.sh <target>
    """
    if not skill_text or not target:
        return False
    if f"commands/{target}.md" in skill_text:
        return True
    if f"agents/{target}.md" in skill_text:
        return True
    if f"skills/{target}/" in skill_text:
        return True
    # chain-runner.sh の引数として呼ばれている明示パターン
    invocation_patterns = [
        rf'chain-runner\.sh\s+{re.escape(target)}\b',
        rf'"\$CR"\s+{re.escape(target)}\b',
        rf'\$CR\s+{re.escape(target)}\b',
        rf'cr\s+{re.escape(target)}\b',
    ]
    for pat in invocation_patterns:
        if re.search(pat, skill_text):
            return True
    return False


def _lookup_component(deps: dict, target: str) -> Optional[dict]:
    """deps.yaml の各セクションから target コンポーネントを検索"""
    for section in ('skills', 'commands', 'agents', 'scripts'):
        spec = deps.get(section, {}).get(target)
        if spec is not None:
            return spec
    return None


def _get_dispatch_mode(deps: dict, target: str) -> Optional[str]:
    """target コンポーネントの dispatch_mode を返す（未宣言は None）"""
    spec = _lookup_component(deps, target)
    if spec is None:
        return None
    mode = spec.get('dispatch_mode')
    if mode is None:
        return None
    return str(mode)


def _is_llm_driven(deps: dict, target: str) -> bool:
    """target が LLM 駆動として宣言されているかを判定"""
    return _get_dispatch_mode(deps, target) == 'llm'


def _is_trigger_only(deps: dict, target: str) -> bool:
    """target が trigger 経由のみで起動されると宣言されているかを判定"""
    return _get_dispatch_mode(deps, target) == 'trigger'


def _iter_workflows(deps: dict):
    """deps.yaml の skills セクションから type=workflow を yield する"""
    for name, spec in deps.get('skills', {}).items():
        if spec.get('type') == 'workflow':
            yield name, spec


def audit_chain_integrity(deps: dict, plugin_root: Path) -> List[dict]:
    """Section 9: Chain Integrity

    deps.yaml × chain-runner.sh × SKILL.md text の三者整合性を検証する。

    検出対象:
    - orphan_call (WARNING): step 番号なし + LLM 駆動宣言なし + trigger 宣言なし
    - dispatch_gap (CRITICAL): step あり + chain-runner.sh dispatch なし
                                + LLM 駆動宣言なし + SKILL.md 言及なし

    Returns: items リスト（severity, component, message, section, value, threshold）
    """
    items: List[dict] = []

    runner_path = plugin_root / "scripts" / "chain-runner.sh"
    runner_text = ""
    if runner_path.exists():
        try:
            runner_text = runner_path.read_text(encoding="utf-8")
        except Exception:
            runner_text = ""
    dispatched_steps = _parse_dispatch_table(runner_text)

    skills_root = plugin_root / "skills"

    for wf_name, wf_spec in sorted(_iter_workflows(deps)):
        skill_text = _read_skill_text(skills_root, wf_name)
        for call in wf_spec.get('calls', []):
            if not isinstance(call, dict):
                continue
            # ターゲットの型と名前を抽出（v3.0 type-name keys）
            target = None
            ctype = None
            for k in ('atomic', 'composite', 'workflow', 'controller', 'specialist', 'reference', 'script'):
                if k in call:
                    target = call[k]
                    ctype = k
                    break
            if not target:
                continue
            step = call.get('step')

            llm = _is_llm_driven(deps, target)
            trigger = _is_trigger_only(deps, target)
            mentioned = _skill_has_invocation(skill_text, target)

            # 1. Orphan call
            if step is None and not llm and not trigger and not mentioned:
                items.append({
                    "severity": "warning",
                    "component": f"{wf_name}→{target}",
                    "message": f"orphan_call: step 番号なし、LLM/trigger 駆動宣言なし、SKILL.md 言及もなし",
                    "section": "chain_integrity",
                    "value": 0,
                    "threshold": 1,
                })
                continue

            # 2. Dispatch gap (atomic / script のみ)
            if step is not None and ctype in ('atomic', 'script'):
                if target not in dispatched_steps and not llm and not mentioned:
                    items.append({
                        "severity": "critical",
                        "component": f"{wf_name}→{target}",
                        "message": (
                            f"dispatch_gap: step {step} 宣言、chain-runner.sh に "
                            f"step_{target.replace('-', '_')} なし、SKILL.md 実行指示もなし"
                        ),
                        "section": "chain_integrity",
                        "value": 0,
                        "threshold": 1,
                    })
                    continue

            # OK row（カウント用）
            items.append({
                "severity": "ok",
                "component": f"{wf_name}→{target}",
                "message": f"ok: step={step or '-'} type={ctype}",
                "section": "chain_integrity",
                "value": 1,
                "threshold": 1,
            })

    return items


def _detect_monorepo_root(plugin_root: Path) -> Optional[Path]:
    """git rev-parse --show-toplevel でモノリポルートを検出する。

    失敗した場合は architecture/vision.md を持つ親ディレクトリを探して返す。
    """
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--show-toplevel'],
            cwd=str(plugin_root),
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except Exception:
        pass
    # フォールバック: 親ディレクトリを走査して architecture/vision.md を持つ最上位を探す
    current = plugin_root.resolve()
    found = None
    while current != current.parent:
        if (current / 'architecture' / 'vision.md').exists():
            found = current
        current = current.parent
    return found


def _extract_vision_sections(vision_path: Path) -> Dict[str, List[str]]:
    """vision.md から ## Constraints と ## Non-Goals の箇条書き項目を抽出する。

    Returns: {'constraints': [...], 'non_goals': [...]}
    """
    if not vision_path.exists():
        return {'constraints': [], 'non_goals': []}
    try:
        text = vision_path.read_text(encoding='utf-8')
    except Exception:
        return {'constraints': [], 'non_goals': []}

    sections: Dict[str, List[str]] = {'constraints': [], 'non_goals': []}
    current_section: Optional[str] = None

    for line in text.splitlines():
        stripped = line.strip()
        if re.match(r'^##\s+Constraints\s*$', stripped):
            current_section = 'constraints'
            continue
        if re.match(r'^##\s+Non-Goals\s*$', stripped):
            current_section = 'non_goals'
            continue
        if re.match(r'^##\s+', stripped):
            current_section = None
            continue
        if current_section and re.match(r'^[-*]\s+', stripped):
            item = stripped.lstrip('-*').strip()
            sections[current_section].append(item)

    return sections


def _extract_bold_terms(text: str) -> List[str]:
    """**term** パターンからボールド強調語を抽出する。"""
    return re.findall(r'\*\*([^*]+)\*\*', text)


def _check_layer_consistency(
    lower_name: str,
    lower_constraints: List[str],
    lower_non_goals: List[str],
    upper_constraints: List[str],
) -> List[str]:
    """ADR-0008 の整合性ルールに基づいて下位層と上位層の矛盾を検出する。

    機械的に検出可能なルール:
    - Type 4: 上位層 Constraints のボールド強調語が下位層 Non-Goals に含まれる
      （Constraints に定義された項目が Non-Goals に格下げされている）

    Returns: 検出された問題のメッセージリスト（空ならOK）
    """
    issues: List[str] = []

    # 上位層 Constraints から強調語を抽出
    upper_bold_terms: List[str] = []
    for constraint in upper_constraints:
        upper_bold_terms.extend(_extract_bold_terms(constraint))

    # Type 4: 上位層 Constraints の強調語が下位層 Non-Goals に現れていないか確認
    for term in upper_bold_terms:
        for ng_item in lower_non_goals:
            if term in ng_item:
                issues.append(
                    f"Type4（Constraints→Non-Goals格下げ疑い）: "
                    f"上位層 Constraints キーワード「{term}」が {lower_name} の Non-Goals に含まれる"
                )
                break  # 同じ term について1回だけ報告

    return issues


def audit_cross_layer_consistency(monorepo_root: Path) -> List[dict]:
    """Section 10: Cross-Layer Consistency (ADR-0008)

    三層 Architecture Spec の整合性を検証する。

    検出対象:
    - Type 4 (WARNING): 上位層 Constraints のキーワードが下位層 Non-Goals に含まれる

    Returns: items リスト（severity, component, message, section, value, threshold）
    """
    items: List[dict] = []

    # ADR-0008 の正本ファイルパス定義
    # CLI 層・Plugin 層はともに Monorepo 層を親とする兄弟関係
    canonical_layers = [
        ('monorepo', monorepo_root / 'architecture' / 'vision.md'),
        ('cli_twl', monorepo_root / 'cli' / 'twl' / 'architecture' / 'vision.md'),
        ('plugin_twl', monorepo_root / 'plugins' / 'twl' / 'architecture' / 'vision.md'),
    ]

    layer_data: Dict[str, Dict] = {}
    for name, path in canonical_layers:
        if not path.exists():
            items.append({
                'severity': 'info',
                'component': name,
                'message': f'architecture/vision.md が存在しない — スキップ',
                'section': 'cross_layer_consistency',
                'value': 1,
                'threshold': 1,
            })
            continue
        sections = _extract_vision_sections(path)
        layer_data[name] = sections

    if 'monorepo' not in layer_data:
        return items

    upper = layer_data['monorepo']

    # CLI 層と Plugin 層を Monorepo 層と照合
    for lower_name in ('cli_twl', 'plugin_twl'):
        if lower_name not in layer_data:
            continue
        lower = layer_data[lower_name]
        issues = _check_layer_consistency(
            lower_name=lower_name,
            lower_constraints=lower['constraints'],
            lower_non_goals=lower['non_goals'],
            upper_constraints=upper['constraints'],
        )
        if issues:
            for issue in issues:
                items.append({
                    'severity': 'warning',
                    'component': f'monorepo→{lower_name}',
                    'message': issue,
                    'section': 'cross_layer_consistency',
                    'value': 0,
                    'threshold': 1,
                })
        else:
            items.append({
                'severity': 'ok',
                'component': f'monorepo→{lower_name}',
                'message': 'OK: Constraints/Non-Goals 整合',
                'section': 'cross_layer_consistency',
                'value': 1,
                'threshold': 1,
            })

    return items


def _load_rules_for_section(registry: dict, section_num: int) -> List[dict]:
    """registry.yaml §5 integrity_rules から audit_section == section_num の rule を返す。

    Phase 2 dual-stack 移行時に Section 別 dispatcher へ進化させる際のフック関数。
    """
    rules = registry.get('integrity_rules', []) or []
    if not isinstance(rules, list):
        return []
    return [r for r in rules if isinstance(r, dict) and r.get('audit_section') == section_num]


def audit_vocabulary(
    registry: dict,
    plugin_root: Path,
    monorepo_root: Optional[Path] = None,
    scan_spec: bool = False,
) -> List[dict]:
    """Section 11: Vocabulary Check

    registry['glossary'][*].forbidden の単語を skills/ + agents/ + refs/ 配下
    (+ scan_spec=True 時は monorepo_root/architecture/spec/twill-plugin-rebuild/
    + monorepo_root/architecture/decisions/) の Markdown ファイルで word boundary
    厳密検出する。

    False positive 抑制 (registry.yaml §5 vocabulary_forbidden_use.exclusion_contexts):
      1. backtick 内 (`...`) の公式名引用
      2. 「旧」「廃止予定」を含む説明行
      3. migration-stage 表記 (`Phase 1 PoC` 等、backtick 除去で副次対応)
      4. compound canonical entity:
         - ハイフン区切り compound (e.g., `auto-pilot` 内の `pilot`): compound_pattern で検出 + canonical_names で除外
         - non-hyphen compound (e.g., `co-autopilot` 内の subword `autopilot` の `pilot` 部分):
           `\b` word boundary が自然に防ぐ (`a-pilot` の boundary は OK だが `o + p` の boundary は不成立)

    component prefix:
      - skills/+agents/+refs/ 由来: `vocabulary:{entity}`
      - spec/+ADR/ 由来 (scan_spec=True 時): `vocabulary:spec:{entity}`

    Returns: items リスト (severity, component, message, section, value, threshold)
    """
    items: List[dict] = []
    glossary = registry.get('glossary', {}) or {}
    if not isinstance(glossary, dict) or not glossary:
        return items

    forbidden_map: Dict[str, List[str]] = {}
    canonical_names: Set[str] = set()
    for entity, entry in glossary.items():
        if not isinstance(entry, dict):
            continue
        canonical = entry.get('canonical', entity)
        if isinstance(canonical, str) and canonical.strip():
            canonical_names.add(canonical.strip())
        words = entry.get('forbidden', []) or []
        if isinstance(words, list):
            valid = [str(w).strip() for w in words if isinstance(w, str) and w.strip()]
            if valid:
                forbidden_map[entity] = valid

    if not forbidden_map:
        return items

    # scan_bases: (base_dir, recursive, component_prefix, root_for_relpath)
    scan_bases: List[Tuple[Path, bool, str, Path]] = [
        (plugin_root / 'skills', True, 'vocabulary', plugin_root),
        (plugin_root / 'agents', False, 'vocabulary', plugin_root),
        (plugin_root / 'refs', False, 'vocabulary', plugin_root),
    ]
    if scan_spec:
        _mr = monorepo_root if monorepo_root is not None else _detect_monorepo_root(plugin_root)
        if _mr is not None:
            # spec dir (twill-plugin-rebuild)
            scan_bases.append((_mr / 'architecture' / 'spec' / 'twill-plugin-rebuild',
                               False, 'vocabulary:spec', _mr))
            # ADR dirs: monorepo-level (architecture/decisions/) + plugin-level (plugins/twl/architecture/decisions/)
            # 後者には ADR-043/044/045 (twill plugin rebuild の core ADR) が存在
            scan_bases.append((_mr / 'architecture' / 'decisions',
                               False, 'vocabulary:spec', _mr))
            scan_bases.append((_mr / 'plugins' / 'twl' / 'architecture' / 'decisions',
                               False, 'vocabulary:spec', _mr))

    # target_file_groups: (path, prefix, root_for_relpath)
    target_file_groups: List[Tuple[Path, str, Path]] = []
    for base, recursive, prefix, root in scan_bases:
        if not base.exists() or not base.is_dir():
            continue
        if recursive:
            target_file_groups.extend((p, prefix, root) for p in base.rglob('*.md') if p.is_file())
        else:
            target_file_groups.extend((p, prefix, root) for p in base.glob('*.md') if p.is_file())

    if not target_file_groups:
        items.append({
            "severity": "info",
            "component": "vocabulary:scan",
            "message": "no scannable Markdown files under skills/ + agents/ + refs/" + (" + spec/ + decisions/" if scan_spec else ""),
            "section": "vocabulary_check",
            "value": 0,
            "threshold": 1,
        })
        return items

    # entity × word × source prefix の組合せで集計
    # key: (entity, word, prefix) → set of file paths
    hits_by_source: Dict[Tuple[str, str, str], Set[str]] = {}

    for entity in sorted(forbidden_map.keys()):
        for word in forbidden_map[entity]:
            pattern = re.compile(r'\b' + re.escape(word) + r'\b')
            compound_pattern = re.compile(r'\b([\w]+(?:-[\w]+)*-' + re.escape(word) + r')\b')
            for fpath, prefix, root in sorted(target_file_groups, key=lambda t: str(t[0])):
                try:
                    raw = fpath.read_text(encoding='utf-8')
                except Exception:
                    continue
                cleaned = re.sub(r'`[^`\n]*`', '', raw)
                found = False
                for line in cleaned.splitlines():
                    if '旧' in line or '廃止予定' in line:
                        continue
                    if not pattern.search(line):
                        continue
                    compound_matches = compound_pattern.findall(line)
                    if compound_matches:
                        excluded_compounds = [m for m in compound_matches if m in canonical_names]
                        if excluded_compounds:
                            tmp = line
                            for c in excluded_compounds:
                                tmp = tmp.replace(c, '')
                            if not pattern.search(tmp):
                                continue
                    found = True
                    break
                if found:
                    try:
                        rel = str(fpath.relative_to(root))
                    except ValueError:
                        rel = fpath.name
                    hits_by_source.setdefault((entity, word, prefix), set()).add(rel)

    # emit warning per (entity, word, prefix)
    for (entity, word, prefix) in sorted(hits_by_source.keys()):
        hit_files = hits_by_source[(entity, word, prefix)]
        files_sorted = sorted(hit_files)
        files_preview = ', '.join(files_sorted[:5])
        if len(files_sorted) > 5:
            files_preview += f', ... (+{len(files_sorted) - 5} more)'
        items.append({
            "severity": "warning",
            "component": f"{prefix}:{entity}",
            "message": f"forbidden word '{word}' detected in {len(files_sorted)} file(s): {files_preview}",
            "section": "vocabulary_check",
            "value": len(files_sorted),
            "threshold": 0,
        })

    rules_11 = _load_rules_for_section(registry, 11)
    for rule in rules_11:
        rule_id = rule.get('id')
        if rule_id == 'official_name_collision':
            items.append({
                "severity": "info",
                "component": f"vocabulary:rule:{rule_id}",
                "message": "Phase 1 PoC: not implemented (backtick exclusion partially covers)",
                "section": "vocabulary_check",
                "value": 0,
                "threshold": 1,
            })

    return items


def audit_registry(registry: dict, plugin_root: Path) -> List[dict]:
    """Section 12: Registry Integrity

    registry.yaml の 5 section schema 存在 + components core 2 rule + 3 rule stub。

    Core rules (critical, implemented):
      - prefix_role_match: components の name prefix と role 一致
      - no_duplicate_concern: concern field unique

    Stub rules (warning, Phase 1 PoC は未実装、Phase 2 dual-stack で実装):
      - ssot_authority_unique: ssot_excludes (delegation) と他 component の concern の
                               semantic 整合検証 — 単純な overlap 検出では false positive
                               になるため、Authority field 追加と組み合わせて Phase 2 実装
      - derived_drift_check: types.py fallback drift
      - description_required_consistency: description_required field 整合
      Note: vocabulary_forbidden_use / official_name_collision は Section 11 担当

    Returns: items リスト
    """
    items: List[dict] = []

    REQUIRED_SECTIONS = ['glossary', 'components', 'chains', 'hooks-monitors', 'integrity_rules']
    for sec in REQUIRED_SECTIONS:
        if sec not in registry:
            items.append({
                "severity": "critical",
                "component": f"registry:section:{sec}",
                "message": f"required section '{sec}' missing in registry.yaml",
                "section": "registry_integrity",
                "value": 0,
                "threshold": 1,
            })
        else:
            items.append({
                "severity": "ok",
                "component": f"registry:section:{sec}",
                "message": "section present",
                "section": "registry_integrity",
                "value": 1,
                "threshold": 1,
            })

    components_raw = registry.get('components', []) or []
    components = components_raw if isinstance(components_raw, list) else []

    SEED_NAMES = {'administrator', 'phaser-explore', 'phaser-refine', 'phaser-impl', 'phaser-pr'}
    seed_components = [c for c in components if isinstance(c, dict) and c.get('name') in SEED_NAMES]

    PREFIX_ROLE_MAP = {
        'phaser': 'phaser',
        'tool': 'tool',
        'workflow': 'workflow',
        'atomic': 'atomic',
        'specialist': 'specialist',
        'reference': 'reference',
        'script': 'script',
        'hook': 'hook',
        'monitor': 'monitor',
    }

    # Rule 1: prefix_role_match
    for comp in seed_components:
        name = comp.get('name', '')
        role = comp.get('role', '')
        if name == 'administrator':
            if role != 'administrator':
                items.append({
                    "severity": "critical",
                    "component": f"registry:component:{name}",
                    "message": f"prefix_role_match: 'administrator' has role='{role}' (expected: administrator)",
                    "section": "registry_integrity",
                    "value": 0,
                    "threshold": 1,
                })
            continue
        prefix = name.split('-', 1)[0] if '-' in name else name
        expected_role = PREFIX_ROLE_MAP.get(prefix)
        if expected_role is None:
            continue
        if role != expected_role:
            items.append({
                "severity": "critical",
                "component": f"registry:component:{name}",
                "message": f"prefix_role_match: '{name}' prefix '{prefix}' implies role '{expected_role}', got '{role}'",
                "section": "registry_integrity",
                "value": 0,
                "threshold": 1,
            })

    # Rule 2: no_duplicate_concern
    concern_owners: Dict[str, str] = {}
    for comp in seed_components:
        name = comp.get('name', '')
        concern_raw = comp.get('concern', '')
        concern = concern_raw.strip() if isinstance(concern_raw, str) else ''
        if not concern:
            continue
        if concern in concern_owners:
            items.append({
                "severity": "critical",
                "component": f"registry:component:{name}",
                "message": f"no_duplicate_concern: concern '{concern}' duplicated with '{concern_owners[concern]}'",
                "section": "registry_integrity",
                "value": 0,
                "threshold": 1,
            })
        else:
            concern_owners[concern] = name

    # Stub 3 rule (warning) - Section 12 担当の Phase 1 PoC 未実装
    # ssot_authority_unique は ssot_excludes (delegation 宣言) と他 component の concern の
    # semantic 整合性を見る必要があり、単純な overlap 検出では delegation を critical 化する
    # false positive を生む。Phase 2 で Authority field 追加と組み合わせて実装。
    STUB_RULES_12 = [
        ('ssot_authority_unique',
         'Phase 1 PoC seed: Authority delegation semantic verification deferred to Phase 2'),
        ('derived_drift_check',
         'Phase 1 PoC seed: types.py _FALLBACK_TOKEN_THRESHOLDS drift check not implemented'),
        ('description_required_consistency',
         'Phase 1 PoC seed: description_required field consistency check not implemented'),
    ]
    rules_12_ids = {r.get('id') for r in _load_rules_for_section(registry, 12) if isinstance(r, dict)}
    for rule_id, msg in STUB_RULES_12:
        if rule_id in rules_12_ids:
            items.append({
                "severity": "warning",
                "component": f"registry:rule:{rule_id}",
                "message": msg,
                "section": "registry_integrity",
                "value": 0,
                "threshold": 1,
            })

    # EXP-034: seed component file existence (frontmatter parse は Phase 2)
    for comp in seed_components:
        name = comp.get('name', '')
        file_rel = comp.get('file', '')
        if not file_rel or not isinstance(file_rel, str):
            continue
        fpath = plugin_root / file_rel
        if not fpath.exists():
            items.append({
                "severity": "info",
                "component": f"registry:component:{name}",
                "message": f"file '{file_rel}' not found (Phase 1 PoC seed, frontmatter check skipped)",
                "section": "registry_integrity",
                "value": 0,
                "threshold": 1,
            })

    return items


def audit_collect(
    deps: dict,
    plugin_root: Path,
    monorepo_root: Optional[Path] = None,
    scan_spec: bool = False,
) -> List[dict]:
    """12 セクションの TWiLL 準拠度データを収集（print なし）

    Section 11/12 は registry.yaml を auto-detect: plugin_root / "registry.yaml" が
    存在すれば実行、不在なら skip（既存 Section 1-10 への影響なし）。

    scan_spec=True 時、Section 11 は monorepo_root/architecture/spec/twill-plugin-rebuild/
    + monorepo_root/architecture/decisions/ も scan 対象に含める。

    Returns: items リスト（severity, component, message, section, value, threshold）
    """
    from twl.core.types import _is_within_root

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
        critical_threshold = _CONTROLLER_SIZE_OVERRIDES.get(name, 200)
        if lines > critical_threshold:
            severity = 'critical'
        elif lines > 120:
            severity = 'warning'
        else:
            severity = 'ok'
        items.append({
            "severity": severity,
            "component": name,
            "message": f"Controller size {lines} lines" + (f" (threshold: {critical_threshold if lines > critical_threshold else 120})" if severity != 'ok' else ""),
            "section": "controller_size",
            "value": lines,
            "threshold": critical_threshold if lines > critical_threshold else 120,
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
        elif output_schema_val is not None:
            schema_str = 'Invalid'
            schema_ok = False
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

    # Section 6: Token Bloat
    from twl.core.plugin import count_tokens
    from twl.core.types import load_token_thresholds as _ltt, resolve_type as _rt
    TOKEN_THRESHOLDS = _ltt()

    for name, comp in sorted(all_components.items()):
        comp_type = _rt(comp['type'])
        if comp_type not in TOKEN_THRESHOLDS:
            continue
        path_str = comp['path']
        if not path_str:
            continue
        path = plugin_root / path_str
        if not _is_within_root(path, plugin_root) or not path.exists():
            continue
        tok = count_tokens(path)
        if tok == 0:
            continue
        warn_threshold, crit_threshold = TOKEN_THRESHOLDS[comp_type]
        if tok > crit_threshold:
            severity = 'critical'
        elif tok > warn_threshold:
            severity = 'warning'
        else:
            severity = 'ok'
        items.append({
            "severity": severity,
            "component": name,
            "message": f"{comp_type}: {tok} tok (warn={warn_threshold}, crit={crit_threshold})",
            "section": "token_bloat",
            "value": tok,
            "threshold": warn_threshold,
        })

    # Section 7: Model Declaration
    for name, comp in sorted(all_components.items()):
        resolved = resolve_type(comp['type'])
        if resolved != 'specialist':
            continue
        model = comp.get('model')
        if model is None:
            severity = 'warning'
            message = f"model 未宣言: {name}"
        elif model == 'opus':
            severity = 'warning'
            message = f"opus 使用: {name}"
        elif model not in ALLOWED_MODELS:
            severity = 'info'
            message = f"不明なモデル: {model}"
        else:
            severity = 'ok'
            message = f"model: {model}"
        items.append({
            "severity": severity,
            "component": name,
            "message": message,
            "section": "model_declaration",
            "value": 0 if severity == 'warning' else 1,
            "threshold": 1,
        })

    # Section 8: Prompt Compliance
    current_hash = _compute_ref_prompt_guide_hash(plugin_root)
    for section in ('skills', 'commands', 'agents'):
        for name, spec in sorted(deps.get(section, {}).items()):
            refined_by = spec.get('refined_by')
            if refined_by is None:
                severity = 'info'
                message = "未レビュー（refined_by 未設定）"
                value = 0
            else:
                # Format: ref-prompt-guide@XXXXXXXX
                m = re.match(r'^ref-prompt-guide@([0-9a-f]{8})$', str(refined_by))
                if not m:
                    severity = 'critical'
                    message = f"refined_by フォーマット不正: {refined_by}"
                    value = 0
                elif current_hash is None:
                    severity = 'info'
                    message = "ref-prompt-guide.md が見つからないためハッシュ照合不可"
                    value = 1
                elif m.group(1) == current_hash:
                    severity = 'ok'
                    message = f"最新 ({refined_by})"
                    value = 1
                else:
                    severity = 'warning'
                    message = f"stale: {refined_by} (現在={current_hash})"
                    value = 0
            items.append({
                "severity": severity,
                "component": name,
                "message": message,
                "section": "prompt_compliance",
                "value": value,
                "threshold": 1,
            })

    # Section 9: Chain Integrity
    items.extend(audit_chain_integrity(deps, plugin_root))

    # Section 10: Cross-Layer Consistency
    if monorepo_root is None:
        monorepo_root = _detect_monorepo_root(plugin_root)
    if monorepo_root is not None:
        items.extend(audit_cross_layer_consistency(monorepo_root))

    # Section 11 & 12: Registry-based audit (auto-detect registry.yaml)
    _registry_path = plugin_root / "registry.yaml"
    if _registry_path.exists():
        try:
            import yaml as _yaml
            _registry = _yaml.safe_load(_registry_path.read_text(encoding='utf-8')) or {}
        except Exception as _e:
            items.append({
                "severity": "warning",
                "component": "registry:parse",
                "message": f"registry.yaml parse error — Section 11/12 skipped: {_e}",
                "section": "registry_integrity",
                "value": 0,
                "threshold": 1,
            })
        else:
            if isinstance(_registry, dict):
                items.extend(audit_vocabulary(_registry, plugin_root,
                                              monorepo_root=monorepo_root,
                                              scan_spec=scan_spec))
                items.extend(audit_registry(_registry, plugin_root))

    return items


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
    body = '\n'.join(lines[body_start:])
    tools = set(re.findall(r'mcp__[\w-]+__[\w-]+', body))
    # Exclude placeholder patterns (e.g., mcp__xxx__yyy)
    tools = {t for t in tools if not re.fullmatch(r'mcp__x+__y+', t)}
    return tools


def audit_report(deps: dict, plugin_root: Path, monorepo_root: Optional[Path] = None, scan_spec: bool = False) -> Tuple[int, int, int]:
    """12 セクションの TWiLL 準拠度レポートを出力

    Sections:
        1. Controller Size
        2. Inline Implementation
        3. 1C=1W (Step 0 Routing)
        4. Tools Accuracy
        5. Self-Contained
        6. Token Bloat
        7. Model Declaration
        8. Prompt Compliance
        9. Chain Integrity
       10. Cross-Layer Consistency
       11. Vocabulary Check (registry.yaml glossary forbidden words)
       12. Registry Integrity (registry.yaml schema + components rules)

    Section 11/12 は plugin_root / "registry.yaml" 存在時のみ実行（auto-detect）。

    Returns: (critical_count, warning_count, ok_count)
    """
    items = audit_collect(deps, plugin_root, monorepo_root=monorepo_root, scan_spec=scan_spec)

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
        critical_threshold = _CONTROLLER_SIZE_OVERRIDES.get(name, 200)
        if lines > critical_threshold:
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
        elif output_schema_val is not None:
            schema_str = 'Invalid'
            schema_ok = False
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

    # === Section 6: Token Bloat ===
    print("## 6. Token Bloat")
    print()
    print("| Component | Type | Tokens | Warn | Crit | Severity |")
    print("|-----------|------|--------|------|------|----------|")

    from twl.core.plugin import count_tokens as _ct
    from twl.core.types import load_token_thresholds as _ltt2
    _TT = _ltt2()

    for name, comp in sorted(all_components.items()):
        comp_type = resolve_type(comp['type'])
        if comp_type not in _TT:
            continue
        path_str = comp['path']
        if not path_str:
            continue
        path = plugin_root / path_str
        if not path.exists():
            continue
        tok = _ct(path)
        if tok == 0:
            continue
        warn_t, crit_t = _TT[comp_type]
        if tok > crit_t:
            severity = 'CRITICAL'
        elif tok > warn_t:
            severity = 'WARNING'
        else:
            severity = 'OK'
        print(f"| {name} | {comp_type} | {tok} | {warn_t} | {crit_t} | {severity} |")
    print()

    # === Section 7: Model Declaration ===
    print("## 7. Model Declaration")
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
        elif model == 'opus':
            model_str = model
            severity = 'WARNING'
        elif model not in ALLOWED_MODELS:
            model_str = model
            severity = 'INFO'
        else:
            model_str = model
            severity = 'OK'
        print(f"| {name} | {comp['type']} | {model_str} | {severity} |")
    print()

    # === Section 8: Prompt Compliance ===
    print("## 8. Prompt Compliance")
    print()
    print("| Component | Status | Severity |")
    print("|-----------|--------|----------|")

    # audit_collect の prompt_compliance 項目を表示（カウントは既に items から計算済み）
    current_hash = _compute_ref_prompt_guide_hash(plugin_root)
    for section_key in ('skills', 'commands', 'agents'):
        for name, spec in sorted(deps.get(section_key, {}).items()):
            refined_by = spec.get('refined_by')
            if refined_by is None:
                status_str = '未レビュー'
                severity = 'INFO'
            else:
                m = re.match(r'^ref-prompt-guide@([0-9a-f]{8})$', str(refined_by))
                if not m:
                    status_str = f'フォーマット不正: {refined_by}'
                    severity = 'WARNING'
                elif current_hash is None:
                    status_str = f'照合不可: {refined_by}'
                    severity = 'INFO'
                elif m.group(1) == current_hash:
                    status_str = f'最新 ({refined_by})'
                    severity = 'OK'
                else:
                    status_str = f'stale ({refined_by} → 現在={current_hash})'
                    severity = 'WARNING'
            print(f"| {name} | {status_str} | {severity} |")
    print()

    # === Section 9: Chain Integrity ===
    print("## 9. Chain Integrity")
    print()
    print("| Workflow → Target | Issue | Severity |")
    print("|-------------------|-------|----------|")
    # Note: chain_integrity items are already included in audit_collect's items
    # at the top of this function (and counted into criticals/warnings/oks).
    chain_items = [i for i in items if i['section'] == 'chain_integrity']
    has_issue = False
    for item in chain_items:
        sev = item['severity']
        if sev == 'critical':
            sev_label = 'CRITICAL'
        elif sev == 'warning':
            sev_label = 'WARNING'
        else:
            continue  # OK 行は非表示（量削減）
        has_issue = True
        print(f"| {item['component']} | {item['message']} | {sev_label} |")
    if not has_issue:
        ok_count_s9 = sum(1 for i in chain_items if i['severity'] in ('ok', 'info'))
        print(f"| (all {ok_count_s9} entries) | OK | OK |")
    print()

    # === Section 10: Cross-Layer Consistency ===
    print("## 10. Cross-Layer Consistency")
    print()
    print("| Layer Pair | Issue | Severity |")
    print("|------------|-------|----------|")
    cross_items = [i for i in items if i['section'] == 'cross_layer_consistency']
    if not cross_items:
        print("| (monorepo_root not detected) | skipped | INFO |")
    else:
        has_cross_issue = False
        for item in cross_items:
            sev = item['severity']
            if sev == 'warning':
                sev_label = 'WARNING'
                has_cross_issue = True
                print(f"| {item['component']} | {item['message']} | {sev_label} |")
            elif sev == 'info':
                print(f"| {item['component']} | {item['message']} | INFO |")
        if not has_cross_issue:
            ok_count_s10 = sum(1 for i in cross_items if i['severity'] == 'ok')
            print(f"| (all {ok_count_s10} pairs) | OK | OK |")
    print()

    # === Section 11: Vocabulary Check ===
    print("## 11. Vocabulary Check")
    print()
    print("| Entity | Forbidden / Rule | Files | Severity |")
    print("|--------|------------------|-------|----------|")
    vocab_items = [i for i in items if i['section'] == 'vocabulary_check']
    if not vocab_items:
        print("| (registry.yaml not found) | Section 11 skipped | - | INFO |")
    else:
        has_vocab_issue = False
        for item in vocab_items:
            sev = item['severity']
            if sev == 'warning':
                has_vocab_issue = True
                entity = item['component'].split(':', 1)[-1] if ':' in item['component'] else item['component']
                print(f"| {entity} | {item['message']} | {item['value']} | WARNING |")
            elif sev == 'info':
                entity = item['component'].split(':', 1)[-1] if ':' in item['component'] else item['component']
                print(f"| {entity} | {item['message']} | - | INFO |")
        if not has_vocab_issue:
            print(f"| (no forbidden word violations) | - | - | OK |")
    print()

    # === Section 12: Registry Integrity ===
    print("## 12. Registry Integrity")
    print()
    print("| Component / Rule | Issue | Severity |")
    print("|------------------|-------|----------|")
    reg_items = [i for i in items if i['section'] == 'registry_integrity']
    if not reg_items:
        print("| (registry.yaml not found) | Section 12 skipped | INFO |")
    else:
        has_reg_issue = False
        for item in reg_items:
            sev = item['severity']
            if sev == 'critical':
                has_reg_issue = True
                print(f"| {item['component']} | {item['message']} | CRITICAL |")
            elif sev == 'warning':
                has_reg_issue = True
                print(f"| {item['component']} | {item['message']} | WARNING |")
            elif sev == 'info':
                print(f"| {item['component']} | {item['message']} | INFO |")
        if not has_reg_issue:
            ok_count_s12 = sum(1 for i in reg_items if i['severity'] == 'ok')
            print(f"| (all {ok_count_s12} checks) | OK | OK |")
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
