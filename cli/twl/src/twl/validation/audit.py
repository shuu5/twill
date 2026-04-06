import hashlib
import re
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


def audit_collect(deps: dict, plugin_root: Path) -> List[dict]:
    """7セクションの TWiLL 準拠度データを収集（print なし）

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
        if lines > 200:
            severity = 'critical'
        elif lines > 120:
            severity = 'warning'
        else:
            severity = 'ok'
        items.append({
            "severity": severity,
            "component": name,
            "message": f"Controller size {lines} lines" + (f" (threshold: {200 if lines > 200 else 120})" if severity != 'ok' else ""),
            "section": "controller_size",
            "value": lines,
            "threshold": 200 if lines > 200 else 120,
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

    # Section 7: Prompt Compliance
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
                    severity = 'warning'
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


def audit_report(deps: dict, plugin_root: Path) -> Tuple[int, int, int]:
    """8セクションの TWiLL 準拠度レポートを出力

    Returns: (critical_count, warning_count, ok_count)
    """
    items = audit_collect(deps, plugin_root)

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
        if lines > 200:
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
            warnings += 1
        elif model == 'opus':
            model_str = model
            severity = 'WARNING'
            warnings += 1
        elif model not in ALLOWED_MODELS:
            model_str = model
            severity = 'INFO'
            oks += 1
        else:
            model_str = model
            severity = 'OK'
            oks += 1
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

    # === Summary ===
    print("## Summary")
    print()
    print("| Severity | Count |")
    print("|----------|-------|")
    print(f"| CRITICAL | {criticals} |")
    print(f"| WARNING  | {warnings} |")
    print(f"| OK       | {oks} |")

    return criticals, warnings, oks
