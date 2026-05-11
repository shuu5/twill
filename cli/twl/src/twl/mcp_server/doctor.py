"""twl MCP doctor — self-check for .mcp.json configuration integrity."""
import json
import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path
from typing import Any

from twl.mcp_server.lifecycle import _validate_command


def _find_mcp_json() -> "Path | None":
    """Find .mcp.json by walking up from CWD to git root."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return Path(result.stdout.strip()) / ".mcp.json"
    except Exception:
        pass
    # Fallback: walk up from CWD
    current = Path.cwd()
    for parent in [current, *current.parents]:
        candidate = parent / ".mcp.json"
        if candidate.exists():
            return candidate
    return None


def _check_mcp_json_readable(mcp_json: "Path | None") -> dict[str, Any]:
    if mcp_json is None:
        return {
            "name": "mcp_json_readable",
            "result": "fail",
            "detail": ".mcp.json not found in git root or any parent directory",
            "fix": None,
            "exit_code": 2,
        }
    try:
        with open(mcp_json) as f:
            config = json.load(f)
        return {
            "name": "mcp_json_readable",
            "result": "pass",
            "detail": f"Read {mcp_json}",
            "fix": None,
            "exit_code": 0,
            "_config": config,
        }
    except Exception as e:
        return {
            "name": "mcp_json_readable",
            "result": "fail",
            "detail": f"Failed to read {mcp_json}: {e}",
            "fix": None,
            "exit_code": 2,
        }


def _check_validate_command(config: dict[str, Any]) -> tuple[dict[str, Any], str, list[str]]:
    """Returns (check_result, command, args)."""
    twl_server = config.get("mcpServers", {}).get("twl", {})
    command = twl_server.get("command", "")
    args = twl_server.get("args", [])

    if not command:
        return (
            {
                "name": "validate_command",
                "result": "fail",
                "detail": "mcpServers.twl.command is empty or missing",
                "fix": "Set 'command' in .mcp.json under mcpServers.twl",
                "exit_code": 2,
            },
            command,
            args,
        )

    try:
        _validate_command(command)
        return (
            {
                "name": "validate_command",
                "result": "pass",
                "detail": f"command '{command}' is in allowlist",
                "fix": None,
                "exit_code": 0,
            },
            command,
            args,
        )
    except ValueError as exc:
        from twl.mcp_server.lifecycle import _format_fix_guidance
        fix_msg = _format_fix_guidance(str(exc))
        return (
            {
                "name": "validate_command",
                "result": "fail",
                "detail": str(exc),
                "fix": fix_msg,
                "exit_code": 2,
            },
            command,
            args,
        )


def _check_binary_exists(command: str) -> dict[str, Any]:
    if not command:
        return {
            "name": "binary_exists",
            "result": "fail",
            "detail": "No command to check",
            "fix": None,
            "exit_code": 1,
        }

    if os.path.isabs(command):
        found = os.access(command, os.F_OK | os.X_OK)
        if found:
            return {
                "name": "binary_exists",
                "result": "pass",
                "detail": f"Found executable at {command}",
                "fix": None,
                "exit_code": 0,
            }
        return {
            "name": "binary_exists",
            "result": "fail",
            "detail": f"Absolute path '{command}' not found or not executable",
            "fix": f"Ensure '{command}' exists and is executable",
            "exit_code": 1,
        }
    else:
        resolved = shutil.which(command)
        if resolved:
            return {
                "name": "binary_exists",
                "result": "pass",
                "detail": f"Found '{command}' at {resolved}",
                "fix": None,
                "exit_code": 0,
            }
        return {
            "name": "binary_exists",
            "result": "fail",
            "detail": f"'{command}' not found in PATH",
            "fix": f"Install '{command}' or add its directory to PATH",
            "exit_code": 1,
        }


def _check_stdio_probe(command: str, args: list[str]) -> dict[str, Any]:
    """Perform a stdio handshake with timeout 5s."""
    if not command:
        return {
            "name": "stdio_probe",
            "result": "skipped",
            "detail": "No command to probe",
            "fix": None,
            "exit_code": 0,
        }

    full_cmd = [command] + args
    proc = None
    try:
        proc = subprocess.Popen(
            full_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        # Send MCP initialize request
        init_request = json.dumps({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"protocolVersion": "2024-11-05", "capabilities": {}},
        }) + "\n"
        try:
            stdout_data, _ = proc.communicate(
                input=init_request.encode(),
                timeout=5,
            )
            # Check for valid JSON-RPC response
            for line in stdout_data.decode(errors="replace").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    if obj.get("jsonrpc") == "2.0":
                        return {
                            "name": "stdio_probe",
                            "result": "pass",
                            "detail": "Received valid JSON-RPC 2.0 response",
                            "fix": None,
                            "exit_code": 0,
                        }
                except json.JSONDecodeError:
                    continue
            return {
                "name": "stdio_probe",
                "result": "fail",
                "detail": "No valid JSON-RPC 2.0 response received within 5s",
                "fix": None,
                "exit_code": 1,
            }
        except subprocess.TimeoutExpired:
            return {
                "name": "stdio_probe",
                "result": "fail",
                "detail": "Process did not respond within 5s (timeout)",
                "fix": None,
                "exit_code": 1,
            }
    except Exception as e:
        return {
            "name": "stdio_probe",
            "result": "fail",
            "detail": f"Failed to start process: {e}",
            "fix": None,
            "exit_code": 1,
        }
    finally:
        if proc is not None and proc.poll() is None:
            try:
                proc.send_signal(signal.SIGTERM)
                proc.wait(timeout=2)
            except Exception:
                pass


def _compute_overall(checks: list[dict[str, Any]]) -> tuple[str, int]:
    """Compute overall status and exit code from checks."""
    max_exit = max((c["exit_code"] for c in checks), default=0)
    if max_exit == 0:
        return "ok", 0
    if max_exit == 1:
        return "warning", 1
    return "critical", 2


def _format_human(checks: list[dict[str, Any]], status: str) -> None:
    STATUS_COLOR = {"ok": "\033[92m", "warning": "\033[93m", "critical": "\033[91m"}
    RESULT_COLOR = {"pass": "\033[92m", "fail": "\033[91m", "skipped": "\033[90m"}
    RESET = "\033[0m"

    status_color = STATUS_COLOR.get(status, "")
    print(f"\ntwl mcp doctor — {status_color}{status.upper()}{RESET}\n")
    for check in checks:
        result = check["result"]
        color = RESULT_COLOR.get(result, "")
        icon = {"pass": "✓", "fail": "✗", "skipped": "−"}.get(result, "?")
        print(f"  {color}{icon} {check['name']}{RESET}: {check['detail']}")
        if check.get("fix"):
            print(f"    → Fix: {check['fix']}")
    print()


def run_doctor(args: Any) -> int:
    """Entry point for twl mcp doctor. Returns exit code."""
    probe = getattr(args, "probe", False)
    auto_restart = getattr(args, "auto_restart", False)
    fmt = getattr(args, "format", "human")

    mcp_json = _find_mcp_json()
    readable_check = _check_mcp_json_readable(mcp_json)
    config = readable_check.pop("_config", {})
    checks: list[dict[str, Any]] = [readable_check]

    if readable_check["result"] == "pass":
        validate_check, command, cmd_args = _check_validate_command(config)
        checks.append(validate_check)

        binary_check = _check_binary_exists(command)
        checks.append(binary_check)

        if probe or auto_restart:
            probe_check = _check_stdio_probe(command, cmd_args)
            checks.append(probe_check)
            # --auto-restart: probe fail 時に lifecycle restart_mcp_server() を呼ぶ (#1612)
            if auto_restart and probe_check["result"] == "fail":
                from twl.mcp_server.lifecycle import restart_mcp_server
                print("auto-restart: probe failed — triggering restart_mcp_server()", file=sys.stderr)
                restart_mcp_server()
        else:
            checks.append({
                "name": "stdio_probe",
                "result": "skipped",
                "detail": "Use --probe to run stdio handshake",
                "fix": None,
                "exit_code": 0,
            })
    else:
        # Fill remaining checks as skipped
        for name in ("validate_command", "binary_exists", "stdio_probe"):
            checks.append({
                "name": name,
                "result": "skipped",
                "detail": "Skipped due to .mcp.json read failure",
                "fix": None,
                "exit_code": 0,
            })

    status, exit_code = _compute_overall(checks)

    clean_checks = [{k: v for k, v in c.items() if k != "exit_code"} for c in checks]

    if fmt == "json":
        output = {
            "status": status,
            "summary": f"{sum(1 for c in clean_checks if c['result'] == 'pass')} passed, "
                       f"{sum(1 for c in clean_checks if c['result'] == 'fail')} failed, "
                       f"{sum(1 for c in clean_checks if c['result'] == 'skipped')} skipped",
            "checks": clean_checks,
        }
        print(json.dumps(output, indent=2))
    else:
        _format_human(checks, status)

    return exit_code
