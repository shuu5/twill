"""Tests for src/twl/spec/list.py"""

import json
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.list import cmd_list


def _ensure_config_yaml(tmp_path: Path) -> None:
    ds = tmp_path / "deltaspec"
    ds.mkdir(exist_ok=True)
    config = ds / "config.yaml"
    if not config.exists():
        config.write_text("schema: spec-driven\ncontext: {}\n", encoding="utf-8")


def make_change(tmp_path: Path, name: str, tasks: str = "") -> Path:
    _ensure_config_yaml(tmp_path)
    change_dir = tmp_path / "deltaspec" / "changes" / name
    change_dir.mkdir(parents=True)
    if tasks:
        (change_dir / "tasks.md").write_text(tasks)
    return change_dir


def test_list_empty(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "deltaspec" / "changes").mkdir(parents=True)
    _ensure_config_yaml(tmp_path)
    rc = cmd_list()
    assert rc == 0
    assert "No changes found." in capsys.readouterr().out


def test_list_shows_changes(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "alpha")
    make_change(tmp_path, "beta")
    rc = cmd_list()
    assert rc == 0
    out = capsys.readouterr().out
    assert "alpha" in out
    assert "beta" in out


def test_list_excludes_archive(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "alpha")
    (tmp_path / "deltaspec" / "changes" / "archive" / "old").mkdir(parents=True)
    rc = cmd_list()
    assert rc == 0
    out = capsys.readouterr().out
    assert "archive" not in out


def test_list_json_output(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "json-test", tasks="- [ ] 1.1 Task A\n- [x] 1.2 Task B\n")
    rc = cmd_list(json_mode=True)
    assert rc == 0
    data = json.loads(capsys.readouterr().out)
    assert "changes" in data
    entry = data["changes"][0]
    assert entry["name"] == "json-test"
    assert entry["totalTasks"] == 2
    assert entry["completedTasks"] == 1
    assert entry["status"] == "in-progress"


def test_list_sort_by_name(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "zebra")
    make_change(tmp_path, "alpha")
    rc = cmd_list(sort_order="name", json_mode=True)
    assert rc == 0
    data = json.loads(capsys.readouterr().out)
    names = [c["name"] for c in data["changes"]]
    assert names == sorted(names)


def test_list_complete_status(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "done-change", tasks="- [x] 1.1 Task A\n- [x] 1.2 Task B\n")
    rc = cmd_list(json_mode=True)
    assert rc == 0
    data = json.loads(capsys.readouterr().out)
    assert data["changes"][0]["status"] == "complete"
