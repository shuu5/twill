"""Shared fixtures and helpers for autopilot tests."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from twl.autopilot.mergegate import MergeGate


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    """Autopilot directory with checkpoints subdirectory."""
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    (d / "checkpoints").mkdir()
    return d


@pytest.fixture
def scripts_root(tmp_path: Path) -> Path:
    d = tmp_path / "scripts"
    d.mkdir()
    return d


@pytest.fixture
def gate(autopilot_dir: Path, scripts_root: Path) -> MergeGate:
    return MergeGate(
        issue="439",
        pr_number="500",
        branch="feat/439-phase-review-guard",
        autopilot_dir=autopilot_dir,
        scripts_root=scripts_root,
    )


@pytest.fixture
def gate_force(autopilot_dir: Path, scripts_root: Path) -> MergeGate:
    return MergeGate(
        issue="439",
        pr_number="500",
        branch="feat/439-phase-review-guard",
        autopilot_dir=autopilot_dir,
        scripts_root=scripts_root,
        force=True,
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _phase_review_json(
    *,
    findings: list[dict] | None = None,
    status: str = "PASS",
) -> dict:
    """Build a minimal phase-review.json payload."""
    findings = findings or []
    critical_count = sum(
        1 for f in findings if f.get("severity") == "CRITICAL"
    )
    return {
        "step": "phase-review",
        "status": status,
        "findings_summary": f"{critical_count} CRITICAL, 0 WARNING",
        "critical_count": critical_count,
        "findings": findings,
        "timestamp": "2026-04-11T00:00:00Z",
    }


def _write_phase_review(autopilot_dir: Path, data: dict) -> Path:
    """Write phase-review.json to the checkpoints directory."""
    ckpt_file = autopilot_dir / "checkpoints" / "phase-review.json"
    ckpt_file.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    return ckpt_file
