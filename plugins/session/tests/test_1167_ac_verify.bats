#!/usr/bin/env bats
# test_1167_ac_verify.bats
# Issue #1167: tech-debt: cld-observe-any.bats L74 slash-containing function name
# Issue #1197 により run_observe_once ヘルパーごと削除済み
# AC1-3: _mock_session_state が存在しないことを確認（削除完了の回帰ガード）

TARGET_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/cld-observe-any.bats"

# ---------------------------------------------------------------------------
# AC1: _mock_session_state() 関数定義が存在しないこと
# #1167 で rename 済み、#1197 で dead code 削除済み
# ---------------------------------------------------------------------------
@test "ac1: _mock_session_state() 関数定義が cld-observe-any.bats に存在しない（#1197 削除確認）" {
    run grep -E '^_mock_session_state\(\)[[:space:]]*\{' "$TARGET_FILE"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# AC2: export -f _mock_session_state が存在しないこと
# #1167 で rename 済み、#1197 で dead code 削除済み
# ---------------------------------------------------------------------------
@test "ac2: export -f _mock_session_state が cld-observe-any.bats に存在しない（#1197 削除確認）" {
    run grep -E '^export -f _mock_session_state[[:space:]]*$' "$TARGET_FILE"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# AC3: session-state.sh モックコメント（run_observe_once ヘルパー内）が存在しないこと
# #1197 で run_observe_once ヘルパーごと削除済み
# ---------------------------------------------------------------------------
@test "ac3: session-state.sh モックコメントが cld-observe-any.bats に存在しない（#1197 削除確認）" {
    run grep -E '#.*session-state\.sh.*モック' "$TARGET_FILE"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# AC4: bats 実行が成功する（rename 前後で test 結果が変わらないこと）
# RED: 修正前は bash の関数定義構文エラーで bats 自体が失敗する可能性がある
# 注意: このテストは bats を入れ子で実行するため時間がかかる場合がある
# ---------------------------------------------------------------------------
@test "ac4: bats plugins/session/tests/cld-observe-any.bats が構文エラーなく読み込める" {
    # bats -c でテスト数が取得できれば構文 OK
    run bats -c "$TARGET_FILE"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC5: "$SCRIPT_DIR/session-state.sh"() というスラッシュ付き関数定義が残っていない
# RED: 修正前はこのパターンが存在するため FAIL
# grep が 0 件 → exit 1 → test PASS、1 件以上 → exit 0 → test FAIL
# ---------------------------------------------------------------------------
@test "ac5: slash-containing 関数定義 \"\$SCRIPT_DIR/session-state.sh\"() が残っていない" {
    # このパターンが存在しない（grep が 1 を返す）なら修正済み → PASS
    # 存在する（grep が 0 を返す）なら未修正 → FAIL
    run grep -E '"[^"]+/session-state\.sh"\(\)' "$TARGET_FILE"
    [ "$status" -ne 0 ]
}
