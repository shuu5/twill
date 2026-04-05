"""Tests for twl.autopilot.checkpoint.

Covers write/read happy paths, field extraction, critical-findings filter,
validation errors, and exit codes via CLI main().
"""

import json
from pathlib import Path

import pytest

from twl.autopilot.checkpoint import (
    CheckpointManager,
    CheckpointError,
    CheckpointArgError,
    main,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def ckpt_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot" / "checkpoints"
    d.mkdir(parents=True)
    return d


@pytest.fixture
def mgr(ckpt_dir: Path) -> CheckpointManager:
    return CheckpointManager(checkpoint_dir=ckpt_dir)


# ---------------------------------------------------------------------------
# CheckpointManager.write
# ---------------------------------------------------------------------------


class TestWrite:
    def test_creates_json_file(self, mgr: CheckpointManager, ckpt_dir: Path) -> None:
        mgr.write(step="phase-review", status="PASS")
        assert (ckpt_dir / "phase-review.json").is_file()

    def test_json_schema(self, mgr: CheckpointManager, ckpt_dir: Path) -> None:
        findings = [
            {"severity": "CRITICAL", "message": "bad"},
            {"severity": "WARNING", "message": "warn"},
        ]
        mgr.write(step="phase-review", status="WARN", findings=findings)
        data = json.loads((ckpt_dir / "phase-review.json").read_text())
        assert data["step"] == "phase-review"
        assert data["status"] == "WARN"
        assert data["critical_count"] == 1
        assert data["findings_summary"] == "1 CRITICAL, 1 WARNING"
        assert len(data["findings"]) == 2
        assert "timestamp" in data

    def test_empty_findings_default(self, mgr: CheckpointManager, ckpt_dir: Path) -> None:
        mgr.write(step="e2e-screening", status="PASS")
        data = json.loads((ckpt_dir / "e2e-screening.json").read_text())
        assert data["findings"] == []
        assert data["critical_count"] == 0
        assert data["findings_summary"] == "0 CRITICAL, 0 WARNING"

    def test_invalid_step_raises(self, mgr: CheckpointManager) -> None:
        with pytest.raises(CheckpointArgError, match="不正な文字"):
            mgr.write(step="bad step!", status="PASS")

    def test_invalid_status_raises(self, mgr: CheckpointManager) -> None:
        with pytest.raises(CheckpointArgError, match="PASS, WARN, FAIL"):
            mgr.write(step="phase-review", status="OK")

    def test_empty_step_raises(self, mgr: CheckpointManager) -> None:
        with pytest.raises(CheckpointArgError, match="--step は必須"):
            mgr.write(step="", status="PASS")


# ---------------------------------------------------------------------------
# CheckpointManager.read
# ---------------------------------------------------------------------------


class TestRead:
    def _write(self, mgr: CheckpointManager, **kwargs) -> None:
        mgr.write(**kwargs)

    def test_read_status_field(self, mgr: CheckpointManager) -> None:
        self._write(mgr, step="merge-gate", status="FAIL")
        assert mgr.read(step="merge-gate", field="status") == "FAIL"

    def test_read_critical_count(self, mgr: CheckpointManager) -> None:
        findings = [{"severity": "CRITICAL", "message": "c1"}, {"severity": "WARNING", "message": "w1"}]
        self._write(mgr, step="merge-gate", status="FAIL", findings=findings)
        assert mgr.read(step="merge-gate", field="critical_count") == "1"

    def test_read_findings_summary(self, mgr: CheckpointManager) -> None:
        self._write(mgr, step="all-pass-check", status="PASS")
        assert mgr.read(step="all-pass-check", field="findings_summary") == "0 CRITICAL, 0 WARNING"

    def test_critical_findings_filter(self, mgr: CheckpointManager) -> None:
        findings = [
            {"severity": "CRITICAL", "message": "c1"},
            {"severity": "WARNING", "message": "w1"},
            {"severity": "CRITICAL", "message": "c2"},
        ]
        self._write(mgr, step="phase-review", status="FAIL", findings=findings)
        result = json.loads(mgr.read(step="phase-review", critical_findings=True))
        assert len(result) == 2
        assert all(f["severity"] == "CRITICAL" for f in result)

    def test_missing_file_raises(self, mgr: CheckpointManager) -> None:
        with pytest.raises(CheckpointError, match="checkpoint not found"):
            mgr.read(step="nonexistent", field="status")

    def test_no_field_no_critical_raises(self, mgr: CheckpointManager) -> None:
        with pytest.raises(CheckpointArgError):
            mgr.read(step="phase-review")

    def test_invalid_step_raises(self, mgr: CheckpointManager) -> None:
        with pytest.raises(CheckpointArgError, match="不正な文字"):
            mgr.read(step="bad step!", field="status")


# ---------------------------------------------------------------------------
# CLI main()
# ---------------------------------------------------------------------------


class TestCLI:
    def test_write_exit_0(self, ckpt_dir: Path) -> None:
        rc = main([
            "write",
            "--step", "phase-review",
            "--status", "PASS",
            "--findings", "[]",
        ])
        assert rc == 0

    def test_read_exit_0(self, ckpt_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(
            "twl.autopilot.checkpoint._checkpoint_dir",
            lambda: ckpt_dir,
        )
        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)
        mgr.write(step="phase-review", status="PASS")
        rc = main(["read", "--step", "phase-review", "--field", "status"])
        assert rc == 0

    def test_missing_file_exit_1(self, ckpt_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(
            "twl.autopilot.checkpoint._checkpoint_dir",
            lambda: ckpt_dir,
        )
        rc = main(["read", "--step", "nonexistent", "--field", "status"])
        assert rc == 1

    def test_invalid_status_exit_2(self, ckpt_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(
            "twl.autopilot.checkpoint._checkpoint_dir",
            lambda: ckpt_dir,
        )
        rc = main(["write", "--step", "phase-review", "--status", "INVALID"])
        assert rc == 2

    def test_invalid_findings_json_exit_1(self, ckpt_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(
            "twl.autopilot.checkpoint._checkpoint_dir",
            lambda: ckpt_dir,
        )
        rc = main(["write", "--step", "phase-review", "--status", "PASS", "--findings", "not-json"])
        assert rc == 1

    def test_no_subcommand_exit_2(self) -> None:
        rc = main([])
        assert rc == 2
