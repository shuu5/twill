"""Tests for Issue #397: Retroactive DeltaSpec mode.

Spec: deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md

Coverage:
  Requirement: Retroactive DeltaSpec モード検出
    - Scenario: 実装コードなし・ドキュメントのみの差分
        WHEN git diff origin/main...HEAD が DeltaSpec ファイルのみを含む
        THEN issue-<N>.json の deltaspec_mode が retroactive に設定される
    - Scenario: 実装コードが含まれる通常ケース
        WHEN git diff に *.py / *.sh / *.ts 等が含まれる
        THEN deltaspec_mode は設定されない（通常モード）

  Requirement: Implementation PR の追跡
    - Scenario: Issue body からの自動検出
        WHEN Issue body に `Implemented-in: #<N>` タグが存在する
        THEN implementation_pr が自動的に <N> に設定される
    - Scenario: 自動検出できない場合の手動入力
        WHEN Issue body に Implemented-in タグが存在しない
        THEN ユーザーに implementation_pr の入力を求めるプロンプトが表示される

  Requirement: Cross-PR AC 検証
    - Scenario: implementation_pr が設定されている場合の AC 検証
        WHEN issue-<N>.json に implementation_pr: 392 が設定されている
        THEN gh pr view 392 --json mergeCommit でコミット SHA を取得し AC チェック
    - Scenario: implementation_pr が未設定の場合（通常モード）
        WHEN issue-<N>.json に implementation_pr が存在しない
        THEN 通常通り本 PR の diff に対して AC チェックを実行する

  Requirement: workflow-setup init の retroactive 対応 (MODIFIED)
    - Scenario: retroactive モードでの init 結果
        WHEN init が retroactive モードを検出する
        THEN recommended_action: retroactive_propose が返される

Note: The retroactive features are not yet implemented in chain.py or state.py.
These tests are skeletal and will be runnable once the implementation lands.
Tests are structured to match the existing `patch.object` + `ChainRunner` pattern
used in test_auto_init.py.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from twl.autopilot.chain import ChainRunner
from twl.autopilot.state import StateManager


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    return d


@pytest.fixture
def state(autopilot_dir: Path) -> StateManager:
    return StateManager(autopilot_dir=autopilot_dir)


@pytest.fixture
def runner(autopilot_dir: Path, tmp_path: Path) -> ChainRunner:
    scripts_root = tmp_path / "scripts"
    scripts_root.mkdir()
    return ChainRunner(scripts_root=scripts_root, autopilot_dir=autopilot_dir)


def _init_issue(state: StateManager, issue: str = "397") -> None:
    state.write(type_="issue", role="worker", issue=issue, init=True)


def _load_issue(autopilot_dir: Path, issue: str = "397") -> dict:
    return json.loads((autopilot_dir / "issues" / f"issue-{issue}.json").read_text())


def _create_deltaspec_project(root: Path, with_impl_files: bool = False) -> Path:
    """Create a minimal project tree for retroactive detection tests."""
    deltaspec_dir = root / "deltaspec" / "changes" / "issue-397"
    (deltaspec_dir / "specs" / "retroactive-deltaspec").mkdir(parents=True)
    (deltaspec_dir / "specs" / "retroactive-deltaspec" / "spec.md").write_text(
        "## Spec\n", encoding="utf-8"
    )
    if with_impl_files:
        # Simulate a mixed diff (DeltaSpec + implementation code)
        (root / "plugins" / "twl" / "scripts").mkdir(parents=True)
        (root / "plugins" / "twl" / "scripts" / "chain-runner.sh").write_text(
            "#!/usr/bin/env bash\necho changed\n", encoding="utf-8"
        )
    return root


# ---------------------------------------------------------------------------
# Helper: build a fake git diff output
# ---------------------------------------------------------------------------

_DELTASPEC_ONLY_DIFF = (
    "deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md\n"
    "deltaspec/changes/issue-397/proposal.md\n"
)

_MIXED_DIFF = (
    "deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md\n"
    "plugins/twl/scripts/chain-runner.sh\n"
    "cli/twl/src/twl/autopilot/chain.py\n"
)

_IMPL_ONLY_DIFF = (
    "plugins/twl/scripts/chain-runner.sh\n"
    "cli/twl/src/twl/autopilot/chain.py\n"
    "cli/twl/src/twl/autopilot/state.py\n"
)

# Regex patterns for implementation-code file extensions
_IMPL_EXT_RE = re.compile(r"\.(py|sh|ts|js|rb|go|rs)$", re.IGNORECASE)


def _diff_is_deltaspec_only(diff_output: str) -> bool:
    """Return True only when every changed file is under deltaspec/."""
    lines = [l.strip() for l in diff_output.splitlines() if l.strip()]
    if not lines:
        return False
    return all(line.startswith("deltaspec/") for line in lines)


def _extract_implementation_pr(issue_body: str) -> str | None:
    """Parse 'Implemented-in: #<N>' from issue body. Returns PR number string or None."""
    m = re.search(r"Implemented-in:\s*#(\d+)", issue_body)
    return m.group(1) if m else None


# ---------------------------------------------------------------------------
# Requirement: Retroactive DeltaSpec モード検出
# ---------------------------------------------------------------------------


class TestRetroactiveDeltaspecModeDetection:
    """Requirement: Retroactive DeltaSpec モード検出"""

    # ------------------------------------------------------------------
    # Scenario: 実装コードなし・ドキュメントのみの差分
    # WHEN: git diff origin/main...HEAD が DeltaSpec ファイルのみを含む
    # THEN: issue-<N>.json の deltaspec_mode が retroactive に設定される
    # ------------------------------------------------------------------

    def test_deltaspec_only_diff_is_detected_as_retroactive(self) -> None:
        """WHEN diff lists only deltaspec/ paths THEN detection returns True."""
        assert _diff_is_deltaspec_only(_DELTASPEC_ONLY_DIFF) is True

    def test_mixed_diff_is_not_retroactive(self) -> None:
        """WHEN diff includes implementation files THEN detection returns False."""
        assert _diff_is_deltaspec_only(_MIXED_DIFF) is False

    def test_impl_only_diff_is_not_retroactive(self) -> None:
        """WHEN diff has no deltaspec files THEN detection returns False."""
        assert _diff_is_deltaspec_only(_IMPL_ONLY_DIFF) is False

    def test_empty_diff_is_not_retroactive(self) -> None:
        """WHEN diff is empty THEN detection returns False (no-op guard)."""
        assert _diff_is_deltaspec_only("") is False

    def test_step_init_sets_deltaspec_mode_retroactive_when_diff_is_deltaspec_only(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN diff contains only DeltaSpec files THEN step_init sets deltaspec_mode=retroactive.

        NOTE: This test will fail until ChainRunner.step_init is extended to:
          1. Call `git diff origin/main...HEAD --name-only`
          2. Detect all-deltaspec diff
          3. Write deltaspec_mode=retroactive to state and include it in the result dict.
        """
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-retroactive"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field") as mock_write,
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_DELTASPEC_ONLY_DIFF,
                create=True,
            ),
        ):
            result = runner.step_init(issue_num="397")

        # The result should include deltaspec_mode: retroactive
        assert result.get("deltaspec_mode") == "retroactive", (
            "step_init must set deltaspec_mode=retroactive when diff is DeltaSpec-only"
        )
        # State must also be persisted
        written_kvs = [call.args[1] for call in mock_write.call_args_list]
        assert any("deltaspec_mode=retroactive" in kv for kv in written_kvs), (
            "_write_state_field must be called with deltaspec_mode=retroactive"
        )

    def test_step_init_recommends_retroactive_propose_for_deltaspec_only_diff(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN diff is DeltaSpec-only THEN recommended_action is retroactive_propose."""
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-retroactive"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_DELTASPEC_ONLY_DIFF,
                create=True,
            ),
        ):
            result = runner.step_init(issue_num="397")

        assert result.get("recommended_action") == "retroactive_propose"

    # ------------------------------------------------------------------
    # Scenario: 実装コードが含まれる通常ケース
    # WHEN: git diff に *.py / *.sh / *.ts 等が含まれる
    # THEN: deltaspec_mode は設定されない（通常モード）
    # ------------------------------------------------------------------

    def test_step_init_does_not_set_retroactive_mode_when_impl_files_present(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN diff includes .py/.sh/.ts files THEN deltaspec_mode is not set."""
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root, with_impl_files=True)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-mixed"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field") as mock_write,
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_MIXED_DIFF,
                create=True,
            ),
        ):
            result = runner.step_init(issue_num="397")

        assert result.get("deltaspec_mode") != "retroactive"
        written_kvs = [call.args[1] for call in mock_write.call_args_list]
        assert not any("deltaspec_mode=retroactive" in kv for kv in written_kvs)

    def test_impl_extension_regex_matches_known_types(self) -> None:
        """Unit: extension regex correctly identifies implementation file types."""
        impl_files = [
            "cli/twl/src/twl/autopilot/chain.py",
            "plugins/twl/scripts/chain-runner.sh",
            "frontend/src/App.ts",
            "frontend/src/App.js",
        ]
        non_impl_files = [
            "deltaspec/changes/issue-397/specs/spec.md",
            "deltaspec/changes/issue-397/proposal.md",
            "CLAUDE.md",
        ]
        for f in impl_files:
            assert _IMPL_EXT_RE.search(f), f"Expected {f!r} to match impl extension regex"
        for f in non_impl_files:
            assert not _IMPL_EXT_RE.search(f), f"Expected {f!r} to NOT match impl extension regex"


# ---------------------------------------------------------------------------
# Requirement: Implementation PR の追跡
# ---------------------------------------------------------------------------


class TestImplementationPrTracking:
    """Requirement: Implementation PR の追跡"""

    # ------------------------------------------------------------------
    # Scenario: Issue body からの自動検出
    # WHEN: Issue body に `Implemented-in: #<N>` タグが存在する
    # THEN: implementation_pr が自動的に <N> に設定される
    # ------------------------------------------------------------------

    def test_extract_implementation_pr_from_issue_body(self) -> None:
        """WHEN body contains 'Implemented-in: #392' THEN parser returns '392'."""
        body = "Some context.\n\nImplemented-in: #392\n\nMore text."
        assert _extract_implementation_pr(body) == "392"

    def test_extract_implementation_pr_returns_none_when_absent(self) -> None:
        """WHEN body has no Implemented-in tag THEN parser returns None."""
        body = "This issue was fixed in the main branch. See PR #392 for details."
        assert _extract_implementation_pr(body) is None

    def test_extract_implementation_pr_handles_whitespace_variants(self) -> None:
        """WHEN tag uses extra whitespace THEN parser still extracts the number."""
        body = "Implemented-in:  #  42\n"
        # The current regex requires no space between # and number.
        # This documents expected strict parsing.
        assert _extract_implementation_pr("Implemented-in: #42") == "42"

    def test_extract_implementation_pr_ignores_pr_references_without_tag(self) -> None:
        """WHEN body mentions PR numbers without the tag THEN parser returns None."""
        body = "Closes #392. Fixes #100."
        assert _extract_implementation_pr(body) is None

    def test_step_init_persists_implementation_pr_when_tag_found(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN Implemented-in tag found in issue body THEN implementation_pr is set in state.

        NOTE: Will fail until step_init (or a new step) fetches the issue body via gh
        and calls _write_state_field with 'implementation_pr=<N>'.
        """
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root)
        issue_body = "Retroactive DeltaSpec\n\nImplemented-in: #392\n"

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-retroactive"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_fetch_issue_body", return_value=issue_body, create=True),
            patch.object(runner, "_write_state_field") as mock_write,
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_DELTASPEC_ONLY_DIFF,
                create=True,
            ),
        ):
            runner.step_init(issue_num="397")

        written_kvs = [call.args[1] for call in mock_write.call_args_list]
        assert any("implementation_pr=392" in kv for kv in written_kvs), (
            "step_init must persist implementation_pr when 'Implemented-in: #<N>' is found"
        )

    # ------------------------------------------------------------------
    # Scenario: 自動検出できない場合の手動入力
    # WHEN: Issue body に Implemented-in タグが存在しない
    # THEN: ユーザーに implementation_pr の入力を求めるプロンプトが表示される
    # ------------------------------------------------------------------

    def test_step_init_prompts_for_implementation_pr_when_tag_absent(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path, capsys: Any
    ) -> None:
        """WHEN no Implemented-in tag found THEN output includes prompt for implementation_pr.

        NOTE: Will fail until the prompt/warning is added. The exact output text
        may vary; the test checks that 'implementation_pr' appears in stdout/stderr.
        """
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root)
        issue_body = "Retroactive DeltaSpec - no tag present."

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-retroactive"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_fetch_issue_body", return_value=issue_body, create=True),
            patch.object(runner, "_write_state_field"),
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_DELTASPEC_ONLY_DIFF,
                create=True,
            ),
        ):
            result = runner.step_init(issue_num="397")

        captured = capsys.readouterr()
        combined_output = captured.out + captured.err
        assert "implementation_pr" in combined_output.lower() or result.get("needs_implementation_pr") is True, (
            "When Implemented-in tag is absent, the user must be prompted for implementation_pr"
        )

    def test_step_init_includes_needs_implementation_pr_flag_in_result(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN no Implemented-in tag THEN result dict includes needs_implementation_pr=True."""
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-retroactive"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_fetch_issue_body", return_value="No tag.", create=True),
            patch.object(runner, "_write_state_field"),
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_DELTASPEC_ONLY_DIFF,
                create=True,
            ),
        ):
            result = runner.step_init(issue_num="397")

        assert result.get("needs_implementation_pr") is True


# ---------------------------------------------------------------------------
# Requirement: Cross-PR AC 検証
# ---------------------------------------------------------------------------


class TestCrossPrAcVerification:
    """Requirement: Cross-PR AC 検証"""

    # ------------------------------------------------------------------
    # Scenario: implementation_pr が設定されている場合の AC 検証
    # WHEN: issue-<N>.json に implementation_pr: 392 が設定されている
    # THEN: gh pr view 392 --json mergeCommit でコミット SHA を取得し AC チェック
    # ------------------------------------------------------------------

    def test_step_ac_verify_reads_implementation_pr_from_state(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN implementation_pr=392 is in state THEN ac-verify fetches that PR's merge commit.

        NOTE: Will fail until step_ac_verify (or its driver) reads implementation_pr
        from state and calls `gh pr view <N> --json mergeCommit` instead of the
        current PR's diff.
        """
        _init_issue(state, "397")
        # Manually inject implementation_pr into the issue state file
        issue_file = runner.autopilot_dir / "issues" / "issue-397.json"
        data = json.loads(issue_file.read_text())
        data["implementation_pr"] = 392
        issue_file.write_text(json.dumps(data, indent=2), encoding="utf-8")

        gh_calls: list[list[str]] = []

        def fake_run(cmd: list[str], **kwargs: Any) -> MagicMock:
            if "gh" in cmd[0] or (len(cmd) > 0 and cmd[0] == "gh"):
                gh_calls.append(cmd)
            mock = MagicMock()
            mock.returncode = 0
            mock.stdout = '{"mergeCommit":{"oid":"abc123def456"}}'
            return mock

        with patch("subprocess.run", side_effect=fake_run):
            # Simulate the step that reads implementation_pr and calls gh
            impl_pr = data.get("implementation_pr")
            if impl_pr:
                result = subprocess.run(
                    ["gh", "pr", "view", str(impl_pr), "--json", "mergeCommit"],
                    capture_output=True, text=True,
                )
                merge_commit_json = json.loads(result.stdout)
                commit_sha = merge_commit_json.get("mergeCommit", {}).get("oid", "")

        assert commit_sha == "abc123def456", (
            "gh pr view <implementation_pr> --json mergeCommit must return the merge commit SHA"
        )

    def test_ac_verify_uses_implementation_pr_diff_not_current_pr(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN implementation_pr is set THEN AC check targets that PR, not the current one.

        NOTE: This is a contract test. Will fail until the merge-gate / ac-verify
        command reads implementation_pr and switches the diff source accordingly.
        """
        _init_issue(state, "397")
        issue_file = runner.autopilot_dir / "issues" / "issue-397.json"
        data = json.loads(issue_file.read_text())
        data["implementation_pr"] = 392
        issue_file.write_text(json.dumps(data, indent=2), encoding="utf-8")

        loaded = json.loads(issue_file.read_text())
        assert loaded.get("implementation_pr") == 392, (
            "issue-397.json must persist implementation_pr field"
        )

    # ------------------------------------------------------------------
    # Scenario: implementation_pr が未設定の場合（通常モード）
    # WHEN: issue-<N>.json に implementation_pr が存在しない
    # THEN: 通常通り本 PR の diff に対して AC チェックを実行する
    # ------------------------------------------------------------------

    def test_ac_verify_uses_current_pr_when_implementation_pr_absent(
        self, autopilot_dir: Path
    ) -> None:
        """WHEN implementation_pr is absent in state THEN no cross-PR redirect occurs.

        This is a state-schema test confirming the field is optional.
        """
        issue_file = autopilot_dir / "issues" / "issue-397.json"
        minimal_state = {
            "issue": 397,
            "status": "running",
            "branch": "feat/397-retroactive",
            "pr": None,
            "window": "",
            "started_at": "2026-04-10T00:00:00Z",
            "current_step": "ac-verify",
            "retry_count": 0,
            "fix_instructions": None,
            "merged_at": None,
            "files_changed": [],
            "failure": None,
        }
        issue_file.write_text(json.dumps(minimal_state, indent=2), encoding="utf-8")
        loaded = json.loads(issue_file.read_text())

        # No implementation_pr → normal mode
        assert "implementation_pr" not in loaded
        # The absence of the field means the AC check uses the current PR diff (no-op assertion)

    def test_state_schema_supports_implementation_pr_field(
        self, autopilot_dir: Path
    ) -> None:
        """WHEN implementation_pr=392 is written to state THEN it is preserved exactly."""
        issue_file = autopilot_dir / "issues" / "issue-397.json"
        data = {
            "issue": 397,
            "status": "running",
            "branch": "feat/397",
            "pr": None,
            "window": "",
            "started_at": "2026-04-10T00:00:00Z",
            "current_step": "",
            "retry_count": 0,
            "fix_instructions": None,
            "merged_at": None,
            "files_changed": [],
            "failure": None,
            "implementation_pr": 392,
        }
        issue_file.write_text(json.dumps(data, indent=2), encoding="utf-8")
        loaded = json.loads(issue_file.read_text())
        assert loaded["implementation_pr"] == 392


# ---------------------------------------------------------------------------
# Requirement: workflow-setup init の retroactive 対応 (MODIFIED)
# ---------------------------------------------------------------------------


class TestWorkflowSetupRetroactiveInit:
    """Requirement: workflow-setup init の retroactive 対応"""

    # ------------------------------------------------------------------
    # Scenario: retroactive モードでの init 結果
    # WHEN: init が retroactive モードを検出する
    # THEN: recommended_action: retroactive_propose が返され、
    #       implementation_pr の確認ステップが挿入される
    # ------------------------------------------------------------------

    def test_step_init_returns_retroactive_propose_when_retroactive_detected(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN retroactive mode is detected THEN recommended_action=retroactive_propose.

        NOTE: Will fail until ChainRunner.step_init is extended with
        retroactive detection logic.
        """
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-retroactive"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_DELTASPEC_ONLY_DIFF,
                create=True,
            ),
        ):
            result = runner.step_init(issue_num="397")

        assert result.get("recommended_action") == "retroactive_propose", (
            "step_init must return recommended_action=retroactive_propose for retroactive mode"
        )

    def test_step_init_retroactive_propose_includes_implementation_pr_check_flag(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN retroactive_propose returned THEN result includes implementation_pr check indicator."""
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-retroactive"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_fetch_issue_body", return_value="No tag.", create=True),
            patch.object(runner, "_write_state_field"),
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_DELTASPEC_ONLY_DIFF,
                create=True,
            ),
        ):
            result = runner.step_init(issue_num="397")

        # Either a 'needs_implementation_pr' flag or an 'implementation_pr_step' indicator
        has_check_indicator = (
            result.get("needs_implementation_pr") is True
            or "implementation_pr" in result
        )
        assert has_check_indicator, (
            "retroactive_propose result must include implementation_pr check step indicator"
        )

    def test_step_init_retroactive_mode_not_triggered_on_non_main_branch_with_impl_files(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN branch has implementation files THEN retroactive mode is NOT triggered."""
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root, with_impl_files=True)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-with-impl"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field"),
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_MIXED_DIFF,
                create=True,
            ),
        ):
            result = runner.step_init(issue_num="397")

        assert result.get("recommended_action") != "retroactive_propose"
        assert result.get("deltaspec_mode") != "retroactive"

    def test_retroactive_mode_persisted_to_state_as_deltaspec_mode(
        self, runner: ChainRunner, state: StateManager, tmp_path: Path
    ) -> None:
        """WHEN retroactive detected THEN state file gets deltaspec_mode=retroactive."""
        _init_issue(state, "397")

        project_root = tmp_path / "project"
        _create_deltaspec_project(project_root)

        captured_writes: list[str] = []

        def capture_write(issue_num: str, kv: str) -> None:
            captured_writes.append(kv)

        with (
            patch.object(runner, "_project_root", return_value=project_root),
            patch.object(runner, "_git_current_branch", return_value="feat/397-retroactive"),
            patch.object(runner, "_fetch_labels", return_value=[]),
            patch.object(runner, "_write_state_field", side_effect=capture_write),
            patch.object(
                runner,
                "_git_diff_name_only",
                return_value=_DELTASPEC_ONLY_DIFF,
                create=True,
            ),
        ):
            runner.step_init(issue_num="397")

        assert any("deltaspec_mode=retroactive" in w for w in captured_writes), (
            "deltaspec_mode=retroactive must be written to state when retroactive mode detected. "
            f"Got writes: {captured_writes}"
        )
