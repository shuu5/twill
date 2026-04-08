import ast
import re
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from twl.core.types import resolve_type
from twl.core.plugin import get_deps_version
from twl.validation.utils import _get_body_text


def _load_chain_py_steps(plugin_root: Path) -> List[str]:
    """Parse CHAIN_STEPS from cli/twl/src/twl/autopilot/chain.py via AST."""
    candidates = [
        plugin_root.parent.parent / "cli" / "twl" / "src" / "twl" / "autopilot" / "chain.py",
        plugin_root.parent / "cli" / "twl" / "src" / "twl" / "autopilot" / "chain.py",
        plugin_root / "cli" / "twl" / "src" / "twl" / "autopilot" / "chain.py",
    ]
    chain_py = None
    for c in candidates:
        if c.is_file():
            chain_py = c
            break
    if chain_py is None:
        return []
    try:
        tree = ast.parse(chain_py.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            # Handle both `CHAIN_STEPS = [...]` (Assign) and `CHAIN_STEPS: list[str] = [...]` (AnnAssign)
            name = None
            value = None
            if isinstance(node, ast.Assign) and len(node.targets) == 1:
                target = node.targets[0]
                if isinstance(target, ast.Name):
                    name = target.id
                    value = node.value
            elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
                name = node.target.id
                value = node.value
            if name == "CHAIN_STEPS" and isinstance(value, ast.List):
                return [
                    elt.value for elt in value.elts
                    if isinstance(elt, ast.Constant) and isinstance(elt.value, str)
                ]
    except Exception:
        pass
    return []


def _load_chain_runner_steps(plugin_root: Path) -> Set[str]:
    """Extract step names from chain-runner.sh case statement."""
    candidates = [
        plugin_root / "scripts" / "chain-runner.sh",
        plugin_root / "plugins" / "twl" / "scripts" / "chain-runner.sh",
    ]
    chain_runner = None
    for c in candidates:
        if c.is_file():
            chain_runner = c
            break
    if chain_runner is None:
        return set()
    steps: Set[str] = set()
    pattern = re.compile(r"^\s+([a-z][a-z0-9-]+)\)\s")
    for line in chain_runner.read_text(encoding="utf-8").splitlines():
        m = pattern.match(line)
        if m:
            steps.add(m.group(1))
    return steps


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
        'meta': None,  # meta chains have no step-level components; skip type guard
    }
    for chain_name, chain_data in chains.items():
        if not isinstance(chain_data, dict):
            continue
        chain_type = chain_data.get('type')
        if chain_type is None:
            continue  # type フィールドなし → スキップ
        if chain_type not in CHAIN_TYPE_ALLOWED:
            warnings.append(
                f"[chain-type] chains/{chain_name}: unknown chain type '{chain_type}'"
            )
            continue
        allowed = CHAIN_TYPE_ALLOWED[chain_type]
        if allowed is None:
            # meta chains skip step-level type guard
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

    # --- 5b. meta-chain-integrity: meta_chains 遷移整合性検証 ---
    meta_chains = deps.get('meta_chains', {})
    if meta_chains and isinstance(meta_chains, dict):
        for meta_name, meta_data in meta_chains.items():
            if not isinstance(meta_data, dict):
                continue
            flow = meta_data.get('flow')
            if not isinstance(flow, list):
                continue

            # flow ノードの id 収集
            flow_ids: Set[str] = {
                node['id'] for node in flow
                if isinstance(node, dict) and isinstance(node.get('id'), str)
            }

            for node in flow:
                if not isinstance(node, dict):
                    continue
                node_id = node.get('id', '?')

                # chain 参照が chains セクションに存在するか
                node_chain = node.get('chain')
                if 'chain' in node and node_chain is not None:
                    if isinstance(node_chain, str) and node_chain not in chains:
                        criticals.append(
                            f"[meta-chain-integrity] meta_chains/{meta_name}/flow/{node_id}: "
                            f"chain '{node_chain}' not found in chains section"
                        )
                    else:
                        ok_count += 1

                # next の goto 参照整合性
                next_entries = node.get('next', [])
                if isinstance(next_entries, list):
                    for entry in next_entries:
                        if not isinstance(entry, dict):
                            continue
                        goto = entry.get('goto')
                        if goto is not None and isinstance(goto, str):
                            if goto not in flow_ids:
                                criticals.append(
                                    f"[meta-chain-integrity] meta_chains/{meta_name}/flow/{node_id}: "
                                    f"goto '{goto}' not found in flow ids"
                                )
                            else:
                                ok_count += 1

    # --- 6. chain-py-ssot: chain.py CHAIN_STEPS ⟺ deps.yaml dispatch_mode 整合性 ---
    chain_py_steps = _load_chain_py_steps(plugin_root)
    chain_py_set: Set[str] = set(chain_py_steps)

    if chain_py_steps:
        # 6a. deps.yaml chains の各コンポーネントを chain.py に照合
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
                    continue
                dispatch_mode = comp[1].get('dispatch_mode')
                if dispatch_mode is None:
                    warnings.append(
                        f"[chain-py-ssot] {step_entry}: "
                        f"in chains/{chain_name}/steps but has no dispatch_mode field"
                    )
                elif dispatch_mode == 'runner' and step_entry not in chain_py_set:
                    criticals.append(
                        f"[chain-py-ssot] {step_entry}: "
                        f"dispatch_mode=runner but not in chain.py CHAIN_STEPS"
                    )
                elif dispatch_mode in ('llm', 'runner', 'trigger'):
                    ok_count += 1

        # 6b. chain.py CHAIN_STEPS の各ステップで deps.yaml に存在するものを照合
        for step_name in chain_py_steps:
            comp = all_components.get(step_name)
            if comp is None:
                continue
            dispatch_mode = comp[1].get('dispatch_mode')
            in_chain = comp[1].get('chain') is not None
            if dispatch_mode is None and in_chain:
                warnings.append(
                    f"[chain-py-ssot] {step_name}: "
                    f"in CHAIN_STEPS and in chains but has no dispatch_mode"
                )
            elif dispatch_mode is not None:
                ok_count += 1

    # --- 7. chain-runner-ssot: chain-runner.sh case 文 と CHAIN_STEPS の同期検証 ---
    # dispatch_mode=runner のステップのみチェック（llm/trigger は chain-runner.sh 不要）
    runner_steps = _load_chain_runner_steps(plugin_root)
    if runner_steps and chain_py_steps:
        orchestration_only = {'next-step', 'autopilot-detect', 'quick-detect', 'quick-guard'}
        # runner-dispatched steps in deps.yaml
        runner_dispatched: Set[str] = {
            name for name, (_, data) in all_components.items()
            if data.get('dispatch_mode') == 'runner'
        }
        for step_name in chain_py_steps:
            if step_name in orchestration_only:
                continue
            comp = all_components.get(step_name)
            # Only check runner-dispatched steps (or steps without dispatch_mode in deps.yaml)
            if comp is not None and comp[1].get('dispatch_mode') not in (None, 'runner'):
                continue
            if step_name not in runner_steps:
                warnings.append(
                    f"[chain-runner-ssot] {step_name}: "
                    f"in CHAIN_STEPS but not found in chain-runner.sh case statement"
                )
            else:
                ok_count += 1

    return criticals, warnings, infos
