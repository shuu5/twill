"""E2E integration tests for autopilot chain transitions — Issue #450.

Verifies that the setup → test-ready → pr-verify chain transition sequence
completes with zero inject-skips.

Covers spec:
  deltaspec/changes/issue-450/specs/chain-e2e-transition/spec.md
    Requirement: E2E chain 遷移 integration test
    Requirement: inject-skip 検出アサーション

Design:
  - Uses ChainRunner.resolve_next_workflow() directly (no tmux/gh/claude)
  - _load_worker_lifecycle_flow patched with same flow fixture as test_resolve_next_workflow.py
  - state ファイル I/O は tmp_path で完結
  - inject-skip = resolve_next_workflow が空文字を返すこと
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from twl.autopilot.chain import ChainRunner


# ---------------------------------------------------------------------------
# Worker lifecycle flow — mirrors plugins/twl/deps.yaml meta_chains
# (same fixture used in test_resolve_next_workflow.py)
# ---------------------------------------------------------------------------

WORKER_LIFECYCLE_FLOW: list[dict] = [
    {
        "id": "setup",
        "chain": "setup",
        "next": [
            {"condition": "quick && autopilot", "goto": "quick-path"},
            {"condition": "!quick && autopilot", "goto": "test-ready"},
            {"condition": "!autopilot", "stop": True,
             "message": "setup chain 完了。次: /twl:workflow-test-ready"},
        ],
    },
    {
        "id": "quick-path",
        "chain": None,
        "description": "quick Issue の短縮パス",
        "inline_steps": ["直接実装 → commit → push", "PR 作成", "ac-verify", "merge-gate"],
        "next": [{"goto": "done"}],
    },
    {
        "id": "test-ready",
        "chain": "test-ready",
        "skill": "workflow-test-ready",
        "next": [
            {"condition": "autopilot", "goto": "pr-verify"},
            {"condition": "!autopilot", "stop": True,
             "message": "完了。次: /twl:workflow-pr-verify"},
        ],
    },
    {
        "id": "pr-verify",
        "chain": "pr-verify",
        "skill": "workflow-pr-verify",
        "next": [
            {"condition": "autopilot", "goto": "pr-fix"},
            {"condition": "!autopilot", "stop": True,
             "message": "workflow-pr-verify 完了。"},
        ],
    },
    {
        "id": "pr-fix",
        "chain": "pr-fix",
        "skill": "workflow-pr-fix",
        "next": [
            {"condition": "autopilot", "goto": "pr-merge"},
            {"condition": "!autopilot", "stop": True,
             "message": "workflow-pr-fix 完了。"},
        ],
    },
    {
        "id": "pr-merge",
        "chain": "pr-merge",
        "skill": "workflow-pr-merge",
        "terminal": True,
    },
    {
        "id": "done",
        "terminal": True,
    },
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _assert_no_inject_skip(result: str, from_workflow: str) -> None:
    """resolve_next_workflow が空文字を返した場合に inject-skip として失敗させる。"""
    assert result != "", (
        f"inject-skip 検出: workflow_done={from_workflow!r} の次 workflow が空です。"
        " orchestrator が inject_next_workflow を呼べません。"
    )


def _make_runner(tmp_path: Path) -> ChainRunner:
    scripts_root = tmp_path / "scripts"
    scripts_root.mkdir()
    autopilot_dir = tmp_path / ".autopilot"
    autopilot_dir.mkdir()
    return ChainRunner(scripts_root=scripts_root, autopilot_dir=autopilot_dir)


def _write_issue_state(autopilot_dir: Path, issue_num: int, workflow_done: str) -> Path:
    """tmp_path 配下に issue state ファイルを作成する。"""
    issues_dir = autopilot_dir / "issues"
    issues_dir.mkdir(exist_ok=True)
    data = {
        "issue": issue_num,
        "status": "running",
        "branch": f"feat/{issue_num}-test-branch",
        "pr": None,
        "window": f"ap-#{issue_num}",
        "started_at": "2026-04-12T00:00:00Z",
        "updated_at": "2026-04-12T00:00:00Z",
        "current_step": "",
        "retry_count": 0,
        "fix_instructions": None,
        "merged_at": None,
        "files_changed": [],
        "failure": None,
        "workflow_done": workflow_done,
        "implementation_pr": None,
        "deltaspec_mode": None,
        "is_quick": False,
    }
    f = issues_dir / f"issue-{issue_num}.json"
    f.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    return f


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def runner(tmp_path: Path) -> ChainRunner:
    return _make_runner(tmp_path)


@pytest.fixture()
def patched_runner(runner: ChainRunner):
    """ChainRunner with _load_worker_lifecycle_flow patched to use test fixture."""
    with patch.object(runner, "_load_worker_lifecycle_flow", return_value=WORKER_LIFECYCLE_FLOW):
        yield runner


# ---------------------------------------------------------------------------
# Scenario: setup 完了後に test-ready が次 workflow として返される
# ---------------------------------------------------------------------------

class TestSetupToTestReadyTransition:
    """Issue #450 AC-1: setup chain 完了 → workflow_done=setup → next=workflow-test-ready."""

    def test_setup_returns_test_ready(self, patched_runner: ChainRunner) -> None:
        """workflow_done=setup で resolve_next_workflow が workflow-test-ready を返す。"""
        result = patched_runner.resolve_next_workflow(
            "setup", is_autopilot=True, is_quick=False
        )
        _assert_no_inject_skip(result, "setup")
        assert result == "workflow-test-ready", (
            f"expected 'workflow-test-ready', got {result!r}"
        )

    def test_setup_with_state_file(self, tmp_path: Path, runner: ChainRunner) -> None:
        """state ファイルに workflow_done=setup が書かれた状態で遷移を検証する。"""
        _write_issue_state(runner.autopilot_dir, issue_num=450, workflow_done="setup")
        with patch.object(runner, "_load_worker_lifecycle_flow", return_value=WORKER_LIFECYCLE_FLOW):
            result = runner.resolve_next_workflow("setup", is_autopilot=True, is_quick=False)
        _assert_no_inject_skip(result, "setup")
        assert result == "workflow-test-ready"


# ---------------------------------------------------------------------------
# Scenario: test-ready 完了後に pr-verify が次 workflow として返される
# ---------------------------------------------------------------------------

class TestTestReadyToPrVerifyTransition:
    """Issue #450 AC-1: test-ready chain 完了 → workflow_done=test-ready → next=workflow-pr-verify."""

    def test_test_ready_returns_pr_verify(self, patched_runner: ChainRunner) -> None:
        """workflow_done=test-ready で resolve_next_workflow が workflow-pr-verify を返す。"""
        result = patched_runner.resolve_next_workflow(
            "test-ready", is_autopilot=True, is_quick=False
        )
        _assert_no_inject_skip(result, "test-ready")
        assert result == "workflow-pr-verify", (
            f"expected 'workflow-pr-verify', got {result!r}"
        )

    def test_test_ready_with_state_file(self, tmp_path: Path, runner: ChainRunner) -> None:
        """state ファイルに workflow_done=test-ready が書かれた状態で遷移を検証する。"""
        _write_issue_state(runner.autopilot_dir, issue_num=450, workflow_done="test-ready")
        with patch.object(runner, "_load_worker_lifecycle_flow", return_value=WORKER_LIFECYCLE_FLOW):
            result = runner.resolve_next_workflow("test-ready", is_autopilot=True, is_quick=False)
        _assert_no_inject_skip(result, "test-ready")
        assert result == "workflow-pr-verify"


# ---------------------------------------------------------------------------
# Scenario: pr-verify 完了後の遷移確認（pr-fix または terminal）
# ---------------------------------------------------------------------------

class TestPrVerifyTransition:
    """Issue #450 AC-1: pr-verify に到達した後の遷移確認。"""

    def test_pr_verify_returns_pr_fix(self, patched_runner: ChainRunner) -> None:
        """workflow_done=pr-verify (autopilot=True) で workflow-pr-fix を返す。"""
        result = patched_runner.resolve_next_workflow(
            "pr-verify", is_autopilot=True, is_quick=False
        )
        # pr-verify → pr-fix (not terminal in autopilot mode)
        assert result == "workflow-pr-fix", (
            f"expected 'workflow-pr-fix', got {result!r}"
        )

    def test_pr_verify_autopilot_false_stops(self, patched_runner: ChainRunner) -> None:
        """workflow_done=pr-verify (autopilot=False) で停止（空を返す）。"""
        result = patched_runner.resolve_next_workflow(
            "pr-verify", is_autopilot=False, is_quick=False
        )
        assert result == "", (
            f"autopilot=False の pr-verify は停止すべきだが {result!r} を返した"
        )


# ---------------------------------------------------------------------------
# Scenario: 3 Issue 以上の chain 遷移が成立する（inject-skip = 0）
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("issue_num,workflow_done,expected_next", [
    (451, "setup", "workflow-test-ready"),
    (452, "test-ready", "workflow-pr-verify"),
    (453, "pr-verify", "workflow-pr-fix"),
])
def test_three_issues_no_inject_skip(
    tmp_path: Path,
    issue_num: int,
    workflow_done: str,
    expected_next: str,
) -> None:
    """Issue #450 AC-3: 3 Issue 分の chain 遷移が inject-skip 0 で成立することを確認。

    3 件の Issue がそれぞれ異なる workflow_done 状態にあるとき、
    resolve_next_workflow が inject-skip（空文字）を返さないことを検証する。
    """
    runner = _make_runner(tmp_path)
    _write_issue_state(runner.autopilot_dir, issue_num=issue_num, workflow_done=workflow_done)
    with patch.object(runner, "_load_worker_lifecycle_flow", return_value=WORKER_LIFECYCLE_FLOW):
        result = runner.resolve_next_workflow(workflow_done, is_autopilot=True, is_quick=False)
    _assert_no_inject_skip(result, workflow_done)
    assert result == expected_next, (
        f"issue #{issue_num}: workflow_done={workflow_done!r} → expected {expected_next!r}, got {result!r}"
    )


# ---------------------------------------------------------------------------
# Scenario: resolve_next_workflow が空を返した場合のテスト失敗（inject-skip 検出）
# ---------------------------------------------------------------------------

class TestInjectSkipDetection:
    """Requirement: inject-skip 検出アサーション。"""

    def test_inject_skip_helper_raises_on_empty(self, patched_runner: ChainRunner) -> None:
        """_assert_no_inject_skip は空文字に対して AssertionError を発生させる。"""
        with pytest.raises(AssertionError, match="inject-skip 検出"):
            _assert_no_inject_skip("", "setup")

    def test_inject_skip_helper_passes_on_nonempty(self) -> None:
        """_assert_no_inject_skip は非空文字に対して AssertionError を発生させない。"""
        _assert_no_inject_skip("workflow-test-ready", "setup")  # should not raise

    def test_unknown_workflow_returns_empty_not_skipped(self, patched_runner: ChainRunner) -> None:
        """未知の workflow_done は空文字を返す（inject-skip として正しく検出される）。"""
        result = patched_runner.resolve_next_workflow(
            "unknown-workflow", is_autopilot=True, is_quick=False
        )
        assert result == "", (
            f"未知の workflow に対して空文字を期待したが {result!r} を返した"
        )


# ---------------------------------------------------------------------------
# Full E2E chain sequence: setup → test-ready → pr-verify
# ---------------------------------------------------------------------------

class TestFullChainSequence:
    """Issue #450 AC-1 全体: setup から pr-verify まで inject-skip 0 で到達する。"""

    def test_full_chain_no_inject_skip(self, patched_runner: ChainRunner) -> None:
        """setup → test-ready → pr-verify の chain 全遷移で inject-skip が 0 であること。"""
        chain_sequence = [
            ("setup", "workflow-test-ready"),
            ("test-ready", "workflow-pr-verify"),
        ]
        inject_skips = 0
        for workflow_done, expected_next in chain_sequence:
            result = patched_runner.resolve_next_workflow(
                workflow_done, is_autopilot=True, is_quick=False
            )
            if not result:
                inject_skips += 1
            assert result == expected_next, (
                f"workflow_done={workflow_done!r}: expected {expected_next!r}, got {result!r}"
            )

        assert inject_skips == 0, (
            f"chain 遷移で {inject_skips} 件の inject-skip が発生しました（AC-3: 0 件であること）"
        )
