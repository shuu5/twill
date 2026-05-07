#!/usr/bin/env bats
# codex-probe-check-1485.bats
#
# Issue #1485: _CODEX_AUTH_ERROR_PATTERN に quota/billing 系パターンを追加し、
# CODEX_SKIP_REASON を keyword で分岐する。
#
# AC-1: _CODEX_AUTH_ERROR_PATTERN に quota/billing/exceeded/insufficient_quota/rate_limit 追加
# AC-2: CODEX_SKIP_REASON を分岐 (quota系 → "quota/billing exhausted", auth系 → "auth/connection error")
# AC-3: quota fixture test 3 件以上追加 (Quota exceeded / billing details / insufficient_quota)
# AC-4: regression: 既存 401/Unauthorized/websocket error 検出が壊れない
#
# RED フェーズ:
#   現在の _CODEX_AUTH_ERROR_PATTERN='401|Unauthorized|connection refused|websocket.*error|websocket.*fail'
#   に quota 系パターンが含まれないため、quota fixture では CODEX_OK=1 のまま → FAIL
#   CODEX_SKIP_REASON の分岐ロジックが未実装のため、分岐テストも FAIL

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
# AC-3: quota fixture test — "Quota exceeded" パターン
#
# RED: quota パターンが _CODEX_AUTH_ERROR_PATTERN に未追加のため CODEX_OK=1 → FAIL
# GREEN: パターン追加後 CODEX_OK=0 → PASS
# ---------------------------------------------------------------------------

@test "ac3-1485-quota-exceeded: Quota exceeded 時 CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
Error: Quota exceeded for org org-xxxxxxxx on tokens per minute for gpt-5.3-codex"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-3: quota fixture test — "billing details" パターン
#
# RED: billing パターンが _CODEX_AUTH_ERROR_PATTERN に未追加のため CODEX_OK=1 → FAIL
# GREEN: パターン追加後 CODEX_OK=0 → PASS
# ---------------------------------------------------------------------------

@test "ac3-1485-billing: billing details メッセージ時 CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
Error: You exceeded your current quota, please check your plan and billing details."
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-3: quota fixture test — "insufficient_quota" パターン
#
# RED: insufficient_quota パターンが _CODEX_AUTH_ERROR_PATTERN に未追加のため CODEX_OK=1 → FAIL
# GREEN: パターン追加後 CODEX_OK=0 → PASS
# ---------------------------------------------------------------------------

@test "ac3-1485-insufficient-quota: insufficient_quota エラー時 CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
{\"error\":{\"code\":\"insufficient_quota\",\"message\":\"You exceeded your current quota\"}}"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-3 (extra): rate_limit パターン
#
# RED: rate_limit パターンが _CODEX_AUTH_ERROR_PATTERN に未追加のため CODEX_OK=1 → FAIL
# GREEN: パターン追加後 CODEX_OK=0 → PASS
# ---------------------------------------------------------------------------

@test "ac3-1485-rate-limit: rate_limit エラー時 CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
Error: rate_limit_exceeded — Request too large for gpt-5.3-codex"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-2: CODEX_SKIP_REASON 分岐 — quota 系 → "quota/billing exhausted"
#
# RED: 現在の実装は CODEX_SKIP_REASON="auth/connection error (...)" と固定のため FAIL
# GREEN: 分岐実装後 quota 系は "quota/billing exhausted" → PASS
# ---------------------------------------------------------------------------

@test "ac2-1485-quota-skip-reason: quota 系エラーで CODEX_SKIP_REASON が quota/billing exhausted になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
Error: Quota exceeded for org org-xxxxxxxx"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_SKIP_REASON" == "quota/billing exhausted" ]]
}

# ---------------------------------------------------------------------------
# AC-2: CODEX_SKIP_REASON 分岐 — auth 系 → "auth/connection error"（パターン文字列なし）
#
# RED: 現在は "auth/connection error (401|Unauthorized|...)" という形式のため FAIL
#      パターン文字列を含まない純粋な "auth/connection error" を期待
# GREEN: 分岐実装後 auth 系は "auth/connection error" のみ → PASS
# ---------------------------------------------------------------------------

@test "ac2-1485-auth-skip-reason: auth 系 (401) エラーで CODEX_SKIP_REASON が auth/connection error になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
HTTP 401 Unauthorized"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_SKIP_REASON" == "auth/connection error" ]]
}

# ---------------------------------------------------------------------------
# AC-4: regression — 401 検出が壊れない
# ---------------------------------------------------------------------------

@test "ac4-1485-regression-401: 既存 401 検出が壊れない" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
HTTP 401 Unauthorized"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-4: regression — Unauthorized 検出が壊れない
# ---------------------------------------------------------------------------

@test "ac4-1485-regression-unauthorized: 既存 Unauthorized 検出が壊れない" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
Error: 401 Unauthorized — API key lacks Responses API scope"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-4: regression — websocket error 検出が壊れない
# ---------------------------------------------------------------------------

@test "ac4-1485-regression-websocket-error: 既存 websocket error 検出が壊れない" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
WebSocket error: failed to connect to wss://api.openai.com/v1/responses"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-4: regression — 正常出力では CODEX_OK=1 のまま（quota パターン追加の false positive 確認）
# ---------------------------------------------------------------------------

@test "ac4-1485-regression-normal: 正常出力では CODEX_OK=1 のまま" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
output: Hello, world!"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 1 ]]
}
