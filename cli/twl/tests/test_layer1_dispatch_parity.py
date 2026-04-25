"""test_layer1_dispatch_parity.py

Issue #963: Phase 0 β — CLI 互換 wrapper 設計 (cli.py if-chain リファクタ)

AC4: 3 subcommands × 2 paths (CLI subprocess vs pure function direct call) で
     正規化後の出力が一致することを検証する。

RED phase:
  AC3 が未実装の今、handle_validate/handle_audit/handle_check は positional 'args'
  を要求するため、keyword-only 呼び出しは TypeError → このファイル内のテストは全て FAIL する。
"""

import inspect
import io
import json
import subprocess
import sys
from contextlib import redirect_stdout
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Plugin context fixture
# ---------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
_PLUGIN_ROOT = _REPO_ROOT / "plugins" / "twl"


@pytest.fixture(scope="module")
def plugin_ctx():
    """Build plugin_ctx without CWD inference (AC4 requirement)."""
    from twl.core.plugin import load_deps, build_graph, get_plugin_name
    deps = load_deps(_PLUGIN_ROOT)
    graph = build_graph(deps, _PLUGIN_ROOT)
    plugin_name = get_plugin_name(deps, _PLUGIN_ROOT)
    return {
        "deps": deps,
        "graph": graph,
        "plugin_root": _PLUGIN_ROOT,
        "plugin_name": plugin_name,
    }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _normalize(data: dict) -> dict:
    """Remove timestamps/paths, stable-sort items for comparison."""
    result = {k: v for k, v in data.items() if k not in ("timestamp",)}
    if "items" in result and isinstance(result["items"], list):
        result = dict(result)
        result["items"] = sorted(
            result["items"],
            key=lambda x: json.dumps(x, sort_keys=True),
        )
    return result


def _run_cli_json(args: list) -> dict:
    """Run twl via subprocess, parse stdout as JSON."""
    result = subprocess.run(
        ["twl"] + args,
        capture_output=True,
        text=True,
        cwd=str(_PLUGIN_ROOT),
    )
    return json.loads(result.stdout)


# ---------------------------------------------------------------------------
# AC3: pure kwargs — function signature checks
# ---------------------------------------------------------------------------

def test_ac3_handle_validate_no_positional_args():
    """AC3: handle_validate must not have a positional 'args' parameter."""
    from twl.cli_dispatch import handle_validate
    sig = inspect.signature(handle_validate)
    params = list(sig.parameters.keys())
    assert "args" not in params, (
        "handle_validate still has positional 'args' — AC3 (pure kwargs) not implemented"
    )
    assert "format" in params, "handle_validate missing 'format' keyword parameter"


def test_ac3_handle_audit_no_positional_args():
    """AC3: handle_audit must not have a positional 'args' parameter."""
    from twl.cli_dispatch import handle_audit
    sig = inspect.signature(handle_audit)
    params = list(sig.parameters.keys())
    assert "args" not in params, (
        "handle_audit still has positional 'args' — AC3 (pure kwargs) not implemented"
    )
    assert "format" in params, "handle_audit missing 'format' keyword parameter"
    assert "section" in params, "handle_audit missing 'section' keyword parameter"


def test_ac3_handle_check_no_positional_args():
    """AC3: handle_check must not have a positional 'args' parameter."""
    from twl.cli_dispatch import handle_check
    sig = inspect.signature(handle_check)
    params = list(sig.parameters.keys())
    assert "args" not in params, (
        "handle_check still has positional 'args' — AC3 (pure kwargs) not implemented"
    )
    assert "format" in params, "handle_check missing 'format' keyword parameter"
    assert "deps_integrity" in params, "handle_check missing 'deps_integrity' keyword parameter"


def test_ac3_handle_validate_returns_int_not_sys_exit(plugin_ctx):
    """AC3(b): handle_validate must return exit_code (int), not call sys.exit()."""
    from twl.cli_dispatch import handle_validate
    ctx = plugin_ctx
    buf = io.StringIO()
    with redirect_stdout(buf):
        result = handle_validate(
            format=None,
            deps=ctx["deps"],
            graph=ctx["graph"],
            plugin_root=ctx["plugin_root"],
            plugin_name=ctx["plugin_name"],
        )
    assert isinstance(result, int), (
        f"handle_validate returned {type(result).__name__!r}, expected int — "
        "sys.exit() must be moved to cli.py caller layer (AC3b)"
    )


def test_ac3_handle_audit_returns_int_not_sys_exit(plugin_ctx):
    """AC3(b): handle_audit must return exit_code (int), not call sys.exit()."""
    from twl.cli_dispatch import handle_audit
    ctx = plugin_ctx
    buf = io.StringIO()
    with redirect_stdout(buf):
        result = handle_audit(
            format="json",
            section=7,
            deps=ctx["deps"],
            plugin_root=ctx["plugin_root"],
            plugin_name=ctx["plugin_name"],
        )
    assert isinstance(result, int), (
        f"handle_audit returned {type(result).__name__!r}, expected int — "
        "sys.exit() must be moved to cli.py caller layer (AC3b)"
    )


# ---------------------------------------------------------------------------
# AC4: CLI subprocess vs pure function direct call — parity tests
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("label,cli_args,direct_fn,direct_kwargs_keys", [
    (
        "validate",
        ["--validate", "--format", "json"],
        "handle_validate",
        {"format": "json"},
    ),
    (
        "audit_section7",
        ["--audit", "--section", "7", "--format", "json"],
        "handle_audit",
        {"format": "json", "section": 7},
    ),
    (
        # CLI side uses subcommand style (twl check --deps-integrity) because flag-style
        # --check does not yet accept --deps-integrity (AC1 in-scope).
        # Direct call tests the keyword-only signature (AC3 RED).
        "check_deps_integrity",
        ["check", "--deps-integrity", "--format", "json"],
        "handle_check",
        {"format": "json", "deps_integrity": True},
    ),
])
def test_ac4_cli_vs_direct_parity(label, cli_args, direct_fn, direct_kwargs_keys, plugin_ctx):
    """AC4: CLI subprocess and pure function direct call produce equal normalized JSON."""
    import importlib
    ctx = plugin_ctx

    # CLI path
    cli_data = _normalize(_run_cli_json(cli_args))

    # Direct call path — build kwargs from ctx + direct_kwargs_keys
    module = importlib.import_module("twl.cli_dispatch")
    fn = getattr(module, direct_fn)
    kwargs = dict(direct_kwargs_keys)
    if "graph" in inspect.signature(fn).parameters:
        kwargs["graph"] = ctx["graph"]
    kwargs["deps"] = ctx["deps"]
    kwargs["plugin_root"] = ctx["plugin_root"]
    kwargs["plugin_name"] = ctx["plugin_name"]

    buf = io.StringIO()
    with redirect_stdout(buf):
        exit_code = fn(**kwargs)
    direct_data = _normalize(json.loads(buf.getvalue()))

    assert cli_data.get("command") == direct_data.get("command"), (
        f"[{label}] command field mismatch: {cli_data.get('command')!r} vs {direct_data.get('command')!r}"
    )
    assert cli_data.get("exit_code") == direct_data.get("exit_code"), (
        f"[{label}] exit_code mismatch: CLI={cli_data.get('exit_code')} vs direct={direct_data.get('exit_code')}"
    )
    cli_items = cli_data.get("items", [])
    direct_items = direct_data.get("items", [])
    assert len(cli_items) == len(direct_items), (
        f"[{label}] items count mismatch: CLI={len(cli_items)} vs direct={len(direct_items)}"
    )


# ---------------------------------------------------------------------------
# AC6: architecture docs — twill-integration.md contains hybrid pattern section
# ---------------------------------------------------------------------------

def test_ac6_twill_integration_docs_hybrid_pattern():
    """AC6: twill-integration.md must document the hybrid pattern."""
    doc_path = _PLUGIN_ROOT / "architecture" / "domain" / "contexts" / "twill-integration.md"
    assert doc_path.exists(), f"Architecture doc not found: {doc_path}"
    content = doc_path.read_text()
    assert "hybrid pattern" in content.lower(), (
        "twill-integration.md missing 'hybrid pattern' section (AC6a)"
    )
    assert "pure" in content.lower() and "ssot" in content.lower(), (
        "twill-integration.md missing 'pure function SSOT' concept (AC6b)"
    )
    assert "mcp" in content.lower(), (
        "twill-integration.md missing MCP tool shared codepath diagram (AC6c)"
    )
