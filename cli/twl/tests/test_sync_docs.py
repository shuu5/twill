#!/usr/bin/env python3
"""Tests for twl sync-docs command."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

_TWL_SRC = str(Path(__file__).resolve().parent.parent / "src")


def make_docs(loom_root: Path):
    """Create docs/ with ref-*.md files."""
    docs = loom_root / "docs"
    docs.mkdir()
    (docs / "ref-alpha.md").write_text("# Alpha\n\nAlpha content.\n", encoding="utf-8")
    (docs / "ref-beta.md").write_text("# Beta\n\nBeta content.\n", encoding="utf-8")
    # non-ref file should be ignored
    (docs / "guide.md").write_text("# Guide\n", encoding="utf-8")


def make_deps_yaml(target_dir: Path):
    """Create deps.yaml with reference definitions matching ref-alpha.md."""
    deps = {
        "version": "2.0",
        "plugin": "myplugin",
        "skills": {
            "ref-alpha": {
                "type": "reference",
                "path": "refs/ref-alpha.md",
                "spawnable_by": ["controller", "atomic"],
                "description": "Alpha reference doc",
            },
        },
        "commands": {},
        "agents": {},
    }
    (target_dir / "deps.yaml").write_text(
        yaml.dump(deps, default_flow_style=False, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def run_sync_docs(target_dir: str, check: bool = False, loom_root: str = None):
    """Run twl --sync-docs using the package.

    loom_root: if provided, set TWL_LOOM_ROOT env var so sync_docs finds docs/ there.
    """
    cmd = [sys.executable, "-m", "twl", "--sync-docs", target_dir]
    if check:
        cmd.append("--check")
    env = {**os.environ, "PYTHONPATH": _TWL_SRC}
    if loom_root:
        env["TWL_LOOM_ROOT"] = loom_root
    return subprocess.run(cmd, capture_output=True, text=True, env=env)


def test_basic_sync():
    """ref-*.md files are synced to target dir with minimal frontmatter."""
    with tempfile.TemporaryDirectory() as tmpdir:
        loom_root = Path(tmpdir) / "twl"
        loom_root.mkdir()
        make_docs(loom_root)

        target = Path(tmpdir) / "target"
        target.mkdir()

        result = run_sync_docs(str(target), loom_root=str(loom_root))
        assert result.returncode == 0, f"stdout={result.stdout}\nstderr={result.stderr}"

        # ref-*.md should be synced
        assert (target / "ref-alpha.md").exists()
        assert (target / "ref-beta.md").exists()
        # non-ref file should NOT be synced
        assert not (target / "guide.md").exists()

        # Check minimal frontmatter
        content = (target / "ref-alpha.md").read_text(encoding="utf-8")
        assert content.startswith("---\ntype: reference\n---")
        assert "<!-- Synced from twl docs/" in content
        assert "# Alpha" in content


def test_sync_with_deps_yaml():
    """Synced files get frontmatter from deps.yaml reference definitions."""
    with tempfile.TemporaryDirectory() as tmpdir:
        loom_root = Path(tmpdir) / "twl"
        loom_root.mkdir()
        make_docs(loom_root)

        target = Path(tmpdir) / "target"
        target.mkdir()
        make_deps_yaml(target)

        result = run_sync_docs(str(target), loom_root=str(loom_root))
        assert result.returncode == 0, f"stderr={result.stderr}"

        content = (target / "ref-alpha.md").read_text(encoding="utf-8")
        assert "name: myplugin:ref-alpha" in content
        assert "description:" in content
        assert "spawnable_by:" in content
        assert "controller" in content
        assert "atomic" in content

        # ref-beta has no deps.yaml entry → minimal frontmatter
        beta = (target / "ref-beta.md").read_text(encoding="utf-8")
        assert beta.startswith("---\ntype: reference\n---")


def test_check_in_sync():
    """--check returns 0 when files are in sync."""
    with tempfile.TemporaryDirectory() as tmpdir:
        loom_root = Path(tmpdir) / "twl"
        loom_root.mkdir()
        make_docs(loom_root)

        target = Path(tmpdir) / "target"
        target.mkdir()

        # First sync
        run_sync_docs(str(target), loom_root=str(loom_root))

        # Then check
        result = run_sync_docs(str(target), check=True, loom_root=str(loom_root))
        assert result.returncode == 0
        assert "in sync" in result.stdout.lower()


def test_check_detects_diff():
    """--check returns 1 when body content differs."""
    with tempfile.TemporaryDirectory() as tmpdir:
        loom_root = Path(tmpdir) / "twl"
        loom_root.mkdir()
        make_docs(loom_root)

        target = Path(tmpdir) / "target"
        target.mkdir()

        # Sync first
        run_sync_docs(str(target), loom_root=str(loom_root))

        # Modify target file body
        alpha = target / "ref-alpha.md"
        alpha.write_text(alpha.read_text(encoding="utf-8") + "\n# Extra section\n", encoding="utf-8")

        result = run_sync_docs(str(target), check=True, loom_root=str(loom_root))
        assert result.returncode == 1
        assert "[changed]" in result.stdout


def test_check_detects_missing():
    """--check reports missing files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        loom_root = Path(tmpdir) / "twl"
        loom_root.mkdir()
        make_docs(loom_root)

        target = Path(tmpdir) / "target"
        target.mkdir()

        result = run_sync_docs(str(target), check=True, loom_root=str(loom_root))
        assert result.returncode == 1
        assert "[missing]" in result.stdout


def test_existing_files_not_overwritten():
    """Files not matching ref-*.md pattern in target are preserved."""
    with tempfile.TemporaryDirectory() as tmpdir:
        loom_root = Path(tmpdir) / "twl"
        loom_root.mkdir()
        make_docs(loom_root)

        target = Path(tmpdir) / "target"
        target.mkdir()

        # Create a pre-existing file
        existing = target / "custom-ref.md"
        existing.write_text("# My custom ref\n", encoding="utf-8")

        run_sync_docs(str(target), loom_root=str(loom_root))

        # Custom file should still exist unchanged
        assert existing.exists()
        assert existing.read_text(encoding="utf-8") == "# My custom ref\n"


if __name__ == "__main__":
    import pytest
    sys.exit(pytest.main([__file__, "-v"]))
