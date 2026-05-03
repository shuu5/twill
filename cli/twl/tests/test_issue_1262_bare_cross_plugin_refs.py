"""Tests for Issue #1262: bare cross-plugin / skills/ prefix refs cleanup in su-observer docs.

TDD RED phase — all tests FAIL before the fixes are applied.

Files under test:
  plugins/twl/skills/su-observer/refs/pitfalls-catalog.md
  plugins/twl/skills/su-observer/refs/su-observer-wave-management.md

AC list:
  AC-1: bare cross-plugin reference in pitfalls-catalog.md §17 L876 is replaced with
        bash "$(git rev-parse --show-toplevel)/plugins/session/scripts/session-comm.sh"
        + # cross-plugin reference comment
  AC-2: tmux kill-window -t <WORKER_WINDOW> bare window-name usage in §17 L879 is fixed
        to use a session-qualified target (session:window form)
  AC-3: skills/ prefix references in su-observer-wave-management.md L134-135 are resolved
        to full portable paths
  AC-4: regression guard — none of the three bad patterns re-appear after fix
"""

from __future__ import annotations

from pathlib import Path

WORKTREE_ROOT = Path(__file__).resolve().parents[3]

PITFALLS_CATALOG = (
    WORKTREE_ROOT / "plugins/twl/skills/su-observer/refs/pitfalls-catalog.md"
)
WAVE_MANAGEMENT = (
    WORKTREE_ROOT / "plugins/twl/skills/su-observer/refs/su-observer-wave-management.md"
)


# ---------------------------------------------------------------------------
# AC-1: bare cross-plugin session-comm.sh reference in pitfalls-catalog.md §17
# ---------------------------------------------------------------------------


def test_ac1_session_comm_not_bare_cross_plugin():
    """AC-1: pitfalls-catalog.md §17 の session-comm.sh 参照が bare 形式でない
    RED: 修正前は 'bash plugins/session/scripts/session-comm.sh' が含まれるため FAIL
    GREEN: $(git rev-parse --show-toplevel)/... 形式に修正後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    assert "bash plugins/session/scripts/session-comm.sh" not in content, (
        "bare cross-plugin reference detected in pitfalls-catalog.md — "
        "expected: bash \"$(git rev-parse --show-toplevel)/plugins/session/scripts/session-comm.sh\""
    )


def test_ac1_session_comm_uses_absolute_path_form():
    """AC-1: pitfalls-catalog.md §17 の session-comm.sh 参照が絶対パス形式を含む
    RED: 修正前は git rev-parse 形式が存在しないため FAIL
    GREEN: 修正後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    assert 'git rev-parse --show-toplevel)/plugins/session/scripts/session-comm.sh' in content, (
        "expected session-comm.sh reference with $(git rev-parse --show-toplevel) not found in "
        "pitfalls-catalog.md §17"
    )


# ---------------------------------------------------------------------------
# AC-2: bare tmux kill-window in pitfalls-catalog.md §17
# ---------------------------------------------------------------------------


def test_ac2_kill_window_not_bare_window_name():
    """AC-2: §17 の tmux kill-window -t <WORKER_WINDOW> が session 修飾なし形式でない
    RED: 修正前は bare window name が残存するため FAIL
    GREEN: session:window 形式に修正後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    lines = content.splitlines()

    # §17 section 内 (L860 以降) の kill-window 行を探す
    in_section17 = False
    for line in lines:
        if "§17" in line or "## 17" in line:
            in_section17 = True
        if in_section17 and "kill-window" in line and "<WORKER_WINDOW>" in line:
            # session 修飾なし (":"が含まれない) は NG
            assert ":" in line, (
                f"bare window-name kill-window found in §17: {line.strip()!r} — "
                "expected session-qualified target e.g. $SESSION:<WORKER_WINDOW>"
            )


# ---------------------------------------------------------------------------
# AC-3: skills/ prefix in su-observer-wave-management.md L134-135
# ---------------------------------------------------------------------------


def test_ac3_wave_management_no_bare_skills_prefix():
    """AC-3: su-observer-wave-management.md の skills/ prefix 形式が除去されている
    RED: 修正前は 'skills/su-observer/scripts/' が残存するため FAIL
    GREEN: 正規パス形式に修正後 PASS
    """
    content = WAVE_MANAGEMENT.read_text(encoding="utf-8")
    # bare 'skills/' prefix (CLAUDE_PLUGIN_ROOT や git rev-parse なし) を検出
    lines = content.splitlines()
    violations = [
        (i + 1, line)
        for i, line in enumerate(lines)
        if "`skills/su-observer/scripts/" in line
    ]
    assert not violations, (
        "bare skills/ prefix references found in su-observer-wave-management.md:\n"
        + "\n".join(f"  L{lineno}: {line.strip()}" for lineno, line in violations)
    )


# ---------------------------------------------------------------------------
# AC-4: regression guard — all three bad patterns absent
# ---------------------------------------------------------------------------


def test_ac4_regression_all_bad_patterns_absent():
    """AC-4: 3 件の bad pattern がいずれも修正後に再出現しない
    RED: 修正前は少なくとも 1 件が残存するため FAIL
    GREEN: 全件修正後 PASS
    """
    pitfalls = PITFALLS_CATALOG.read_text(encoding="utf-8")
    wave = WAVE_MANAGEMENT.read_text(encoding="utf-8")

    errors: list[str] = []

    if "bash plugins/session/scripts/session-comm.sh" in pitfalls:
        errors.append(
            "pitfalls-catalog.md: bare 'bash plugins/session/scripts/session-comm.sh' still present"
        )

    if "`skills/su-observer/scripts/auto-next-spawn.sh`" in wave:
        errors.append(
            "su-observer-wave-management.md: bare 'skills/su-observer/scripts/auto-next-spawn.sh' still present"
        )

    if "`skills/su-observer/scripts/lib/observer-wave-check.sh`" in wave:
        errors.append(
            "su-observer-wave-management.md: bare 'skills/su-observer/scripts/lib/observer-wave-check.sh' still present"
        )

    assert not errors, "Regression failures:\n" + "\n".join(f"  - {e}" for e in errors)
