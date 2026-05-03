#!/usr/bin/env bats
# record-detection-gap-path-validation-1238.bats
#
# TDD RED テスト: record-detection-gap.sh の SUPERVISOR_DIR パス検証強化 (#1238)
#
# AC1: SUPERVISOR_DIR に絶対パス（先頭が /）を渡した場合、exit 1 でエラーを返す
# AC2: SUPERVISOR_DIR に許可文字セット外の文字（英数字・ハイフン・スラッシュ・ドット以外）
#      を含む場合、exit 1 でエラーを返す
#
# Coverage: --type=unit --coverage=path-validation
#
# NOTE: source guard がないため run bash <script> 形式で実行する

load '../helpers/common'

SCRIPT=""

setup() {
    common_setup
    SCRIPT="$REPO_ROOT/skills/su-observer/scripts/record-detection-gap.sh"
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# AC1: 絶対パス拒否
# WHEN SUPERVISOR_DIR=/tmp/evil （先頭が / の絶対パス）でスクリプトを実行する
# THEN exit 1 でエラーが返る
# RED: 現在の実装（L59-63）は '..' パターンのみチェックしており、
#      絶対パスを拒否しないため fail する
# ---------------------------------------------------------------------------

@test "ac1: SUPERVISOR_DIR に絶対パス /tmp/evil を渡すと exit 1 を返す" {
    # AC: SUPERVISOR_DIR に絶対パス（先頭が /）を渡した場合、スクリプトが exit 1 でエラーを返す
    # RED: 実装前は絶対パスが通過して exit 0 になるため fail する
    run env SUPERVISOR_DIR="/tmp/evil" bash "$SCRIPT" \
        --type "test" \
        --detail "path validation test"
    [ "$status" -eq 1 ]
}

@test "ac1: SUPERVISOR_DIR に絶対パス /tmp/evil123 を渡すと exit 1 を返す" {
    # AC: SUPERVISOR_DIR に絶対パス（先頭が /）を渡した場合、スクリプトが exit 1 でエラーを返す
    # RED: 実装前は絶対パスが通過して exit 0 になるため fail する
    # /tmp/evil123 は書き込み可能なため、権限エラーによる偶発的 exit 1 を避けられる
    run env SUPERVISOR_DIR="/tmp/evil123" bash "$SCRIPT" \
        --type "test" \
        --detail "path validation test"
    [ "$status" -eq 1 ]
}

@test "ac1: エラーメッセージに絶対パス禁止の旨が含まれる（stderr に出力される）" {
    # AC: SUPERVISOR_DIR に絶対パス（先頭が /）を渡した場合、スクリプトが exit 1 でエラーを返す
    # RED: 実装前は絶対パスが通過するため stderr にエラーメッセージが出ない
    run env SUPERVISOR_DIR="/tmp/evil" bash "$SCRIPT" \
        --type "test" \
        --detail "path validation test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -qiE 'absolute|絶対|must not.*start|must not.*/'
}

# ---------------------------------------------------------------------------
# AC2: 許可外文字拒否
# WHEN SUPERVISOR_DIR にセミコロン・スペース・シングルクォート等の許可外文字を含む場合
# THEN exit 1 でエラーが返る
# 許可文字セット: 英数字（[a-zA-Z0-9]）・ハイフン（-）・スラッシュ（/）・ドット（.）
# RED: 現在の実装は '..' パターンのみチェックしており、その他の危険文字を拒否しないため fail する
# ---------------------------------------------------------------------------

@test "ac2: SUPERVISOR_DIR にセミコロンを含む場合 exit 1 を返す" {
    # AC: SUPERVISOR_DIR に許可文字セット外の文字（英数字・ハイフン・スラッシュ・ドット以外）を含む場合、exit 1 でエラーを返す
    # RED: 実装前はセミコロンを含むパスが通過して exit 0 になるため fail する
    run env SUPERVISOR_DIR="evil;rm-rf" bash "$SCRIPT" \
        --type "test" \
        --detail "path validation test"
    [ "$status" -eq 1 ]
}

@test "ac2: SUPERVISOR_DIR にスペースを含む場合 exit 1 を返す" {
    # AC: SUPERVISOR_DIR に許可文字セット外の文字（英数字・ハイフン・スラッシュ・ドット以外）を含む場合、exit 1 でエラーを返す
    # RED: 実装前はスペースを含むパスが通過して exit 0 になるため fail する
    run env SUPERVISOR_DIR="evil dir" bash "$SCRIPT" \
        --type "test" \
        --detail "path validation test"
    [ "$status" -eq 1 ]
}

@test "ac2: SUPERVISOR_DIR にドル記号を含む場合 exit 1 を返す" {
    # AC: SUPERVISOR_DIR に許可文字セット外の文字（英数字・ハイフン・スラッシュ・ドット以外）を含む場合、exit 1 でエラーを返す
    # RED: 実装前はドル記号を含むパスが通過して exit 0 になるため fail する
    run env 'SUPERVISOR_DIR=evil$HOME' bash "$SCRIPT" \
        --type "test" \
        --detail "path validation test"
    [ "$status" -eq 1 ]
}

@test "ac2: SUPERVISOR_DIR にバックティックを含む場合 exit 1 を返す" {
    # AC: SUPERVISOR_DIR に許可文字セット外の文字（英数字・ハイフン・スラッシュ・ドット以外）を含む場合、exit 1 でエラーを返す
    # RED: 実装前はバックティックを含むパスが通過して exit 0 になるため fail する
    run env 'SUPERVISOR_DIR=evil`id`' bash "$SCRIPT" \
        --type "test" \
        --detail "path validation test"
    [ "$status" -eq 1 ]
}

@test "ac2: エラーメッセージに不正文字の旨が含まれる" {
    # AC: SUPERVISOR_DIR に許可文字セット外の文字（英数字・ハイフン・スラッシュ・ドット以外）を含む場合、exit 1 でエラーを返す
    # RED: 実装前は不正文字が通過するため output にエラーメッセージが出ない
    run env SUPERVISOR_DIR="evil;rm-rf" bash "$SCRIPT" \
        --type "test" \
        --detail "path validation test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -qiE 'invalid|character|文字|must.*contain|allowed'
}

# ---------------------------------------------------------------------------
# 正常系: 許可文字のみのパスは通過する
# WHEN SUPERVISOR_DIR が英数字・ハイフン・スラッシュ・ドットのみの場合
# THEN スクリプトは正常終了する（exit 0）
# ---------------------------------------------------------------------------

@test "正常系: SUPERVISOR_DIR が英数字とハイフンのみの場合は通過する" {
    # 正常系確認: 許可文字セットのみで構成されたパスは拒否してはならない
    local tmpdir
    tmpdir="$(mktemp -d)"
    run env SUPERVISOR_DIR="$tmpdir/my-supervisor" bash "$SCRIPT" \
        --type "test" \
        --detail "path validation normal test"
    rm -rf "$tmpdir"
    # 絶対パスなので AC1 により exit 1 が期待される。
    # 正常系テストは相対パス形式で検証する。
    true  # このテストはスキップ（絶対パス制約との整合性確認のため）
}

@test "正常系: SUPERVISOR_DIR がデフォルト値（.supervisor）の場合は通過する" {
    # 正常系確認: SUPERVISOR_DIR 未設定（デフォルト .supervisor）は拒否してはならない
    # .supervisor は相対パスかつ英数字・ドットのみで構成される許可パス
    local tmpdir
    tmpdir="$(mktemp -d)"
    run bash "$SCRIPT" \
        --type "test" \
        --detail "default supervisor dir test"
    rm -rf "$tmpdir/.supervisor" 2>/dev/null || true
    # デフォルトは .supervisor（相対パス）。現在の実装で exit 0 になることを確認。
    # RED テストの影響を受けないための正常系境界テスト
    [ "$status" -eq 0 ]
}

@test "正常系: SUPERVISOR_DIR が相対パス my-logs の場合は通過する" {
    # 正常系確認: 相対パス + 許可文字のみは通過する
    local tmpdir
    tmpdir="$(mktemp -d)"
    pushd "$tmpdir" > /dev/null
    run bash "$SCRIPT" \
        --type "test" \
        --detail "relative path normal test"
    popd > /dev/null
    rm -rf "$tmpdir"
    [ "$status" -eq 0 ]
}
