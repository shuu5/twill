#!/usr/bin/env bats
# test_1167_ac_verify.bats
# Issue #1167: tech-debt: cld-observe-any.bats L74 slash-containing function name
# RED フェーズ — 修正前の現状では全テストが FAIL する
# 修正後（実装完了後）は全テストが PASS する

TARGET_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/cld-observe-any.bats"

# ---------------------------------------------------------------------------
# AC1: L74 の関数定義を _mock_session_state() に rename する（slash 除去）
# RED: 修正前は "\"$SCRIPT_DIR/session-state.sh\"()" 形式が残っているため FAIL
# ---------------------------------------------------------------------------
@test "ac1: L74 の関数定義が _mock_session_state() { ... } 形式になっている" {
    # 修正済みならこのパターンが存在する → PASS
    grep -qE '^_mock_session_state\(\)[[:space:]]*\{' "$TARGET_FILE"
}

# ---------------------------------------------------------------------------
# AC2: L75 の export 行が export -f _mock_session_state に置換されている
# RED: 修正前は export -f "$SCRIPT_DIR/session-state.sh" 形式が残っているため FAIL
# ---------------------------------------------------------------------------
@test "ac2: L75 の export 行が export -f _mock_session_state になっている" {
    # 修正済みならこのパターンが存在する → PASS
    grep -qE '^export -f _mock_session_state[[:space:]]*$' "$TARGET_FILE"
}

# ---------------------------------------------------------------------------
# AC3: L73 のコメントが保持または更新されている
# GREEN 寄りだが、コメント行の存在確認として記録する
# 修正前でもコメントは存在するため、このテストは PASS する可能性がある
# ただし rename 前後でコメントが消去されていないことを担保するために配置する
# ---------------------------------------------------------------------------
@test "ac3: L73 の session-state.sh モックコメントが存在する" {
    # コメント行（"session-state.sh" と "モック" を含む）が存在する → PASS
    grep -qE '#.*session-state\.sh.*モック' "$TARGET_FILE"
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
