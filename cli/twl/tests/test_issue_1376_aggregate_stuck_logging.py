"""Tests for Issue #1376: co-issue Phase 4 aggregate stuck logging & pitfalls documentation.

TDD RED phase — AC-1〜AC-5 は実装前に FAIL する。AC-6 は回帰ガード（既存制約の維持確認）。

Files under test:
  plugins/twl/commands/issue-review-aggregate.md   (AC-1)
  plugins/twl/skills/su-observer/refs/pitfalls-catalog.md  (AC-2〜AC-5)
  plugins/twl/architecture/domain/contexts/issue-mgmt.md   (AC-6)

AC list:
  AC-1: issue-review-aggregate.md の Step 1〜6 全ての入退出時に
        [AGGREGATE-STEP] step=<N> status=<enter|exit> ts=<ISO8601> 形式の
        ログ出力宣言が追加される
  AC-2: pitfalls-catalog.md §3 テーブル末尾（§3.7）に
        「co-issue Phase 4 aggregate stuck (進行停止)」エントリが追加され、
        Issue #1376 と source Issue #1038 を参照する記述がある
  AC-3: pitfalls-catalog.md §3.7 エントリは §3.3（specialist 打ち切り — 出力なし完了）
        との区別を明示する
  AC-4: pitfalls-catalog.md §3.7 エントリに aggregate phase >5 min 無進行の
        pane 監視 regex（[AGGREGATE-STEP] タグの mtime 監視）が明記される
  AC-5: pitfalls-catalog.md §3.7 エントリに [AGGREGATE-STEP] ログ機構の
        「再現確認方法」が記述される（e2e scenario / 手動確認手順で代替）
  AC-6: issue-mgmt.md L164 の [B] manual fix path retrospective 記録要件が維持される
        （回帰ガード）
"""

from __future__ import annotations

import re
from pathlib import Path

WORKTREE_ROOT = Path(__file__).resolve().parents[3]  # tests(0) → twl(1) → cli(2) → repo-root(3)

AGGREGATE_MD = WORKTREE_ROOT / "plugins/twl/commands/issue-review-aggregate.md"
PITFALLS_CATALOG = WORKTREE_ROOT / "plugins/twl/skills/su-observer/refs/pitfalls-catalog.md"
ISSUE_MGMT = WORKTREE_ROOT / "plugins/twl/architecture/domain/contexts/issue-mgmt.md"


# ---------------------------------------------------------------------------
# AC-1: [AGGREGATE-STEP] ログ宣言が issue-review-aggregate.md に追加される
# ---------------------------------------------------------------------------


def test_ac1_aggregate_step_log_keyword_present():
    """AC-1: issue-review-aggregate.md に [AGGREGATE-STEP] キーワードが存在する
    RED: 修正前はログ宣言が一切ないため FAIL
    GREEN: ログ宣言追加後 PASS
    """
    content = AGGREGATE_MD.read_text(encoding="utf-8")
    assert "[AGGREGATE-STEP]" in content, (
        "issue-review-aggregate.md に [AGGREGATE-STEP] ログ宣言が見つからない — "
        "Step 1〜6 の入退出ログ宣言を追加してください"
    )


def test_ac1_aggregate_step_log_format_correct():
    """AC-1: [AGGREGATE-STEP] ログが正しいフォーマット宣言を含む
    期待フォーマット: [AGGREGATE-STEP] step=<N> status=<enter|exit> ts=<ISO8601>
    RED: 修正前はフォーマット宣言がないため FAIL
    GREEN: 正しいフォーマット宣言追加後 PASS
    """
    content = AGGREGATE_MD.read_text(encoding="utf-8")
    # grep -E '^\[AGGREGATE-STEP\] step=[0-9]+ status=(enter|exit) ts=' 相当のパターンが
    # ドキュメント内に記述されていること（実際の出力例またはフォーマット仕様として）
    # ドキュメント内のフォーマット仕様例にマッチするパターン
    # "[AGGREGATE-STEP] step=<N> status=<enter|exit> ts=" または実際の出力例 "step=1 status=enter ts=" 等
    pattern = re.compile(
        r"\[AGGREGATE-STEP\]\s+step=(?:[0-9]+|<N>)\s+status=(?:enter|exit|<enter\|exit>)\s+ts=",
        re.MULTILINE,
    )
    assert pattern.search(content) is not None, (
        "issue-review-aggregate.md に [AGGREGATE-STEP] step=N status=enter|exit ts= 形式の"
        "フォーマット宣言が見つからない"
    )


def test_ac1_aggregate_step_log_covers_all_six_steps():
    """AC-1: ログ宣言が Step 1〜6 全てをカバーしている
    RED: 修正前はログ宣言がないため FAIL
    GREEN: Step 1〜6 全ての enter/exit 宣言追加後 PASS
    """
    content = AGGREGATE_MD.read_text(encoding="utf-8")
    assert "[AGGREGATE-STEP]" in content, (
        "[AGGREGATE-STEP] 宣言が存在しないため Step カバレッジを確認できない"
    )
    # Step 1〜6 の全ステップに対して enter/exit が言及されていることを確認
    for step_num in range(1, 7):
        assert f"step={step_num}" in content or f"Step {step_num}" in content, (
            f"issue-review-aggregate.md の [AGGREGATE-STEP] 宣言に Step {step_num} への言及がない"
        )


def test_ac1_aggregate_step_log_includes_both_statuses():
    """AC-1: [AGGREGATE-STEP] 宣言が enter と exit の両方のステータスを含む
    RED: 修正前は宣言がないため FAIL
    GREEN: enter/exit 両方の宣言追加後 PASS
    """
    content = AGGREGATE_MD.read_text(encoding="utf-8")
    assert "status=enter" in content or "enter|exit" in content, (
        "issue-review-aggregate.md に status=enter の宣言が見つからない"
    )
    assert "status=exit" in content or "enter|exit" in content, (
        "issue-review-aggregate.md に status=exit の宣言が見つからない"
    )


# ---------------------------------------------------------------------------
# AC-2: pitfalls-catalog.md §3.7 エントリが存在し #1376 と #1038 を参照する
# ---------------------------------------------------------------------------


def test_ac2_pitfalls_catalog_has_section_3_7():
    """AC-2: pitfalls-catalog.md の §3 テーブルに §3.7 エントリが存在する
    RED: 修正前は §3.6 が末尾のため FAIL
    GREEN: §3.7 エントリ追加後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    assert "3.7" in content, (
        "pitfalls-catalog.md に §3.7 エントリが見つからない — "
        "§3 テーブル末尾に aggregate stuck エントリを追加してください"
    )


def test_ac2_pitfalls_catalog_3_7_references_issue_1376():
    """AC-2: §3.7 エントリが Issue #1376 を参照する
    RED: 修正前は §3.7 がないため FAIL
    GREEN: #1376 参照を含む §3.7 追加後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    assert "#1376" in content, (
        "pitfalls-catalog.md に Issue #1376 への参照が見つからない"
    )


def test_ac2_pitfalls_catalog_3_7_references_source_issue_1038():
    """AC-2: §3.7 エントリが発生 source Issue #1038 を参照する
    RED: 修正前は §3.7 がないため FAIL
    GREEN: #1038 参照を含む §3.7 追加後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    assert "#1038" in content, (
        "pitfalls-catalog.md に source Issue #1038 への参照が見つからない"
    )


def test_ac2_pitfalls_catalog_3_7_describes_aggregate_stuck():
    """AC-2: §3.7 エントリが 'aggregate stuck' または '進行停止' を説明する
    RED: 修正前は §3.7 がないため FAIL
    GREEN: aggregate stuck 説明を含む §3.7 追加後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    has_aggregate_stuck = "aggregate stuck" in content or (
        "aggregate" in content and "進行停止" in content
    )
    assert has_aggregate_stuck, (
        "pitfalls-catalog.md に 'aggregate stuck' または 'aggregate' + '進行停止' の記述が見つからない"
    )


# ---------------------------------------------------------------------------
# AC-3: §3.7 エントリが §3.3（specialist 打ち切り）との区別を明示する
# ---------------------------------------------------------------------------


def test_ac3_pitfalls_catalog_3_7_distinguishes_from_3_3():
    """AC-3: §3.7 エントリが §3.3 との区別を明示する
    既知 §3.3 の特徴: specialist が tool_uses 25-30 で打ち切り → 最終 report なし
    §3.7 の区別: specialist は完了済み、aggregate phase 自体で停止
    RED: 修正前は §3.7 がないため FAIL
    GREEN: §3.3 との区別を明示した §3.7 追加後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    # §3.3 との区別が明示されているかチェック
    # 「specialists は完了済み」かつ「aggregate 自体で停止」という区別が必要
    distinguishes = (
        ("§3.3" in content and "aggregate" in content)
        and (
            "specialist" in content
            and ("完了済み" in content or "specialists は完了" in content or "specialist complete" in content.lower())
        )
    )
    assert distinguishes, (
        "pitfalls-catalog.md §3.7 に §3.3（specialist 打ち切り）との区別が明示されていない — "
        "「specialists は完了済み、aggregate phase 自体で停止」との差異を記載してください"
    )


# ---------------------------------------------------------------------------
# AC-4: §3.7 エントリに >5 min 無進行検知の pane 監視 regex が明記される
# ---------------------------------------------------------------------------


def test_ac4_pitfalls_catalog_3_7_has_monitoring_regex():
    """AC-4: §3.7 エントリに [AGGREGATE-STEP] タグの mtime 監視 regex が明記される
    aggregate phase が >5 min 無進行の場合の検知手順が必要
    RED: 修正前は §3.7 がないため FAIL
    GREEN: mtime 監視 regex を含む §3.7 追加後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    # [AGGREGATE-STEP] と mtime 監視の両方が §3.7 周辺に存在することを確認
    has_aggregate_step = "[AGGREGATE-STEP]" in content
    has_mtime_monitoring = "mtime" in content and (
        "5 min" in content or "5min" in content or "300" in content or ">5" in content
    )
    assert has_aggregate_step, (
        "pitfalls-catalog.md に [AGGREGATE-STEP] タグへの言及が見つからない"
    )
    assert has_mtime_monitoring, (
        "pitfalls-catalog.md に >5 min 無進行の mtime 監視に関する記述が見つからない"
    )


# ---------------------------------------------------------------------------
# AC-5: §3.7 エントリに「再現確認方法」が記述される
# ---------------------------------------------------------------------------


def test_ac5_pitfalls_catalog_3_7_has_reproduction_procedure():
    """AC-5: §3.7 エントリに [AGGREGATE-STEP] ログ機構の「再現確認方法」が記述される
    atomic LLM skill のため bats unit test ではなく e2e / 手動確認手順で代替
    RED: 修正前は §3.7 がないため FAIL
    GREEN: 再現確認方法を含む §3.7 追加後 PASS
    """
    content = PITFALLS_CATALOG.read_text(encoding="utf-8")
    has_reproduction = (
        "再現確認" in content
        or "再現確認方法" in content
        or "動作確認手順" in content
    )
    assert has_reproduction, (
        "pitfalls-catalog.md §3.7 に「再現確認方法」または「動作確認手順」が見つからない — "
        "e2e scenario または手動確認手順を記載してください"
    )


# ---------------------------------------------------------------------------
# AC-6: issue-mgmt.md L164 の [B] manual fix path retrospective 記録要件が維持される
# （回帰ガード — 実装変更で既存制約が削除されていないことを確認）
# ---------------------------------------------------------------------------


def test_ac6_issue_mgmt_b_path_retrospective_requirement_maintained():
    """AC-6: issue-mgmt.md の [B] manual fix path に retrospective 記録義務が維持される
    回帰ガード: 実装変更でこの制約が削除されていないことを確認
    GREEN: 既存制約が維持されている（現在も PASS、実装変更後も維持すること）
    """
    content = ISSUE_MGMT.read_text(encoding="utf-8")
    # L164 相当: [B] manual fix path + retrospective 記録義務
    assert "manual fix" in content and "retrospective" in content, (
        "issue-mgmt.md の [B] manual fix path retrospective 記録要件が削除されている — "
        "この制約は維持 MUST（ADR-017 隔離原則の例外処理）"
    )
    assert "retrospective 記録義務あり" in content, (
        "issue-mgmt.md L164 の 'retrospective 記録義務あり' が削除されている"
    )
