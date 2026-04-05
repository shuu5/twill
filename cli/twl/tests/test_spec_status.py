"""Tests for src/twl/spec/status.py"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.status import cmd_status


def make_change(tmp_path: Path, name: str, **artifacts) -> Path:
    change_dir = tmp_path / "openspec" / "changes" / name
    change_dir.mkdir(parents=True)
    (change_dir / ".openspec.yaml").write_text("schema: spec-driven\ncreated: 2024-01-01\n")
    if artifacts.get("proposal"):
        (change_dir / "proposal.md").write_text("# Proposal\n")
    if artifacts.get("design"):
        (change_dir / "design.md").write_text("# Design\n")
    if artifacts.get("specs"):
        specs_dir = change_dir / "specs" / "cap-a"
        specs_dir.mkdir(parents=True)
        (specs_dir / "spec.md").write_text("## ADDED Requirements\n")
    if artifacts.get("tasks"):
        (change_dir / "tasks.md").write_text("- [ ] 1.1 Do something\n")
    return change_dir


def test_status_no_artifacts(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "empty-change")
    rc = cmd_status("empty-change")
    assert rc == 0
    out = capsys.readouterr().out
    assert "[ ] proposal" in out
    assert "[ ] design" in out
    assert "Some artifacts still pending." in out


def test_status_all_artifacts(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "full", proposal=True, design=True, specs=True, tasks=True)
    rc = cmd_status("full")
    assert rc == 0
    out = capsys.readouterr().out
    assert "All artifacts complete!" in out


def test_status_json_output(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "jtest", proposal=True)
    rc = cmd_status("jtest", json_mode=True)
    assert rc == 0
    lines = capsys.readouterr().out
    # extract JSON from output (skip "- Loading..." line)
    json_text = "\n".join(l for l in lines.splitlines() if not l.startswith("-"))
    data = json.loads(json_text)
    assert data["changeName"] == "jtest"
    assert data["schemaName"] == "spec-driven"
    assert isinstance(data["artifacts"], list)
    assert len(data["artifacts"]) == 4


def test_status_missing_change(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "openspec" / "changes").mkdir(parents=True)
    rc = cmd_status("nonexistent")
    assert rc == 1


def test_status_blocked_deps(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "blocked")  # no proposal
    rc = cmd_status("blocked", json_mode=True)
    assert rc == 0
    lines = capsys.readouterr().out
    json_text = "\n".join(l for l in lines.splitlines() if not l.startswith("-"))
    data = json.loads(json_text)
    design = next(a for a in data["artifacts"] if a["id"] == "design")
    assert design["status"] == "blocked"
    assert "proposal" in design.get("missingDeps", [])
