import re
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.types import TYPE_RULES, load_type_rules, resolve_type
from twl.core.plugin import get_plugin_name, get_deps_version, parse_cross_plugin_ref, get_cross_plugin_component
from twl.refactor.promote import _is_within_root
from twl.validation.utils import _get_body_text


def validate_types(deps: dict, graph: Dict, plugin_root: Optional[Path] = None) -> Tuple[int, List[str], List[str]]:
    """型ルール（can_spawn/spawnable_by）の整合性を検証

    5つのチェック:
    1. セクション配置: controller は skills に、atomic は commands に等
    2. can_spawn 宣言: 宣言値が TYPE_RULES の許可範囲内か
    3. spawnable_by 宣言: 宣言値が TYPE_RULES の許可範囲内か
    4. 呼び出しエッジ: 各 calls が caller の can_spawn と callee の spawnable_by を満たすか

    Returns: (ok_count, violations_list)
    """
    ok_count = 0
    violations = []

    # セクション → コンポーネント型のマッピング
    section_map = {'skills': 'skill', 'commands': 'command', 'agents': 'agent', 'scripts': 'script', 'refs': 'skill'}

    for section in ('skills', 'commands', 'agents', 'scripts', 'refs'):
        for name, data in deps.get(section, {}).items():
            comp_type = data.get('type')
            if not comp_type:
                continue

            resolved = resolve_type(comp_type)
            rule = TYPE_RULES.get(resolved)
            if not rule:
                violations.append(f"[unknown-type] {section}/{name}: type '{comp_type}' is not defined in TYPE_RULES")
                continue

            # Check 1: セクション配置（refs セクションは skills の特殊形態として許可）
            expected_section = rule['section']
            actual_section = section
            if actual_section == 'refs' and expected_section == 'skills':
                ok_count += 1  # refs セクションの reference は valid
            elif expected_section != actual_section:
                violations.append(
                    f"[section] {section}/{name}: type '{comp_type}' should be in '{expected_section}', not '{actual_section}'"
                )
            else:
                ok_count += 1

            # Check 2: can_spawn 宣言値
            declared_can_spawn = set(data.get('can_spawn', []))
            allowed_can_spawn = rule['can_spawn']
            invalid_spawn = {resolve_type(s) for s in declared_can_spawn} - allowed_can_spawn
            if invalid_spawn:
                violations.append(
                    f"[can_spawn] {section}/{name}: declares can_spawn={sorted(invalid_spawn)} but type '{comp_type}' only allows {sorted(allowed_can_spawn)}"
                )
            else:
                ok_count += 1

            # Check 3: spawnable_by 宣言値
            declared_spawnable = set(data.get('spawnable_by', []))
            allowed_spawnable = rule['spawnable_by']
            invalid_spawnable = {resolve_type(s) for s in declared_spawnable} - {resolve_type(a) for a in allowed_spawnable}
            if invalid_spawnable:
                violations.append(
                    f"[spawnable_by] {section}/{name}: declares spawnable_by={sorted(invalid_spawnable)} but type '{comp_type}' only allows {sorted(allowed_spawnable)}"
                )
            else:
                ok_count += 1

            # Check 3b: can_supervise 宣言値（can_supervise フィールドを持つ型のみ）
            allowed_supervise = rule.get('can_supervise', set())
            declared_supervise = set(data.get('can_supervise', []))
            if declared_supervise:
                invalid_supervise = {resolve_type(s) for s in declared_supervise} - {resolve_type(a) for a in allowed_supervise}
                if invalid_supervise:
                    violations.append(
                        f"[can_supervise] {section}/{name}: declares can_supervise={sorted(invalid_supervise)} but type '{comp_type}' only allows {sorted(allowed_supervise)}"
                    )
                else:
                    ok_count += 1

    # Check 4: 呼び出しエッジの型整合性
    # 各 calls エントリについて、caller の can_spawn に callee の型が含まれるか、
    # callee の spawnable_by に caller の型が含まれるかを確認
    call_key_to_section = {
        # v2.0 section-name keys
        'command': 'commands', 'skill': 'skills', 'agent': 'agents',
        # v3.0 type-name keys
        'atomic': 'commands', 'composite': 'commands',
        'controller': 'skills', 'workflow': 'skills', 'reference': 'skills',
        'supervisor': 'skills',
        'specialist': 'agents',
        # Agent Teams 固有の calls キー
        'phase': 'commands', 'worker': 'agents',
        # script 型
        'script': 'scripts',
    }

    for section in ('skills', 'commands', 'agents', 'scripts', 'refs'):
        for name, data in deps.get(section, {}).items():
            caller_type = resolve_type(data.get('type', ''))
            caller_rule = TYPE_RULES.get(caller_type)
            if not caller_rule:
                continue

            for call in data.get('calls', []):
                for call_key, callee_name in call.items():
                    target_section = call_key_to_section.get(call_key)
                    if not target_section:
                        continue

                    # callee をターゲットセクションから探索。reference は refs セクションにもある
                    callee_data = deps.get(target_section, {}).get(callee_name, {})
                    if not callee_data and target_section == 'skills':
                        callee_data = deps.get('refs', {}).get(callee_name, {})
                    callee_type = resolve_type(callee_data.get('type', ''))
                    callee_rule = TYPE_RULES.get(callee_type)
                    if not callee_rule:
                        continue

                    # caller の can_spawn に callee の型が含まれるか
                    if callee_type not in caller_rule['can_spawn']:
                        violations.append(
                            f"[edge] {section}/{name} ({caller_type}) -> {target_section}/{callee_name} ({callee_type}): "
                            f"'{caller_type}' cannot spawn '{callee_type}' (allowed: {sorted(caller_rule['can_spawn'])})"
                        )
                    else:
                        ok_count += 1

                    # callee の spawnable_by に caller の型が含まれるか
                    callee_spawnable = {resolve_type(s) for s in callee_rule['spawnable_by']}
                    if caller_type not in callee_spawnable:
                        violations.append(
                            f"[edge] {section}/{name} ({caller_type}) -> {target_section}/{callee_name} ({callee_type}): "
                            f"'{callee_type}' is not spawnable_by '{caller_type}' (allowed: {sorted(callee_rule['spawnable_by'])})"
                        )
                    else:
                        ok_count += 1

    # Check 5: cross-plugin 参照エッジの型整合性
    warnings = []
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for name, data in deps.get(section, {}).items():
            caller_type = resolve_type(data.get('type', ''))
            caller_rule = TYPE_RULES.get(caller_type)
            if not caller_rule:
                continue

            for call in data.get('calls', []):
                for call_key, callee_value in call.items():
                    if call_key in ('step', 'plugin') or not isinstance(callee_value, str):
                        continue
                    xref = parse_cross_plugin_ref(callee_value)
                    if not xref:
                        continue

                    target_plugin, target_comp = xref
                    comp_info = get_cross_plugin_component(target_plugin, target_comp, plugin_root)
                    if comp_info is None:
                        # 参照先 plugin が見つからない → warning
                        warnings.append(
                            f"[xref-unresolved] {section}/{name}: cross-plugin ref '{callee_value}' "
                            f"could not be resolved (plugin '{target_plugin}' not found)"
                        )
                        continue

                    _target_section, comp_data, _target_root = comp_info
                    callee_type = resolve_type(comp_data.get('type', ''))
                    callee_rule = TYPE_RULES.get(callee_type)
                    if not callee_rule:
                        continue

                    # caller の can_spawn に callee の型が含まれるか
                    if callee_type not in caller_rule['can_spawn']:
                        violations.append(
                            f"[edge] {section}/{name} ({caller_type}) -> xref:{callee_value} ({callee_type}): "
                            f"'{caller_type}' cannot spawn '{callee_type}' (allowed: {sorted(caller_rule['can_spawn'])})"
                        )
                    else:
                        ok_count += 1

                    # callee の spawnable_by に caller の型が含まれるか
                    callee_spawnable = {resolve_type(s) for s in callee_rule['spawnable_by']}
                    if caller_type not in callee_spawnable:
                        violations.append(
                            f"[edge] {section}/{name} ({caller_type}) -> xref:{callee_value} ({callee_type}): "
                            f"'{callee_type}' is not spawnable_by '{caller_type}' (allowed: {sorted(callee_rule['spawnable_by'])})"
                        )
                    else:
                        ok_count += 1

    return ok_count, violations, warnings


def validate_body_refs(deps: dict, plugin_root: Path) -> Tuple[int, List[str]]:
    """body 内の /{plugin}:{name} 参照が deps.yaml に存在するか検証

    Returns: (ok_count, violations_list)
    """
    ok_count = 0
    violations = []

    plugin_name = get_plugin_name(deps, plugin_root)

    # deps.yaml の全コンポーネント名集合を構築
    all_names: Set[str] = set()
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for name in deps.get(section, {}).keys():
            all_names.add(name)

    # 参照パターン: /{plugin}:{name} or /{plugin}:[\w-]+
    ref_pattern = re.compile(r'/(' + re.escape(plugin_name) + r'):([\w-]+)')

    # 全 .md ファイルの body をスキャン
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            path = data.get('path')
            if not path:
                continue
            file_path = plugin_root / path
            if not _is_within_root(file_path, plugin_root):
                continue
            body = _get_body_text(file_path)
            if not body:
                continue

            matches = ref_pattern.findall(body)
            seen = set()
            for _plugin, ref_name in matches:
                if ref_name in seen:
                    continue
                seen.add(ref_name)
                if ref_name in all_names:
                    ok_count += 1
                else:
                    violations.append(
                        f"[body-ref] {section}/{comp_name}: reference '/{plugin_name}:{ref_name}' not found in deps.yaml"
                    )

    return ok_count, violations


def validate_v3_schema(deps: dict) -> Tuple[int, List[str]]:
    """v3.0 スキーマ固有の構文検証

    v2.0 では呼ばれない。v3.0 時のみ以下を検証:
    1. calls キーが型名（atomic/composite/workflow/controller/specialist/reference）であること
    2. step フィールドが文字列であること
    3. step_in 構造が {parent: str} であること
    4. chain フィールド値が chains セクションに存在すること
    5. chains セクションの steps 内コンポーネントが存在すること

    Returns: (ok_count, violations_list)
    """
    ok_count = 0
    violations = []

    version = get_deps_version(deps)
    if not version.startswith('3'):
        return ok_count, violations

    # 許可される v3.0 型名キー
    v3_type_keys = {'atomic', 'composite', 'workflow', 'controller', 'supervisor', 'specialist', 'reference', 'script'}
    valid_dispatch_modes = {'llm', 'runner', 'trigger'}

    # Check: dispatch_mode フィールド (任意) の値検証
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for comp_name, data in deps.get(section, {}).items():
            if not isinstance(data, dict):
                continue
            mode = data.get('dispatch_mode')
            if mode is None:
                continue
            if not isinstance(mode, str) or mode not in valid_dispatch_modes:
                violations.append(
                    f"[v3-dispatch-mode] {section}/{comp_name}: "
                    f"dispatch_mode must be one of {sorted(valid_dispatch_modes)}, got {mode!r}"
                )
            else:
                ok_count += 1

    # v2.0 セクション名キー（v3.0 では非推奨）
    v2_section_keys = {'command', 'skill', 'agent'}

    # 全コンポーネント名集合
    all_components: Set[str] = set()
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for name in deps.get(section, {}).keys():
            all_components.add(name)

    chains = deps.get('chains', {})

    # Check 1: calls キーが型名であること
    for section in ('skills', 'commands', 'agents', 'scripts'):
        for comp_name, data in deps.get(section, {}).items():
            for i, call in enumerate(data.get('calls', [])):
                call_keys = [k for k in call.keys() if k not in ('step', 'plugin')]
                for key in call_keys:
                    if key in v2_section_keys:
                        violations.append(
                            f"[v3-calls-key] {section}/{comp_name}/calls[{i}]: "
                            f"section-name key '{key}' is not allowed in v3.0, use type-name key "
                            f"(atomic/composite/workflow/controller/specialist/reference)"
                        )
                    elif key not in v3_type_keys:
                        violations.append(
                            f"[v3-calls-key] {section}/{comp_name}/calls[{i}]: "
                            f"unknown key '{key}'"
                        )
                    else:
                        ok_count += 1

                # Check 2: step フィールドが文字列であること
                step = call.get('step')
                if step is not None:
                    if not isinstance(step, str):
                        violations.append(
                            f"[v3-step-type] {section}/{comp_name}/calls[{i}]: "
                            f"step must be a string, got {type(step).__name__}"
                        )
                    else:
                        ok_count += 1

            # Check 3: step_in 構造
            step_in = data.get('step_in')
            if step_in is not None:
                if not isinstance(step_in, dict):
                    violations.append(
                        f"[v3-step_in-type] {section}/{comp_name}: "
                        f"step_in must be a dict, got {type(step_in).__name__}"
                    )
                elif 'parent' not in step_in:
                    violations.append(
                        f"[v3-step_in-parent] {section}/{comp_name}: "
                        f"step_in must have 'parent' key"
                    )
                elif not isinstance(step_in['parent'], str):
                    violations.append(
                        f"[v3-step_in-parent] {section}/{comp_name}: "
                        f"step_in.parent must be a string"
                    )
                else:
                    if step_in['parent'] not in all_components:
                        violations.append(
                            f"[v3-step_in-ref] {section}/{comp_name}: "
                            f"step_in.parent '{step_in['parent']}' not found in deps.yaml"
                        )
                    else:
                        ok_count += 1

            # Check 4: chain フィールド値が chains セクションに存在すること
            chain = data.get('chain')
            if chain is not None:
                if not isinstance(chain, str):
                    violations.append(
                        f"[v3-chain-type] {section}/{comp_name}: "
                        f"chain must be a string, got {type(chain).__name__}"
                    )
                elif chain not in chains:
                    violations.append(
                        f"[v3-chain-ref] {section}/{comp_name}: "
                        f"chain '{chain}' not found in chains section"
                    )
                else:
                    ok_count += 1

    # Check 5: chains セクションの構造と steps 内コンポーネント存在確認
    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            violations.append(
                f"[v3-chains-type] chains/{chain_name}: must be a dict"
            )
            continue

        steps = chain_data.get('steps', [])
        if not isinstance(steps, list):
            violations.append(
                f"[v3-chains-steps] chains/{chain_name}: steps must be a list"
            )
            continue

        for i, step_entry in enumerate(steps):
            if isinstance(step_entry, str):
                if step_entry not in all_components:
                    violations.append(
                        f"[v3-chains-ref] chains/{chain_name}/steps[{i}]: "
                        f"component '{step_entry}' not found in deps.yaml"
                    )
                else:
                    ok_count += 1
            else:
                violations.append(
                    f"[v3-chains-step-type] chains/{chain_name}/steps[{i}]: "
                    f"step entry must be a string, got {type(step_entry).__name__}"
                )

    # Check 6: 旧形式 scripts フィールド WARNING
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            legacy_scripts = data.get('scripts')
            if legacy_scripts is not None and isinstance(legacy_scripts, list):
                violations.append(
                    f"[v3-legacy-scripts] {section}/{comp_name}: "
                    f"component-level 'scripts' field is deprecated in v3.0, "
                    f"use top-level 'scripts' section with 'calls' references instead"
                )

    # Check 6b: meta_chains セクション構造検証
    meta_chains = deps.get('meta_chains', {})
    if meta_chains and isinstance(meta_chains, dict):
        for meta_name, meta_data in meta_chains.items():
            if not isinstance(meta_data, dict):
                violations.append(
                    f"[v3-meta-chains-type] meta_chains/{meta_name}: must be a dict"
                )
                continue

            # type: "meta" 必須
            mc_type = meta_data.get('type')
            if mc_type != 'meta':
                violations.append(
                    f"[v3-meta-chains-type-field] meta_chains/{meta_name}: "
                    f"type must be 'meta', got {mc_type!r}"
                )
            else:
                ok_count += 1

            # flow は list であること
            flow = meta_data.get('flow')
            if flow is None:
                violations.append(
                    f"[v3-meta-chains-flow] meta_chains/{meta_name}: "
                    f"flow field is required"
                )
                continue
            if not isinstance(flow, list):
                violations.append(
                    f"[v3-meta-chains-flow] meta_chains/{meta_name}: "
                    f"flow must be a list"
                )
                continue

            # flow ノードの id 収集（goto 解決に使用）
            flow_ids: Set[str] = set()
            for node in flow:
                if isinstance(node, dict) and isinstance(node.get('id'), str):
                    flow_ids.add(node['id'])

            for i, node in enumerate(flow):
                if not isinstance(node, dict):
                    violations.append(
                        f"[v3-meta-chains-node] meta_chains/{meta_name}/flow[{i}]: "
                        f"node must be a dict"
                    )
                    continue

                # id は必須
                node_id = node.get('id')
                if not isinstance(node_id, str) or not node_id:
                    violations.append(
                        f"[v3-meta-chains-node-id] meta_chains/{meta_name}/flow[{i}]: "
                        f"node must have a string 'id'"
                    )

                # chain フィールド: 存在する場合は chains セクションに存在するか null
                node_chain = node.get('chain')
                if 'chain' in node and node_chain is not None:
                    if not isinstance(node_chain, str):
                        violations.append(
                            f"[v3-meta-chains-chain-ref] meta_chains/{meta_name}/flow[{i}]: "
                            f"chain must be a string or null"
                        )
                    elif node_chain not in chains:
                        violations.append(
                            f"[v3-meta-chains-chain-ref] meta_chains/{meta_name}/flow[{i}]: "
                            f"chain '{node_chain}' not found in chains section"
                        )
                    else:
                        ok_count += 1

                # next の goto 参照整合性
                next_entries = node.get('next', [])
                if next_entries and isinstance(next_entries, list):
                    for j, entry in enumerate(next_entries):
                        if not isinstance(entry, dict):
                            continue
                        goto = entry.get('goto')
                        if goto is not None and isinstance(goto, str) and goto not in flow_ids:
                            violations.append(
                                f"[v3-meta-chains-goto] meta_chains/{meta_name}/flow[{i}]/next[{j}]: "
                                f"goto '{goto}' not found in flow ids"
                            )
                        elif goto is not None and isinstance(goto, str) and goto in flow_ids:
                            ok_count += 1

    # Check 7: refined_by / refined_at フォーマット検証
    _REFINED_BY_PATTERN = re.compile(r'^ref-prompt-guide@[0-9a-f]{8}$')
    _REFINED_AT_PATTERN = re.compile(r'^\d{4}-\d{2}-\d{2}$')
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            refined_by = data.get('refined_by')
            if refined_by is not None:
                if not _REFINED_BY_PATTERN.match(str(refined_by)):
                    violations.append(
                        f"[refined_by-format] {section}/{comp_name}: "
                        f"refined_by must match 'ref-prompt-guide@[0-9a-f]{{8}}', got: {refined_by!r}"
                    )
                else:
                    ok_count += 1
            refined_at = data.get('refined_at')
            if refined_at is not None:
                if not _REFINED_AT_PATTERN.match(str(refined_at)):
                    violations.append(
                        f"[refined_at-format] {section}/{comp_name}: "
                        f"refined_at must be ISO 8601 date (YYYY-MM-DD), got: {refined_at!r}"
                    )
                else:
                    ok_count += 1

    return ok_count, violations
