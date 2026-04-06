"""Tests for src/twl/spec/instructions.py"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from twl.spec.instructions import cmd_instructions


def make_change(tmp_path: Path, name: str, **artifacts) -> Path:
    change_dir = tmp_path / "deltaspec" / "changes" / name
    change_dir.mkdir(parents=True)
    (change_dir / ".deltaspec.yaml").write_text("schema: spec-driven\ncreated: 2024-01-01\n")
    if artifacts.get("proposal"):
        (change_dir / "proposal.md").write_text("# Proposal\n")
    if artifacts.get("tasks"):
        (change_dir / "tasks.md").write_text(
            "- [ ] 1.1 First task\n- [x] 1.2 Second task\n- [ ] 1.3 Third task\n"
        )
    return change_dir


def test_instructions_proposal_text(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange")
    rc = cmd_instructions("proposal", "mychange")
    assert rc == 0
    out = capsys.readouterr().out
    assert "Artifact: proposal" in out
    assert "proposal.md" in out


def test_instructions_proposal_json(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange")
    rc = cmd_instructions("proposal", "mychange", json_mode=True)
    assert rc == 0
    lines = capsys.readouterr().out
    json_text = "\n".join(l for l in lines.splitlines() if not l.startswith("-"))
    data = json.loads(json_text)
    assert data["artifactId"] == "proposal"
    assert data["changeName"] == "mychange"
    assert "instruction" in data
    assert "template" in data


def test_instructions_design_shows_deps(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange")  # no proposal
    rc = cmd_instructions("design", "mychange", json_mode=True)
    assert rc == 0
    lines = capsys.readouterr().out
    json_text = "\n".join(l for l in lines.splitlines() if not l.startswith("-"))
    data = json.loads(json_text)
    dep = data["dependencies"][0]
    assert dep["id"] == "proposal"
    assert dep["done"] is False


def test_instructions_design_dep_done(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange", proposal=True)
    rc = cmd_instructions("design", "mychange", json_mode=True)
    assert rc == 0
    lines = capsys.readouterr().out
    json_text = "\n".join(l for l in lines.splitlines() if not l.startswith("-"))
    data = json.loads(json_text)
    dep = data["dependencies"][0]
    assert dep["done"] is True


def test_instructions_apply_with_tasks(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange", tasks=True)
    rc = cmd_instructions("apply", "mychange", json_mode=True)
    assert rc == 0
    lines = capsys.readouterr().out
    json_text = "\n".join(l for l in lines.splitlines() if not l.startswith("-"))
    data = json.loads(json_text)
    assert data["progress"]["total"] == 3
    assert data["progress"]["complete"] == 1
    assert data["progress"]["remaining"] == 2
    assert data["state"] == "ready"


def test_instructions_apply_all_done(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    change_dir = make_change(tmp_path, "done")
    (change_dir / "tasks.md").write_text("- [x] 1.1 Done\n")
    rc = cmd_instructions("apply", "done", json_mode=True)
    assert rc == 0
    lines = capsys.readouterr().out
    json_text = "\n".join(l for l in lines.splitlines() if not l.startswith("-"))
    data = json.loads(json_text)
    assert data["state"] == "all_done"


def test_instructions_apply_no_tasks(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "notasks")  # no tasks.md
    rc = cmd_instructions("apply", "notasks", json_mode=True)
    assert rc == 0
    data = json.loads(capsys.readouterr().out)
    assert data["state"] == "blocked"


def test_instructions_unknown_artifact(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    make_change(tmp_path, "mychange")
    rc = cmd_instructions("unknown", "mychange")
    assert rc == 1


def test_instructions_missing_change(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "deltaspec" / "changes").mkdir(parents=True)
    rc = cmd_instructions("proposal", "ghost")
    assert rc == 1
