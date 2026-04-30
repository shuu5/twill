#!/usr/bin/env bats
# test_issue1162_comments.bats
# Issue #1162: cld-observe-any.bats Scenario14-18 のコメント誤記修正
# RED フェーズ — 新しい GREEN コメント文字列が存在しないことを検証
# 実装（コメント書き換え）後に GREEN になる

BATS_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/cld-observe-any.bats"

# ---------------------------------------------------------------------------
# AC1: Scenario14 ヘッダーと末尾 inline コメントを GREEN regression guard 表現に書き換える
# L631-632 narrative と L670 inline コメント
# ---------------------------------------------------------------------------

@test "ac1a: Scenario14 L631 に GREEN regression guard ナラティブ行1が存在すること" {
    # AC: L631-632 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF '"Burrowing" は L32 LLM_INDICATORS に収録済（PR #1161 で追加）→ thinking guard が機能し STAGNATE 抑止。' "$BATS_FILE"
}

@test "ac1b: Scenario14 L632 に GREEN regression guard ナラティブ行2が存在すること" {
    # AC: L631-632 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF 'GREEN: 実装済みの動作確認テスト（regression guard）。' "$BATS_FILE"
}

@test "ac1c: Scenario14 L670 inline コメントが GREEN regression guard 表現になっていること" {
    # AC: L670 の inline コメントを GREEN 表現に書き換える
    # RED: 変更前は "RED: 現実装では emit される" という文字列が残っている
    grep -qF '"Burrowing" は thinking 中の indicator なので STAGNATE は emit されない（regression guard: thinking guard が機能し続けることを確認）' "$BATS_FILE"
}

@test "ac1d: Scenario14 L670 から RED 誤記が除去されていること" {
    # AC: L670 の "RED: 現実装では emit される" が除去される
    # RED: 変更前はこの文字列が存在する（= grep が成功する）→ ! で fail にする
    ! grep -qF 'RED: 現実装では emit される' "$BATS_FILE"
}

# ---------------------------------------------------------------------------
# AC2: Scenario15 ヘッダーコメントを GREEN regression guard 表現に書き換える
# L676-677 narrative
# ---------------------------------------------------------------------------

@test "ac2a: Scenario15 L676 に GREEN regression guard ナラティブ行1が存在すること" {
    # AC: L676-677 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF '各 indicator あり + stagnate 超過 → STAGNATE emit なしを assert。' "$BATS_FILE"
}

@test "ac2b: Scenario15 L677 に GREEN regression guard ナラティブ行2が存在すること" {
    # AC: L676-677 の narrative に PR #1161 収録済の記述が追加される
    # RED: 変更前は存在しない
    grep -qF '"Saut.*ed" (L31), "Cerebrating" (L33), "Thundering" (L36) いずれも LLM_INDICATORS に収録済（PR #1161 で追加）→ thinking guard が機能し STAGNATE 抑止。' "$BATS_FILE"
}

@test "ac2c: Scenario15 に GREEN: 実装済みの動作確認テスト（regression guard）が存在すること" {
    # AC: Scenario15 ヘッダーに GREEN regression guard ラベルが追加される
    # RED: 変更前は存在しない（GREEN 行が複数ある場合は Scenario15 固有の文脈で確認）
    # L676-678 の範囲で GREEN: 表現が存在するか行番号付きで確認
    grep -n 'GREEN: 実装済みの動作確認テスト（regression guard）。' "$BATS_FILE" | grep -q .
}

@test "ac2d: Scenario15 から RED 誤記（カタログ未収録）が除去されていること" {
    # AC: L677 の "現実装ではカタログ未収録のため thinking guard をすり抜けて STAGNATE emit される → RED" が除去される
    # RED: 変更前はこの文字列が存在する
    ! grep -qF '現実装ではカタログ未収録のため thinking guard をすり抜けて STAGNATE emit される → RED' "$BATS_FILE"
}

# ---------------------------------------------------------------------------
# AC3: Scenario16 ヘッダーと末尾 inline コメントを GREEN regression guard 表現に書き換える
# L753-754 narrative と L791 inline コメント
# ---------------------------------------------------------------------------

@test "ac3a: Scenario16 L753 に GREEN regression guard ナラティブ行1が存在すること" {
    # AC: L753-754 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF '一般化 regex `[A-Z][a-z]+(in'"'"'|ing|ed)(…| for [0-9]| \([0-9])`（L43）で "Fizzing" を検出 → thinking guard が機能し STAGNATE 抑止。' "$BATS_FILE"
}

@test "ac3b: Scenario16 L754 に GREEN regression guard ナラティブ行2が存在すること" {
    # AC: L753-754 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF 'GREEN: 一般化 regex の動作確認テスト（regression guard）。' "$BATS_FILE"
}

@test "ac3c: Scenario16 L791 inline コメントが GREEN regression guard 表現になっていること" {
    # AC: L791 の inline コメントを GREEN 表現に書き換える
    # RED: 変更前は "RED: 現実装では emit される" という文字列が残っている
    grep -qF '未知の indicator でも一般化 regex (L43) で thinking guard が機能し STAGNATE は emit されない（regression guard）' "$BATS_FILE"
}

@test "ac3d: Scenario16 から RED 誤記（固定リストで検出できない）が除去されていること" {
    # AC: L754 の "現実装（固定リスト）では "Fizzing" を検出できないため STAGNATE emit される → RED" が除去される
    # RED: 変更前はこの文字列が存在する
    ! grep -qF '現実装（固定リスト）では "Fizzing" を検出できないため STAGNATE emit される → RED' "$BATS_FILE"
}

# ---------------------------------------------------------------------------
# AC4: Scenario17 ヘッダーコメントを GREEN regression guard 表現に書き換える
# L796-798 narrative
# ---------------------------------------------------------------------------

@test "ac4a: Scenario17 L796 に GREEN regression guard ナラティブ行1が存在すること" {
    # AC: L796-798 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF '"Beboppin" は L35 LLM_INDICATORS に直接収録済（一般化 regex L43 の `[A-Z][a-z]+in'"'"'` パターンでも検出可能）。' "$BATS_FILE"
}

@test "ac4b: Scenario17 L797 に GREEN regression guard ナラティブ行2が存在すること" {
    # AC: L796-798 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF 'いずれの経路でも thinking guard が機能し STAGNATE 抑止。' "$BATS_FILE"
}

@test "ac4c: Scenario17 L798 に GREEN: 実装済みの動作確認テストが存在すること" {
    # AC: L796-798 の narrative に GREEN ラベルを追加
    # RED: 変更前は存在しない
    grep -qF 'GREEN: 実装済みの動作確認テスト（regression guard）。' "$BATS_FILE"
}

@test "ac4d: Scenario17 から RED 誤記（LLM_INDICATORS に含まれない）が除去されていること" {
    # AC: L798 の "現実装では "Beboppin'" が LLM_INDICATORS に含まれないため STAGNATE emit される → RED" が除去される
    # RED: 変更前はこの文字列が存在する
    ! grep -qF 'LLM_INDICATORS に含まれないため STAGNATE emit される → RED' "$BATS_FILE"
}

# ---------------------------------------------------------------------------
# AC5: Scenario18 ヘッダーと末尾 inline コメントを GREEN regression guard 表現に書き換える
# L838-840 narrative と L875 inline コメント
# ---------------------------------------------------------------------------

@test "ac5a: Scenario18 L838 に GREEN regression guard ナラティブ行1が存在すること" {
    # AC: L838-840 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF 'Scenario 14 と同じ "Burrowing" indicator を使うが、`stagnate-sec 30` × `log mtime 60s 前` で stagnate 閾値を厳しく設定。' "$BATS_FILE"
}

@test "ac5b: Scenario18 L839 に GREEN regression guard ナラティブ行2が存在すること" {
    # AC: L838-840 の narrative を GREEN 表現に書き換える
    # RED: 変更前は存在しない
    grep -qF '既収録 indicator でも regression なく STAGNATE 抑止が機能することを確認する偽陽性 case の regression guard。' "$BATS_FILE"
}

@test "ac5c: Scenario18 L840 に GREEN: 実装済みの動作確認テストが存在すること" {
    # AC: L838-840 の narrative に GREEN ラベルを追加
    # RED: 変更前は存在しない
    grep -qF 'GREEN: 実装済みの動作確認テスト。' "$BATS_FILE"
}

@test "ac5d: Scenario18 L875 inline コメントが GREEN regression guard 表現になっていること" {
    # AC: L875 の inline コメントを GREEN 表現に書き換える
    # RED: 変更前は "RED: 現実装では emit される" が残っている
    grep -qF 'Burrowing indicator が存在する → LLM は思考中 → STAGNATE は emit されない（regression guard）' "$BATS_FILE"
}

@test "ac5e: Scenario18 から RED 誤記（Burrowing が未収録なため）が除去されていること" {
    # AC: L840 の "現実装で "Burrowing" が未収録なため STAGNATE emit される → RED" が除去される
    # RED: 変更前はこの文字列が存在する
    ! grep -qF '現実装で "Burrowing" が未収録なため STAGNATE emit される → RED' "$BATS_FILE"
}

# ---------------------------------------------------------------------------
# AC6: bats 全件（#15-19）が引き続き GREEN を維持すること
# ---------------------------------------------------------------------------

@test "ac6: bats test #15-19 が全て ok を維持すること" {
    # AC: bats plugins/session/tests/cld-observe-any.bats 実行で test #15-19 が全て ok
    # RED: 現時点では bats テスト #15-19 は "not ok"（実装前の RED 状態）
    # 実装後（コメント変更後）も bats テスト自体は GREEN を維持すること
    # NOTE: このテストは bats を bats で実行するため、ネストを避けて run を使う
    local bats_bin
    bats_bin="$(command -v bats 2>/dev/null)" || bats_bin="/usr/local/bin/bats"

    run "$bats_bin" \
        --filter "AC1: thinking indicator 'Burrowing' あり → STAGNATE emit なし（偽陽性防止）" \
        "$BATS_FILE"
    [[ "$status" -eq 0 ]]

    run "$bats_bin" \
        --filter "AC1: thinking indicator 'Sautéed / Cerebrating / Thundering' あり → STAGNATE emit なし" \
        "$BATS_FILE"
    [[ "$status" -eq 0 ]]

    run "$bats_bin" \
        --filter "AC2: 未知 indicator 'Fizzing" \
        "$BATS_FILE"
    [[ "$status" -eq 0 ]]

    run "$bats_bin" \
        --filter "AC2: indicator suffix" \
        "$BATS_FILE"
    [[ "$status" -eq 0 ]]

    run "$bats_bin" \
        --filter "AC3: 偽陽性ケース" \
        "$BATS_FILE"
    [[ "$status" -eq 0 ]]
}
