"""twl MCP server lifecycle management (restart command)."""
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def _find_mcp_server_pid() -> "int | None":
    """Find running twl MCP server PID via pgrep."""
    result = subprocess.run(
        ["pgrep", "-f", "fastmcp run.*src/twl/mcp_server/server.py"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0 and result.stdout.strip():
        try:
            return int(result.stdout.strip().split("\n")[0])
        except ValueError:
            pass
    return None


def _find_mcp_server_cmd() -> "list[str] | None":
    """Get startup command from .mcp.json in the git repo root."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            return None
        mcp_json = Path(result.stdout.strip()) / ".mcp.json"
        if not mcp_json.exists():
            return None
        with open(mcp_json) as f:
            config = json.load(f)
        twl_server = config.get("mcpServers", {}).get("twl", {})
        if not twl_server:
            return None
        return [twl_server.get("command", "")] + twl_server.get("args", [])
    except Exception:
        return None


def restart_mcp_server() -> int:
    """Restart the twl MCP server. Always returns 0.

    NOTE: After restart, the Claude Code session must also be restarted
    to reconnect to the new server process.
    """
    old_pid = _find_mcp_server_pid()
    if old_pid is not None:
        print(f"Stopping twl MCP server (PID {old_pid})...")
        try:
            os.kill(old_pid, signal.SIGTERM)
            time.sleep(1)
        except ProcessLookupError:
            pass
    else:
        print("No running twl MCP server found.")

    cmd = _find_mcp_server_cmd()
    if cmd is None:
        print("WARNING: Could not determine MCP server startup command from .mcp.json.")
        print("  Start manually: uv run --directory cli/twl --extra mcp fastmcp run src/twl/mcp_server/server.py")
        print("  NOTE: Restart your Claude Code session to reconnect.")
        return 0

    print(f"Starting twl MCP server: {' '.join(cmd)}")
    subprocess.Popen(
        cmd,
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.5)

    new_pid = _find_mcp_server_pid()
    if new_pid is not None:
        print(f"twl MCP server started (PID {new_pid}).")
    else:
        print("twl MCP server starting (PID not yet confirmed).")

    print("NOTE: Restart your Claude Code session to reconnect to the new server.")
    return 0
