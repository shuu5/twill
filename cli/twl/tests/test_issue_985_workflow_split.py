"""TDD tests for Issue #985 — workflow batch split lifecycle.

AC checklist:
  1. 3 workflow とも workflow_token_bloat <= 1200 tok
  2. twl check --deps-integrity PASS
  3. twl check PASS (deps.yaml v3.0 構造整合)
  4. 各 workflow の動作変更なし (smoke test 3 件)
  5. split 先 refs/ が SKILL.md から正規 Read 経路で参照されること
  6. specialist review 3 種 PASS (placeholder)
"""

import subprocess
from pathlib import Path

import pytest

WORKTREE_ROOT = Path(
    "/home/shuu5/projects/local-projects/twill/worktrees/"
    "feat/985-tech-debt-workflow-batch-split-lifecyc"
)
SKILLS_DIR = WORKTREE_ROOT / "plugins" / "twl" / "skills"
REFS_DIR = WORKTREE_ROOT / "plugins" / "twl" / "refs"
LIFECYCLE_SKILL = SKILLS_DIR / "workflow-issue-lifecycle" / "SKILL.md"
REFINE_SKILL = SKILLS_DIR / "workflow-issue-refine" / "SKILL.md"
PR_MERGE_SKILL = SKILLS_DIR / "workflow-pr-merge" / "SKILL.md"
PLUGIN_DIR = WORKTREE_ROOT / "plugins" / "twl"


def _run_twl_audit() -> str:
    result = subprocess.run(
        ["python3", "-m", "twl", "--audit"],
        capture_output=True,
        text=True,
        cwd=str(PLUGIN_DIR),
    )
    return result.stdout + result.stderr


def _get_token_count(audit_output: str, component: str) -> int | None:
    for line in audit_output.splitlines():
        if f"| {component} " in line and "workflow" in line and "1200" in line:
            parts = [p.strip() for p in line.split("|") if p.strip()]
            if len(parts) >= 3:
                try:
                    return int(parts[2])
                except ValueError:
                    pass
    return None


# ---------------------------------------------------------------------------
# AC #1 — token bloat <= 1200 tok for all 3 workflows
# ---------------------------------------------------------------------------

class TestAc1TokenBloat:
    """AC #1: 3 workflow とも workflow_token_bloat <= 1200 tok 達成."""

    def test_ac1_lifecycle_token_bloat_le_1200(self):
        audit = _run_twl_audit()
        tok = _get_token_count(audit, "workflow-issue-lifecycle")
        assert tok is not None, "workflow-issue-lifecycle の token count が取得できなかった"
        assert tok <= 1200, (
            f"AC #1 FAIL: workflow-issue-lifecycle tok={tok} > 1200. "
            "refs/ split を実施してトークンを削減すること。"
        )

    def test_ac1_refine_token_bloat_le_1200(self):
        audit = _run_twl_audit()
        tok = _get_token_count(audit, "workflow-issue-refine")
        assert tok is not None, "workflow-issue-refine の token count が取得できなかった"
        assert tok <= 1200, (
            f"AC #1 FAIL: workflow-issue-refine tok={tok} > 1200. "
            "refs/ split を実施してトークンを削減すること。"
        )

    def test_ac1_pr_merge_token_bloat_le_1200(self):
        audit = _run_twl_audit()
        tok = _get_token_count(audit, "workflow-pr-merge")
        assert tok is not None, "workflow-pr-merge の token count が取得できなかった"
        assert tok <= 1200, (
            f"AC #1 FAIL: workflow-pr-merge tok={tok} > 1200. "
            "refs/ split を実施してトークンを削減すること。"
        )


# ---------------------------------------------------------------------------
# AC #2 — twl check --deps-integrity PASS
# ---------------------------------------------------------------------------

class TestAc2DepsIntegrity:
    """AC #2: twl check --deps-integrity PASS (chain.py / chain-steps.sh / deps.yaml.chains 整合)."""

    def test_ac2_deps_integrity_passes(self):
        result = subprocess.run(
            ["python3", "-m", "twl", "--check", "--deps-integrity"],
            capture_output=True,
            text=True,
            cwd=str(PLUGIN_DIR),
        )
        assert result.returncode == 0, (
            f"AC #2 FAIL: twl check --deps-integrity が exit {result.returncode}。"
            f"stdout: {result.stdout[:500]}\nstderr: {result.stderr[:500]}"
        )


# ---------------------------------------------------------------------------
# AC #3 — twl check PASS (deps.yaml v3.0 構造整合)
# ---------------------------------------------------------------------------

class TestAc3TwlCheck:
    """AC #3: twl check PASS — deps.yaml v3.0 構造整合."""

    def test_ac3_twl_check_passes(self):
        result = subprocess.run(
            ["python3", "-m", "twl", "--check"],
            capture_output=True,
            text=True,
            cwd=str(PLUGIN_DIR),
        )
        assert result.returncode == 0, (
            f"AC #3 FAIL: twl check が exit {result.returncode}。"
            f"stdout: {result.stdout[:500]}\nstderr: {result.stderr[:500]}"
        )


# ---------------------------------------------------------------------------
# AC #4 — 各 workflow の動作変更なし (smoke test 3 件)
# ---------------------------------------------------------------------------

class TestAc4SmokeTests:
    """AC #4: 各 workflow の動作変更なし — refs/ ファイルに必須ステップが保持されていること。

    Note: 実際の workflow 実行 smoke test はリソース制約上困難なため、
    refs/ ファイルに必須ステップ記述が存在することで動作変更なしを検証する。
    """

    def test_ac4_lifecycle_smoke_state_transition(self):
        refs_file = REFS_DIR / "lifecycle-processing-flow.md"
        assert refs_file.exists(), f"AC #4: {refs_file} が存在しない"
        content = refs_file.read_text(encoding="utf-8")
        required_steps = ["issue-structure", "issue-spec-review", "issue-review-aggregate",
                          "issue-arch-drift", "issue-create", "STATE"]
        for step in required_steps:
            assert step in content, (
                f"AC #4 FAIL: lifecycle-processing-flow.md に '{step}' が存在しない。"
                "split 後も必須ステップが refs/ ファイルに保持されていること。"
            )

    def test_ac4_refine_smoke_state_transition(self):
        refs_file = REFS_DIR / "refine-processing-flow.md"
        assert refs_file.exists(), f"AC #4: {refs_file} が存在しない"
        content = refs_file.read_text(encoding="utf-8")
        required_steps = ["issue-spec-review", "issue-review-aggregate",
                          "issue-arch-drift", "STATE", "dual-write"]
        for step in required_steps:
            assert step in content, (
                f"AC #4 FAIL: refine-processing-flow.md に '{step}' が存在しない。"
                "split 後も必須ステップが refs/ ファイルに保持されていること。"
            )

    def test_ac4_pr_merge_smoke_state_transition(self):
        refs_file = REFS_DIR / "pr-merge-chain-steps.md"
        assert refs_file.exists(), f"AC #4: {refs_file} が存在しない"
        content = refs_file.read_text(encoding="utf-8")
        required_steps = ["e2e-screening", "pr-cycle-report", "all-pass-check",
                          "merge-gate", "auto-merge"]
        for step in required_steps:
            assert step in content, (
                f"AC #4 FAIL: pr-merge-chain-steps.md に '{step}' が存在しない。"
                "split 後も必須ステップが refs/ ファイルに保持されていること。"
            )


# ---------------------------------------------------------------------------
# AC #5 — split 先 refs/ が SKILL.md から正規 Read 経路で参照されること
# ---------------------------------------------------------------------------

class TestAc5RefsReferences:
    """AC #5: split 先 (refs/ 配下の各 .md) が SKILL.md から正規 Read 経路で参照されること."""

    def test_ac5_lifecycle_skill_references_refs(self):
        content = LIFECYCLE_SKILL.read_text(encoding="utf-8")
        assert "refs/" in content, (
            f"AC #5 FAIL: {LIFECYCLE_SKILL} に refs/ への参照が存在しない。"
        )
        assert "lifecycle-processing-flow.md" in content, (
            f"AC #5 FAIL: {LIFECYCLE_SKILL} に lifecycle-processing-flow.md への参照が存在しない。"
        )

    def test_ac5_refine_skill_references_refs(self):
        content = REFINE_SKILL.read_text(encoding="utf-8")
        assert "refs/" in content, (
            f"AC #5 FAIL: {REFINE_SKILL} に refs/ への参照が存在しない。"
        )
        assert "refine-processing-flow.md" in content, (
            f"AC #5 FAIL: {REFINE_SKILL} に refine-processing-flow.md への参照が存在しない。"
        )

    def test_ac5_pr_merge_skill_references_refs(self):
        content = PR_MERGE_SKILL.read_text(encoding="utf-8")
        refs_count = content.count("refs/")
        assert refs_count >= 2, (
            f"AC #5 FAIL: {PR_MERGE_SKILL} の refs/ 参照数が {refs_count} 件。"
            "split 実装後は複数の refs/ 参照が必要（pr-merge-domain-rules.md + pr-merge-chain-steps.md + ref-compaction-recovery.md）。"
        )

    def test_ac5_refs_files_exist_for_each_workflow(self):
        expected_refs = [
            REFS_DIR / "lifecycle-processing-flow.md",
            REFS_DIR / "refine-processing-flow.md",
            REFS_DIR / "pr-merge-domain-rules.md",
            REFS_DIR / "pr-merge-chain-steps.md",
        ]
        for refs_file in expected_refs:
            assert refs_file.exists(), (
                f"AC #5 FAIL: {refs_file} が存在しない。split 実装後に作成されること。"
            )


# ---------------------------------------------------------------------------
# AC #6 — specialist review 3 種 PASS (placeholder)
# ---------------------------------------------------------------------------

class TestAc6SpecialistReview:
    """AC #6: specialist review 3 種 PASS — worker-architecture 必須 + worker-codex-reviewer + issue-critic/issue-feasibility.

    Note: specialist review は PR レビューフローで実施されるため、
    このテストは review 完了を示すプレースホルダー。
    """

    def test_ac6_worker_architecture_review_completed(self):
        # AC: worker-architecture specialist review が PASS していること
        # (chain SSoT 境界 / refs 切り出し境界の妥当性確認)
        # RED: PR レビューがまだ実施されていない。レビュー完了後に GREEN とする。
        raise NotImplementedError(
            "AC #6 placeholder: worker-architecture specialist review 未完了。"
            "PR レビューで確認後、このテストを削除またはスキップに変更すること。"
        )

    def test_ac6_worker_codex_reviewer_completed(self):
        # AC: worker-codex-reviewer specialist review が PASS していること
        # RED: PR レビューがまだ実施されていない。レビュー完了後に GREEN とする。
        raise NotImplementedError(
            "AC #6 placeholder: worker-codex-reviewer specialist review 未完了。"
            "PR レビューで確認後、このテストを削除またはスキップに変更すること。"
        )

    def test_ac6_issue_critic_or_feasibility_completed(self):
        # AC: issue-critic または issue-feasibility specialist review が PASS していること
        # RED: PR レビューがまだ実施されていない。レビュー完了後に GREEN とする。
        raise NotImplementedError(
            "AC #6 placeholder: issue-critic / issue-feasibility specialist review 未完了。"
            "PR レビューで確認後、このテストを削除またはスキップに変更すること。"
        )
