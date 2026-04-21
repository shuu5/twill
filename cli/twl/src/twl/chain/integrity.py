"""deps-integrity: hash-compare chain.py (SSoT) vs chain-steps.sh and deps.yaml.chains."""

from __future__ import annotations

import ast
import hashlib
import re
from pathlib import Path
from typing import Optional


def _hash_list(items: list[str]) -> str:
    return hashlib.sha256("|".join(items).encode()).hexdigest()


def _hash_set(items: set[str] | frozenset[str]) -> str:
    return hashlib.sha256("|".join(sorted(items)).encode()).hexdigest()


def _load_chain_py_constants(plugin_root: Path) -> Optional[dict]:
    """Parse CHAIN_STEPS, QUICK_SKIP_STEPS, DIRECT_SKIP_STEPS, STEP_TO_WORKFLOW from chain.py via AST."""
    candidates = [
        plugin_root.parent.parent / "cli" / "twl" / "src" / "twl" / "autopilot" / "chain.py",
        plugin_root.parent / "cli" / "twl" / "src" / "twl" / "autopilot" / "chain.py",
        plugin_root / "cli" / "twl" / "src" / "twl" / "autopilot" / "chain.py",
    ]
    chain_py = next((c for c in candidates if c.is_file()), None)
    if chain_py is None:
        return None

    try:
        tree = ast.parse(chain_py.read_text(encoding="utf-8"))
    except Exception:
        return None

    result: dict = {}
    for node in ast.walk(tree):
        name: Optional[str] = None
        value = None
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            t = node.targets[0]
            if isinstance(t, ast.Name):
                name, value = t.id, node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            name, value = node.target.id, node.value

        if name == "CHAIN_STEPS" and isinstance(value, ast.List):
            result["CHAIN_STEPS"] = [
                e.value for e in value.elts
                if isinstance(e, ast.Constant) and isinstance(e.value, str)
            ]
        elif name in ("QUICK_SKIP_STEPS", "DIRECT_SKIP_STEPS") and value is not None:
            elts = None
            if isinstance(value, (ast.List, ast.Set)):
                elts = value.elts
            elif isinstance(value, ast.Call) and value.args and isinstance(value.args[0], (ast.List, ast.Set)):
                elts = value.args[0].elts
            if elts is not None:
                result[name] = frozenset(
                    e.value for e in elts
                    if isinstance(e, ast.Constant) and isinstance(e.value, str)
                )
        elif name == "STEP_TO_WORKFLOW" and isinstance(value, ast.Dict):
            result["STEP_TO_WORKFLOW"] = {
                k.value: v.value
                for k, v in zip(value.keys, value.values)
                if isinstance(k, ast.Constant) and isinstance(v, ast.Constant)
            }

    return result or None


def _parse_bash_array(content: str, var_name: str) -> Optional[list[str]]:
    m = re.search(rf'{re.escape(var_name)}=\(\s*(.*?)\s*\)', content, re.DOTALL)
    if not m:
        return None
    result = []
    for line in m.group(1).splitlines():
        token = line.strip()
        if token and not token.startswith('#'):
            result.append(token)
    return result


def _expected_chains(step_to_workflow: dict[str, str], chain_steps: list[str]) -> dict[str, list[str]]:
    chains: dict[str, list[str]] = {}
    for step in chain_steps:
        wf = step_to_workflow.get(step)
        if wf:
            chains.setdefault(wf, []).append(step)
    return chains


def check_deps_integrity(plugin_root: Path) -> tuple[list[str], list[str]]:
    """Hash-compare chain.py (SSoT) against chain-steps.sh and deps.yaml.chains.

    Returns (errors, warnings). Errors indicate drift that must be fixed.
    """
    errors: list[str] = []
    warnings: list[str] = []
    fix_hint = "Run: twl chain export --yaml --shell"

    constants = _load_chain_py_constants(plugin_root)
    if not constants:
        warnings.append("[deps-integrity] chain.py not found or unreadable — skipping integrity check")
        return errors, warnings

    py_chain_steps: list[str] = constants.get("CHAIN_STEPS", [])
    py_quick_skip: frozenset[str] = constants.get("QUICK_SKIP_STEPS", frozenset())
    py_direct_skip: frozenset[str] = constants.get("DIRECT_SKIP_STEPS", frozenset())
    py_step_to_workflow: dict[str, str] = constants.get("STEP_TO_WORKFLOW", {})

    # --- chain-steps.sh comparison ---
    sh_path = plugin_root / "scripts" / "chain-steps.sh"
    if not sh_path.exists():
        warnings.append("[deps-integrity] chain-steps.sh not found — skipping shell comparison")
    else:
        content = sh_path.read_text(encoding="utf-8")

        sh_chain_steps = _parse_bash_array(content, "CHAIN_STEPS")
        if sh_chain_steps is None:
            warnings.append("[deps-integrity] CHAIN_STEPS not found in chain-steps.sh")
        elif _hash_list(py_chain_steps) != _hash_list(sh_chain_steps):
            errors.append(
                f"[deps-integrity] CHAIN_STEPS mismatch: chain.py vs chain-steps.sh\n"
                f"  chain.py:       {py_chain_steps}\n"
                f"  chain-steps.sh: {sh_chain_steps}\n"
                f"  {fix_hint}"
            )

        sh_quick = _parse_bash_array(content, "QUICK_SKIP_STEPS")
        if sh_quick is None:
            warnings.append("[deps-integrity] QUICK_SKIP_STEPS not found in chain-steps.sh")
        elif _hash_set(py_quick_skip) != _hash_set(set(sh_quick)):
            errors.append(
                f"[deps-integrity] QUICK_SKIP_STEPS mismatch: chain.py vs chain-steps.sh\n"
                f"  chain.py:       {sorted(py_quick_skip)}\n"
                f"  chain-steps.sh: {sorted(sh_quick)}\n"
                f"  {fix_hint}"
            )

        sh_direct = _parse_bash_array(content, "DIRECT_SKIP_STEPS")
        if sh_direct is None:
            warnings.append("[deps-integrity] DIRECT_SKIP_STEPS not found in chain-steps.sh")
        elif _hash_set(py_direct_skip) != _hash_set(set(sh_direct)):
            errors.append(
                f"[deps-integrity] DIRECT_SKIP_STEPS mismatch: chain.py vs chain-steps.sh\n"
                f"  chain.py:       {sorted(py_direct_skip)}\n"
                f"  chain-steps.sh: {sorted(sh_direct)}\n"
                f"  {fix_hint}"
            )

    # --- deps.yaml.chains comparison ---
    deps_path = plugin_root / "deps.yaml"
    if not deps_path.exists():
        warnings.append("[deps-integrity] deps.yaml not found — skipping YAML comparison")
        return errors, warnings

    try:
        import yaml
        deps = yaml.safe_load(deps_path.read_text(encoding="utf-8"))
    except ImportError:
        warnings.append("[deps-integrity] PyYAML not available — skipping YAML comparison")
        return errors, warnings

    actual_chains = deps.get("chains", {})
    expected = _expected_chains(py_step_to_workflow, py_chain_steps)

    for chain_name, exp_steps in expected.items():
        actual = actual_chains.get(chain_name)
        if actual is None:
            errors.append(
                f"[deps-integrity] deps.yaml.chains.{chain_name}: missing\n"
                f"  expected steps: {exp_steps}\n"
                f"  {fix_hint}"
            )
            continue
        act_steps = actual.get("steps", []) if isinstance(actual, dict) else list(actual)
        if _hash_list(exp_steps) != _hash_list(act_steps):
            errors.append(
                f"[deps-integrity] deps.yaml.chains.{chain_name}.steps mismatch\n"
                f"  expected: {exp_steps}\n"
                f"  actual:   {act_steps}\n"
                f"  {fix_hint}"
            )

    return errors, warnings
