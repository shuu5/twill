"""twl MCP server lifecycle management (restart command)."""
import json
import os
import signal
import subprocess
import time
from pathlib import Path


def _find_mcp_server_pids() -> "list[int]":
    """Find running twl MCP server PIDs via pgrep."""
    result = subprocess.run(
        ["pgrep", "-f", "fastmcp run.*src/twl/mcp_server/server.py"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0 and result.stdout.strip():
        pids = []
        for line in result.stdout.strip().split("\n"):
            try:
                pids.append(int(line.strip()))
            except ValueError:
                pass
        return pids
    return []


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
        command = twl_server.get("command", "")
        if not command:
            return None
        return [command] + twl_server.get("args", [])
    except Exception:
        return None


def _wait_for_pids_exit(pids: "list[int]", timeout: int = 5) -> bool:
    """Wait up to `timeout` seconds for all PIDs to exit. Returns True if all exited."""
    deadline = time.monotonic() + timeout
    remaining = list(pids)
    while remaining and time.monotonic() < deadline:
        time.sleep(0.5)
        still_running = []
        for pid in remaining:
            try:
                os.kill(pid, 0)
                still_running.append(pid)
            except ProcessLookupError:
                pass
        remaining = still_running
    return len(remaining) == 0


def restart_mcp_server() -> int:
    """Restart the twl MCP server. Always returns 0.

    NOTE: After restart, the Claude Code session must also be restarted
    to reconnect to the new server process.
    """
    old_pids = _find_mcp_server_pids()
    if old_pids:
        print(f"Stopping twl MCP server (PIDs {old_pids})...")
        for pid in old_pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if not _wait_for_pids_exit(old_pids, timeout=5):
            print("Server did not exit within 5s after SIGTERM; sending SIGKILL...")
            for pid in old_pids:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            _wait_for_pids_exit(old_pids, timeout=3)
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

    new_pids = _find_mcp_server_pids()
    if new_pids:
        print(f"twl MCP server started (PIDs {new_pids}).")
    else:
        print("twl MCP server starting (PID not yet confirmed).")

    print("NOTE: Restart your Claude Code session to reconnect to the new server.")
    return 0
