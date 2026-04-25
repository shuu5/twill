"""twl MCP tool definitions (Phase 0 PoC).

Exposes twl_validate / twl_audit / twl_check as FastMCP tools.
Handler functions (_handler suffix) are pure Python for in-process testing.
"""
import json
from pathlib import Path


def _load_plugin_ctx(plugin_root: str) -> "tuple[Path, dict, dict, str]":
    from twl.core.plugin import load_deps, build_graph, get_plugin_name
    # Resolve to absolute path to prevent path traversal
    p = Path(plugin_root).expanduser().resolve()
    if not p.is_dir():
        raise ValueError(f"plugin_root '{plugin_root}' is not a directory")
    try:
        deps = load_deps(p)
        graph = build_graph(deps, p)
        plugin_name = get_plugin_name(deps, p)
    except SystemExit as exc:
        raise ValueError(
            f"Failed to load plugin context from '{plugin_root}': "
            "deps.yaml not found or invalid"
        ) from exc
    return p, deps, graph, plugin_name


def twl_validate_handler(plugin_root: str) -> dict:
    """Validate plugin structure and return JSON envelope dict."""
    from twl.validation.validate import validate_types, validate_body_refs, validate_v3_schema
    from twl.chain.validate import chain_validate
    from twl.core.plugin import get_deps_version
    from twl.core.output import build_envelope, violations_to_items

    p, deps, graph, plugin_name = _load_plugin_ctx(plugin_root)
    _ok, violations, xref_warnings = validate_types(deps, graph, p)
    _ok2, body_violations = validate_body_refs(deps, p)
    violations.extend(body_violations)
    _ok3, v3_violations = validate_v3_schema(deps)
    violations.extend(v3_violations)
    cv_criticals, cv_warnings, _cv_infos = chain_validate(deps, p)
    violations.extend(cv_criticals)
    violations.extend(cv_warnings)
    exit_code = 1 if violations else 0
    items = violations_to_items(violations)
    items.extend(violations_to_items(xref_warnings, "warning"))
    return build_envelope("validate", get_deps_version(deps), plugin_name, items, exit_code)


def twl_audit_handler(plugin_root: str) -> dict:
    """Audit plugin for compliance issues and return JSON envelope dict."""
    from twl.validation.audit import audit_collect
    from twl.core.plugin import get_deps_version
    from twl.core.output import build_envelope

    p, deps, _graph, plugin_name = _load_plugin_ctx(plugin_root)
    items = audit_collect(deps, p)
    exit_code = 1 if any(i["severity"] == "critical" for i in items) else 0
    return build_envelope("audit", get_deps_version(deps), plugin_name, items, exit_code)


def twl_check_handler(plugin_root: str) -> dict:
    """Check file existence and chain integrity, return JSON envelope dict."""
    from twl.validation.check import check_files
    from twl.core.plugin import get_deps_version
    from twl.core.output import (
        build_envelope,
        check_results_to_items,
        violations_to_items,
        deep_validate_to_items,
    )

    p, deps, graph, plugin_name = _load_plugin_ctx(plugin_root)
    results, xref_warnings = check_files(graph, p)
    missing_count = sum(1 for r in results if r[0] == "missing")
    items = check_results_to_items(results)
    items.extend(violations_to_items(xref_warnings, "warning"))
    if get_deps_version(deps).startswith("3"):
        from twl.chain.validate import chain_validate
        cv_criticals, cv_warnings, cv_infos = chain_validate(deps, p)
        items.extend(deep_validate_to_items(cv_criticals, cv_warnings, cv_infos))
        exit_code = 1 if (missing_count > 0 or cv_criticals) else 0
    else:
        exit_code = 1 if missing_count > 0 else 0
    return build_envelope("check", get_deps_version(deps), plugin_name, items, exit_code)


# MCP tool registration — requires fastmcp (optional dep)
try:
    from fastmcp import FastMCP as _FastMCP

    mcp = _FastMCP("twl")

    @mcp.tool()
    def twl_validate(plugin_root: str) -> str:
        """Validate plugin structure. Checks type rules, body refs, v3 schema, and chain consistency."""
        return json.dumps(twl_validate_handler(plugin_root=plugin_root), ensure_ascii=False)

    @mcp.tool()
    def twl_audit(plugin_root: str) -> str:
        """Audit plugin for TWiLL compliance issues across 10 sections."""
        return json.dumps(twl_audit_handler(plugin_root=plugin_root), ensure_ascii=False)

    @mcp.tool()
    def twl_check(plugin_root: str) -> str:
        """Check file existence and chain integrity for a plugin."""
        return json.dumps(twl_check_handler(plugin_root=plugin_root), ensure_ascii=False)

except ImportError:
    mcp = None  # type: ignore[assignment]

    def twl_validate(plugin_root: str) -> str:  # type: ignore[misc]
        """Validate plugin structure (fastmcp not installed)."""
        return json.dumps(twl_validate_handler(plugin_root=plugin_root), ensure_ascii=False)

    def twl_audit(plugin_root: str) -> str:  # type: ignore[misc]
        """Audit plugin for TWiLL compliance issues (fastmcp not installed)."""
        return json.dumps(twl_audit_handler(plugin_root=plugin_root), ensure_ascii=False)

    def twl_check(plugin_root: str) -> str:  # type: ignore[misc]
        """Check file existence and chain integrity (fastmcp not installed)."""
        return json.dumps(twl_check_handler(plugin_root=plugin_root), ensure_ascii=False)
