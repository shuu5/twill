"""twl MCP server entry point (Phase 0 PoC).

Start via:
    pip install -e '.[mcp]'
    fastmcp run src/twl/mcp_server/server.py

Or with uv:
    uv run --directory cli/twl --extra mcp fastmcp run src/twl/mcp_server/server.py
"""
from twl.mcp_server.tools import mcp

if __name__ == "__main__":
    if mcp is None:
        raise RuntimeError("fastmcp is not installed. Run: pip install -e '.[mcp]'")
    mcp.run()
