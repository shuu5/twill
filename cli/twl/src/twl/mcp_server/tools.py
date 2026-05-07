"""twl MCP tool definitions (Phase 0 PoC + autopilot Phase 2).

Exposes twl_validate / twl_audit / twl_check / twl_state_read / twl_state_write
+ 12 autopilot tools as FastMCP tools.
Handler functions (_handler suffix) are pure Python for in-process testing.
"""
import concurrent.futures
import json
import os
import re
from pathlib import Path
from typing import Any, TypedDict


def _load_plugin_ctx(plugin_root: str) -> "tuple[Path, dict, dict, str]":
    from twl.core.plugin import load_deps, build_graph, get_plugin_name
    # Resolve to absolute path to prevent path traversal
    p = Path(plugin_root).expanduser().resolve()
    # Accept file path (e.g. deps.yaml) and derive plugin root from parent dir
    if p.is_file():
        p = p.parent
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


# Phase γ Wave 2-B: Session aggregate view TypedDict (AC3-11)

class SessionAggregateView(TypedDict, total=False):
    """Aggregate view of autopilot session for observer/supervisor consumption.

    Required keys (ok=True path always present):
      session, active_issues, current_phase, phase_count, cross_issue_warnings,
      pending_checkpoints, wave_summaries_count, resolved_session_id, autopilot_dir,
      is_archived
    Error keys (ok=False path):
      ok, error, error_type, exit_code
    """
    # --- ok=True keys ---
    session: dict[str, Any]
    active_issues: list[dict[str, Any]]
    current_phase: int
    phase_count: int
    cross_issue_warnings: list[dict[str, Any]]
    pending_checkpoints: list[dict[str, Any]]
    wave_summaries_count: int
    resolved_session_id: str
    autopilot_dir: str
    is_archived: bool
    # --- ok=False keys ---
    ok: bool
    error: str
    error_type: str
    exit_code: int


# SESSION_STATE_SCRIPT path resolution — env var override for testing
_DEFAULT_SCRIPT = (
    Path(__file__).resolve().parent.parent.parent.parent.parent
    / "plugins" / "session" / "scripts" / "session-state.sh"
)
# SESSION_STATE_SCRIPT env var で実行時上書き可能。テスト時は monkeypatch で設定。

_VALID_SESSION_ID_RE = re.compile(r"^[a-zA-Z0-9]+\Z")  # \Z は絶対末尾、$ より厳密（改行を許容しない）
_VALID_WINDOW_NAME_RE = re.compile(r"^[A-Za-z0-9_./:@-]+\Z")
_VALID_MANIFEST_CTX_RE = re.compile(r"^[a-zA-Z0-9_-]+\Z")
_REQUIRED_CHECKPOINT_FIELDS = frozenset(
    {"step", "status", "findings_summary", "critical_count", "findings", "timestamp"}
)


def _resolve_autopilot_dir(autopilot_dir: str | None) -> Path:
    """Resolve autopilot_dir from arg or AUTOPILOT_DIR env var or git root."""
    if autopilot_dir:
        return Path(autopilot_dir).expanduser().resolve()
    env = os.environ.get("AUTOPILOT_DIR", "")
    if env:
        return Path(env).expanduser().resolve()
    try:
        import subprocess  # noqa: PLC0415
        root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL, text=True,
        ).strip()
        return Path(root) / ".autopilot"
    except Exception:
        return Path.cwd() / ".autopilot"


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
# Phase γ Wave 2-B: Session aggregate handlers (AC3-11, Issue #1113)
# Issue #1514: twl_get_session_state subcommand extension (session-state.sh wrapper)
# ---------------------------------------------------------------------------


def _session_state_subcommand_handler(
    subcommand: str,
    window_name: str | None,
    target_state: str | None,
    timeout: int,
    json_output: bool,
) -> dict:
    """Route state/list/wait subcommands to session-state.sh (AC2, AC3, AC5-AC7)."""
    import subprocess  # noqa: PLC0415

    shadow = os.environ.get("TWL_SHADOW_MODE") == "1"

    _valid_subcommands = {"state", "list", "wait"}
    if subcommand not in _valid_subcommands:
        result: dict = {
            "ok": False,
            "error": f"invalid subcommand '{subcommand}': must be one of {sorted(_valid_subcommands)}",
            "error_type": "invalid_subcommand",
            "exit_code": 2,
            "state": None,
            "details": None,
        }
        if shadow:
            result["shadow"] = True
        return result

    script_path = Path(os.environ.get("SESSION_STATE_SCRIPT", str(_DEFAULT_SCRIPT)))
    if not script_path.exists():
        result = {
            "ok": False,
            "error": f"session-state.sh not found: {script_path}",
            "error_type": "script_not_found",
            "exit_code": 2,
            "state": None,
            "details": None,
        }
        if shadow:
            result["shadow"] = True
        return result

    cmd = [str(script_path), subcommand]
    if subcommand == "state":
        if window_name:
            cmd.append(window_name)
    elif subcommand == "list":
        if json_output:
            cmd.append("--json")
    elif subcommand == "wait":
        if window_name:
            cmd.append(window_name)
        if target_state:
            cmd.append(target_state)
        cmd.extend(["--timeout", str(timeout)])

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        result = {
            "ok": False,
            "error": "timeout",
            "error_type": "timeout",
            "exit_code": 124,
            "state": None,
            "details": None,
        }
        if shadow:
            result["shadow"] = True
        return result
    except (OSError, FileNotFoundError) as e:
        result = {
            "ok": False,
            "error": str(e),
            "error_type": "script_not_found",
            "exit_code": 2,
            "state": None,
            "details": None,
        }
        if shadow:
            result["shadow"] = True
        return result

    if proc.returncode != 0:
        result = {
            "ok": False,
            "error": proc.stderr.strip() or f"exit code {proc.returncode}",
            "error_type": "shell_error",
            "exit_code": proc.returncode,
            "state": None,
            "details": None,
        }
        if shadow:
            result["shadow"] = True
        return result

    output = proc.stdout.strip()

    if subcommand == "state":
        _valid_states = {"idle", "input-waiting", "processing", "error", "exited"}
        state = output
        if state not in _valid_states:
            result = {
                "ok": False,
                "error": f"unknown state: '{state}'",
                "error_type": "unknown_state",
                "exit_code": 3,
                "state": None,
                "details": output,
            }
        else:
            result = {
                "ok": True,
                "state": state,
                "details": None,
                "error": None,
                "exit_code": 0,
            }
    elif subcommand == "list":
        if json_output:
            try:
                windows = json.loads(output) if output else []
            except json.JSONDecodeError:
                windows = []
            result = {
                "ok": True,
                "windows": windows,
                "details": None,
                "error": None,
                "exit_code": 0,
            }
        else:
            result = {
                "ok": True,
                "output": output,
                "details": None,
                "error": None,
                "exit_code": 0,
            }
    else:  # wait
        result = {
            "ok": True,
            "state": target_state,
            "details": output or None,
            "error": None,
            "exit_code": 0,
        }

    if shadow:
        result["shadow"] = True
    return result


def twl_get_session_state_handler(
    session_id: str | None = None,
    autopilot_dir: str | None = None,
    subcommand: str | None = None,
    window_name: str | None = None,
    target_state: str | None = None,
    timeout: int = 30,
    json_output: bool = False,
) -> dict:
    """Return aggregate view of autopilot session, or tmux pane state via session-state.sh.

    subcommand=None (default): autopilot aggregate view (backward compatible).
    subcommand="state": session-state.sh state <window_name> -> {ok, state, details, error}.
    subcommand="list": session-state.sh list [--json] -> {ok, windows|output, error}.
    subcommand="wait": session-state.sh wait <window_name> <target_state> [--timeout N].

    Session-state.sh path: SESSION_STATE_SCRIPT env var (default: plugins/session/scripts/session-state.sh).
    Shadow mode: TWL_SHADOW_MODE=1 adds shadow=True to response.
    """
    if subcommand is not None:
        return _session_state_subcommand_handler(
            subcommand=subcommand,
            window_name=window_name,
            target_state=target_state,
            timeout=timeout,
            json_output=json_output,
        )

    # --- backward-compatible autopilot aggregate view ---
    ap_dir = _resolve_autopilot_dir(autopilot_dir)

    if session_id is None:
        # active session path
        session_path = ap_dir / "session.json"
        is_archived = False
        resolved_session_id = ""
    else:
        # session_id バリデーション — パストラバーサル防止 (AC3-12 / security)
        if not isinstance(session_id, str) or not _VALID_SESSION_ID_RE.match(session_id):
            return {
                "ok": False,
                "error": f"invalid session_id '{session_id}': must match ^[a-zA-Z0-9]+$",
                "error_type": "invalid_session_id",
                "exit_code": 2,
            }
        archive_base = (ap_dir / "archive" / session_id).resolve()
        # resolve() 後に ap_dir 配下であることを確認（パストラバーサル防止）
        try:
            archive_base.relative_to(ap_dir.resolve())
        except ValueError:
            return {
                "ok": False,
                "error": f"invalid session_id '{session_id}': path traversal detected",
                "error_type": "invalid_session_id",
                "exit_code": 2,
            }
        session_path = archive_base / "session.json"
        if not session_path.exists():
            return {
                "ok": False,
                "error": f"archive session not found: {session_path}",
                "error_type": "archive_not_found",
                "exit_code": 2,
            }
        is_archived = True
        resolved_session_id = session_id

    # read session.json
    try:
        session_data = json.loads(session_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {
            "ok": False,
            "error": f"session.json not found: {session_path}",
            "error_type": "session_not_found",
            "exit_code": 1,
        }
    except json.JSONDecodeError as e:
        return {
            "ok": False,
            "error": f"session.json parse error: {e}",
            "error_type": "json_error",
            "exit_code": 1,
        }

    if not resolved_session_id:
        resolved_session_id = session_data.get("session_id", "")

    # aggregate: active_issues (status != "done")
    active_issues: list[dict] = []
    issues_dir = ap_dir / "issues"
    if issues_dir.is_dir():
        for issue_file in sorted(issues_dir.glob("issue-*.json")):
            try:
                issue_data = json.loads(issue_file.read_text(encoding="utf-8"))
                if issue_data.get("status") != "done":
                    active_issues.append(issue_data)
            except (json.JSONDecodeError, OSError):
                pass

    # aggregate: pending_checkpoints (status == "FAIL")
    pending_checkpoints: list[dict] = []
    checkpoints_dir = ap_dir / "checkpoints"
    if checkpoints_dir.is_dir():
        for cp_file in sorted(checkpoints_dir.glob("*.json")):
            try:
                cp_data = json.loads(cp_file.read_text(encoding="utf-8"))
                if cp_data.get("status") == "FAIL":
                    pending_checkpoints.append(cp_data)
            except (json.JSONDecodeError, OSError):
                pass

    # aggregate: wave_summaries_count
    waves_dir = ap_dir / "waves"
    wave_summaries_count = len(list(waves_dir.glob("*.summary.md"))) if waves_dir.is_dir() else 0

    return {
        "ok": True,
        "session": session_data,
        "active_issues": active_issues,
        "current_phase": session_data.get("current_phase", 0),
        "phase_count": session_data.get("phase_count", 0),
        "cross_issue_warnings": session_data.get("cross_issue_warnings", []),
        "pending_checkpoints": pending_checkpoints,
        "wave_summaries_count": wave_summaries_count,
        "resolved_session_id": resolved_session_id,
        "autopilot_dir": str(ap_dir),
        "is_archived": is_archived,
    }


def twl_get_pane_state_handler(
    window_name: str,
    timeout_sec: int = 30,
) -> dict:
    """Return tmux pane/window state. window_name: tmux window name or session:index form."""
    import subprocess  # noqa: PLC0415

    # validate window_name — return error dict (defense in depth, no subprocess injection)
    if not _VALID_WINDOW_NAME_RE.match(window_name):
        return {
            "ok": False,
            "error": f"Invalid window_name '{window_name}': must match [A-Za-z0-9_./:@-]+",
            "error_type": "invalid_window_name",
            "exit_code": 2,
        }

    # SESSION_STATE_SCRIPT: env var が設定されていれば優先（テスト用上書き対応）
    script_path = Path(os.environ.get("SESSION_STATE_SCRIPT", str(_DEFAULT_SCRIPT)))
    if not script_path.exists():
        return {
            "ok": False,
            "error": f"session-state.sh not found: {script_path}",
            "error_type": "script_not_found",
            "exit_code": 2,
        }

    valid_states = {"exited", "idle", "processing", "input-waiting", "error"}

    try:
        result = subprocess.run(
            [str(script_path), window_name],
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "error": "timeout",
            "error_type": "timeout",
            "exit_code": 124,
        }
    except (OSError, FileNotFoundError) as e:
        return {
            "ok": False,
            "error": str(e),
            "error_type": "script_not_found",
            "exit_code": 2,
        }

    if result.returncode != 0:
        return {
            "ok": False,
            "error": result.stderr.strip() or f"exit code {result.returncode}",
            "error_type": "shell_error",
            "exit_code": result.returncode,
        }

    state = result.stdout.strip()
    if state not in valid_states:
        return {
            "ok": False,
            "error": f"unknown state: '{state}'",
            "error_type": "unknown_state",
            "exit_code": 3,
        }

    return {
        "ok": True,
        "state": state,
        "exit_code": 0,
    }


def twl_capture_pane_handler(
    window_name: str,
    lines: int | None = None,
    mode: str = "raw",
    from_line: int | None = None,
    to_line: int | None = None,
) -> dict:
    """Capture tmux pane/window content as raw or plain text. AC4: content retrieval only."""
    import subprocess  # noqa: PLC0415
    import re as _re  # noqa: PLC0415

    if not _VALID_WINDOW_NAME_RE.match(window_name):
        return {
            "ok": False,
            "error": f"Invalid window_name '{window_name}': must match [A-Za-z0-9_./:@-]+",
            "error_type": "invalid_window_name",
        }

    if mode not in ("raw", "plain"):
        return {
            "ok": False,
            "error": f"Invalid mode '{mode}': must be 'raw' or 'plain'",
            "error_type": "invalid_mode",
        }

    cmd = ["tmux", "capture-pane", "-t", window_name, "-p"]
    if mode == "raw":
        cmd.append("-e")
    if from_line is not None:
        cmd.extend(["-S", str(from_line)])
    elif lines is not None:
        cmd.extend(["-S", str(-lines)])
    if to_line is not None:
        cmd.extend(["-E", str(to_line)])

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "timeout", "error_type": "timeout"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc), "error_type": "error"}

    if proc.returncode != 0:
        return {
            "ok": False,
            "error": proc.stderr.strip() or f"exit code {proc.returncode}",
            "error_type": "shell_error",
        }

    content = proc.stdout
    ansi_stripped = False
    if mode == "plain":
        ansi_escape = _re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
        content = ansi_escape.sub("", content)
        ansi_stripped = True

    return {
        "ok": True,
        "content": content,
        "ansi_stripped": ansi_stripped,
        "lines": len(content.splitlines()),
    }


def twl_list_windows_handler(
    session: str | None = None,
    format: str = "minimal",
) -> dict:
    """List tmux windows/sessions as structured JSON.

    AC1: handler 追加 (twl_capture_pane_handler と並列配置).
    AC2: 引数 {session?, format?: 'minimal'|'detailed'}.
    AC3: 戻り値 {ok, windows: [{name, index, session, active, panes_count, ...}], error}.
    AC4: tmux list-sessions と list-windows -F 両方サポート (session=None で全 session 横断).
    AC5-7: shadow mode rollout / AT 非依存性 / short-lived 設計 (subprocess timeout=10s).

    Issue #1513 SUB-5 handler 本体補完 (Wave 71 PR #1534 が test scaffold のみだった補完、observer 直接 implement、Issue #1535 関連)。
    """
    import subprocess  # noqa: PLC0415

    if format not in ("minimal", "detailed"):
        return {
            "ok": False,
            "error": f"Invalid format '{format}': must be 'minimal' or 'detailed'",
            "error_type": "invalid_format",
            "windows": [],
        }

    if session is not None and not _VALID_WINDOW_NAME_RE.match(session):
        return {
            "ok": False,
            "error": f"Invalid session name '{session}': must match [A-Za-z0-9_./:@-]+",
            "error_type": "invalid_session",
            "windows": [],
        }

    if session is None:
        cmd = ["tmux", "list-windows", "-a"]
    else:
        cmd = ["tmux", "list-windows", "-t", session]

    if format == "detailed":
        cmd.extend(["-F", "#{session_name}|#{window_index}|#{window_name}|#{window_active}|#{window_panes}"])
    else:
        cmd.extend(["-F", "#{session_name}|#{window_index}|#{window_name}"])

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "timeout", "error_type": "timeout", "windows": []}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc), "error_type": "error", "windows": []}

    if proc.returncode != 0:
        return {
            "ok": False,
            "error": proc.stderr.strip() or f"exit code {proc.returncode}",
            "error_type": "shell_error",
            "windows": [],
        }

    windows: list[dict] = []
    for line in proc.stdout.strip().split("\n"):
        if not line:
            continue
        parts = line.split("|")
        entry: dict = {
            "session": parts[0] if len(parts) > 0 else "",
            "index": int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0,
            "name": parts[2] if len(parts) > 2 else "",
        }
        if format == "detailed":
            entry["active"] = parts[3] == "1" if len(parts) > 3 else False
            entry["panes_count"] = int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else 0
        windows.append(entry)

    return {"ok": True, "windows": windows, "error": None}


# Issue #1515: SUB-7 — budget capture + regex extraction + format spec
_BUDGET_PCT_RE = re.compile(r'5h:(\d+)%\(([^)]+)\)')
_BUDGET_RAW_UNIT_RE = re.compile(r'^(?:(\d+)h)?(?:(\d+)m)?$')


def _parse_budget_raw_to_min(raw: str) -> int:
    """Parse '83m', '1h21m', '2h' → minutes. Returns -1 on parse failure."""
    m = _BUDGET_RAW_UNIT_RE.match(raw.strip())
    if not m:
        return -1
    h = int(m.group(1) or 0)
    mins = int(m.group(2) or 0)
    return h * 60 + mins


def twl_get_budget_handler(
    window_name: str,
    threshold_remaining_minutes: int = 40,
    threshold_cycle_minutes: int = 5,
    config_path: str | None = None,
) -> dict:
    """Capture tmux pane and extract budget info via 5h:%(Ym) regex.

    AC1: handler 追加。AC2: 引数 {window_name, threshold_remaining_minutes?,
    threshold_cycle_minutes?, config_path?}。AC3: 戻り値 {ok, budget_pct,
    budget_min, cycle_reset_min, low: bool, error}。AC5: format mismatch →
    low=True, error="format-mismatch"。AC7: subprocess mock 可能。AC8: timeout=10s。
    """
    import subprocess  # noqa: PLC0415

    cmd = ["tmux", "capture-pane", "-t", window_name, "-p", "-S", "-1"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        return {"ok": False, "budget_pct": None, "budget_min": None,
                "cycle_reset_min": None, "low": True, "error": "timeout"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "budget_pct": None, "budget_min": None,
                "cycle_reset_min": None, "low": True, "error": str(exc)}

    if proc.returncode != 0:
        return {"ok": False, "budget_pct": None, "budget_min": None,
                "cycle_reset_min": None, "low": True,
                "error": proc.stderr.strip() or f"exit code {proc.returncode}"}

    pane_text = proc.stdout

    # load threshold overrides from config_path if provided
    config_error: str | None = None
    if config_path:
        try:
            resolved = Path(config_path).expanduser().resolve()
            # prevent path traversal — only allow .json files under CWD or home
            cwd = Path.cwd().resolve()
            home = Path.home().resolve()
            if not (str(resolved).startswith(str(cwd)) or str(resolved).startswith(str(home))):
                raise ValueError(f"config_path outside allowed directories: {resolved}")
            cfg = json.loads(resolved.read_text(encoding="utf-8"))
            threshold_remaining_minutes = int(
                cfg.get("threshold_remaining_minutes", threshold_remaining_minutes)
            )
            threshold_cycle_minutes = int(
                cfg.get("threshold_cycle_minutes", threshold_cycle_minutes)
            )
        except Exception as _cfg_exc:  # noqa: BLE001
            config_error = str(_cfg_exc)

    m = _BUDGET_PCT_RE.search(pane_text)
    if not m:
        return {"ok": True, "budget_pct": None, "budget_min": None,
                "cycle_reset_min": None, "low": True, "error": "format-mismatch"}

    budget_pct = int(m.group(1))
    cycle_reset_min = _parse_budget_raw_to_min(m.group(2))
    budget_min = 300 * (100 - budget_pct) // 100

    low = False
    if budget_min >= 0 and budget_min <= threshold_remaining_minutes:
        low = True
    if cycle_reset_min >= 0 and cycle_reset_min <= threshold_cycle_minutes:
        low = True

    return {
        "ok": True,
        "budget_pct": budget_pct,
        "budget_min": budget_min,
        "cycle_reset_min": cycle_reset_min,
        "low": low,
        "error": config_error,
    }


def twl_audit_session_handler(
    autopilot_dir: str | None = None,
) -> dict:
    """Audit autopilot session.json for structural integrity (R1-R4 rules). Idempotent."""
    ap_dir = _resolve_autopilot_dir(autopilot_dir)
    items: list[dict] = []

    # read session.json
    session_path = ap_dir / "session.json"
    session_data: dict = {}
    if session_path.exists():
        try:
            session_data = json.loads(session_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            items.append({
                "severity": "critical",
                "code": "R0",
                "message": f"session.json parse error: {e}",
            })
    else:
        items.append({
            "severity": "warning",
            "code": "R0",
            "message": f"session.json not found: {session_path}",
        })

    if session_data:
        # R1: session_id must match ^[a-zA-Z0-9]+\Z
        session_id = session_data.get("session_id", "")
        if not session_id or not _VALID_SESSION_ID_RE.match(session_id):
            items.append({
                "severity": "critical",
                "code": "R1",
                "message": f"session_id invalid (must be alphanumeric): '{session_id}'",
            })

        # R2: plan_path must exist
        plan_path_str = session_data.get("plan_path", "")
        if plan_path_str and not Path(plan_path_str).exists():
            items.append({
                "severity": "warning",
                "code": "R2",
                "message": f"plan_path does not exist: '{plan_path_str}'",
            })

    # R3: checkpoints/*.json structure — warning
    checkpoints_dir = ap_dir / "checkpoints"
    if checkpoints_dir.is_dir():
        for cp_file in sorted(checkpoints_dir.glob("*.json")):
            try:
                cp_data = json.loads(cp_file.read_text(encoding="utf-8"))
                missing_fields = _REQUIRED_CHECKPOINT_FIELDS - set(cp_data.keys())
                if missing_fields:
                    items.append({
                        "severity": "warning",
                        "code": "R3",
                        "message": f"checkpoint '{cp_file.name}' missing fields: {sorted(missing_fields)}",
                    })
            except json.JSONDecodeError as e:
                items.append({
                    "severity": "warning",
                    "code": "R3",
                    "message": f"checkpoint '{cp_file.name}' parse error: {e}",
                })

    # R4: wave summaries — info only (N.summary.md files)
    waves_dir = ap_dir / "waves"
    if waves_dir.is_dir():
        wave_count = len(list(waves_dir.glob("*.summary.md")))
        if wave_count > 0:
            items.append({
                "severity": "info",
                "code": "R4",
                "message": f"{wave_count} wave summary file(s) found",
            })

    has_critical = any(i.get("severity") == "critical" for i in items)
    exit_code = 1 if has_critical else 0

    return {
        "items": items,
        "exit_code": exit_code,
    }


# ---------------------------------------------------------------------------
# Phase 2: Autopilot handlers (ADR-029 Decision 2, Hybrid Path 5 原則)
# ---------------------------------------------------------------------------

# --- Mergegate ---

def _resolve_issue_from_labels(labels: list[dict]) -> str | None:
    """Extract issue number from PR labels (autopilot label convention: 'issue-N')."""
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

        import twl.autopilot.mergegate as _mergegate_mod
        import twl.autopilot.mergegate_guards as _mgguards
        ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
        try:
            mg = _mergegate_mod.MergeGate(
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
        except _mgguards.MergeGateError as e:
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
    violation = _check_invariant_b(cwd)
    if violation:
        return violation
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

        import twl.autopilot.mergegate as _mergegate_mod
        import twl.autopilot.mergegate_guards as _mgguards
        ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
        try:
            mg = _mergegate_mod.MergeGate(
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
        except _mgguards.MergeGateError as e:
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
    violation = _check_invariant_b(cwd)
    if violation:
        return violation
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

        import twl.autopilot.mergegate as _mergegate_mod
        import twl.autopilot.mergegate_guards as _mgguards
        ap_dir = Path(autopilot_dir).expanduser().resolve() if autopilot_dir else None
        try:
            mg = _mergegate_mod.MergeGate(
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
        except _mgguards.MergeGateError as e:
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
    timeout_sec: int = 1800,
    cwd: str | None = None,
) -> dict:
    """autopilot.orchestrator: invoke PhaseOrchestrator.run() with handler-level timeout wrap (1800s wall-clock guard for tmux + state.py subprocess). Note: set MCP_CLIENT_TIMEOUT>=1860s. plan_file existence check + tmux FileNotFoundError catch."""
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


# ---------------------------------------------------------------------------
# Issue #1224: 5 validation tool handlers
# ---------------------------------------------------------------------------


def twl_validate_deps_handler(plugin_root: str) -> dict:
    """validation module: deps.yaml syntax validation for plugin structure."""
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
    return build_envelope("validate_deps", get_deps_version(deps), plugin_name, items, exit_code)


def twl_validate_merge_handler(
    branch: str,
    base: str = "main",
    timeout_sec: int | None = 300,
) -> dict:
    """validation module: merge pre-flight guard (2-guard scope only)."""
    if timeout_sec is not None and timeout_sec <= 0:
        return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}

    def _inner() -> dict:
        import twl.autopilot.mergegate_guards as _mgguards2
        cwd = os.getcwd()
        try:
            _mgguards2._check_worktree_guard(cwd)
            _mgguards2._check_worker_window_guard()
            return {
                "ok": True,
                "branch": branch,
                "base": base,
                "exit_code": 0,
                "summary": "merge pre-flight guards passed",
            }
        except _mgguards2.MergeGateError as e:
            return {"ok": False, "error": str(e), "error_type": "merge_guard_error", "exit_code": 1}
        except Exception as e:
            return {"ok": False, "error": str(e), "error_type": "error", "exit_code": 1}

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


def extract_commit_message_from_command(command: str) -> str:
    """Extract commit message body from a git commit command string.

    Handles -m/--message flags (with and without =); returns "" for -F (file-based) or unrecognized forms.
    """
    import shlex

    try:
        parts = shlex.split(command)
    except ValueError:
        return ""

    i = 0
    while i < len(parts):
        token = parts[i]
        if token in ("-m", "--message") and i + 1 < len(parts):
            return parts[i + 1]
        # --message=value form
        if token.startswith("--message="):
            return token[len("--message="):]
        # -m"message" without space (e.g. -m"feat: X")
        if token.startswith("-m") and len(token) > 2:
            return token[2:]
        i += 1
    return ""


def twl_validate_commit_handler(
    command: str,
    files: list[str],
    timeout_sec: int | None = 300,
) -> dict:
    """validation module: commit message and file deps validation (in-process, no subprocess).

    現状: Claude Code の PreToolUse hook では tool_input から staged files リストを取得する
    仕組みがない（hook 仕様制約）。そのため settings.json の files フィールドは常に空リスト
    で呼び出され、このハンドラは files 空リストにより実質 no-op となる。
    deps.yaml validation の実体は pre-bash-commit-validate.sh (bash hook) が担当する。
    代替: pre-bash-commit-validate.sh (bash hook) が deps.yaml validation を担当。
    MCP hook は記録専用（shadow mode）として位置づける。
    # TODO: Claude Code hook 仕様拡張時に再検討 — staged files が取得可能になった場合に
    #       files パラメータを実活用できる。Issue #1335 参照（self-deferred）。
    """
    if timeout_sec is not None and timeout_sec <= 0:
        return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}

    _message = extract_commit_message_from_command(command)

    def _inner() -> dict:
        from twl.validation.validate import validate_v3_schema
        import yaml
        all_violations: list[str] = []
        for f in files:
            p = Path(f).expanduser().resolve()
            if not p.exists() or p.name != "deps.yaml":
                continue
            try:
                deps = yaml.safe_load(p.read_text())
                if isinstance(deps, dict):
                    _, v3_violations = validate_v3_schema(deps)
                    all_violations.extend(v3_violations)
            except Exception as e:
                all_violations.append(f"parse error in {f}: {e}")
        ok = len(all_violations) == 0
        return {
            "ok": ok,
            "items": all_violations,
            "exit_code": 0 if ok else 1,
            "summary": f"{len(all_violations)} violation(s) found",
            "commit_message": _message,
        }

    if timeout_sec is None:
        return _inner()
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(_inner)
        try:
            return future.result(timeout=timeout_sec)
        except concurrent.futures.TimeoutError:
            return {"ok": False, "error": "timeout", "error_type": "timeout", "exit_code": 124}


def twl_check_completeness_handler(manifest_context: str) -> dict:
    """validation module: specialist completeness check via flock-guarded manifest files."""
    import fcntl

    if not manifest_context or not _VALID_MANIFEST_CTX_RE.match(manifest_context):
        return {"ok": False, "error": f"invalid manifest_context: {manifest_context!r}", "error_type": "arg_error", "exit_code": 2}

    expected_path = Path(f"/tmp/.specialist-manifest-{manifest_context}.txt")
    actual_path = Path(f"/tmp/.specialist-spawned-{manifest_context}.txt")

    def _read_locked(path: Path) -> list[str]:
        if not path.exists():
            return []
        with path.open("r") as fd:
            fcntl.flock(fd, fcntl.LOCK_SH)
            try:
                return [line.strip() for line in fd.readlines() if line.strip()]
            finally:
                fcntl.flock(fd, fcntl.LOCK_UN)

    expected = _read_locked(expected_path)
    actual = set(_read_locked(actual_path))
    missing = [name for name in expected if name not in actual]
    ok = len(missing) == 0
    return {
        "ok": ok,
        "items": missing,
        "exit_code": 0 if ok else 1,
        "summary": f"{len(missing)} specialist(s) missing",
    }


def twl_check_specialist_handler(manifest_context: str) -> dict:
    """Shadow mode: check specialist spawn completeness vs bash hook. Logs to shadow log when manifest file exists; returns stub envelope silently when manifest is absent (no runtime state to check)."""
    import glob
    import time
    from pathlib import Path

    SHADOW_LOG = Path("/tmp/mcp-shadow-specialist-completeness.log")
    _MANIFEST_GLOB = "/tmp/.specialist-manifest-*.txt"
    _CTX_RE = re.compile(r"^[a-zA-Z0-9_-]+$")

    def _check_context(ctx: str) -> list[str]:
        manifest_file = Path(f"/tmp/.specialist-manifest-{ctx}.txt")
        spawned_file = Path(f"/tmp/.specialist-spawned-{ctx}.txt")
        if not manifest_file.exists() or manifest_file.is_symlink():
            return []
        try:
            lines = manifest_file.read_text().splitlines()
        except Exception:
            return []
        expected = [
            ln.strip().removeprefix("twl:twl:")
            for ln in lines
            if ln.strip() and not ln.startswith("#") and re.match(r"^[a-zA-Z0-9:_-]+$", ln.strip())
        ]
        if not expected:
            return []
        spawned: set[str] = set()
        if spawned_file.exists() and not spawned_file.is_symlink():
            try:
                spawned = {l.strip() for l in spawned_file.read_text().splitlines() if l.strip()}
            except Exception:
                pass
        return [e for e in expected if e not in spawned]

    missing_by_ctx: dict[str, list[str]] = {}
    ctx_path = Path(manifest_context) if manifest_context else None

    if ctx_path and ctx_path.is_dir():
        # Directory mode (test fixtures): no runtime spawn state → return ok
        pass
    elif manifest_context and _CTX_RE.match(manifest_context):
        # Context-specific mode: check that context; fall back to scan-all if file absent
        specific = Path(f"/tmp/.specialist-manifest-{manifest_context}.txt")
        if specific.exists() and not specific.is_symlink():
            m = _check_context(manifest_context)
            if m:
                missing_by_ctx[manifest_context] = m
        else:
            # File not found for this context → stub envelope (R2-m2: no runtime state to check)
            return {
                "ok": True,
                "items": [],
                "exit_code": 0,
                "summary": "stub",
            }

    all_missing = [item for items in missing_by_ctx.values() for item in items]
    ok = len(all_missing) == 0
    verdict = "ok" if ok else "warn"

    event_id = f"specialist-check-{int(time.time() * 1000)}"
    log_entry = json.dumps({
        "event_id": event_id,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": "mcp_tool",
        "verdict": verdict,
        "tool_name": "Stop",
        "file_path": "specialist-completeness",
        "manifest_context": manifest_context,
    }, ensure_ascii=False)
    try:
        with open(str(SHADOW_LOG), "a") as f:
            f.write(log_entry + "\n")
    except Exception:
        pass

    return {
        "ok": ok,
        "items": all_missing,
        "exit_code": 0 if ok else 1,
        "summary": f"{len(all_missing)} specialist(s) missing" if all_missing else "all specialists present",
    }


# --- spawn_session (Issue #1510) ---

_CLD_SPAWN_SCRIPT = (
    Path(__file__).resolve().parent.parent.parent.parent.parent
    / "plugins" / "session" / "scripts" / "cld-spawn"
)
_SPAWN_SHADOW_LOG = Path("/tmp/mcp-shadow-spawn.log")

# --- spawn_controller (Issue #1511) ---

_SPAWN_CONTROLLER_SCRIPT = (
    Path(__file__).resolve().parent.parent.parent.parent.parent
    / "plugins" / "twl" / "skills" / "su-observer" / "scripts" / "spawn-controller.sh"
)
_SPAWN_CONTROLLER_SHADOW_LOG = Path("/tmp/mcp-shadow-spawn-controller.log")

_VALID_CONTROLLER_SKILLS = [
    "co-explore",
    "co-issue",
    "co-architect",
    "co-autopilot",
    "co-project",
    "co-utility",
    "co-self-improve",
]


def twl_spawn_session_handler(
    prompt: str,
    cwd: str | None = None,
    env_file: str | None = None,
    window_name: str | None = None,
    timeout: int | None = 120,
    model: str | None = None,
    force_new: bool = False,
) -> dict:
    """Start a new cld session in a tmux window via cld-spawn.

    AC7: fire-and-forget — cld-spawn launches the tmux window and returns immediately;
    the Claude Code session runs independently (no blocking wait).
    Returns {ok, session, window, pid, error}.
    """
    import subprocess  # noqa: PLC0415
    import time  # noqa: PLC0415

    script = Path(os.environ.get("CLD_SPAWN_SCRIPT", str(_CLD_SPAWN_SCRIPT)))
    if not script.exists():
        return {"ok": False, "session": None, "window": None, "pid": None, "error": f"cld-spawn script not found: {script}"}

    if window_name and not _VALID_WINDOW_NAME_RE.match(window_name):
        return {"ok": False, "session": None, "window": None, "pid": None, "error": f"window_name contains invalid characters: {window_name!r}"}

    cmd: list[str] = ["bash", str(script)]
    if cwd:
        cmd += ["--cd", cwd]
    if env_file:
        cmd += ["--env-file", env_file]
    if window_name:
        cmd += ["--window-name", window_name]
    if timeout is not None:
        cmd += ["--timeout", str(timeout)]
    if model:
        cmd += ["--model", model]
    if force_new:
        cmd.append("--force-new")
    if prompt:
        cmd.append(prompt)

    run_timeout = (timeout or 120) + 30  # extra headroom beyond inject timeout

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=run_timeout,
        )
    except FileNotFoundError as exc:
        _spawn_shadow_log({"ok": False, "exit_code": -1, "stderr": str(exc), "cmd": cmd})
        return {"ok": False, "session": None, "window": None, "pid": None, "error": str(exc)}
    except subprocess.TimeoutExpired as exc:
        _spawn_shadow_log({"ok": False, "exit_code": -2, "stderr": "timeout", "cmd": cmd})
        return {"ok": False, "session": None, "window": None, "pid": None, "error": f"cld-spawn timed out after {run_timeout}s"}
    except Exception as exc:
        _spawn_shadow_log({"ok": False, "exit_code": -3, "stderr": str(exc), "cmd": cmd})
        return {"ok": False, "session": None, "window": None, "pid": None, "error": str(exc)}

    ok = result.returncode == 0
    _spawn_shadow_log({
        "ok": ok,
        "exit_code": result.returncode,
        "stderr": result.stderr,
        "stdout": result.stdout,
        "cmd": cmd,
    })

    if not ok:
        return {
            "ok": False,
            "session": None,
            "window": None,
            "pid": None,
            "error": result.stderr.strip() or f"cld-spawn exited {result.returncode}",
        }

    # Parse window name from stdout "spawned → tmux window 'NAME'" or "reusing existing window: NAME (...)"
    parsed_window = _parse_spawn_window(result.stdout)

    # Try to get tmux window PID (best-effort)
    pid = _get_window_pid(parsed_window) if parsed_window else None

    # Get current tmux session name (best-effort)
    try:
        session_name = subprocess.check_output(
            ["tmux", "display-message", "-p", "#{session_name}"],
            text=True, timeout=5, stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        session_name = None

    return {
        "ok": True,
        "session": session_name,
        "window": parsed_window,
        "pid": pid,
        "error": None,
    }


def _spawn_shadow_log(entry: dict) -> None:
    import time  # noqa: PLC0415
    record = json.dumps({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tool": "twl_spawn_session",
        **{k: v for k, v in entry.items() if k != "cmd"},
    }, ensure_ascii=False)
    try:
        with open(str(_SPAWN_SHADOW_LOG), "a") as f:
            f.write(record + "\n")
    except Exception:
        pass


def _parse_spawn_window(stdout: str) -> str | None:
    import re  # noqa: PLC0415
    for line in stdout.splitlines():
        m = re.search(r"spawned → tmux window '([^']+)'", line)
        if m:
            return m.group(1)
        m = re.search(r"prompt injected → '([^']+)'", line)
        if m:
            return m.group(1)
        m = re.search(r"reusing existing window: (\S+)", line)
        if m:
            return m.group(1).split()[0]
    return None


def _get_window_pid(window_name: str | None) -> int | None:
    if not window_name:
        return None
    if not _VALID_WINDOW_NAME_RE.match(window_name):
        return None
    import subprocess  # noqa: PLC0415
    try:
        out = subprocess.check_output(
            ["tmux", "list-panes", "-t", window_name, "-F", "#{pane_pid}"],
            text=True, timeout=5, stderr=subprocess.DEVNULL,
        ).strip()
        return int(out.splitlines()[0]) if out else None
    except Exception:
        return None


def twl_spawn_controller_handler(
    skill_name: str,
    prompt_file_or_text: str,
    with_chain: bool = False,
    issue: str | None = None,
    project_dir: str | None = None,
    autopilot_dir: str | None = None,
    extra_args: list[str] | None = None,
) -> dict:
    """Spawn a TWiLL controller skill via spawn-controller.sh.

    AC3: skill_name validated against allow-list (co-explore/co-issue/co-architect/
    co-autopilot/co-project/co-utility/co-self-improve; "twl:" prefix accepted).
    Returns {ok, window, session, prompt_prepended, error}.
    AC9: fire-and-forget — spawn-controller.sh returns once the tmux window is created.
    """
    import subprocess  # noqa: PLC0415
    import tempfile  # noqa: PLC0415

    # AC3: allow-list validation (strip "twl:" prefix)
    skill_normalized = skill_name.removeprefix("twl:")
    if skill_normalized not in _VALID_CONTROLLER_SKILLS:
        return {
            "ok": False,
            "window": None,
            "session": None,
            "prompt_prepended": None,
            "error": f"invalid skill name '{skill_name}'. Valid: {', '.join(_VALID_CONTROLLER_SKILLS)}",
        }

    script = Path(os.environ.get("SPAWN_CONTROLLER_SCRIPT", str(_SPAWN_CONTROLLER_SCRIPT)))
    if not script.exists():
        return {
            "ok": False,
            "window": None,
            "session": None,
            "prompt_prepended": None,
            "error": f"spawn-controller.sh not found: {script}",
        }

    # Write prompt text to temp file if not a file path
    prompt_is_file = Path(prompt_file_or_text).is_file() if prompt_file_or_text else False
    _tmpfile_path: str | None = None
    try:
        if prompt_is_file:
            prompt_path = prompt_file_or_text
        else:
            tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
            tmp.write(prompt_file_or_text)
            tmp.flush()
            tmp.close()
            _tmpfile_path = tmp.name
            prompt_path = _tmpfile_path

        cmd: list[str] = ["bash", str(script), skill_name, prompt_path]
        if with_chain:
            cmd.append("--with-chain")
        if issue:
            cmd += ["--issue", str(issue)]
        if project_dir:
            cmd += ["--project-dir", project_dir]
        if autopilot_dir:
            cmd += ["--autopilot-dir", autopilot_dir]
        if extra_args:
            cmd.extend(extra_args)

        # AC6: inherit env so SKIP_PARALLEL_CHECK / SKIP_PARALLEL_REASON pass through
        env = os.environ.copy()

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60,
                env=env,
            )
        except FileNotFoundError as exc:
            _spawn_controller_shadow_log({"ok": False, "exit_code": -1, "stderr": str(exc)})
            return {"ok": False, "window": None, "session": None, "prompt_prepended": None, "error": str(exc)}
        except subprocess.TimeoutExpired:
            _spawn_controller_shadow_log({"ok": False, "exit_code": -2, "stderr": "timeout"})
            return {"ok": False, "window": None, "session": None, "prompt_prepended": None, "error": "spawn-controller.sh timed out after 60s"}
        except Exception as exc:
            _spawn_controller_shadow_log({"ok": False, "exit_code": -3, "stderr": str(exc)})
            return {"ok": False, "window": None, "session": None, "prompt_prepended": None, "error": str(exc)}

        ok = result.returncode == 0
        _spawn_controller_shadow_log({
            "ok": ok,
            "exit_code": result.returncode,
            "stderr": result.stderr,
            "stdout": result.stdout,
        })

        if not ok:
            return {
                "ok": False,
                "window": None,
                "session": None,
                "prompt_prepended": None,
                "error": result.stderr.strip() or f"spawn-controller.sh exited {result.returncode}",
            }

        parsed_window = _parse_spawn_window(result.stdout)

        try:
            session_name = subprocess.check_output(
                ["tmux", "display-message", "-p", "#{session_name}"],
                text=True, timeout=5, stderr=subprocess.DEVNULL,
            ).strip()
        except Exception:
            session_name = None

        return {
            "ok": True,
            "window": parsed_window,
            "session": session_name,
            "prompt_prepended": True,  # spawn-controller.sh always prepends /twl:<skill>
            "error": None,
        }
    finally:
        if _tmpfile_path is not None:
            try:
                Path(_tmpfile_path).unlink(missing_ok=True)
            except Exception:
                pass


def _spawn_controller_shadow_log(entry: dict) -> None:
    import time  # noqa: PLC0415
    record = json.dumps({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tool": "twl_spawn_controller",
        **entry,
    }, ensure_ascii=False)
    try:
        with open(str(_SPAWN_CONTROLLER_SHADOW_LOG), "a") as f:
            f.write(record + "\n")
    except Exception:
        pass


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
        """plugin file integrity check: file existence and chain integrity for a plugin."""
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
    def twl_orchestrator_phase_review(phase: int, plan_file: str, session_file: str, project_dir: str, autopilot_dir: str, repos_json: str = "", timeout_sec: int = 1800, cwd: str | None = None) -> str:
        """autopilot.orchestrator: invoke PhaseOrchestrator.run() with handler-level timeout wrap (1800s wall-clock guard for tmux + state.py subprocess). Note: set MCP_CLIENT_TIMEOUT>=1860s. plan_file existence check + tmux FileNotFoundError catch."""
        return json.dumps(twl_orchestrator_phase_review_handler(phase=phase, plan_file=plan_file, session_file=session_file, project_dir=project_dir, autopilot_dir=autopilot_dir, repos_json=repos_json, timeout_sec=timeout_sec, cwd=cwd), ensure_ascii=False)

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

    @mcp.tool()
    def twl_get_session_state(session_id: str | None = None, autopilot_dir: str | None = None, subcommand: str | None = None, window_name: str | None = None, target_state: str | None = None, timeout: int = 30, json_output: bool = False) -> str:
        """Return autopilot session view or tmux pane state via session-state.sh subcommands (state/list/wait)."""
        return json.dumps(twl_get_session_state_handler(session_id=session_id, autopilot_dir=autopilot_dir, subcommand=subcommand, window_name=window_name, target_state=target_state, timeout=timeout, json_output=json_output), ensure_ascii=False)

    @mcp.tool()
    def twl_get_pane_state(window_name: str, timeout_sec: int = 30) -> str:
        """Return tmux pane/window state. window_name: tmux window name or session:index form."""
        return json.dumps(twl_get_pane_state_handler(window_name=window_name, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_capture_pane(window_name: str, lines: int | None = None, mode: str = "raw", from_line: int | None = None, to_line: int | None = None) -> str:
        """Capture tmux pane content as raw or plain (ANSI-stripped) text."""
        return json.dumps(twl_capture_pane_handler(window_name=window_name, lines=lines, mode=mode, from_line=from_line, to_line=to_line), ensure_ascii=False)

    @mcp.tool()
    def twl_get_budget(window_name: str, threshold_remaining_minutes: int = 40, threshold_cycle_minutes: int = 5, config_path: str | None = None) -> str:
        """Capture tmux pane and extract Claude budget via 5h:%(Ym) regex. Returns {ok, budget_pct, budget_min, cycle_reset_min, low, error}."""
        return json.dumps(twl_get_budget_handler(window_name=window_name, threshold_remaining_minutes=threshold_remaining_minutes, threshold_cycle_minutes=threshold_cycle_minutes, config_path=config_path), ensure_ascii=False)

    @mcp.tool()
    def twl_audit_session(autopilot_dir: str | None = None) -> str:
        """Audit autopilot session.json for structural integrity (R1-R4 rules). Idempotent."""
        return json.dumps(twl_audit_session_handler(autopilot_dir=autopilot_dir), ensure_ascii=False)

    @mcp.tool()
    def twl_validate_deps(plugin_root: str) -> str:
        """validation module: deps.yaml syntax validation for plugin structure."""
        return json.dumps(twl_validate_deps_handler(plugin_root=plugin_root), ensure_ascii=False)

    @mcp.tool()
    def twl_validate_merge(branch: str, base: str = "main", timeout_sec: int | None = 300) -> str:
        """validation module: merge pre-flight guard (2-guard scope only)."""
        return json.dumps(twl_validate_merge_handler(branch=branch, base=base, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_validate_commit(command: str, files: list[str], timeout_sec: int | None = 300) -> str:
        """validation module: commit message and file deps validation (in-process, no subprocess)."""
        return json.dumps(twl_validate_commit_handler(command=command, files=files, timeout_sec=timeout_sec), ensure_ascii=False)

    @mcp.tool()
    def twl_check_completeness(manifest_context: str) -> str:
        """validation module: specialist completeness check via flock-guarded manifest files."""
        return json.dumps(twl_check_completeness_handler(manifest_context=manifest_context), ensure_ascii=False)

    @mcp.tool()
    def twl_check_specialist(manifest_context: str) -> str:
        """validation module: specialist check (stub — detailed spec in future Issue)."""
        return json.dumps(twl_check_specialist_handler(manifest_context=manifest_context), ensure_ascii=False)

    @mcp.tool()
    def twl_spawn_session(  # type: ignore[misc]
        prompt: str,
        cwd: str | None = None,
        env_file: str | None = None,
        window_name: str | None = None,
        timeout: int | None = 120,
        model: str | None = None,
        force_new: bool = False,
    ) -> str:
        """Start a new Claude Code (cld) session in a tmux window via cld-spawn.

        Returns JSON {ok, session, window, pid, error}.
        Fire-and-forget: the cld session runs independently; this tool returns once the window is created.
        """
        return json.dumps(
            twl_spawn_session_handler(
                prompt=prompt,
                cwd=cwd,
                env_file=env_file,
                window_name=window_name,
                timeout=timeout,
                model=model,
                force_new=force_new,
            ),
            ensure_ascii=False,
        )

    @mcp.tool()
    def twl_spawn_controller(  # type: ignore[misc]
        skill_name: str,
        prompt_file_or_text: str,
        with_chain: bool = False,
        issue: str | None = None,
        project_dir: str | None = None,
        autopilot_dir: str | None = None,
        extra_args: list[str] | None = None,
    ) -> str:
        """Spawn a TWiLL controller skill via spawn-controller.sh.

        skill_name: one of co-explore/co-issue/co-architect/co-autopilot/co-project/
        co-utility/co-self-improve (accepts "twl:" prefix).
        prompt_file_or_text: prompt file path or inline text.
        Returns JSON {ok, window, session, prompt_prepended, error}.
        Fire-and-forget: the controller session runs independently.
        """
        return json.dumps(
            twl_spawn_controller_handler(
                skill_name=skill_name,
                prompt_file_or_text=prompt_file_or_text,
                with_chain=with_chain,
                issue=issue,
                project_dir=project_dir,
                autopilot_dir=autopilot_dir,
                extra_args=extra_args,
            ),
            ensure_ascii=False,
        )

except ImportError:
    mcp = None  # type: ignore[assignment]

    def twl_validate(plugin_root: str) -> str:  # type: ignore[misc]
        """Validate plugin structure (fastmcp not installed)."""
        return json.dumps(twl_validate_handler(plugin_root=plugin_root), ensure_ascii=False)

    def twl_audit(plugin_root: str) -> str:  # type: ignore[misc]
        """Audit plugin for TWiLL compliance issues (fastmcp not installed)."""
        return json.dumps(twl_audit_handler(plugin_root=plugin_root), ensure_ascii=False)

    def twl_check(plugin_root: str) -> str:  # type: ignore[misc]
        """plugin file integrity check: file existence and chain integrity (fastmcp not installed)."""
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

    def twl_orchestrator_phase_review(phase: int, plan_file: str, session_file: str, project_dir: str, autopilot_dir: str, repos_json: str = "", timeout_sec: int = 1800, cwd: str | None = None) -> str:  # type: ignore[misc]
        """autopilot.orchestrator: invoke PhaseOrchestrator.run() with handler-level timeout wrap (1800s wall-clock guard for tmux + state.py subprocess). Note: set MCP_CLIENT_TIMEOUT>=1860s. plan_file existence check + tmux FileNotFoundError catch."""
        return json.dumps(twl_orchestrator_phase_review_handler(phase=phase, plan_file=plan_file, session_file=session_file, project_dir=project_dir, autopilot_dir=autopilot_dir, repos_json=repos_json, timeout_sec=timeout_sec, cwd=cwd), ensure_ascii=False)

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

    def twl_get_session_state(session_id: str | None = None, autopilot_dir: str | None = None, subcommand: str | None = None, window_name: str | None = None, target_state: str | None = None, timeout: int = 30, json_output: bool = False) -> str:  # type: ignore[misc]
        """Return autopilot session view or tmux pane state via session-state.sh subcommands (state/list/wait)."""
        return json.dumps(twl_get_session_state_handler(session_id=session_id, autopilot_dir=autopilot_dir, subcommand=subcommand, window_name=window_name, target_state=target_state, timeout=timeout, json_output=json_output), ensure_ascii=False)

    def twl_get_pane_state(window_name: str, timeout_sec: int = 30) -> str:  # type: ignore[misc]
        """Return tmux pane/window state. window_name: tmux window name or session:index form."""
        return json.dumps(twl_get_pane_state_handler(window_name=window_name, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_capture_pane(window_name: str, lines: int | None = None, mode: str = "raw", from_line: int | None = None, to_line: int | None = None) -> str:  # type: ignore[misc]
        """Capture tmux pane content as raw or plain (ANSI-stripped) text (fastmcp not installed)."""
        return json.dumps(twl_capture_pane_handler(window_name=window_name, lines=lines, mode=mode, from_line=from_line, to_line=to_line), ensure_ascii=False)

    def twl_get_budget(window_name: str, threshold_remaining_minutes: int = 40, threshold_cycle_minutes: int = 5, config_path: str | None = None) -> str:  # type: ignore[misc]
        """Capture tmux pane and extract Claude budget via 5h:%(Ym) regex (fastmcp not installed)."""
        return json.dumps(twl_get_budget_handler(window_name=window_name, threshold_remaining_minutes=threshold_remaining_minutes, threshold_cycle_minutes=threshold_cycle_minutes, config_path=config_path), ensure_ascii=False)

    def twl_audit_session(autopilot_dir: str | None = None) -> str:  # type: ignore[misc]
        """Audit autopilot session.json for structural integrity (R1-R4 rules). Idempotent."""
        return json.dumps(twl_audit_session_handler(autopilot_dir=autopilot_dir), ensure_ascii=False)

    def twl_validate_deps(plugin_root: str) -> str:  # type: ignore[misc]
        """validation module: deps.yaml syntax validation for plugin structure."""
        return json.dumps(twl_validate_deps_handler(plugin_root=plugin_root), ensure_ascii=False)

    def twl_validate_merge(branch: str, base: str = "main", timeout_sec: int | None = 300) -> str:  # type: ignore[misc]
        """validation module: merge pre-flight guard (2-guard scope only)."""
        return json.dumps(twl_validate_merge_handler(branch=branch, base=base, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_validate_commit(command: str, files: list[str], timeout_sec: int | None = 300) -> str:  # type: ignore[misc]
        """validation module: commit message and file deps validation (in-process, no subprocess)."""
        return json.dumps(twl_validate_commit_handler(command=command, files=files, timeout_sec=timeout_sec), ensure_ascii=False)

    def twl_check_completeness(manifest_context: str) -> str:  # type: ignore[misc]
        """validation module: specialist completeness check via flock-guarded manifest files."""
        return json.dumps(twl_check_completeness_handler(manifest_context=manifest_context), ensure_ascii=False)

    def twl_check_specialist(manifest_context: str) -> str:  # type: ignore[misc]
        """validation module: specialist check (stub — detailed spec in future Issue)."""
        return json.dumps(twl_check_specialist_handler(manifest_context=manifest_context), ensure_ascii=False)

    def twl_spawn_session(  # type: ignore[misc]
        prompt: str,
        cwd: str | None = None,
        env_file: str | None = None,
        window_name: str | None = None,
        timeout: int | None = 120,
        model: str | None = None,
        force_new: bool = False,
    ) -> str:
        """Start a new Claude Code (cld) session in a tmux window via cld-spawn (fastmcp not installed)."""
        return json.dumps(
            twl_spawn_session_handler(
                prompt=prompt,
                cwd=cwd,
                env_file=env_file,
                window_name=window_name,
                timeout=timeout,
                model=model,
                force_new=force_new,
            ),
            ensure_ascii=False,
        )

    def twl_spawn_controller(  # type: ignore[misc]
        skill_name: str,
        prompt_file_or_text: str,
        with_chain: bool = False,
        issue: str | None = None,
        project_dir: str | None = None,
        autopilot_dir: str | None = None,
        extra_args: list[str] | None = None,
    ) -> str:
        """Spawn a TWiLL controller skill via spawn-controller.sh (fastmcp not installed)."""
        return json.dumps(
            twl_spawn_controller_handler(
                skill_name=skill_name,
                prompt_file_or_text=prompt_file_or_text,
                with_chain=with_chain,
                issue=issue,
                project_dir=project_dir,
                autopilot_dir=autopilot_dir,
                extra_args=extra_args,
            ),
            ensure_ascii=False,
        )

# Communication tools (tools_comm.py) — outside the try/except gate to avoid double-gate (AC5-8 Option A)
from .tools_comm import *  # noqa: E402, F401, F403
# Mount comm FastMCP instance onto main mcp so comm tools are exposed via the MCP server
try:
    from .tools_comm import _mcp_comm as _comm_mcp  # noqa: F401
    if mcp is not None and _comm_mcp is not None:
        mcp.mount(_comm_mcp)
except (ImportError, AttributeError, NameError):
    pass
