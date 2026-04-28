"""
Tests for Issue #1010: self-improve(false-positive) — issue-pr-alignment が
pre-existing 変更を AC7 違反として誤検出する

AC1: worker-issue-pr-alignment.md が PR diff 取得に git diff origin/main のみを
     使用していない（issue 番号で commits をフィルタする仕組みを含む）
AC2: 実行ロジックに「現在 Issue 番号に紐づくコミットの特定」ステップが存在する
AC3: pre-existing commits（issue 番号を含まないコミット）が diff 対象から除外される
     説明が存在する
"""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
PLUGINS_TWL_DIR = REPO_ROOT / "plugins" / "twl"
AGENTS_DIR = PLUGINS_TWL_DIR / "agents"

WORKER_ALIGNMENT_MD = AGENTS_DIR / "worker-issue-pr-alignment.md"


class TestAC1GitDiffOriginMainNotSolelyUsed:
    """AC1: worker-issue-pr-alignment.md が PR diff 取得に git diff origin/main のみを使用していない"""

    def test_ac1_worker_alignment_file_exists(self):
        assert WORKER_ALIGNMENT_MD.exists(), f"{WORKER_ALIGNMENT_MD} が存在しない"

    def test_ac1_no_sole_git_diff_origin_main_in_pr_diff_step(self):
        content = WORKER_ALIGNMENT_MD.read_text()
        # 「PR diff」入力行が `git diff origin/main` 単独でないことを確認
        for line in content.splitlines():
            if "**PR diff**" in line and "git diff origin/main" in line:
                raise AssertionError(
                    "入力セクションの '**PR diff**' 行が `git diff origin/main` 単独のまま:"
                    f"\n  {line}"
                )

    def test_ac1_commit_filter_mechanism_present(self):
        content = WORKER_ALIGNMENT_MD.read_text()
        assert "--grep" in content, (
            "issue 番号でコミットをフィルタする `git log --grep` の記述が存在しない"
        )


class TestAC2IssueCommitIdentificationStepExists:
    """AC2: 実行ロジックに「現在 Issue 番号に紐づくコミットの特定」ステップが存在する"""

    def test_ac2_issue_commit_identification_step_in_logic(self):
        content = WORKER_ALIGNMENT_MD.read_text()
        assert "Issue 固有コミット範囲を特定" in content, (
            "実行ロジックに Issue 固有コミット範囲を特定するステップが存在しない"
        )

    def test_ac2_git_log_grep_or_equivalent_described(self):
        content = WORKER_ALIGNMENT_MD.read_text()
        assert "git log --grep" in content, (
            "git log --grep または相当コマンドの記述が実行ロジックに存在しない"
        )

    def test_ac2_issue_num_variable_used_in_diff_command(self):
        content = WORKER_ALIGNMENT_MD.read_text()
        assert "ISSUE_NUM" in content and "ISSUE_COMMITS" in content, (
            "diff コマンドが Issue 番号変数 (ISSUE_NUM/ISSUE_COMMITS) を参照する記述がない"
        )


class TestAC3PreExistingCommitsExclusionExplained:
    """AC3: pre-existing commits が diff 対象から除外される説明が存在する"""

    def test_ac3_pre_existing_commits_exclusion_described(self):
        content = WORKER_ALIGNMENT_MD.read_text()
        assert "pre-existing" in content, (
            "pre-existing commits を diff 対象から除外することの説明が存在しない"
        )

    def test_ac3_false_positive_prevention_mechanism_stated(self):
        content = WORKER_ALIGNMENT_MD.read_text()
        assert "false positive" in content, (
            "false positive 防止機構の記述が worker-issue-pr-alignment.md に存在しない"
        )

    def test_ac3_git_diff_origin_main_not_the_only_diff_source(self):
        content = WORKER_ALIGNMENT_MD.read_text()
        # フォールバックとして git diff origin/main は許容するが、
        # それが唯一の手段ではなく FIRST_SHA^..HEAD 範囲が存在することを確認
        assert "FIRST_SHA" in content, (
            "issue 固有コミット SHA 範囲 (FIRST_SHA^..HEAD) の記述が存在しない"
        )
