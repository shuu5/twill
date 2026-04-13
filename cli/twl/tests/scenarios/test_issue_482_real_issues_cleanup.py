#!/usr/bin/env python3
"""Tests for test-project-reset --real-issues cleanup requirements.

Spec: deltaspec/changes/issue-482/specs/real-issues-cleanup/spec.md

Coverage:
  Requirement: real-issues クリーンアップフラグ
    Scenario: real-issues フラグで全リソース削除
    Scenario: loaded-issues.json が存在しない

  Requirement: older-than フィルタリング
    Scenario: older-than で古いエントリのみ削除
    Scenario: 無効な duration 指定

  Requirement: ドライランモード
    Scenario: dry-run で削除予定リストのみ出力

  Requirement: local モードと real-issues の相互排他
    Scenario: 両フラグ同時指定時エラー

  Requirement: local モード分岐整理
    Scenario: local モードで既存動作を維持

TDD: これらのテストは実装前に書かれており、実装完了後に passing になる。
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent.parent
COMMAND_MD = (
    REPO_ROOT
    / "plugins"
    / "twl"
    / "commands"
    / "test-project-reset.md"
)


def _read_command() -> str:
    """Read test-project-reset.md, skip if not found."""
    if not COMMAND_MD.exists():
        pytest.skip(f"test-project-reset.md not found at {COMMAND_MD}")
    return COMMAND_MD.read_text(encoding="utf-8")



# ---------------------------------------------------------------------------
# Requirement: real-issues クリーンアップフラグ
# ---------------------------------------------------------------------------


class TestRealIssuesFlagDeleteAll:
    """Scenario: real-issues フラグで全リソース削除

    WHEN --real-issues フラグ付きで実行し、loaded-issues.json が存在する
    THEN 各エントリの PR close → Issue close → branch 削除が順次実行される
    """

    def test_command_md_exists(self) -> None:
        """test-project-reset.md が存在する。"""
        assert COMMAND_MD.exists(), (
            f"test-project-reset.md not found at {COMMAND_MD}. "
            "Issue #482 の実装が必要。"
        )

    def test_real_issues_flag_accepted(self) -> None:
        """--real-issues フラグが定義またはドキュメントされている。"""
        content = _read_command()
        assert re.search(
            r"--real-issues|real.issues",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に --real-issues フラグの記述がない。"
        )

    def test_loaded_issues_json_referenced(self) -> None:
        """loaded-issues.json への参照がある。"""
        content = _read_command()
        assert re.search(
            r"loaded.issues\.json|loaded_issues",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に loaded-issues.json への参照がない。"
        )

    def test_pr_close_step_defined(self) -> None:
        """PR close の処理ステップが定義されている。"""
        content = _read_command()
        assert re.search(
            r"pr\s+close|gh\s+pr\s+close|PR.{0,20}clos",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に PR close のステップが定義されていない。"
        )

    def test_issue_close_step_defined(self) -> None:
        """Issue close の処理ステップが定義されている。"""
        content = _read_command()
        assert re.search(
            r"issue\s+close|gh\s+issue\s+close|Issue.{0,20}clos",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に Issue close のステップが定義されていない。"
        )

    def test_branch_delete_step_defined(self) -> None:
        """branch 削除の処理ステップが定義されている。"""
        content = _read_command()
        assert re.search(
            r"branch.{0,20}delet|gh\s+api.{0,40}branch|git\s+branch\s+-[dD]",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に branch 削除のステップが定義されていない。"
        )

    def test_sequential_order_pr_then_issue_then_branch(self) -> None:
        """PR close → Issue close → branch 削除の順序が明示されている。"""
        content = _read_command()
        pr_pos = re.search(r"pr\s+close|gh\s+pr\s+close", content, re.IGNORECASE)
        issue_pos = re.search(r"issue\s+close|gh\s+issue\s+close", content, re.IGNORECASE)
        branch_pos = re.search(
            r"branch.{0,20}delet|gh\s+api.{0,40}branch|git\s+branch\s+-[dD]",
            content,
            re.IGNORECASE,
        )
        if not (pr_pos and issue_pos and branch_pos):
            pytest.skip("PR/Issue/branch 操作のいずれかが未実装のためスキップ")
        assert pr_pos.start() < issue_pos.start() < branch_pos.start(), (
            "PR close → Issue close → branch 削除の順序が正しくない。"
            f"PR位置={pr_pos.start()}, Issue位置={issue_pos.start()}, "
            f"branch位置={branch_pos.start()}"
        )


class TestLoadedIssuesJsonNotFound:
    """Scenario: loaded-issues.json が存在しない

    WHEN --real-issues フラグ付きで実行し、.test-target/loaded-issues.json が存在しない
    THEN エラーメッセージを出力して終了する（実操作なし）
    """

    def test_file_not_found_error_handling_defined(self) -> None:
        """loaded-issues.json が存在しない場合のエラー処理が定義されている。"""
        content = _read_command()
        # ファイル存在チェック + エラー処理のパターン
        assert re.search(
            r"\[\[\s*-[ef]\s+[^]]+loaded.issues|"
            r"loaded.issues.*exist|"
            r"FileNotFoundError|"
            r"loaded.issues.*not\s+found|"
            r"loaded.issues.*存在しない",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に loaded-issues.json が存在しない場合の"
            "エラー処理が定義されていない。"
        )

    def test_error_exit_on_missing_json(self) -> None:
        """ファイルが存在しない場合に loaded-issues.json 固有のエラー文言が定義されている。"""
        content = _read_command()
        assert re.search(
            r"loaded.issues\.json.{0,30}(見つかりません|not found|存在しない)",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に loaded-issues.json 不在時の固有エラー文言が定義されていない。"
        )

    def test_no_real_operations_on_missing_json(self) -> None:
        """loaded-issues.json が存在しない場合は実操作を行わない旨が明示されている。"""
        content = _read_command()
        # 「実操作なし」または MUST NOT 系の記述
        assert re.search(
            r"実操作.{0,20}(なし|行わない|しない)|"
            r"no.{0,20}operation|"
            r"MUST NOT.{0,50}execut|"
            r"without.{0,30}operat",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に loaded-issues.json 不在時の"
            "「実操作なし」の明示がない。"
        )


# ---------------------------------------------------------------------------
# Requirement: older-than フィルタリング
# ---------------------------------------------------------------------------


class TestOlderThanFilterDeleteOldOnly:
    """Scenario: older-than で古いエントリのみ削除

    WHEN --real-issues --older-than 30d で実行する
    THEN loaded_at が 30 日以上前のエントリのみが削除対象となる
    """

    def test_older_than_option_defined(self) -> None:
        """--older-than オプションが定義されている。"""
        content = _read_command()
        assert re.search(
            r"--older.than|older_than",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に --older-than オプションの記述がない。"
        )

    def test_loaded_at_field_referenced(self) -> None:
        """loaded_at フィールドが参照されている。"""
        content = _read_command()
        assert re.search(
            r"loaded_at|loaded.at",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に loaded_at フィールドへの参照がない。"
        )

    def test_day_unit_supported(self) -> None:
        """d（日）単位がサポートされている。"""
        content = _read_command()
        assert re.search(
            r"\bd\b.{0,20}(日|day)|day.{0,10}unit|\dd\b|30d",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に d（日）単位のサポートが明示されていない。"
        )

    def test_week_unit_supported(self) -> None:
        """w（週）単位がサポートされている。"""
        content = _read_command()
        assert re.search(
            r"\bw\b.{0,20}(週|week)|week.{0,10}unit|\dw\b",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に w（週）単位のサポートが明示されていない。"
        )

    def test_month_unit_supported(self) -> None:
        """m（月）単位がサポートされている。"""
        content = _read_command()
        assert re.search(
            r"\bm\b.{0,20}(月|month)|month.{0,10}unit|\dm\b",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に m（月）単位のサポートが明示されていない。"
        )

    def test_filter_logic_described(self) -> None:
        """フィルタリングロジック（指定期間より古いもののみ対象）が記述されている。"""
        content = _read_command()
        assert re.search(
            r"古い.{0,30}エントリ|"
            r"older\s+than|"
            r"期間.{0,20}前|"
            r"loaded_at.{0,50}前|"
            r"filter.{0,30}date|"
            r"date.{0,30}filter",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に older-than フィルタリングロジックの記述がない。"
        )


class TestInvalidDurationSpec:
    """Scenario: 無効な duration 指定

    WHEN --older-than 2x のような無効な単位を指定する
    THEN エラーメッセージを出力して終了する（実操作なし）
    """

    def test_invalid_duration_error_handling_defined(self) -> None:
        """無効な duration 指定のエラー処理が定義されている。"""
        content = _read_command()
        assert re.search(
            r"(invalid|無効).{0,30}(duration|単位|format)|"
            r"(duration|単位).{0,30}(invalid|無効|error)|"
            r"unknown.{0,20}unit|"
            r"サポート.{0,20}(外|しない|されない)",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に無効な duration 指定のエラー処理が定義されていない。"
        )

    def test_exit_on_invalid_duration(self) -> None:
        """無効な duration 指定時に --older-than 固有のエラー文言が定義されている。"""
        content = _read_command()
        assert re.search(
            r"--older.than.{0,30}(形式が無効|invalid|無効です)",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に --older-than 無効時の固有エラー文言が定義されていない。"
        )


# ---------------------------------------------------------------------------
# Requirement: ドライランモード
# ---------------------------------------------------------------------------


class TestDryRunOutputOnly:
    """Scenario: dry-run で削除予定リストのみ出力

    WHEN --real-issues --dry-run で実行する
    THEN 削除予定の PR#/Issue#/branch のリストが出力され、
         gh CLI による実操作は行われない
    """

    def test_dry_run_flag_defined(self) -> None:
        """--dry-run フラグが定義されている。"""
        content = _read_command()
        assert re.search(
            r"--dry.run|dry_run",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に --dry-run フラグの記述がない。"
        )

    def test_dry_run_outputs_list(self) -> None:
        """dry-run 時に削除予定リストの出力が定義されている。"""
        content = _read_command()
        assert re.search(
            r"dry.run.{0,100}(list|リスト|output|出力)|"
            r"(list|リスト|output|出力).{0,100}dry.run|"
            r"削除予定.{0,30}(出力|リスト)|"
            r"would.{0,30}(delete|remove)",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に dry-run 時の出力リスト定義がない。"
        )

    def test_dry_run_no_real_operations(self) -> None:
        """dry-run 時に実操作を行わない旨が定義されている（MUST NOT）。"""
        content = _read_command()
        assert re.search(
            r"dry.run.{0,100}(実操作.*行わない|MUST NOT|no.{0,20}operat|操作.*しない)|"
            r"(実操作.*行わない|MUST NOT|no.{0,20}operat|操作.*しない).{0,100}dry.run",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に dry-run 時の「実操作なし（MUST NOT）」定義がない。"
        )

    def test_dry_run_shows_pr_numbers(self) -> None:
        """dry-run 出力に PR# が含まれることが明示されている。"""
        content = _read_command()
        assert re.search(
            r"PR#|PR\s+number|#\d+|pr_number|PR.{0,10}番号",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に dry-run 出力が PR# を含む定義がない。"
        )

    def test_dry_run_shows_issue_numbers(self) -> None:
        """dry-run 出力に Issue# が含まれることが明示されている。"""
        content = _read_command()
        assert re.search(
            r"Issue#|issue\s+number|issue_number|Issue.{0,10}番号",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に dry-run 出力が Issue# を含む定義がない。"
        )

    def test_dry_run_shows_branch_names(self) -> None:
        """dry-run 出力に branch 名が含まれることが明示されている。"""
        content = _read_command()
        assert re.search(
            r"branch.{0,20}name|branch.{0,20}名|branch_name",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に dry-run 出力が branch 名を含む定義がない。"
        )


# ---------------------------------------------------------------------------
# Requirement: local モードと real-issues の相互排他
# ---------------------------------------------------------------------------


class TestMutualExclusionLocalAndRealIssues:
    """Scenario: 両フラグ同時指定時エラー

    WHEN --mode local --real-issues を同時に指定する
    THEN エラーメッセージを出力して終了する（いずれの操作も実行しない）
    """

    def test_mutual_exclusion_defined(self) -> None:
        """--mode local と --real-issues の相互排他が定義されている。"""
        content = _read_command()
        assert re.search(
            r"(local|mode.{0,10}local).{0,100}real.issues|"
            r"real.issues.{0,100}(local|mode.{0,10}local)|"
            r"相互排他|mutually.exclusive|mutex|cannot.{0,30}together|"
            r"同時.{0,20}(指定|使用).{0,20}(エラー|できない|不可)|"
            r"exclusive|排他",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に --mode local と --real-issues の"
            "相互排他の定義がない。"
        )

    def test_error_output_on_mutual_exclusion(self) -> None:
        """相互排他違反時に --mode local / --real-issues 固有のエラー文言が定義されている。"""
        content = _read_command()
        assert re.search(
            r"--mode local.{0,50}--real.issues|--real.issues.{0,50}--mode local",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に --mode local と --real-issues の相互排他固有エラー文言が定義されていない。"
        )

    def test_no_operations_on_mutual_exclusion(self) -> None:
        """相互排他違反時にいずれの操作も実行しない旨が定義されている。"""
        content = _read_command()
        assert re.search(
            r"(いずれ|どちら).{0,30}(実行|操作).{0,30}(しない|なし)|"
            r"no.{0,30}operation.{0,30}execut|"
            r"SHALL.{0,30}(exit|error)|"
            r"操作.{0,30}(行わない|しない|なし)",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に相互排他違反時の「いずれの操作も実行しない」定義がない。"
        )


# ---------------------------------------------------------------------------
# Requirement: local モード分岐整理
# ---------------------------------------------------------------------------


class TestLocalModePreservesExistingFlow:
    """Scenario: local モードで既存動作を維持

    WHEN フラグなしまたは --mode local で実行する
    THEN Step 4（ユーザー確認）→ Step 5（git reset --hard）の既存フローが維持される
    """

    def test_step4_user_confirmation_exists(self) -> None:
        """Step 4 ユーザー確認ステップが定義されている。"""
        content = _read_command()
        assert re.search(
            r"Step\s+4|ユーザー確認|AskUserQuestion|確認.*続行",
            content,
        ), (
            "test-project-reset.md に Step 4（ユーザー確認）の定義がない。"
        )

    def test_step5_git_reset_hard_exists(self) -> None:
        """Step 5 git reset --hard ステップが定義されている。"""
        content = _read_command()
        assert re.search(
            r"git\s+reset\s+--hard",
            content,
        ), (
            "test-project-reset.md に Step 5（git reset --hard）の定義がない。"
        )

    def test_local_mode_scope_defined(self) -> None:
        """Step 4/5 が local モード（またはフラグなし）時のみ実行される条件が定義されている。"""
        content = _read_command()
        assert re.search(
            r"(--mode\s+local|mode\s+local|local\s+mode|フラグなし|no.{0,10}flag).{0,200}"
            r"(Step\s+4|Step\s+5|git\s+reset|ユーザー確認)|"
            r"(Step\s+4|Step\s+5|git\s+reset|ユーザー確認).{0,200}"
            r"(--mode\s+local|mode\s+local|local\s+mode|フラグなし|no.{0,10}flag)|"
            r"mode.{0,10}local.*のみ|local.*only",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に Step 4/5 が local モード時のみ実行される条件定義がない。"
        )

    def test_real_issues_does_not_execute_steps_4_5(self) -> None:
        """--real-issues 時に Step 4/5 を実行しない旨が定義されている。"""
        content = _read_command()
        assert re.search(
            r"real.issues.{0,200}(Step\s+4|Step\s+5|ユーザー確認|git\s+reset).{0,200}"
            r"(しない|行わない|MUST NOT|skip|除外)|"
            r"(Step\s+4|Step\s+5|ユーザー確認|git\s+reset).{0,200}"
            r"real.issues.{0,200}(しない|行わない|MUST NOT|skip)|"
            r"MUST NOT.{0,100}(Step\s+4|Step\s+5|ユーザー確認|git\s+reset)|"
            r"--real-issues.{0,100}(実行.*しない|実行.*してはならない|除外)",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md に --real-issues 時の Step 4/5 除外定義がない。"
        )

    def test_default_behavior_unchanged(self) -> None:
        """デフォルト（フラグなし）の動作が変更されていないことが明示されている。"""
        content = _read_command()
        # 既存フロー維持 or デフォルト動作 の記述
        assert re.search(
            r"既存.{0,30}(動作|フロー|維持)|"
            r"default.{0,30}behavior|"
            r"(フラグなし|without\s+flag|no.{0,10}flag).{0,50}"
            r"(維持|変わらない|unchanged|same)|"
            r"backward.{0,20}compat",
            content,
            re.IGNORECASE,
        ), (
            "test-project-reset.md にデフォルト動作が維持される旨の記述がない。"
        )
