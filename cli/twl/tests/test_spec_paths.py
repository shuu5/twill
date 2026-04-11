"""Tests for src/twl/spec/paths.py"""

import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.paths import (
    DeltaspecNotFound,
    find_deltaspec_root,
    get_change_dir,
    get_changes_dir,
    get_specs_dir,
)


def _make_deltaspec(path: Path) -> None:
    """Create deltaspec/config.yaml under path."""
    ds = path / "deltaspec"
    ds.mkdir(parents=True, exist_ok=True)
    (ds / "config.yaml").write_text("schema: spec-driven\ncontext: {}\n", encoding="utf-8")


def test_find_deltaspec_root_in_project_root(tmp_path):
    _make_deltaspec(tmp_path)
    assert find_deltaspec_root(tmp_path) == tmp_path


def test_find_deltaspec_root_from_subdir(tmp_path):
    _make_deltaspec(tmp_path)
    sub = tmp_path / "a" / "b"
    sub.mkdir(parents=True)
    assert find_deltaspec_root(sub) == tmp_path


def test_find_deltaspec_root_not_found(tmp_path):
    with pytest.raises(DeltaspecNotFound):
        find_deltaspec_root(tmp_path)


def test_get_changes_dir(tmp_path):
    assert get_changes_dir(tmp_path) == tmp_path / "deltaspec" / "changes"


def test_get_specs_dir(tmp_path):
    assert get_specs_dir(tmp_path) == tmp_path / "deltaspec" / "specs"


def test_get_change_dir(tmp_path):
    assert get_change_dir(tmp_path, "my-change") == tmp_path / "deltaspec" / "changes" / "my-change"
