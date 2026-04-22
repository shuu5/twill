"""MergeGate guard functions and shared helpers — pre-merge invariant checks.

Extracted from mergegate.py to keep module size manageable.
These functions have no dependency on MergeGate instance attributes.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Shared error type
# ---------------------------------------------------------------------------


class MergeGateError(Exception):
    """Raised for validation or execution errors."""


# ---------------------------------------------------------------------------
# Shared regex
# ---------------------------------------------------------------------------

_ASCII_PRINTABLE = re.compile(r"[^\x20-\x7e]")


# ---------------------------------------------------------------------------
# Guard helpers
# ---------------------------------------------------------------------------


def _check_worktree_guard(cwd: str) -> None:
    """Reject execution from within a worktree (invariant B/C)."""
    if "/worktrees/" in cwd:
        raise MergeGateError(
            "worktrees/ 配下からの実行は禁止されています。"
            "main/ worktree から実行してください（不変条件B/C）"
        )


def _check_worker_window_guard() -> None:
    """Reject execution from autopilot Worker tmux window (defense-in-depth)."""
    result = subprocess.run(
        ["tmux", "display-message", "-p", "#W"],
        capture_output=True, text=True,
    )
    window = result.stdout.strip() if result.returncode == 0 else ""
    if re.match(r"^ap-#\d+$", window):
        safe_window = re.sub(r"[^a-zA-Z0-9#_-]", "", window)
        raise MergeGateError(
            f"autopilot Worker（{safe_window}）からの merge 実行は禁止されています（不変条件C）"
        )


def _check_running_guard(autopilot_status: str) -> None:
    """Reject merge when status=running (Worker has not declared merge-ready)."""
    if autopilot_status == "running":
        raise MergeGateError(
            "status=running（merge-ready 未宣言）での merge 実行は禁止されています（不変条件C）"
        )


# ---------------------------------------------------------------------------
# State helpers (wraps python3 -m twl.autopilot.state)
# ---------------------------------------------------------------------------


def _state_write(issue: str, role: str, **kwargs: str) -> None:
    """Write autopilot state fields via twl.autopilot.state module."""
    cmd = [
        sys.executable, "-m", "twl.autopilot.state",
        "write",
        "--type", "issue",
        "--issue", issue,
        "--role", role,
    ]
    for k, v in kwargs.items():
        cmd += ["--set", f"{k}={v}"]
    subprocess.run(cmd, check=False)


def _state_read(issue: str, field: str) -> str:
    """Read a single autopilot state field."""
    result = subprocess.run(
        [sys.executable, "-m", "twl.autopilot.state",
         "read", "--type", "issue", "--issue", issue, "--field", field],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout.strip()
    return ""


def _board_update(issue: str, scripts_root: Path, status: str = "Done") -> None:
    runner = scripts_root / "chain-runner.sh"
    if runner.exists():
        subprocess.run(
            ["bash", str(runner), "project-board-status-update", issue, status],
            check=False,
        )


def _detect_repo_mode() -> str:
    """Return 'worktree' or 'standard' based on git dir type."""
    result = subprocess.run(
        ["git", "rev-parse", "--git-dir"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise MergeGateError("git リポジトリ外で実行されています")
    git_dir = result.stdout.strip()
    return "standard" if git_dir == ".git" else "worktree"


# ---------------------------------------------------------------------------
# Phase-review guard constants
# ---------------------------------------------------------------------------

_PHASE_REVIEW_SKIP_LABELS = frozenset({"scope/direct", "quick"})


def _check_phase_review_guard(
    autopilot_dir: Path,
    issue_labels: list[str],
    force: bool,
) -> None:
    """Reject merge when phase-review checkpoint is absent or has CRITICAL findings.

    Skip logic:
    - If the issue has a scope/direct or quick label, skip all checks.
    - If --force is set and checkpoint is absent, emit a WARNING but continue.
    - If checkpoint is absent (and not skipped), raise MergeGateError.
    - If checkpoint has CRITICAL findings with confidence >= 80, raise MergeGateError.
    """
    # Label-based skip (scope/direct or quick)
    matched_labels = _PHASE_REVIEW_SKIP_LABELS.intersection(issue_labels)
    if matched_labels:
        print(
            "[merge-gate] INFO: phase-review チェックをスキップしました"
            f"（ラベル: {', '.join(sorted(matched_labels))}）",
            file=sys.stderr,
        )
        return

    checkpoint_file = autopilot_dir / "checkpoints" / "phase-review.json"

    if not checkpoint_file.exists():
        if force:
            print(
                "[merge-gate] WARNING: phase-review checkpoint が不在です"
                "（--force により続行）",
                file=sys.stderr,
            )
            return
        raise MergeGateError(
            "phase-review checkpoint が不在です。specialist review を実行してください"
        )

    # Read and check CRITICAL findings
    try:
        data = json.loads(checkpoint_file.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        raise MergeGateError(f"phase-review checkpoint の読み込みに失敗しました: {exc}") from exc

    findings = data.get("findings", [])
    if not isinstance(findings, list):
        findings = []
    blocking = [
        f for f in findings
        if isinstance(f, dict)
        and f.get("severity") == "CRITICAL"
        and f.get("confidence", 0) >= 80
    ]
    if blocking:
        details = "; ".join(
            _ASCII_PRINTABLE.sub("?", str(f.get("message", "no message")))
            for f in blocking
        )
        raise MergeGateError(
            f"phase-review で CRITICAL findings が検出されました（{len(blocking)} 件）: {details}"
        )
