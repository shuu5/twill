import re
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.types import resolve_type, ALLOWED_MODELS, _is_within_root
from twl.core.plugin import count_tokens
from twl.validation.utils import _count_body_lines
from twl.validation.audit import (
    _parse_frontmatter_tools, _scan_body_for_mcp_tools,
    _check_output_schema_keywords
)

# Token bloat thresholds per type (warning, critical)
TOKEN_THRESHOLDS: Dict[str, Tuple[int, int]] = {
    'controller': (1500, 2500),
    'workflow': (1200, 2000),
    'atomic': (1500, 2500),
    'composite': (1500, 2500),
    'specialist': (1800, 2500),
}
# reference and script types are intentionally excluded


def deep_validate(deps: dict, plugin_root: Path) -> Tuple[List[str], List[str], List[str]]:
    """深層検証: controller bloat, ref配置, tools整合性

    Returns: (criticals, warnings, infos)
    """
    criticals_set: Set[str] = set()
    warnings_set: Set[str] = set()
    infos_set: Set[str] = set()

    criticals: List[str] = []
    warnings: List[str] = []
    infos: List[str] = []

    def add_critical(msg: str):
        if msg not in criticals_set:
            criticals_set.add(msg)
            criticals.append(msg)

    def add_warning(msg: str):
        if msg not in warnings_set:
            warnings_set.add(msg)
            warnings.append(msg)

    def add_info(msg: str):
        if msg not in infos_set:
            infos_set.add(msg)
            infos.append(msg)

    COMMON_TOOLS = {'Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Task',
                    'SendMessage', 'AskUserQuestion', 'WebSearch', 'WebFetch',
                    'Agent', 'Skill'}

    # (A) Controller 行数チェック
    for name, spec in deps.get('skills', {}).items():
        comp_type = spec.get('type', '')
        if comp_type == 'controller':
            path_str = spec.get('path', '')
            if not path_str:
                continue
            path = plugin_root / path_str
            if not _is_within_root(path, plugin_root):
                continue
            body_lines = _count_body_lines(path)
            if body_lines > 200:
                add_critical(f"[controller-bloat] {name}: {body_lines} lines (>200)")
            elif body_lines > 120:
                add_warning(f"[controller-bloat] {name}: {body_lines} lines (>120)")

    # (A2) Token bloat チェック（全型対応）
    for section in ('skills', 'commands', 'agents'):
        for name, spec in deps.get(section, {}).items():
            comp_type = resolve_type(spec.get('type', ''))
            if comp_type not in TOKEN_THRESHOLDS:
                continue
            path_str = spec.get('path', '')
            if not path_str:
                continue
            path = plugin_root / path_str
            if not _is_within_root(path, plugin_root):
                continue
            if not path.exists():
                continue
            tok = count_tokens(path)
            if tok == 0:
                continue
            warn_threshold, crit_threshold = TOKEN_THRESHOLDS[comp_type]
            if tok > crit_threshold:
                add_critical(f"[token-bloat] {name} ({comp_type}): {tok} tok (>{crit_threshold})")
            elif tok > warn_threshold:
                add_warning(f"[token-bloat] {name} ({comp_type}): {tok} tok (>{warn_threshold})")

    # (B) Reference 配置監査
    # 全コンポーネントの calls から reference と downstream を収集
    all_components = {}
    for section in ('skills', 'commands', 'agents'):
        for cname, cdata in deps.get(section, {}).items():
            all_components[cname] = (section, cdata)

    for parent_name, (parent_section, parent_spec) in all_components.items():
        refs_in_calls = []
        downstreams_in_calls = []
        for call in parent_spec.get('calls', []):
            for call_key, callee_name in call.items():
                callee_data = all_components.get(callee_name, (None, {}))
                callee_type = callee_data[1].get('type', '') if callee_data[0] else ''
                resolved_callee = resolve_type(callee_type)
                if call_key == 'reference' or resolved_callee == 'reference':
                    refs_in_calls.append(callee_name)
                elif resolved_callee in ('atomic', 'composite', 'specialist'):
                    downstreams_in_calls.append(callee_name)

        # 各 downstream の body を読んで、ref 名が出現するか確認
        for ds_name in downstreams_in_calls:
            ds_data = all_components.get(ds_name, (None, {}))
            if not ds_data[0]:
                continue
            ds_path_str = ds_data[1].get('path', '')
            if not ds_path_str:
                continue
            ds_path = plugin_root / ds_path_str
            if not _is_within_root(ds_path, plugin_root):
                continue
            if not ds_path.exists():
                continue
            try:
                ds_body = ds_path.read_text(encoding='utf-8')
            except Exception:
                continue
            ds_calls_refs = set()
            for call in ds_data[1].get('calls', []):
                for ck, cv in call.items():
                    if ck == 'reference':
                        ds_calls_refs.add(cv)
            for ref_name in refs_in_calls:
                if ref_name in ds_body and ref_name not in ds_calls_refs:
                    add_warning(
                        f"[ref-placement] {ds_name} body references {ref_name} but doesn't declare it in calls"
                    )

    # (C) Frontmatter-Body ツール整合性
    for section in ('commands', 'agents'):
        for cname, cdata in deps.get(section, {}).items():
            path_str = cdata.get('path', '')
            if not path_str:
                continue
            path = plugin_root / path_str
            if not _is_within_root(path, plugin_root):
                continue
            declared = _parse_frontmatter_tools(path)
            used_mcp = _scan_body_for_mcp_tools(path)
            for tool in used_mcp - declared:
                add_warning(f"[tools-mismatch] {cname}: body uses {tool} but not declared in frontmatter")
            for tool in declared - used_mcp - COMMON_TOOLS:
                add_info(f"[tools-unused] {cname}: frontmatter declares {tool} but not used in body")

    # (D) Model Declaration: specialist の model フィールド検証
    for section in ('skills', 'commands', 'agents'):
        for cname, cdata in deps.get(section, {}).items():
            comp_type = cdata.get('type', '')
            if resolve_type(comp_type) != 'specialist':
                continue
            model = cdata.get('model')
            if model is None:
                add_warning(f"[model-required] {cname}: specialist で model 未宣言")
            elif model == 'opus':
                add_warning(f"[model-required] {cname}: specialist に opus は推奨されません")
            elif model not in ALLOWED_MODELS:
                add_info(f"[model-required] {cname}: model '{model}' は許可リストにありません")

    # (E) Specialist 出力スキーマ検証
    for section in ('skills', 'commands', 'agents'):
        for cname, cdata in deps.get(section, {}).items():
            resolved = resolve_type(cdata.get('type', ''))
            if resolved != 'specialist':
                continue

            output_schema = cdata.get('output_schema', None)
            if output_schema == 'custom':
                continue
            if output_schema is not None:
                if output_schema == '':
                    add_warning(f"[specialist-output-schema] {cname}: empty output_schema value (expected 'custom' or omit)")
                else:
                    add_warning(f"[specialist-output-schema] {cname}: invalid output_schema value '{output_schema}' (expected 'custom' or omit)")
                continue

            path_str = cdata.get('path', '')
            if not path_str:
                continue
            path = plugin_root / path_str
            if not _is_within_root(path, plugin_root):
                continue
            if not path.exists():
                continue

            schema_kw = _check_output_schema_keywords(path)
            missing = [cat for cat, present in schema_kw.items() if not present]
            if missing:
                add_warning(f"[specialist-output-schema] {cname}: missing output schema keywords: {', '.join(missing)}")

    # (F) 非ポータブル scripts/ パス検出
    # skills/*/SKILL.md と commands/*.md をファイルシステム glob で走査
    _NON_PORTABLE_PATTERNS = [
        re.compile(r'bash\s+scripts/'),
        re.compile(r'\$SCRIPTS_ROOT'),
    ]
    _SOURCE_SCRIPTS_PATTERN = re.compile(r'source\s+.*scripts/')

    def _check_non_portable_paths(md_path: Path) -> List[str]:
        violations: List[str] = []
        try:
            content = md_path.read_text(encoding='utf-8')
        except Exception:
            return violations
        for lineno, line in enumerate(content.splitlines(), start=1):
            if 'CLAUDE_PLUGIN_ROOT' in line:
                continue
            for pat in _NON_PORTABLE_PATTERNS:
                if pat.search(line):
                    violations.append(f"  line {lineno}: {line.strip()}")
                    break
            else:
                if _SOURCE_SCRIPTS_PATTERN.search(line):
                    violations.append(f"  line {lineno}: {line.strip()}")
        return violations

    for skill_md in plugin_root.glob('skills/*/SKILL.md'):
        if not _is_within_root(skill_md, plugin_root):
            continue
        violations = _check_non_portable_paths(skill_md)
        rel = skill_md.relative_to(plugin_root)
        for v in violations:
            add_critical(
                f"[non-portable-path] {rel}: non-portable script path: "
                f"use ${{CLAUDE_PLUGIN_ROOT}}/scripts/ instead of relative scripts/\n{v}"
            )

    for cmd_md in plugin_root.glob('commands/*.md'):
        if not _is_within_root(cmd_md, plugin_root):
            continue
        violations = _check_non_portable_paths(cmd_md)
        rel = cmd_md.relative_to(plugin_root)
        for v in violations:
            add_critical(
                f"[non-portable-path] {rel}: non-portable script path: "
                f"use ${{CLAUDE_PLUGIN_ROOT}}/scripts/ instead of relative scripts/\n{v}"
            )

    return criticals, warnings, infos
