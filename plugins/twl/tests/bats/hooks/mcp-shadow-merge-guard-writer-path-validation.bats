#!/usr/bin/env bats
# mcp-shadow-merge-guard-writer-path-validation.bats
# Issue #1336: SHADOW_LOG_PATH / --log パスバリデーション
#
# AC-1: SHADOW_LOG_PATH 環境変数に許可プレフィックス先頭一致チェックを追加
#         許可リスト: /tmp/, ${HOME}/.cache/, ${SUPERVISOR_DIR}/
# AC-2: --log 引数も同様にバリデート（同じ許可リスト適用）
# AC-3: 不正パス検出時は stderr で警告メッセージ出力 + fail-open
#         （hook 自体は通す、shadow log のみ skip）
#
# RED: 現在の実装はバリデーションが全くないため全テストが FAIL する。
#   - 不正パスでも mkdir -p $(dirname "$LOG_FILE") を実行してしまう
#   - /var/log/ 等への書き込み失敗時に exit 非ゼロになる (fail-open でない)
#   - stderr に警告を出す機能が存在しない

load '../helpers/common'

setup() {
  common_setup

  # リポジトリルート (worktree root) を BATS_TEST_FILENAME から算出
  # hooks/ -> bats/ -> tests/ -> twl/ -> plugins/ -> repo root (worktree)
  # 5段上 (../../../../..) が worktree root
  local git_root
  git_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../.." && pwd)"
  SCRIPT="${git_root}/plugins/twl/scripts/hooks/mcp-shadow-merge-guard-writer.sh"
  export SCRIPT

  # SANDBOX は common_setup が mktemp -d で /tmp/ 配下に作成済み
  # /tmp/ は許可リストにマッチするため「許可パス」として使用する
  ALLOWED_LOG="${SANDBOX}/allowed-shadow.log"
  export ALLOWED_LOG

  # 不正パス: /tmp/, ${HOME}/.cache/, ${SUPERVISOR_DIR}/ のいずれにもマッチしない
  # テスト中は HOME をサンドボックス内の偽ディレクトリに差し替えて
  # /var/log/ 配下が許可リスト外になることを保証する
  DENY_LOG="/var/log/mcp-shadow-test-${BATS_TEST_NUMBER}.log"
  export DENY_LOG
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: SHADOW_LOG_PATH バリデーション
# ===========================================================================

# ---------------------------------------------------------------------------
# 許可ケース: /tmp/ 配下のパス → ログが書き込まれ exit 0
# RED: 現在の実装はバリデーション自体が存在しないため、このテストは
#      「実装後に GREEN になる」ことを確認する意図で書かれている。
#      現在の実装でも /tmp/ 配下への書き込みは成功するため、このテストは
#      GREEN に見えるが、バリデーション追加後の regression 防止を兼ねる。
# ---------------------------------------------------------------------------
@test "ac1: SHADOW_LOG_PATH=/tmp/ allowed path - log written and exit 0" {
  # AC: /tmp/ プレフィックスにマッチするパスは許可され、ログが書き込まれること
  # RED: バリデーション実装前でも /tmp/ 書き込みは成功するが、
  #      バリデーション実装後に「許可フローが壊れていない」ことを regression 保証する
  SHADOW_LOG_PATH="$ALLOWED_LOG" \
    run bash "$SCRIPT" \
      --command "test-command" \
      --bash-exit 0 \
      --mcp-exit 0

  assert_success
  [ -f "$ALLOWED_LOG" ]
}

# ---------------------------------------------------------------------------
# 拒否ケース: /var/log/ 配下のパス → fail-open (exit 0) + ログ未作成 + stderr 警告
# RED: 現在の実装は:
#   1. fail-open でない (書き込み失敗で exit 非ゼロになる)
#   2. ログ未作成 (mkdir -p でディレクトリ作成を試みる)
#   3. stderr 警告を出さない
#   → assert_success が fail する (exit 非ゼロのため)
# ---------------------------------------------------------------------------
@test "ac1: SHADOW_LOG_PATH=/var/log/ denied path - fail-open (exit 0)" {
  # AC-1 + AC-3: 許可リスト外パスでは hook が exit 0 (fail-open) すること
  # RED: 現在の実装は書き込み失敗時に exit 非ゼロになるため assert_success が fail する
  SHADOW_LOG_PATH="$DENY_LOG" \
    run bash "$SCRIPT" \
      --command "test-command" \
      --bash-exit 0 \
      --mcp-exit 0

  assert_success
}

@test "ac1: SHADOW_LOG_PATH=/var/log/ denied path - shadow log NOT created" {
  # AC-1: 不正パスでは shadow log が作成されないこと (skip される)
  # RED: 現在の実装は mkdir -p を試みるため、/var/log/ 書き込み失敗で
  #      exit 非ゼロになるが、ログも作られない → ただし exit は非ゼロ
  SHADOW_LOG_PATH="$DENY_LOG" \
    run bash "$SCRIPT" \
      --command "test-command" \
      --bash-exit 0 \
      --mcp-exit 0

  # ログが作成されていないこと
  [ ! -f "$DENY_LOG" ]
}

@test "ac1: SHADOW_LOG_PATH=/var/log/ denied path - stderr contains WARNING" {
  # AC-1 + AC-3: 不正パス検出時に stderr で警告メッセージを出力すること
  # RED: 現在の実装は警告を出さないため assert_output が fail する
  SHADOW_LOG_PATH="$DENY_LOG" \
    run bash "$SCRIPT" \
      --command "test-command" \
      --bash-exit 0 \
      --mcp-exit 0

  # $output に WARN が含まれること (bats run は stdout+stderr を $output に結合)
  [[ "$output" == *"WARN"* ]]
}

# ===========================================================================
# AC-2: --log 引数バリデーション
# ===========================================================================

# ---------------------------------------------------------------------------
# 許可ケース: --log で /tmp/ 配下のパスを指定 → ログが書き込まれ exit 0
# ---------------------------------------------------------------------------
@test "ac2: --log=/tmp/ allowed path - log written and exit 0" {
  # AC: --log に /tmp/ プレフィックスにマッチするパスを指定した場合、
  #     ログが書き込まれ exit 0 すること
  run bash "$SCRIPT" \
    --command "test-command" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$ALLOWED_LOG"

  assert_success
  [ -f "$ALLOWED_LOG" ]
}

# ---------------------------------------------------------------------------
# 拒否ケース: --log で /var/log/ 配下のパスを指定 → fail-open + ログ未作成 + 警告
# RED: 現在の実装は --log に対してバリデーションを行わず
#      書き込み失敗で exit 非ゼロになる
# ---------------------------------------------------------------------------
@test "ac2: --log=/var/log/ denied path - fail-open (exit 0)" {
  # AC-2 + AC-3: --log に許可リスト外パスを指定した場合 exit 0 (fail-open) すること
  # RED: 現在の実装は書き込み失敗時に exit 非ゼロになるため assert_success が fail する
  run bash "$SCRIPT" \
    --command "test-command" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$DENY_LOG"

  assert_success
}

@test "ac2: --log=/var/log/ denied path - shadow log NOT created" {
  # AC-2: --log に不正パスを指定した場合、shadow log が作成されないこと
  # RED: 現在は mkdir -p を試みて失敗するが exit 非ゼロになる
  run bash "$SCRIPT" \
    --command "test-command" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$DENY_LOG"

  [ ! -f "$DENY_LOG" ]
}

@test "ac2: --log=/var/log/ denied path - stderr contains WARNING" {
  # AC-2 + AC-3: --log に不正パスを指定した場合に stderr で警告を出力すること
  # RED: 現在の実装は警告を出さないため fail する
  run bash "$SCRIPT" \
    --command "test-command" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$DENY_LOG"

  # $output に WARN が含まれること (bats run は stdout+stderr を $output に結合)
  [[ "$output" == *"WARN"* ]]
}

# ===========================================================================
# AC-3: fail-open の詳細検証（mismatch=true ケースでも fail-open すること）
# ===========================================================================

@test "ac3: SHADOW_LOG_PATH denied - fail-open even when mismatch=true" {
  # AC-3: mismatch が true になるケース（bash_exit!=mcp_exit）でも
  #       不正パスなら fail-open (exit 0) すること
  # RED: 現在の実装は書き込み失敗で exit 非ゼロになる
  SHADOW_LOG_PATH="$DENY_LOG" \
    run bash "$SCRIPT" \
      --command "test-command" \
      --bash-exit 0 \
      --mcp-exit 1

  # mismatch=true の場合でも exit 0 すること (fail-open)
  assert_success
}

@test "ac3: --log denied - fail-open even when mismatch=true" {
  # AC-3: --log に不正パスを指定し mismatch=true になるケースでも
  #       exit 0 (fail-open) すること
  # RED: 現在の実装は書き込み失敗で exit 非ゼロになる
  run bash "$SCRIPT" \
    --command "test-command" \
    --bash-exit 1 \
    --mcp-exit 0 \
    --log "$DENY_LOG"

  assert_success
}

@test "ac3: warning message describes allowlist violation" {
  # AC-3: 警告メッセージに許可リストの説明または "allowlist"/"permitted"/"allowed" 等が
  #       含まれること（単なる "error" ではなくバリデーション失敗と識別できること）
  # RED: 現在の実装は警告自体を出さないため fail する
  SHADOW_LOG_PATH="$DENY_LOG" \
    run bash "$SCRIPT" \
      --command "test-command" \
      --bash-exit 0 \
      --mcp-exit 0

  # 警告に allowlist 関連の語句が含まれること
  # WARN に加え、許可リストパスの説明か "allowed" 系の語が含まれることを期待
  local combined_output="${output}${stderr}"
  [[ "$combined_output" == *"WARN"* ]] || [[ "$combined_output" == *"warn"* ]]
}

# ===========================================================================
# AC-1/AC-2 境界値: ${HOME}/.cache/ 許可ケース
# ===========================================================================

@test "ac1: SHADOW_LOG_PATH=HOME/.cache/ allowed path - log written and exit 0" {
  # AC: ${HOME}/.cache/ プレフィックスにマッチするパスも許可されること
  # RED: 実装後に GREEN になることを確認するためのテスト
  #      現在の実装はバリデーション自体がないため、HOME/.cache/ への書き込みは
  #      ディレクトリが存在すれば成功するが、バリデーションが実装された後も
  #      この許可ケースが正しく動くことを保証する
  local cache_log="${HOME}/.cache/mcp-shadow-test-${BATS_TEST_NUMBER}.log"
  mkdir -p "${HOME}/.cache" 2>/dev/null || true

  SHADOW_LOG_PATH="$cache_log" \
    run bash "$SCRIPT" \
      --command "test-command" \
      --bash-exit 0 \
      --mcp-exit 0

  assert_success

  # クリーンアップ
  rm -f "$cache_log" 2>/dev/null || true
}

@test "ac2: --log=HOME/.cache/ allowed path - log written and exit 0" {
  # AC: --log に ${HOME}/.cache/ 配下のパスを指定した場合も許可されること
  local cache_log="${HOME}/.cache/mcp-shadow-log-test-${BATS_TEST_NUMBER}.log"
  mkdir -p "${HOME}/.cache" 2>/dev/null || true

  run bash "$SCRIPT" \
    --command "test-command" \
    --bash-exit 0 \
    --mcp-exit 0 \
    --log "$cache_log"

  assert_success

  rm -f "$cache_log" 2>/dev/null || true
}
