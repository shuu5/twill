#!/usr/bin/env bash
# PreToolUse hook: ホスト環境破壊防止ガード
#
# Bash tool 呼び出し時にホスト環境を破壊しうるコマンドを検出し deny する。
# AUTOPILOT_DIR 設定時のみ発火（通常セッション無影響）。
#
# 検出パターン:
#   - --break-system-packages: システム Python 破壊
#   - pip install / pip3 install / python3 -m pip install (VIRTUAL_ENV 外): ホストへの直接インストール
#   - sudo apt-get install / sudo apt install: ホストへのパッケージ導入
#
# Issue #199: Worker が autopilot でホスト環境を破壊する問題の防止

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")

# AUTOPILOT_DIR 未設定 → no-op（通常セッション）
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

# JSON パース失敗時は no-op
if ! echo "$payload" | jq empty 2>/dev/null; then
  exit 0
fi

tool_name=$(echo "$payload" | jq -r '.tool_name // empty')
case "$tool_name" in
  Bash) ;;
  *) exit 0 ;;
esac

cmd=$(echo "$payload" | jq -r '.tool_input.command // empty')
if [[ -z "$cmd" ]]; then
  exit 0
fi

deny() {
  local reason="$1"
  jq -nc \
    --arg reason "$reason" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
  exit 0
}

# --break-system-packages → 即 deny
if [[ "$cmd" == *"--break-system-packages"* ]]; then
  deny "ホスト環境保護: --break-system-packages はシステム Python を破壊するため禁止。コンテナ内で実行してください"
fi

# pip install (VIRTUAL_ENV 外) → deny
if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  if echo "$cmd" | grep -qE '(^|[;&|]\s*)(pip3?\s+install|python3?\s+-m\s+pip\s+install)'; then
    deny "ホスト環境保護: pip install はホスト環境では禁止。コンテナ内または VIRTUAL_ENV 内で実行してください"
  fi
fi

# sudo apt-get install / sudo apt install → deny
if echo "$cmd" | grep -qE '(^|[;&|]\s*)sudo\s+(apt-get|apt)\s+install'; then
  deny "ホスト環境保護: sudo apt install はホスト環境では禁止。コンテナ内で実行してください"
fi

exit 0
