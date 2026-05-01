#!/usr/bin/env bats
# test_ac1168_observe_any_cleanup.bats
# Issue #1168: cld-observe-any.bats L42 コマンドなし変数代入の解消
#
# RED テスト: AC1/AC4 は実装前 FAIL、実装後 PASS
# 回帰確認: AC2/AC3 は実装前後ともに PASS

BATS_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/cld-observe-any.bats"

# ---------------------------------------------------------------------------
# AC1/AC4: L42 standalone 変数代入が除去されていること（RED before fix）
# ---------------------------------------------------------------------------

@test "ac1/ac4: L42 standalone variable assignment is removed (RED before fix)" {
    # AC1: コマンドなし変数代入（行末に \ がない行）が存在しない
    # AC4: grep -v "\\" で行末バックスラッシュなし行を除外した後、カウントが 0
    # 現状: L42 に standalone 行が 1 件存在するため FAIL（RED）
    # 修正後: standalone 行が削除されるため PASS（GREEN）
    run bash -c "grep '^_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR' \"$BATS_FILE\" | grep -vc '\\\\'"
    [ "$output" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC3: L77 以降の env-prefix 形式が維持されていること（GREEN before/after fix）
# ---------------------------------------------------------------------------

@test "ac3: env-prefix form at L77 is preserved (regression guard)" {
    # AC3: _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \ 形式（行末 \ 付き）が
    #      少なくとも 1 件以上存在すること（子プロセスへの環境変数伝播が維持されている）
    # 現状: 多数の env-prefix 行（行末 \ 付き）が存在するため PASS
    # 修正後: これらは変更されないため PASS を維持
    run bash -c "grep -c '^_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR.*\\\\' \"$BATS_FILE\""
    [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# AC2: bats 全件 PASS（回帰確認、実装前後ともに PASS）
# ---------------------------------------------------------------------------

@test "ac2: existing cld-observe-any.bats parses correctly (regression guard)" {
    # AC2: bats 全件 PASS の前提として、bats 自体がファイルを正常にカウントできること
    # 注意: L42 の standalone 変数代入は bash の heredoc 内のため bats 文法エラーにはならない
    # ファイルが bats パース可能であることを確認（--count は文法エラーで非 0 を返す）
    run bats --count "$BATS_FILE"
    [ "$status" -eq 0 ]
}
