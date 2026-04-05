#!/usr/bin/env python3
"""Tests for pyproject.toml + src/twl/ package structure (Issue #4).

Verifies AC1-AC5:
  AC1: python3 -m twl --help displays help
  AC2: existing commands work via twl-engine.py
  AC3: pip install -e . succeeds (manual / CI only)
  AC4: pyproject.toml defines PyYAML dependency
  AC5: existing tests continue to pass (covered by pytest run)
"""

import subprocess
import sys
from pathlib import Path

TWL_DIR = Path(__file__).parent.parent
PYPROJECT = TWL_DIR / "pyproject.toml"
SRC_TWL = TWL_DIR / "src" / "twl"


class TestPyprojectToml:
    """AC4: pyproject.toml structure and dependencies."""

    def test_pyproject_exists(self):
        assert PYPROJECT.exists(), "pyproject.toml must exist"

    def test_pyyaml_dependency(self):
        content = PYPROJECT.read_text()
        assert "PyYAML" in content or "pyyaml" in content, \
            "pyproject.toml must define PyYAML as a dependency"

    def test_requires_python(self):
        content = PYPROJECT.read_text()
        assert "requires-python" in content, \
            "pyproject.toml must define requires-python"
        assert "3.10" in content, \
            "requires-python must specify >= 3.10"

    def test_entry_point_defined(self):
        content = PYPROJECT.read_text()
        assert "twl.cli:run" in content or "twl.cli" in content, \
            "pyproject.toml must define [project.scripts] entry point"


class TestSrcLayout:
    """Package structure: src/twl/ files must exist."""

    def test_init_exists(self):
        assert (SRC_TWL / "__init__.py").exists(), \
            "src/twl/__init__.py must exist"

    def test_main_exists(self):
        assert (SRC_TWL / "__main__.py").exists(), \
            "src/twl/__main__.py must exist"

    def test_cli_exists(self):
        assert (SRC_TWL / "cli.py").exists(), \
            "src/twl/cli.py must exist"


import pytest

ENGINE_EXISTS = (TWL_DIR / "twl-engine.py").exists()


class TestEntryPoint:
    """AC1, AC2: python3 -m twl entry point behavior."""

    @pytest.mark.skipif(not ENGINE_EXISTS, reason="twl-engine.py not found")
    def test_help_exits_zero(self):
        """AC1: python3 -m twl --help shows help and exits 0."""
        result = subprocess.run(
            [sys.executable, "-m", "twl", "--help"],
            capture_output=True,
            text=True,
            cwd=str(TWL_DIR),
        )
        # help should exit 0 or show usage
        output = result.stdout + result.stderr
        assert result.returncode == 0, \
            f"python3 -m twl --help failed: {output}"
        assert len(output) > 0, "help output must not be empty"

    @pytest.mark.skipif(not ENGINE_EXISTS, reason="twl-engine.py not found")
    def test_unknown_flag_shows_usage(self):
        """AC2: unknown command falls through to twl-engine.py error handling."""
        result = subprocess.run(
            [sys.executable, "-m", "twl", "--version"],
            capture_output=True,
            text=True,
            cwd=str(TWL_DIR),
        )
        output = result.stdout + result.stderr
        # should either succeed or show a meaningful error (not ImportError)
        assert "ImportError" not in output, \
            "Entry point must not raise ImportError"
        assert "ModuleNotFoundError" not in output, \
            "Entry point must not raise ModuleNotFoundError"
