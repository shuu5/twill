"""conftest.py: shared test configuration for twl package tests.

Sets PYTHONPATH so subprocess calls to `python -m twl` can find the package.
"""
import os
import sys
from pathlib import Path

# Add src/ to PYTHONPATH for subprocess-based tests
_TWL_SRC = str(Path(__file__).resolve().parent.parent / "src")
os.environ.setdefault("PYTHONPATH", _TWL_SRC)
# Ensure the package is importable in the current process too
if _TWL_SRC not in sys.path:
    sys.path.insert(0, _TWL_SRC)
