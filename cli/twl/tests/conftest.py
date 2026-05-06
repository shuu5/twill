"""conftest.py: shared test configuration for twl package tests.

Sets PYTHONPATH so subprocess calls to `python -m twl` can find the package.
"""
import json
import os
import sys
from pathlib import Path

import pytest

# Add src/ to PYTHONPATH for subprocess-based tests
_TWL_SRC = str(Path(__file__).resolve().parent.parent / "src")
existing = os.environ.get("PYTHONPATH", "")
os.environ["PYTHONPATH"] = _TWL_SRC + (os.pathsep + existing if existing else "")
# Ensure the package is importable in the current process too
if _TWL_SRC not in sys.path:
    sys.path.insert(0, _TWL_SRC)


def make_mcp_json(command: str, args: list[str] | None = None, *, tmp_path: Path) -> Path:
    """Create a .mcp.json file in tmp_path for testing."""
    mcp_json = tmp_path / ".mcp.json"
    data = {
        "mcpServers": {
            "twl": {
                "command": command,
                "args": args if args is not None else [],
            }
        }
    }
    mcp_json.write_text(json.dumps(data))
    return mcp_json


_make_mcp_json_impl = make_mcp_json


@pytest.fixture  # noqa: F811
def make_mcp_json():  # noqa: F811
    """Pytest fixture returning the make_mcp_json factory."""
    return _make_mcp_json_impl
