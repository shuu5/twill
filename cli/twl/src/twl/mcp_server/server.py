"""twl MCP server entry point (Phase 0 PoC).

Start via:
    pip install -e '.[mcp]'
    fastmcp run src/twl/mcp_server/server.py

Or with uv:
    uv run --directory cli/twl --extra mcp fastmcp run src/twl/mcp_server/server.py
"""
from twl.mcp_server.tools import mcp

# Note: mcp is None only when fastmcp is not installed.
# `fastmcp run` itself requires fastmcp, so mcp is always a FastMCP instance
# when invoked via `fastmcp run`. The guard below covers direct `python server.py` only.
if __name__ == "__main__":
    if mcp is None:
        raise RuntimeError("fastmcp is not installed. Run: pip install -e '.[mcp]'")
    mcp.run()
