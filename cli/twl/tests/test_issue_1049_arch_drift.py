"""TDD RED phase tests for Issue #1049.

cli/twl pytest テストが plugins/twl を直接参照する architecture-drift を解消する。

AC 1件につき 1テスト。全テストは実装前に FAIL（RED）する。
"""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).parents[3]
CLI_TWL_TESTS = REPO_ROOT / "cli" / "twl" / "tests"
PLUGINS_TWL = REPO_ROOT / "plugins" / "twl"
TWILL_INTEGRATION_MD = PLUGINS_TWL / "architecture" / "domain" / "contexts" / "twill-integration.md"
TEST_FIXTURES = REPO_ROOT / "test-fixtures"

# AC5 対象 9 ファイル
AC5_TARGET_FILES = [
    CLI_TWL_TESTS / "test_981_chain_runner_triage.py",
    CLI_TWL_TESTS / "test_adr_025.py",
    CLI_TWL_TESTS / "test_issue_1084_human_gate.py",
    CLI_TWL_TESTS / "test_issue_1118_workflow_can_spawn.py",
    CLI_TWL_TESTS / "test_issue_1123_observe_loop_can_spawn.py",
    CLI_TWL_TESTS / "test_issue_1265_recommended_structure.py",
    CLI_TWL_TESTS / "test_issue_1300_architect_group_refine_type.py",
    CLI_TWL_TESTS / "test_issue_1313_adr_033_deprecated.py",
    CLI_TWL_TESTS / "test_issue_980_audit_mode.py",
]


# ---------------------------------------------------------------------------
# AC1: cli/twl/tests/ 配下に Path(__file__).parents[.*] / "plugins" パターンが残存しない
# ---------------------------------------------------------------------------


def test_ac1_no_plugins_path_pattern_in_cli_tests():
    """AC1: cli/twl/tests/ 配下に Path(__file__).parents[.*] / "plugins" パターンが残存しないこと（grep で 0 件）。

    ただし test_issue_980_audit_mode.py 内の .supervisor/ 参照は対象外。
    当該ファイルは plugins/twl 参照部分のみ AC5 の対象。
    """
    # RED: 実装前は 9 ファイルに plugins 参照が残存しているため fail する
    raise NotImplementedError("AC #1 未実装")


# ---------------------------------------------------------------------------
# AC2: plugins/twl 由来の fixture が test-fixtures/ 配下に複製・配置されていること
# ---------------------------------------------------------------------------


def test_ac2_fixture_assets_exist_in_test_fixtures():
    """AC2: テストが必要とする plugins/twl 由来の fixture（agents/*.md, deps.yaml,
    scripts/chain-runner.sh 等）は test-fixtures/ 配下に複製または最小再現として配置されていること。
    """
    # RED: 実装前は test-fixtures/ に必要な fixture が存在しないため fail する
    raise NotImplementedError("AC #2 未実装")


# ---------------------------------------------------------------------------
# AC3: pytest cli/twl/tests/ の全 PASS 数が refactor 前と同等以上
# ---------------------------------------------------------------------------


def test_ac3_no_regression_in_pass_count():
    """AC3: pytest cli/twl/tests/ の全 PASS 数が refactor 前と同等以上であること（リグレッションなし）。
    """
    # RED: 実装前は plugins/twl 直接参照が原因でパスカウントが保証されないため fail する
    raise NotImplementedError("AC #3 未実装")


# ---------------------------------------------------------------------------
# AC4: twill-integration.md の Rules セクションに依存方向ルールが明記されていること
# ---------------------------------------------------------------------------


def test_ac4_twill_integration_rules_contain_fixture_direction():
    """AC4: plugins/twl/architecture/domain/contexts/twill-integration.md の Rules セクションに
    「TWiLL Integration -> plugins/* 方向の test fixture 参照は test-fixtures/ 経由のみ許可」
    の依存方向ルールを明記すること（drift 再発防止）。
    """
    # RED: 実装前はルールが存在しないため fail する
    raise NotImplementedError("AC #4 未実装")


# ---------------------------------------------------------------------------
# AC5: 該当する 9 ファイル全てが plugins/twl への直接参照部分を書き換えられていること
# ---------------------------------------------------------------------------


def test_ac5_all_nine_files_rewritten():
    """AC5: 該当する 9 ファイル全てが plugins/twl への直接参照部分を上記方針に沿って
    書き換えられていること。

    対象ファイル:
      - test_981_chain_runner_triage.py
      - test_adr_025.py
      - test_issue_1084_human_gate.py
      - test_issue_1118_workflow_can_spawn.py
      - test_issue_1123_observe_loop_can_spawn.py
      - test_issue_1265_recommended_structure.py
      - test_issue_1300_architect_group_refine_type.py
      - test_issue_1313_adr_033_deprecated.py
      - test_issue_980_audit_mode.py（plugins/twl 参照部分のみ）
    """
    # RED: 実装前は全ファイルに plugins/twl 直接参照が残っているため fail する
    raise NotImplementedError("AC #5 未実装")
