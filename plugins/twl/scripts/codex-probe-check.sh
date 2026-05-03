#!/usr/bin/env bash
# codex-probe-check.sh
#
# probe 出力から model_id を検証し、retired model blocklist を適用する関数ライブラリ。
# worker-codex-reviewer.md の Step 1 から source して run_probe_check() を呼び出す。
#
# 使い方:
#   PROBE_MODEL="gpt-5.3-codex"
#   PROBE_OUT="$(echo test | codex exec -m "$PROBE_MODEL" ...)"
#   CODEX_OK=1
#   source codex-probe-check.sh
#   run_probe_check   # CODEX_OK を上書きする可能性がある
#
# 参照:
#   https://developers.openai.com/codex/models (失効確認日: 2026-05-01)

# source guard: スクリプトとして直接実行された場合は何もしない
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "このスクリプトは source して使用してください" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Retired/deprecated model ID blocklist
# 根拠: https://developers.openai.com/codex/models (失効確認日: 2026-05-01)
# 対象: gpt-5.3-codex のデフォルト採用後に明らかに古い世代のモデル
# 除外: gpt-5.1-codex (AC #7 — env override 利用時の誤発火防止)
# ---------------------------------------------------------------------------
_CODEX_BLOCKLIST_PATTERN='gpt-4[^-]|gpt-3|o3-|o4-'
# 注: ^ アンカーなし — probe 出力全体を grep するため行頭限定にしない
# gpt-4- 系列（gpt-4-turbo 等）は [^-] 除外のため blocklist 対象外（意図的）

# ---------------------------------------------------------------------------
# Auth/connection error detection pattern (AC-1 #1289, fixed #1308)
# probe 出力（stdout+stderr merged via 2>&1）に 401 系エラーが含まれる場合に CODEX_OK=0。
# head -20（worker-codex-reviewer.md で設定）で 401 retry ログを確実にキャプチャ。
# websocket は 'websocket connected' 等の正常ログで false positive が発生するため
# websocket.*error|websocket.*fail のエラー限定パターンに絞る（Issue #1308）。
# ---------------------------------------------------------------------------
_CODEX_AUTH_ERROR_PATTERN='401|Unauthorized|connection refused|websocket.*error|websocket.*fail'

# ---------------------------------------------------------------------------
# run_probe_check
#
# 引数: なし（PROBE_OUT, PROBE_MODEL, CODEX_OK を環境変数として参照）
# 副作用: CODEX_OK を 0 に設定する可能性がある（1 には戻さない）
#         CODEX_SKIP_REASON を設定する（CODEX_OK=0 の場合のみ）
# 出力: WARN ログを stderr に出力
# ---------------------------------------------------------------------------
run_probe_check() {
  local resolved_model=""
  local warn_prefix="WARN: model resolution mismatch:"

  # AC #1289: auth/connection error detection — model 解決前に先行チェック
  # PROBE_OUT には stdout+stderr が merged されており 401 retry ログが含まれる
  if echo "${PROBE_OUT:-}" | grep -qiE "${_CODEX_AUTH_ERROR_PATTERN}"; then
    CODEX_OK=0
    CODEX_SKIP_REASON="auth/connection error (${_CODEX_AUTH_ERROR_PATTERN})"
    echo "WARN: auth/connection error detected in probe output (pattern: ${_CODEX_AUTH_ERROR_PATTERN})" >&2
    return
  fi

  # AC #3: probe stdout の `model: <name>` 行を抽出
  resolved_model=$(echo "${PROBE_OUT:-}" | grep -E "^model:" | head -1 | awk '{print $2}')

  # AC #4/#13: resolved_model が空文字列 or PROBE_MODEL と不一致 → CODEX_OK=0
  if [[ -z "$resolved_model" || "$resolved_model" != "${PROBE_MODEL:-}" ]]; then
    CODEX_OK=0
    CODEX_SKIP_REASON="model resolution mismatch: requested=${PROBE_MODEL:-}, resolved=${resolved_model:-<empty>}"
    # AC #5: warning ログ（空文字列の場合は resolved=<empty>）
    local display_resolved="${resolved_model:-<empty>}"
    echo "${warn_prefix} requested=${PROBE_MODEL:-}, resolved=${display_resolved}" >&2
    return
  fi

  # AC #6: retired/deprecated model ID が probe 出力に含まれる場合 → CODEX_OK=0
  # blocklist: gpt-4* (非ハイフン), gpt-3*, o3-*, o4-* （gpt-5.1-codex は除外）
  if echo "${PROBE_OUT:-}" | grep -qE "${_CODEX_BLOCKLIST_PATTERN}"; then
    CODEX_OK=0
    CODEX_SKIP_REASON="retired model detected (blocklist: ${_CODEX_BLOCKLIST_PATTERN})"
    echo "WARN: retired model detected in probe output (blocklist: ${_CODEX_BLOCKLIST_PATTERN})" >&2
    return
  fi
}
