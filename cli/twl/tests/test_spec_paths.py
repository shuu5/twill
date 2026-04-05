"""Tests for src/twl/spec/paths.py"""

import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.paths import (
    OpenspecNotFound,
    find_openspec_root,
    get_change_dir,
    get_changes_dir,
    get_specs_dir,
)


def test_find_openspec_root_in_project_root(tmp_path):
    (tmp_path / "openspec").mkdir()
    assert find_openspec_root(tmp_path) == tmp_path


def test_find_openspec_root_from_subdir(tmp_path):
    (tmp_path / "openspec").mkdir()
    sub = tmp_path / "a" / "b"
    sub.mkdir(parents=True)
    assert find_openspec_root(sub) == tmp_path


def test_find_openspec_root_not_found(tmp_path):
    with pytest.raises(OpenspecNotFound):
        find_openspec_root(tmp_path)


def test_get_changes_dir(tmp_path):
    assert get_changes_dir(tmp_path) == tmp_path / "openspec" / "changes"


def test_get_specs_dir(tmp_path):
    assert get_specs_dir(tmp_path) == tmp_path / "openspec" / "specs"


def test_get_change_dir(tmp_path):
    assert get_change_dir(tmp_path, "my-change") == tmp_path / "openspec" / "changes" / "my-change"
