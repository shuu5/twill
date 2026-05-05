#!/usr/bin/env bats
# su-observer-record-detection-gap-log-safe.bats
#
# TDD RED フェーズ: record-detection-gap.sh のログインジェクション対策テスト
# Issue #1386: SUPERVISOR_DIR に改行/制御文字が含まれる場合の stderr sanitize
#
# AC1: L65 (絶対パス拒否エラー) で ${_supervisor_dir} 出力時に printf '%q' または
#      コントロール文字除去を適用する
# AC2: 本ファイル自体の存在と内容の正常動作を確認する
# AC4: L62 (.. 拒否) / L67 (forbidden-chars 拒否) のエラーメッセージに
#      ${_supervisor_dir} を埋め込む場合は同等の sanitize を適用すること
#
# Coverage: --type=unit --coverage=log-injection-prevention

load '../helpers/common'

SCRIPT=""

setup() {
    common_setup
    SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/record-detection-gap.sh"
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# AC2: 本テストファイルが存在することの確認
# WHEN: テストファイルのパスを確認する
# THEN: ファイルが存在する
#
# NOTE: このテストは bats ランタイム上で実行されているため、常に PASS する。
#       RED フェーズでは AC1/AC4 のテストが fail することで RED を構成する。
# ---------------------------------------------------------------------------

@test "ac2: テストファイル su-observer-record-detection-gap-log-safe.bats が存在する" {
    # AC: 新規 bats test ファイルが追加されている
    [[ -f "${BATS_TEST_FILENAME}" ]] \
        || fail "テストファイルが存在しない: ${BATS_TEST_FILENAME}"
}

# ---------------------------------------------------------------------------
# AC1: 改行を含む SUPERVISOR_DIR を渡したとき stderr が単一行に収まること
# WHEN: SUPERVISOR_DIR=$'/path\nFAKE LOG ENTRY' を渡してスクリプトを実行する
# THEN: stderr の出力が単一行に収まる（"FAKE LOG ENTRY" が独立行として現れない）
#
# RED: 実装前は echo "${_supervisor_dir}" がそのまま改行を含む文字列を出力するため
#      stderr が複数行になり fail する
# ---------------------------------------------------------------------------

@test "ac1: 改行を含む SUPERVISOR_DIR の絶対パス拒否 stderr が単一行に収まる" {
    # AC: printf '%q' またはコントロール文字除去を適用して stderr を単一行に抑制する
    # RED: sanitize 未実装のため stderr に "FAKE LOG ENTRY" が独立行として現れ fail する
    run env SUPERVISOR_DIR=$'/path\nFAKE LOG ENTRY' \
        bash "$SCRIPT" --type test --detail test 2>&1 1>/dev/null
    # status は 1 (exit 1) になるはず
    [ "$status" -eq 1 ]
    # stderr 出力行数チェック: 改行で分割された FAKE LOG ENTRY が独立行として現れない
    [ "${#lines[@]}" -le 1 ] \
        || fail "stderr が複数行になった（改行インジェクション未防止）: ${lines[*]}"
}

# ---------------------------------------------------------------------------
# AC1 補足: CR (carriage return) を含む SUPERVISOR_DIR でも同様に保護されること
# WHEN: SUPERVISOR_DIR=$'prefix\rFAKE LOG ENTRY' を渡す
# THEN: stderr 出力に CR を含む制御文字が出力されない
#
# RED: sanitize 未実装のため CR 含む文字列がそのまま stderr に出力され fail する
# ---------------------------------------------------------------------------

@test "ac1: CR を含む SUPERVISOR_DIR の絶対パス拒否 stderr に制御文字が含まれない" {
    # AC: CR 含む入力でも stderr が安全な ASCII のみで構成される
    # RED: sanitize 未実装のため CR がそのまま出力され fail する
    run env SUPERVISOR_DIR=$'prefix\rFAKE LOG ENTRY' \
        bash "$SCRIPT" --type test --detail test 2>&1 1>/dev/null
    [ "$status" -eq 1 ]
    # CR (0x0d) が stderr に含まれていないことを確認
    if echo "$output" | cat -v | grep -q '\^M'; then
        fail "stderr に CR (^M) が含まれている: $(echo "$output" | cat -v)"
    fi
}

# ---------------------------------------------------------------------------
# AC4: 絶対パス (`^/`) を含む SUPERVISOR_DIR の拒否メッセージに
#      改行/制御文字が含まれる場合、sanitize が適用されていること
# WHEN: SUPERVISOR_DIR=$'/absolute\nFAKE LOG ENTRY' を渡す
# THEN: stderr が単一行に収まる（FAKE LOG ENTRY が独立行として現れない）
#
# NOTE: 現在の実装では絶対パス拒否は L61-64 の単一ブランチで処理される。
#       `^/` の場合も改行を含む値が echo されると multi-line になる。
# RED: sanitize 未実装のため fail する
# ---------------------------------------------------------------------------

@test "ac4: 絶対パス (^/) を含む SUPERVISOR_DIR の拒否 stderr が単一行に収まる" {
    # AC: L62 (^/ 拒否) のエラーメッセージに ${_supervisor_dir} を使う場合は
    #     同等の sanitize を適用すること
    # RED: sanitize 未実装のため stderr に FAKE LOG ENTRY が独立行として現れ fail する
    run env SUPERVISOR_DIR=$'/absolute\nFAKE LOG ENTRY' \
        bash "$SCRIPT" --type test --detail test 2>&1 1>/dev/null
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -le 1 ] \
        || fail "絶対パス拒否 stderr が複数行になった（改行インジェクション未防止）: ${lines[*]}"
}

# ---------------------------------------------------------------------------
# AC4: `..` を含む SUPERVISOR_DIR の拒否メッセージに
#      改行/制御文字が含まれる場合、sanitize が適用されていること
# WHEN: SUPERVISOR_DIR=$'../etc\nFAKE LOG ENTRY' を渡す
# THEN: stderr が単一行に収まる（FAKE LOG ENTRY が独立行として現れない）
#
# RED: sanitize 未実装のため fail する
# ---------------------------------------------------------------------------

@test "ac4: .. を含む SUPERVISOR_DIR の拒否 stderr が単一行に収まる" {
    # AC: L62 (.. 拒否) のエラーメッセージに ${_supervisor_dir} を使う場合は
    #     同等の sanitize を適用すること
    # RED: sanitize 未実装のため stderr に FAKE LOG ENTRY が独立行として現れ fail する
    run env SUPERVISOR_DIR=$'../etc\nFAKE LOG ENTRY' \
        bash "$SCRIPT" --type test --detail test 2>&1 1>/dev/null
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -le 1 ] \
        || fail ".. 拒否 stderr が複数行になった（改行インジェクション未防止）: ${lines[*]}"
}
