"""Tests for audit integration in checkpoint.write() (issue-642).

Covers:
- checkpoint 保全コピー: audit 有効時に既存ファイルをタイムスタンプ付きでコピーしてから上書き
- checkpoint 初回 write は保全不要: 既存ファイルなしのケースはコピーなし
- audit 無効時の動作不変: コピーなしで通常の書き込みのみ

Scenarios from: spec.md Requirement: checkpoint 自動保全
"""

from __future__ import annotations

import json
import re
import time
from pathlib import Path

import pytest

from twl.autopilot.checkpoint import CheckpointManager


def _write_active(project_dir: Path, run_id: str = "cp-test-run") -> Path:
    """Write .audit/.active and return the audit run directory."""
    audit_dir = project_dir / ".audit"
    audit_dir.mkdir(parents=True, exist_ok=True)
    run_dir = audit_dir / run_id
    run_dir.mkdir(exist_ok=True)
    (run_dir / "checkpoints").mkdir(exist_ok=True)
    payload = {
        "run_id": run_id,
        "started_at": "2024-01-01T00:00:00Z",
        "audit_dir": str(run_dir),
    }
    (audit_dir / ".active").write_text(json.dumps(payload), encoding="utf-8")
    return run_dir


# ===========================================================================
# Requirement: checkpoint 自動保全
# ===========================================================================


class TestCheckpointAuditPreservation:
    """Scenario: checkpoint 保全コピー"""

    def test_existing_checkpoint_copied_before_overwrite(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """WHEN audit が有効で既存 phase-review.json がある状態で checkpoint.write() を実行する
        THEN 既存ファイルが .audit/<run-id>/checkpoints/phase-review-<ISO8601>.json にコピーされ
             新データで上書きされる"""
        # Setup: create checkpoint dir + existing checkpoint
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        ckpt_dir.mkdir(parents=True)
        original_data = {
            "step": "phase-review", "status": "PASS",
            "findings": [], "critical_count": 0,
            "findings_summary": "0 CRITICAL, 0 WARNING",
            "timestamp": "2024-01-01T00:00:00Z",
        }
        (ckpt_dir / "phase-review.json").write_text(
            json.dumps(original_data), encoding="utf-8"
        )

        # Setup: audit active
        run_dir = _write_active(tmp_path, run_id="cp-audit-run")

        # Patch is_audit_active and resolve_audit_dir if audit module exists
        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: True
            )
            monkeypatch.setattr(
                audit_mod, "resolve_audit_dir",
                lambda project_root=None: run_dir
            )
        except ImportError:
            pytest.skip("twl.autopilot.audit not yet implemented")

        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)
        mgr.write(step="phase-review", status="FAIL", findings=[
            {"severity": "CRITICAL", "message": "new finding"}
        ])

        # New checkpoint written
        new_data = json.loads((ckpt_dir / "phase-review.json").read_text())
        assert new_data["status"] == "FAIL"

        # Archived copy exists in audit dir
        archive_dir = run_dir / "checkpoints"
        archived = list(archive_dir.glob("phase-review-*.json"))
        assert len(archived) == 1, \
            f"Expected exactly 1 archived checkpoint, got: {list(archive_dir.iterdir())}"

        # Archive filename has ISO8601 timestamp pattern
        archived_name = archived[0].name
        assert re.search(r"phase-review-\d{8}T\d{6}Z\.json", archived_name), \
            f"Archive filename does not match expected pattern: {archived_name}"

        # Archived content is the original data
        archived_data = json.loads(archived[0].read_text())
        assert archived_data["status"] == "PASS"

    def test_first_write_no_archive_created(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """WHEN audit が有効な状態で既存ファイルなしに checkpoint.write() を実行する
        THEN コピーなしで通常通り新規書き込みされる"""
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        ckpt_dir.mkdir(parents=True)

        run_dir = _write_active(tmp_path, run_id="first-write-run")

        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: True
            )
            monkeypatch.setattr(
                audit_mod, "resolve_audit_dir",
                lambda project_root=None: run_dir
            )
        except ImportError:
            pytest.skip("twl.autopilot.audit not yet implemented")

        # No existing checkpoint
        assert not (ckpt_dir / "phase-review.json").exists()

        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)
        mgr.write(step="phase-review", status="PASS")

        # Checkpoint created normally
        assert (ckpt_dir / "phase-review.json").is_file()

        # No archive (no previous file to copy)
        archive_dir = run_dir / "checkpoints"
        archived = list(archive_dir.glob("phase-review-*.json")) if archive_dir.exists() else []
        assert len(archived) == 0, \
            f"Expected no archived copies for first write, got: {archived}"

    def test_audit_inactive_no_archive(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """WHEN audit が無効な状態で checkpoint.write() を実行する
        THEN コピーなしで通常の書き込みのみ（既存動作不変）"""
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        ckpt_dir.mkdir(parents=True)
        (ckpt_dir / "phase-review.json").write_text(
            json.dumps({"step": "phase-review", "status": "PASS", "findings": []}),
            encoding="utf-8"
        )

        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: False
            )
        except ImportError:
            # audit not implemented — assume checkpoint behaves normally
            pass

        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)
        mgr.write(step="phase-review", status="FAIL")

        # New data written
        data = json.loads((ckpt_dir / "phase-review.json").read_text())
        assert data["status"] == "FAIL"

        # No audit directory created
        audit_dir = tmp_path / ".audit"
        if audit_dir.exists():
            for run_dir in audit_dir.iterdir():
                cp_dir = run_dir / "checkpoints"
                if cp_dir.exists():
                    assert list(cp_dir.glob("phase-review-*.json")) == [], \
                        "Audit archive should not be created when audit is inactive"

    def test_multiple_writes_create_multiple_archives(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Edge case: 複数回 write すると複数のアーカイブが作成される"""
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        ckpt_dir.mkdir(parents=True)
        run_dir = _write_active(tmp_path, run_id="multi-write-run")

        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: True
            )
            monkeypatch.setattr(
                audit_mod, "resolve_audit_dir",
                lambda project_root=None: run_dir
            )
        except ImportError:
            pytest.skip("twl.autopilot.audit not yet implemented")

        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)
        mgr.write(step="phase-review", status="PASS")  # first: no archive
        time.sleep(0.01)  # ensure different timestamps
        mgr.write(step="phase-review", status="WARN")  # second: archives first
        time.sleep(0.01)
        mgr.write(step="phase-review", status="FAIL")  # third: archives second

        archive_dir = run_dir / "checkpoints"
        archived = list(archive_dir.glob("phase-review-*.json")) if archive_dir.exists() else []
        assert len(archived) >= 2, \
            f"Expected at least 2 archives after 3 writes, got {len(archived)}: {archived}"


# ===========================================================================
# Edge cases: archive timestamp format
# ===========================================================================


class TestCheckpointArchiveTimestamp:
    def test_archive_filename_timestamp_format(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Edge case: アーカイブファイル名のタイムスタンプが YYYYMMDDTHHMMSSz 形式"""
        ckpt_dir = tmp_path / ".autopilot" / "checkpoints"
        ckpt_dir.mkdir(parents=True)
        (ckpt_dir / "e2e-screening.json").write_text(
            json.dumps({"step": "e2e-screening", "status": "PASS", "findings": []}),
            encoding="utf-8"
        )
        run_dir = _write_active(tmp_path, run_id="ts-format-run")

        try:
            import twl.autopilot.audit as audit_mod  # type: ignore[import]
            monkeypatch.setattr(
                audit_mod, "is_audit_active",
                lambda project_root=None: True
            )
            monkeypatch.setattr(
                audit_mod, "resolve_audit_dir",
                lambda project_root=None: run_dir
            )
        except ImportError:
            pytest.skip("twl.autopilot.audit not yet implemented")

        mgr = CheckpointManager(checkpoint_dir=ckpt_dir)
        mgr.write(step="e2e-screening", status="FAIL")

        archive_dir = run_dir / "checkpoints"
        archived = list(archive_dir.glob("e2e-screening-*.json")) if archive_dir.exists() else []
        assert archived, "Expected at least one archived file"
        # Check: YYYYMMDDTHHMMSSz pattern
        pattern = re.compile(r"e2e-screening-\d{8}T\d{6}Z\.json")
        assert pattern.match(archived[0].name), \
            f"Archive filename format mismatch: {archived[0].name}"
