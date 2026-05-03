#!/usr/bin/env bats
# test_ac1197_mock_intercept.bats - Issue #1197 RED tests
# Dead mock / run_observe_once helper の設計修正を検証する

BATS_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/cld-observe-any.bats"
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"

# ---------------------------------------------------------------------------
# AC-1: 対象 file/script の修正実施
# export -f _mock_session_state は dead mock（フルパス subprocess をインターセプトできない）
# 修正後（option 3: 削除）はこの行が消えるため、grep が 0 を返す → PASS
# ---------------------------------------------------------------------------
@test "ac1 (#1197): export -f _mock_session_state が cld-observe-any.bats から削除されていること (RED)" {
    count=$(grep -c 'export -f _mock_session_state' "$BATS_FILE" || true)
    [[ "$count" -eq 0 ]] || {
        echo "FAIL: 'export -f _mock_session_state' が $count 行残存（dead mock 未削除）"
        false
    }
}

# ---------------------------------------------------------------------------
# AC-2: 該当テストの green 化（run_observe_once 削除による dead code 解消）
# run_observe_once ヘルパーは全テストが独立 heredoc を使用するため未呼び出し
# 修正後は関数定義ごと削除されるため grep が 0 を返す → PASS
# ---------------------------------------------------------------------------
@test "ac2 (#1197): run_observe_once dead code ヘルパーが cld-observe-any.bats から削除されていること (RED)" {
    count=$(grep -c '^run_observe_once()' "$BATS_FILE" || true)
    [[ "$count" -eq 0 ]] || {
        echo "FAIL: run_observe_once 関数定義が $count 行残存（dead code 未削除）"
        false
    }
}

# ---------------------------------------------------------------------------
# AC-3: twl validate または該当 specialist で WARNING 解消確認
# twl check が errors なしで完了することを確認
# ---------------------------------------------------------------------------
@test "ac3 (#1197): twl check が errors なしで完了すること (RED)" {
    run twl check 2>&1
    echo "$output"
    # errors があれば "errors:" が出力に含まれる
    [[ "$output" != *"errors:"* ]] || {
        echo "FAIL: twl check に errors が検出された"
        false
    }
}

# ---------------------------------------------------------------------------
# AC-4: regression test — _mock_session_state の参照が残存しないこと
# 削除後に再追加されていないことを確認する回帰ガード
# ---------------------------------------------------------------------------
@test "ac4 (#1197): _mock_session_state の参照が cld-observe-any.bats に残存しないこと (RED)" {
    count=$(grep -c '_mock_session_state' "$BATS_FILE" || true)
    [[ "$count" -eq 0 ]] || {
        echo "FAIL: '_mock_session_state' が $count 行残存（回帰リスク）"
        false
    }
}
