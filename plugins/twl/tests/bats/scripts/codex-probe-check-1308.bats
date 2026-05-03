#!/usr/bin/env bats
# codex-probe-check-1308.bats
#
# Issue #1308: _CODEX_AUTH_ERROR_PATTERN の 'websocket' が正常接続ログ
# (websocket connected) に false positive でマッチする問題の regression test。
#
# AC-1: codex-probe-check.sh の _CODEX_AUTH_ERROR_PATTERN を
#       'websocket' から 'websocket.*error|websocket.*fail' 等に絞る
# AC-2: 修正後 twl validate または該当 specialist で WARNING 解消確認
# AC-3: 関連 ADR/SKILL/refs に整合する更新があれば同時実施
# AC-4: regression test または fixture で修正の persistence 確認
#
# RED フェーズ:
#   現在の _CODEX_AUTH_ERROR_PATTERN='401|Unauthorized|connection refused|websocket'
#   は 'websocket connected' にマッチするため CODEX_OK=0 になる → false positive
#   AC-1 修正前は ac1-1308 が FAIL することを意図する。

load '../helpers/common'

PROBE_CHECK_SCRIPT=""

setup() {
  common_setup
  PROBE_CHECK_SCRIPT="$SANDBOX/scripts/codex-probe-check.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-1: 'websocket connected' (正常接続ログ) が false positive を引き起こさない
#
# RED: 現在の 'websocket' パターンは 'websocket connected' にマッチするため
#      CODEX_OK=0 になる → テストは FAIL
# GREEN: 'websocket.*error|websocket.*fail' 等に絞ると CODEX_OK=1 のまま → PASS
# ---------------------------------------------------------------------------

@test "ac1-1308: websocket connected (正常接続ログ) が false positive を引き起こさない" {
  # RED: 現在の _CODEX_AUTH_ERROR_PATTERN='...|websocket' が 'websocket connected' に
  #      マッチして CODEX_OK=0 を設定するため、このテストは FAIL する
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
websocket connected to wss://api.openai.com/v1/responses
output: Hello, world!"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  # 正常接続ログなので CODEX_OK は 1 のまま期待
  [[ "$CODEX_OK" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# AC-1 (variant): 'websocket connected' を含む複数行出力でも false positive しない
#
# 実際の codex CLI は複数行ログを出力する場合がある。
# RED: 同上 — 現在のパターンにより CODEX_OK=0 になる
# ---------------------------------------------------------------------------

@test "ac1-1308-multiline: websocket connected を含む複数行出力で CODEX_OK=1 のまま" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
connecting to api.openai.com...
websocket connected to wss://api.openai.com/v1/responses
session started
output: test response"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# AC-1 (regression guard): websocket error は引き続き CODEX_OK=0 になる
#
# このテストは 'websocket.*error' パターンへの変更後も GREEN であるべきテスト。
# 既存 codex-probe-check.bats の ac2-websocket テストと同等の確認。
# 修正前・修正後ともに PASS が期待される（RED ではない）が、
# AC-1 の変更が websocket error 検知を壊さないことを宣言する。
# ---------------------------------------------------------------------------

@test "ac1-1308-websocket-error-still-detected: websocket error は引き続き CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
WebSocket error: failed to connect to wss://api.openai.com/v1/responses"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  # websocket error は修正後も引き続き検知されるべき
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-1 (variant): websocket failed メッセージも CODEX_OK=0 になる
# ---------------------------------------------------------------------------

@test "ac1-1308-websocket-failed-detected: websocket failed は CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
websocket failed: connection timeout wss://api.openai.com/v1/responses"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-2: _CODEX_AUTH_ERROR_PATTERN の値が 'websocket' 単体を含まない
#
# RED: 現在のパターンは 'websocket' 単体を含むため FAIL
# GREEN: パターンが 'websocket.*error|websocket.*fail' 等に変更された後 PASS
# ---------------------------------------------------------------------------

@test "ac2-1308: _CODEX_AUTH_ERROR_PATTERN が 'websocket' 単体を含まない" {
  # RED: 現在は _CODEX_AUTH_ERROR_PATTERN='401|Unauthorized|connection refused|websocket'
  #      なので 'websocket' 単体がパターンに存在 → FAIL
  source "$PROBE_CHECK_SCRIPT"
  # パターンが 'websocket' 単体（前後に文字修飾子なし）を含まないことを確認
  # 'websocket.*error' や 'websocket.*fail' のような限定パターンは許可
  if echo "${_CODEX_AUTH_ERROR_PATTERN}" | grep -qE '\|websocket\||\|websocket$|^websocket\|'; then
    echo "FAIL: _CODEX_AUTH_ERROR_PATTERN に 'websocket' 単体が含まれている: ${_CODEX_AUTH_ERROR_PATTERN}" >&2
    false
  fi
}

# ---------------------------------------------------------------------------
# AC-3: 関連ドキュメント/コメントに修正済みパターンが反映されている
#
# RED: 現在は修正未実施のため、codex-probe-check.sh のコメントに
#      古い 'websocket' パターンの記述が残っている可能性あり
# GREEN: コメント・ドキュメントが新パターンに合わせて更新されている
# ---------------------------------------------------------------------------

@test "ac3-1308: codex-probe-check.sh のコメントが最新パターンを反映している" {
  # RED: 現在は '_CODEX_AUTH_ERROR_PATTERN' の定義行に 'websocket' 単体が残っている
  #      ファイル内コメントが古いパターンを参照していた場合 FAIL
  [[ -f "$PROBE_CHECK_SCRIPT" ]] || {
    echo "FAIL: codex-probe-check.sh が存在しない" >&2
    return 1
  }
  # 定義行 (= 代入) に 'websocket' 単体（|websocket| や |websocket' で終わる）がないこと
  if grep -E "^_CODEX_AUTH_ERROR_PATTERN=" "$PROBE_CHECK_SCRIPT" \
       | grep -qE "\|websocket'|\|websocket\"$|\|websocket$"; then
    echo "FAIL: _CODEX_AUTH_ERROR_PATTERN 定義に 'websocket' 単体が残っている" >&2
    grep -E "^_CODEX_AUTH_ERROR_PATTERN=" "$PROBE_CHECK_SCRIPT" >&2
    false
  fi
}

# ---------------------------------------------------------------------------
# AC-4: pattern 変更の persistence — _CODEX_AUTH_ERROR_PATTERN の定義を確認
#
# RED: 現在のパターンが修正前のため FAIL
# GREEN: パターンが 'websocket.*error' 等に絞られた後 PASS
# ---------------------------------------------------------------------------

@test "ac4-1308: _CODEX_AUTH_ERROR_PATTERN に websocket 限定パターンが含まれる" {
  # RED: 現在は 'websocket' 単体のため FAIL
  #      'websocket.*error' または 'websocket.*fail' のいずれかを含む必要がある
  source "$PROBE_CHECK_SCRIPT"
  if ! echo "${_CODEX_AUTH_ERROR_PATTERN}" | grep -qE 'websocket\.\*error|websocket\.\*fail'; then
    echo "FAIL: _CODEX_AUTH_ERROR_PATTERN にエラー限定の websocket パターンが含まれない" >&2
    echo "  現在の値: ${_CODEX_AUTH_ERROR_PATTERN}" >&2
    echo "  期待: 'websocket.*error' または 'websocket.*fail' を含む" >&2
    false
  fi
}
