"""twl MCP tool definitions (Phase 0 PoC + autopilot Phase 2).

Exposes twl_validate / twl_audit / twl_check / twl_state_read / twl_state_write
+ 12 autopilot tools as FastMCP tools.
Handler functions (_handler suffix) are pure Python for in-process testing.
"""
import concurrent.futures
import json
import os
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
    except (SystemExit, Exception) as exc:
        raise ValueError(
            f"Failed to load plugin context from '{plugin_root}': {exc}"
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


# Phase 1: State read/write handlers (ADR-0006 §1 Hybrid Path 5 原則)


def twl_state_read_handler(
    type_: str,
    issue: str | None = None,
    repo: str | None = None,
    field: str | None = None,
    autopilot_dir: str | None = None,
) -> dict:
    """Read autopilot state JSON or single field. Pure Python (in-process testable)."""
    from twl.autopilot.state import StateManager, StateError, StateArgError
    ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
    try:
        result = StateManager(autopilot_dir=ap_dir).read(
            type_=type_, issue=issue, repo=repo, field=field,
        )
        return {"ok": True, "result": result, "exit_code": 0}
    except StateArgError as e:
        return {"ok": False, "error": str(e), "error_type": "arg_error", "exit_code": 2}
    except StateError as e:
        return {"ok": False, "error": str(e), "error_type": "state_error", "exit_code": 1}


def twl_state_write_handler(
    type_: str,
    role: str,
    issue: str | None = None,
    repo: str | None = None,
    sets: list[str] | None = None,
    init: bool = False,
    autopilot_dir: str | None = None,
    cwd: str | None = None,
    force_done: bool = False,
    override_reason: str | None = None,
) -> dict:
    """Write autopilot state. Returns {ok, message/error, error_type, exit_code}."""
    from twl.autopilot.state import StateManager, StateError, StateArgError
    ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
    try:
        message = StateManager(autopilot_dir=ap_dir).write(
            type_=type_,
            role=role,
            issue=issue,
            repo=repo,
            sets=sets,
            init=init,
            cwd=cwd,
            force_done=force_done,
            override_reason=override_reason,
        )
        return {"ok": True, "message": message, "exit_code": 0}
    except StateArgError as e:
        return {"ok": False, "error": str(e), "error_type": "arg_error", "exit_code": 2}
    except StateError as e:
        return {"ok": False, "error": str(e), "error_type": "state_error", "exit_code": 1}


# ---------------------------------------------------------------------------
# Phase 2: Autopilot handlers (ADR-029 Decision 2, Hybrid Path 5 原則)
# ---------------------------------------------------------------------------

# --- Mergegate ---

def _resolve_issue_from_labels(labels: list[dict]) -> str | None:
    """Extract issue number from PR labels (autopilot label convention: 'issue-N')."""
    import re
    for lbl in labels:
        name = lbl.get("name", "")
        m = re.search(r"issue-(\d+)", name)
        if m:
            return m.group(1)
    return None


def twl_mergegate_run_handler(
    pr_number: int,
    autopilot_dir: str | None = None,
    cwd: str | None = None,
    timeout_sec: int = 600,
) -> dict:
    """autopilot.mergegate: invoke MergeGate.execute() with SystemExit catch + ThreadPoolExecutor timeout wrap (sys.exit(1)/sys.exit(2) recoverable). Note: handler timeout 600s; set MCP_CLIENT_TIMEOUT>=660s."""
    import subprocess

    def _inner() -> dict:
        try:
            r = subprocess.run(
                ["gh", "pr", "view", str(pr_number), "--json", "number,headRefName,labels"],
                capture_output=True, text=True, timeout=30,
            )
            if r.returncode != 0:
                return {"ok": False, "error": f"gh pr view failed: {r.stderr}", "error_type": "pr_resolve_error", "exit_code": 2}
            data = json.loads(r.stdout)
            branch = data["headRefName"]
            issue = _resolve_issue_from_labels(data.get("labels", []))
            if not issue:
                return {"ok": False, "error": "issue label not found in PR labels", "error_type": "pr_resolve_error", "exit_code": 2}
        except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception) as e:
            return {"ok": False, "error": str(e), "error_type": "pr_resolve_error", "exit_code": 2}

        from twl.autopilot.mergegate import MergeGate, MergeGateError
        ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
        try:
            mg = MergeGate(
                pr_number=str(pr_number),
                branch=branch,
                issue=issue,
                autopilot_dir=ap_dir,
            )
            mg.execute()
            return {"ok": True, "message": "merge completed", "exit_code": 0}
        except SystemExit as e:
            code = int(e.code) if e.code is not None else 0
            if code == 0:
                return {"ok": True, "message": "merge completed (exit 0)", "exit_code": 0}
            return {"ok": False, "error": f"merge_gate exit code {code}", "error_type": f"merge_exit_{code}", "exit_code": code}
        except MergeGateError as e:
            return {"ok": False, "error": str(e), "error_type": "merge_gate_error", "exit_code": 1}

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


def twl_mergegate_reject_handler(
    pr_number: int,
    reason: str,
    autopilot_dir: str | None = None,
    cwd: str | None = None,
    timeout_sec: int = 300,
) -> dict:
    """autopilot.mergegate: invoke MergeGate.reject() with SystemExit catch + timeout wrap (300s)."""
    import subprocess

    def _inner() -> dict:
        try:
            r = subprocess.run(
                ["gh", "pr", "view", str(pr_number), "--json", "number,headRefName,labels"],
                capture_output=True, text=True, timeout=30,
            )
            if r.returncode != 0:
                return {"ok": False, "error": f"gh pr view failed: {r.stderr}", "error_type": "pr_resolve_error", "exit_code": 2}
            data = json.loads(r.stdout)
            branch = data["headRefName"]
            issue = _resolve_issue_from_labels(data.get("labels", []))
            if not issue:
                return {"ok": False, "error": "issue label not found", "error_type": "pr_resolve_error", "exit_code": 2}
        except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception) as e:
            return {"ok": False, "error": str(e), "error_type": "pr_resolve_error", "exit_code": 2}

        from twl.autopilot.mergegate import MergeGate, MergeGateError
        ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
        try:
            mg = MergeGate(
                pr_number=str(pr_number),
                branch=branch,
                issue=issue,
                finding_summary=reason,
                autopilot_dir=ap_dir,
            )
            mg.reject()
            return {"ok": True, "message": "rejected", "exit_code": 0}
        except SystemExit as e:
            code = int(e.code) if e.code is not None else 0
            if code == 0:
                return {"ok": True, "message": "rejected (exit 0)", "exit_code": 0}
            return {"ok": False, "error": f"merge_gate exit code {code}", "error_type": f"merge_exit_{code}", "exit_code": code}
        except MergeGateError as e:
            return {"ok": False, "error": str(e), "error_type": "merge_gate_error", "exit_code": 1}

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


def twl_mergegate_reject_final_handler(
    pr_number: int,
    reason: str,
    autopilot_dir: str | None = None,
    cwd: str | None = None,
    timeout_sec: int = 300,
) -> dict:
    """autopilot.mergegate: invoke MergeGate.reject_final() with SystemExit catch + timeout wrap (300s)."""
    import subprocess

    def _inner() -> dict:
        try:
            r = subprocess.run(
                ["gh", "pr", "view", str(pr_number), "--json", "number,headRefName,labels"],
                capture_output=True, text=True, timeout=30,
            )
            if r.returncode != 0:
                return {"ok": False, "error": f"gh pr view failed: {r.stderr}", "error_type": "pr_resolve_error", "exit_code": 2}
            data = json.loads(r.stdout)
            branch = data["headRefName"]
            issue = _resolve_issue_from_labels(data.get("labels", []))
            if not issue:
                return {"ok": False, "error": "issue label not found", "error_type": "pr_resolve_error", "exit_code": 2}
        except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception) as e:
            return {"ok": False, "error": str(e), "error_type": "pr_resolve_error", "exit_code": 2}

        from twl.autopilot.mergegate import MergeGate, MergeGateError
        ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
        try:
            mg = MergeGate(
                pr_number=str(pr_number),
                branch=branch,
                issue=issue,
                finding_summary=reason,
                autopilot_dir=ap_dir,
            )
            mg.reject_final()
            return {"ok": True, "message": "final rejection completed", "exit_code": 0}
        except SystemExit as e:
            code = int(e.code) if e.code is not None else 0
            if code == 0:
                return {"ok": True, "message": "reject_final completed (exit 0)", "exit_code": 0}
            return {"ok": False, "error": f"merge_gate exit code {code}", "error_type": f"merge_exit_{code}", "exit_code": code}
        except MergeGateError as e:
            return {"ok": False, "error": str(e), "error_type": "merge_gate_error", "exit_code": 1}

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


# --- Orchestrator ---

def twl_orchestrator_phase_review_handler(
    phase: int,
    plan_file: str,
    session_file: str,
    project_dir: str,
    autopilot_dir: str,
    repos_json: str = "",
    cwd: str | None = None,
    timeout_sec: int = 1800,
) -> dict:
    """autopilot.orchestrator: invoke PhaseOrchestrator.run() with CWD-based 不変条件 B role check + handler-level timeout wrap (1800s wall-clock guard for tmux + state.py subprocess). Note: set MCP_CLIENT_TIMEOUT>=1860s. plan_file existence check + tmux FileNotFoundError catch."""
    violation = _check_invariant_b(cwd)
    if violation:
        return violation
    if not Path(plan_file).is_file():
        return {"ok": False, "error": "plan_file not found", "error_type": "arg_error", "exit_code": 2}

    def _inner() -> dict:
        from twl.autopilot.orchestrator import PhaseOrchestrator
        try:
            orch = PhaseOrchestrator(
                plan_file=plan_file,
                phase=phase,
                session_file=session_file,
                project_dir=project_dir,
                autopilot_dir=autopilot_dir,
                repos_json=repos_json,
            )
            result_dict = orch.run()
            return {"ok": True, "result": result_dict, "exit_code": 0}
        except (FileNotFoundError, OSError) as e:
            return {"ok": False, "error": f"tmux subprocess error: {e}", "error_type": "subprocess_error", "exit_code": 127}

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


def twl_orchestrator_get_phase_issues_handler(
    phase: int,
    plan_file: str,
) -> dict:
    """autopilot.orchestrator: pure get_phase_issues() (read-only, no subprocess). plan_file existence check."""
    if not Path(plan_file).is_file():
        return {"ok": False, "error": "plan_file not found", "error_type": "arg_error", "exit_code": 2}
    from twl.autopilot.orchestrator import get_phase_issues
    try:
        issues = get_phase_issues(phase=phase, plan_file=plan_file)
        return {"ok": True, "result": issues, "exit_code": 0}
    except Exception as e:
        return {"ok": False, "error": str(e), "error_type": "orchestrator_error", "exit_code": 1}


def twl_orchestrator_summary_handler(
    autopilot_dir: str,
) -> dict:
    """autopilot.orchestrator: pure generate_summary() (read-only)."""
    from twl.autopilot.orchestrator import generate_summary, OrchestratorError
    try:
        summary = generate_summary(autopilot_dir=autopilot_dir)
        return {"ok": True, "result": summary, "exit_code": 0}
    except OrchestratorError as e:
        return {"ok": False, "error": str(e), "error_type": "orchestrator_error", "exit_code": 1}
    except Exception as e:
        return {"ok": False, "error": str(e), "error_type": "orchestrator_error", "exit_code": 1}


def twl_orchestrator_resolve_repos_handler(
    repos_json: str,
) -> dict:
    """autopilot.orchestrator: pure resolve_repos_config() (read-only)."""
    from twl.autopilot.orchestrator import resolve_repos_config
    result = resolve_repos_config(repos_json=repos_json)
    return {"ok": True, "result": result, "exit_code": 0}


# --- Worktree ---

def _check_invariant_b(cwd: str | None) -> dict | None:
    """Return error dict if CWD is under worktrees/ (invariant B violation), else None."""
    cwd_path = os.path.realpath(cwd if cwd is not None else os.getcwd())
    if "/worktrees/" in cwd_path:
        return {
            "ok": False,
            "error": "不変条件 B 違反: Worker (worktrees/ 配下) からの worktree/orchestrator 操作は禁止されています",
            "error_type": "invariant_b_violation",
            "exit_code": 1,
        }
    return None


def twl_worktree_create_handler(
    branch: str,
    base: str = "main",
    repo: str | None = None,
    repo_path: str | None = None,
    cwd: str | None = None,
    timeout_sec: int = 300,
) -> dict:
    """autopilot.worktree: WorktreeManager.create() with CWD-based 不変条件 B role check (realpath 適用) + timeout wrap (300s)."""
    violation = _check_invariant_b(cwd)
    if violation:
        return violation

    def _inner() -> dict:
        from twl.autopilot.worktree import WorktreeManager, WorktreeError, WorktreeArgError
        try:
            manager = WorktreeManager(repo_path=repo_path)
            worktree_dir = manager.create(branch_name=branch, base_branch=base, repo=repo)
            return {"ok": True, "message": f"worktree created: {worktree_dir}", "path": str(worktree_dir), "exit_code": 0}
        except WorktreeArgError as e:
            return {"ok": False, "error": str(e), "error_type": "arg_error", "exit_code": 2}
        except WorktreeError as e:
            return {"ok": False, "error": str(e), "error_type": "worktree_error", "exit_code": 1}
        except Exception as e:
            return {"ok": False, "error": str(e), "error_type": "worktree_error", "exit_code": 1}

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


def twl_worktree_delete_handler(
    branch: str,
    repo_path: str | None = None,
    cwd: str | None = None,
    timeout_sec: int = 120,
) -> dict:
    """autopilot.worktree: WorktreeManager.delete() (新規追加 method) with CWD-based 不変条件 B role check (realpath 適用) + timeout wrap (120s)."""
    violation = _check_invariant_b(cwd)
    if violation:
        return violation

    def _inner() -> dict:
        from twl.autopilot.worktree import WorktreeManager, WorktreeError, WorktreeArgError
        try:
            manager = WorktreeManager(repo_path=repo_path)
            manager.delete(branch)
            return {"ok": True, "message": f"worktree {branch} deleted", "exit_code": 0}
        except WorktreeArgError as e:
            return {"ok": False, "error": str(e), "error_type": "arg_error", "exit_code": 2}
        except WorktreeError as e:
            return {"ok": False, "error": str(e), "error_type": "worktree_error", "exit_code": 1}
        except Exception as e:
            return {"ok": False, "error": str(e), "error_type": "worktree_error", "exit_code": 1}

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


def twl_worktree_list_handler(
    repo_path: str | None = None,
) -> dict:
    """autopilot.worktree: WorktreeManager.list_porcelain() (新規追加 method) - read-only list[dict] return."""
    from twl.autopilot.worktree import WorktreeManager, WorktreeError
    try:
        manager = WorktreeManager(repo_path=repo_path)
        entries = manager.list_porcelain()
        return {"ok": True, "result": entries, "exit_code": 0}
    except WorktreeError as e:
        return {"ok": False, "error": str(e), "error_type": "worktree_error", "exit_code": 1}


def twl_worktree_generate_branch_name_handler(
    issue_number: str,
    repo: str | None = None,
    timeout_sec: int = 60,
) -> dict:
    """autopilot.worktree: pure generate_branch_name(issue_number: str, ...) with gh issue view subprocess (timeout 60s)."""
    def _inner() -> dict:
        from twl.autopilot.worktree import generate_branch_name, WorktreeArgError, WorktreeError
        try:
            branch = generate_branch_name(issue_number=issue_number, repo=repo)
            return {"ok": True, "result": branch, "exit_code": 0}
        except WorktreeArgError as e:
            return {"ok": False, "error": str(e), "error_type": "arg_error", "exit_code": 2}
        except WorktreeError as e:
            return {"ok": False, "error": str(e), "error_type": "worktree_error", "exit_code": 1}

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


def twl_worktree_validate_branch_name_handler(
    branch: str,
) -> dict:
    """autopilot.worktree: pure validate_branch_name() (read-only, raises WorktreeArgError)."""
    from twl.autopilot.worktree import validate_branch_name, WorktreeArgError
    try:
        validate_branch_name(branch)
        return {"ok": True, "message": f"branch name valid: {branch}", "exit_code": 0}
    except WorktreeArgError as e:
        return {"ok": False, "error": str(e), "error_type": "arg_error", "exit_code": 2}


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

    @mcp.tool()
    def twl_state_read(
        type_: str,
        issue: str | None = None,
        repo: str | None = None,
        field: str | None = None,
        autopilot_dir: str | None = None,
    ) -> str:
        """Read autopilot state JSON or single field."""
        return json.dumps(
            twl_state_read_handler(
                type_=type_, issue=issue, repo=repo, field=field, autopilot_dir=autopilot_dir,
            ),
            ensure_ascii=False,
        )

    @mcp.tool()
    def twl_state_write(
        type_: str,
        role: str,
        issue: str | None = None,
        repo: str | None = None,
        sets: list[str] | None = None,
        init: bool = False,
        autopilot_dir: str | None = None,
        cwd: str | None = None,
        force_done: bool = False,
        override_reason: str | None = None,
    ) -> str:
        """Write autopilot state."""
        return json.dumps(
            twl_state_write_handler(
                type_=type_, role=role, issue=issue, repo=repo, sets=sets,
                init=init, autopilot_dir=autopilot_dir, cwd=cwd,
                force_done=force_done, override_reason=override_reason,
            ),
            ensure_ascii=False,
        )

    # --- Autopilot Phase 2 tools ---

    @mcp.tool()
    def twl_mergegate_run(pr_number: int, autopilot_dir: str | None = None, cwd: str | None = None, timeout_sec: int = 600) -> str:
        """autopilot.mergegate: invoke MergeGate.execute() with SystemExit catch + ThreadPoolExecutor timeout wrap (sys.exit(1)/sys.exit(2) recoverable). Note: handler timeout 600s; set MCP_CLIENT_TIMEOUT>=660s."""
        return json.dumps(twl_mergegate_run_handler(pr_number=pr_number, autopilot_dir=autopilot_dir, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_mergegate_reject(pr_number: int, reason: str, autopilot_dir: str | None = None, cwd: str | None = None, timeout_sec: int = 300) -> str:
        """autopilot.mergegate: invoke MergeGate.reject() with SystemExit catch + timeout wrap (300s)."""
        return json.dumps(twl_mergegate_reject_handler(pr_number=pr_number, reason=reason, autopilot_dir=autopilot_dir, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_mergegate_reject_final(pr_number: int, reason: str, autopilot_dir: str | None = None, cwd: str | None = None, timeout_sec: int = 300) -> str:
        """autopilot.mergegate: invoke MergeGate.reject_final() with SystemExit catch + timeout wrap (300s)."""
        return json.dumps(twl_mergegate_reject_final_handler(pr_number=pr_number, reason=reason, autopilot_dir=autopilot_dir, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_orchestrator_phase_review(phase: int, plan_file: str, session_file: str, project_dir: str, autopilot_dir: str, repos_json: str = "", cwd: str | None = None, timeout_sec: int = 1800) -> str:
        """autopilot.orchestrator: invoke PhaseOrchestrator.run() with handler-level timeout wrap (1800s wall-clock guard for tmux + state.py subprocess). Note: set MCP_CLIENT_TIMEOUT>=1860s. plan_file existence check + tmux FileNotFoundError catch."""
        return json.dumps(twl_orchestrator_phase_review_handler(phase=phase, plan_file=plan_file, session_file=session_file, project_dir=project_dir, autopilot_dir=autopilot_dir, repos_json=repos_json, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_orchestrator_get_phase_issues(phase: int, plan_file: str) -> str:
        """autopilot.orchestrator: pure get_phase_issues() (read-only, no subprocess). plan_file existence check."""
        return json.dumps(twl_orchestrator_get_phase_issues_handler(phase=phase, plan_file=plan_file), ensure_ascii=False)

    @mcp.tool()
    def twl_orchestrator_summary(autopilot_dir: str) -> str:
        """autopilot.orchestrator: pure generate_summary() (read-only)."""
        return json.dumps(twl_orchestrator_summary_handler(autopilot_dir=autopilot_dir), ensure_ascii=False)

    @mcp.tool()
    def twl_orchestrator_resolve_repos(repos_json: str) -> str:
        """autopilot.orchestrator: pure resolve_repos_config() (read-only)."""
        return json.dumps(twl_orchestrator_resolve_repos_handler(repos_json=repos_json), ensure_ascii=False)

    @mcp.tool()
    def twl_worktree_create(branch: str, base: str = "main", repo: str | None = None, repo_path: str | None = None, cwd: str | None = None, timeout_sec: int = 300) -> str:
        """autopilot.worktree: WorktreeManager.create() with CWD-based 不変条件 B role check (realpath 適用) + timeout wrap (300s)."""
        return json.dumps(twl_worktree_create_handler(branch=branch, base=base, repo=repo, repo_path=repo_path, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_worktree_delete(branch: str, repo_path: str | None = None, cwd: str | None = None, timeout_sec: int = 120) -> str:
        """autopilot.worktree: WorktreeManager.delete() (新規追加 method) with CWD-based 不変条件 B role check (realpath 適用) + timeout wrap (120s)."""
        return json.dumps(twl_worktree_delete_handler(branch=branch, repo_path=repo_path, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_worktree_list(repo_path: str | None = None) -> str:
        """autopilot.worktree: WorktreeManager.list_porcelain() (新規追加 method) - read-only list[dict] return."""
        return json.dumps(twl_worktree_list_handler(repo_path=repo_path), ensure_ascii=False)

    @mcp.tool()
    def twl_worktree_generate_branch_name(issue_number: str, repo: str | None = None, timeout_sec: int = 60) -> str:
        """autopilot.worktree: pure generate_branch_name(issue_number: str, ...) with gh issue view subprocess (timeout 60s)."""
        return json.dumps(twl_worktree_generate_branch_name_handler(issue_number=issue_number, repo=repo, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_worktree_validate_branch_name(branch: str) -> str:
        """autopilot.worktree: pure validate_branch_name() (read-only, raises WorktreeArgError)."""
        return json.dumps(twl_worktree_validate_branch_name_handler(branch=branch), ensure_ascii=False)

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

    def twl_state_read(  # type: ignore[misc]
        type_: str,
        issue: str | None = None,
        repo: str | None = None,
        field: str | None = None,
        autopilot_dir: str | None = None,
    ) -> str:
        """Read autopilot state (fastmcp not installed)."""
        return json.dumps(
            twl_state_read_handler(
                type_=type_, issue=issue, repo=repo, field=field, autopilot_dir=autopilot_dir,
            ),
            ensure_ascii=False,
        )

    def twl_state_write(  # type: ignore[misc]
        type_: str,
        role: str,
        issue: str | None = None,
        repo: str | None = None,
        sets: list[str] | None = None,
        init: bool = False,
        autopilot_dir: str | None = None,
        cwd: str | None = None,
        force_done: bool = False,
        override_reason: str | None = None,
    ) -> str:
        """Write autopilot state (fastmcp not installed)."""
        return json.dumps(
            twl_state_write_handler(
                type_=type_, role=role, issue=issue, repo=repo, sets=sets,
                init=init, autopilot_dir=autopilot_dir, cwd=cwd,
                force_done=force_done, override_reason=override_reason,
            ),
            ensure_ascii=False,
        )

    def twl_mergegate_run(pr_number: int, autopilot_dir: str | None = None, cwd: str | None = None, timeout_sec: int = 600) -> str:  # type: ignore[misc]
        """autopilot.mergegate: invoke MergeGate.execute() with SystemExit catch + ThreadPoolExecutor timeout wrap (sys.exit(1)/sys.exit(2) recoverable). Note: handler timeout 600s; set MCP_CLIENT_TIMEOUT>=660s."""
        return json.dumps(twl_mergegate_run_handler(pr_number=pr_number, autopilot_dir=autopilot_dir, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_mergegate_reject(pr_number: int, reason: str, autopilot_dir: str | None = None, cwd: str | None = None, timeout_sec: int = 300) -> str:  # type: ignore[misc]
        """autopilot.mergegate: invoke MergeGate.reject() with SystemExit catch + timeout wrap (300s)."""
        return json.dumps(twl_mergegate_reject_handler(pr_number=pr_number, reason=reason, autopilot_dir=autopilot_dir, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_mergegate_reject_final(pr_number: int, reason: str, autopilot_dir: str | None = None, cwd: str | None = None, timeout_sec: int = 300) -> str:  # type: ignore[misc]
        """autopilot.mergegate: invoke MergeGate.reject_final() with SystemExit catch + timeout wrap (300s)."""
        return json.dumps(twl_mergegate_reject_final_handler(pr_number=pr_number, reason=reason, autopilot_dir=autopilot_dir, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_orchestrator_phase_review(phase: int, plan_file: str, session_file: str, project_dir: str, autopilot_dir: str, repos_json: str = "", cwd: str | None = None, timeout_sec: int = 1800) -> str:  # type: ignore[misc]
        """autopilot.orchestrator: invoke PhaseOrchestrator.run() with handler-level timeout wrap (1800s wall-clock guard for tmux + state.py subprocess). Note: set MCP_CLIENT_TIMEOUT>=1860s. plan_file existence check + tmux FileNotFoundError catch."""
        return json.dumps(twl_orchestrator_phase_review_handler(phase=phase, plan_file=plan_file, session_file=session_file, project_dir=project_dir, autopilot_dir=autopilot_dir, repos_json=repos_json, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_orchestrator_get_phase_issues(phase: int, plan_file: str) -> str:  # type: ignore[misc]
        """autopilot.orchestrator: pure get_phase_issues() (read-only, no subprocess). plan_file existence check."""
        return json.dumps(twl_orchestrator_get_phase_issues_handler(phase=phase, plan_file=plan_file), ensure_ascii=False)

    def twl_orchestrator_summary(autopilot_dir: str) -> str:  # type: ignore[misc]
        """autopilot.orchestrator: pure generate_summary() (read-only)."""
        return json.dumps(twl_orchestrator_summary_handler(autopilot_dir=autopilot_dir), ensure_ascii=False)

    def twl_orchestrator_resolve_repos(repos_json: str) -> str:  # type: ignore[misc]
        """autopilot.orchestrator: pure resolve_repos_config() (read-only)."""
        return json.dumps(twl_orchestrator_resolve_repos_handler(repos_json=repos_json), ensure_ascii=False)

    def twl_worktree_create(branch: str, base: str = "main", repo: str | None = None, repo_path: str | None = None, cwd: str | None = None, timeout_sec: int = 300) -> str:  # type: ignore[misc]
        """autopilot.worktree: WorktreeManager.create() with CWD-based 不変条件 B role check (realpath 適用) + timeout wrap (300s)."""
        return json.dumps(twl_worktree_create_handler(branch=branch, base=base, repo=repo, repo_path=repo_path, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_worktree_delete(branch: str, repo_path: str | None = None, cwd: str | None = None, timeout_sec: int = 120) -> str:  # type: ignore[misc]
        """autopilot.worktree: WorktreeManager.delete() (新規追加 method) with CWD-based 不変条件 B role check (realpath 適用) + timeout wrap (120s)."""
        return json.dumps(twl_worktree_delete_handler(branch=branch, repo_path=repo_path, cwd=cwd, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_worktree_list(repo_path: str | None = None) -> str:  # type: ignore[misc]
        """autopilot.worktree: WorktreeManager.list_porcelain() (新規追加 method) - read-only list[dict] return."""
        return json.dumps(twl_worktree_list_handler(repo_path=repo_path), ensure_ascii=False)

    def twl_worktree_generate_branch_name(issue_number: str, repo: str | None = None, timeout_sec: int = 60) -> str:  # type: ignore[misc]
        """autopilot.worktree: pure generate_branch_name(issue_number: str, ...) with gh issue view subprocess (timeout 60s)."""
        return json.dumps(twl_worktree_generate_branch_name_handler(issue_number=issue_number, repo=repo, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_worktree_validate_branch_name(branch: str) -> str:  # type: ignore[misc]
        """autopilot.worktree: pure validate_branch_name() (read-only, raises WorktreeArgError)."""
        return json.dumps(twl_worktree_validate_branch_name_handler(branch=branch), ensure_ascii=False)
