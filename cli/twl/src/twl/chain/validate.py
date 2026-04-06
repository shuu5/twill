import re
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.types import resolve_type
from twl.core.plugin import get_deps_version
from twl.validation.utils import _get_body_text


def chain_validate(deps: dict, plugin_root: Path) -> Tuple[List[str], List[str], List[str]]:
    """Chain/Step 双方向整合性検証

    v3.0 deps.yaml のみ対象。以下を検証:
    1. chain-bidirectional: chains.steps ⟺ component.chain の双方向一致
    2. step-bidirectional: parent.calls[].step ⟺ child.step_in の双方向一致
    3. chain-type-guard: Chain 種別ごとの参加者型制約
    4. step-ordering: calls 内 step 番号の昇順
    5. prompt-consistency: body 内の chain/step 参照と deps.yaml の整合性

    Returns: (criticals, warnings, infos)
    """
    criticals: List[str] = []
    warnings: List[str] = []
    infos: List[str] = []
    ok_count = 0

    version = get_deps_version(deps)
    if not version.startswith('3'):
        return criticals, warnings, infos

    chains = deps.get('chains', {})

    # 全コンポーネントの名前→(section, data) マップ
    all_components: Dict[str, Tuple[str, dict]] = {}
    for section in ('skills', 'commands', 'agents'):
        for comp_name, data in deps.get(section, {}).items():
            all_components[comp_name] = (section, data)

    # --- 1. chain-bidirectional ---
    # 1a. 順方向: chains.steps の各コンポーネントが component.chain を持つか
    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            continue
        steps = chain_data.get('steps', [])
        if not isinstance(steps, list):
            continue
        for step_entry in steps:
            if not isinstance(step_entry, str):
                continue
            comp = all_components.get(step_entry)
            if comp is None:
                # コンポーネント自体が存在しない（validate_v3_schema で検出済み）
                continue
            comp_chain = comp[1].get('chain')
            if comp_chain is None:
                criticals.append(
                    f"[chain-bidir] {step_entry}: "
                    f"listed in chains/{chain_name}/steps but has no chain field"
                )
            elif comp_chain != chain_name:
                criticals.append(
                    f"[chain-bidir] {step_entry}: "
                    f"listed in chains/{chain_name}/steps but chain='{comp_chain}'"
                )
            else:
                ok_count += 1

    # 1b. 逆方向: component.chain を持つコンポーネントが chains.steps に含まれるか
    for comp_name, (section, data) in all_components.items():
        chain = data.get('chain')
        if chain is None:
            continue
        if not isinstance(chain, str):
            continue
        chain_data = chains.get(chain)
        if chain_data is None:
            # chain 自体が不在（validate_v3_schema で検出済み）
            continue
        steps = chain_data.get('steps', [])
        if not isinstance(steps, list):
            continue
        if comp_name not in steps:
            criticals.append(
                f"[chain-bidir] {comp_name}: "
                f"chain='{chain}' but not listed in chains/{chain}/steps"
            )
        else:
            ok_count += 1

    # --- 2. step-bidirectional ---
    # 2a. 順方向: parent.calls[].step を持つ呼び出しに対し、child が step_in を持つか
    for comp_name, (section, data) in all_components.items():
        for call in data.get('calls', []):
            step = call.get('step')
            if step is None:
                continue
            # call のターゲット名を取得
            callee_name = None
            for key, val in call.items():
                if key != 'step' and isinstance(val, str):
                    callee_name = val
                    break
            if callee_name is None:
                continue
            callee = all_components.get(callee_name)
            if callee is None:
                continue
            callee_step_in = callee[1].get('step_in')
            if callee_step_in is None:
                criticals.append(
                    f"[step-bidir] {callee_name}: "
                    f"called with step='{step}' from {comp_name} but has no step_in"
                )
            elif not isinstance(callee_step_in, dict):
                continue  # 型エラーは validate_v3_schema で検出
            elif callee_step_in.get('parent') != comp_name:
                criticals.append(
                    f"[step-bidir] {callee_name}: "
                    f"called with step='{step}' from {comp_name} "
                    f"but step_in.parent='{callee_step_in.get('parent')}'"
                )
            else:
                ok_count += 1

    # 2b. 逆方向: child.step_in.parent を持つコンポーネントに対し、parent の calls に step があるか
    for comp_name, (section, data) in all_components.items():
        step_in = data.get('step_in')
        if step_in is None or not isinstance(step_in, dict):
            continue
        parent_name = step_in.get('parent')
        if parent_name is None or not isinstance(parent_name, str):
            continue
        parent = all_components.get(parent_name)
        if parent is None:
            continue  # 不在は validate_v3_schema で検出
        # parent の calls から comp_name への step 指定を探す
        found_step_call = False
        for call in parent[1].get('calls', []):
            if call.get('step') is None:
                continue
            callee_name = None
            for key, val in call.items():
                if key != 'step' and isinstance(val, str):
                    callee_name = val
                    break
            if callee_name == comp_name:
                found_step_call = True
                break
        if not found_step_call:
            criticals.append(
                f"[step-bidir] {comp_name}: "
                f"step_in.parent='{parent_name}' but {parent_name} has no step call to {comp_name}"
            )
        else:
            ok_count += 1

    # --- 3. chain-type-guard ---
    CHAIN_TYPE_ALLOWED = {
        'A': {'workflow', 'atomic'},
        'B': {'atomic', 'composite'},
    }
    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            continue
        chain_type = chain_data.get('type')
        if chain_type is None:
            continue  # type フィールドなし → スキップ
        allowed = CHAIN_TYPE_ALLOWED.get(chain_type)
        if allowed is None:
            warnings.append(
                f"[chain-type] chains/{chain_name}: unknown chain type '{chain_type}'"
            )
            continue
        steps = chain_data.get('steps', [])
        if not isinstance(steps, list):
            continue
        for step_entry in steps:
            if not isinstance(step_entry, str):
                continue
            comp = all_components.get(step_entry)
            if comp is None:
                continue
            comp_type = resolve_type(comp[1].get('type', ''))
            if comp_type not in allowed:
                allowed_str = ', '.join(sorted(allowed))
                warnings.append(
                    f"[chain-type] chains/{chain_name}: "
                    f"{comp_type} '{step_entry}' not allowed in Chain {chain_type} "
                    f"(allowed: {allowed_str})"
                )
            else:
                ok_count += 1

    # --- 4. step-ordering ---
    for comp_name, (section, data) in all_components.items():
        calls = data.get('calls', [])
        step_values: List[Tuple[str, float]] = []
        for call in calls:
            step = call.get('step')
            if step is None:
                continue
            try:
                step_num = float(step)
            except (ValueError, TypeError):
                warnings.append(
                    f"[step-order] {comp_name}: step '{step}' is not a valid number"
                )
                continue
            step_values.append((step, step_num))

        for i in range(1, len(step_values)):
            if step_values[i][1] < step_values[i - 1][1]:
                warnings.append(
                    f"[step-order] {comp_name}: "
                    f"step '{step_values[i][0]}' appears after '{step_values[i - 1][0]}' (not ascending)"
                )
            elif step_values[i][1] == step_values[i - 1][1]:
                warnings.append(
                    f"[step-order] {comp_name}: "
                    f"duplicate step '{step_values[i][0]}'"
                )
            else:
                ok_count += 1

    # --- 5. prompt-consistency ---
    # body 内の step 参照パターン（日本語対応）
    step_ref_pattern = re.compile(
        r'(\S+?)(?:\s+の)?\s*Step\s+(\S+)\s*から呼び出される',
        re.IGNORECASE
    )

    for comp_name, (section, data) in all_components.items():
        path_str = data.get('path', '')
        if not path_str:
            continue
        path = plugin_root / path_str
        body = _get_body_text(path)
        if not body:
            continue

        for match in step_ref_pattern.finditer(body):
            ref_parent = match.group(1)
            ref_step = match.group(2)
            # step_in の確認
            step_in = data.get('step_in')
            if step_in is None or not isinstance(step_in, dict):
                warnings.append(
                    f"[prompt-chain] {comp_name}: "
                    f"body mentions '{ref_parent} Step {ref_step}' but no matching step_in in deps.yaml"
                )
            elif step_in.get('parent') != ref_parent:
                warnings.append(
                    f"[prompt-chain] {comp_name}: "
                    f"body mentions '{ref_parent} Step {ref_step}' "
                    f"but step_in.parent='{step_in.get('parent')}'"
                )
            else:
                ok_count += 1

    return criticals, warnings, infos
