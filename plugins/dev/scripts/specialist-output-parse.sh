#!/usr/bin/env bash
# specialist-output-parse.sh
# specialist の出力を共通スキーマ（status, findings[]）に基づいてパースする。
#
# Usage: echo "$SPECIALIST_OUTPUT" | bash scripts/specialist-output-parse.sh
# Output: JSON 形式の構造化データ
#
# パース失敗時: 出力全文を WARNING finding (confidence=50) として扱う

set -euo pipefail

# stdin から specialist 出力を読み込み
INPUT=$(cat)

# --- Step 1: status 行の抽出 ---
STATUS=$(echo "$INPUT" | grep -oP 'status:\s*(PASS|WARN|FAIL)' | head -1 | grep -oP '(PASS|WARN|FAIL)' || true)

# --- Step 2: JSON findings ブロックの抽出 ---
# ```json ... ``` ブロックを検出
FINDINGS_JSON=""
if echo "$INPUT" | grep -q '```json'; then
  FINDINGS_JSON=$(echo "$INPUT" | sed -n '/```json/,/```/p' | sed '1d;$d')
fi

# --- Step 3: パース結果の検証 ---
PARSE_SUCCESS=true

# status が取得できない場合
if [[ -z "$STATUS" ]]; then
  PARSE_SUCCESS=false
fi

# findings JSON が取得できない、または不正な JSON の場合
if [[ -n "$FINDINGS_JSON" ]]; then
  if ! echo "$FINDINGS_JSON" | jq . >/dev/null 2>&1; then
    PARSE_SUCCESS=false
  fi
else
  # findings がない場合は空配列として扱う（status があれば成功）
  if [[ "$PARSE_SUCCESS" == "true" ]]; then
    FINDINGS_JSON="[]"
  fi
fi

# --- Step 4: 出力 ---
if [[ "$PARSE_SUCCESS" == "true" ]]; then
  # 正常パース: 構造化データを出力
  jq -n \
    --arg status "$STATUS" \
    --argjson findings "$FINDINGS_JSON" \
    --arg parse_error "false" \
    '{status: $status, findings: $findings, parse_error: ($parse_error == "true")}'
else
  # パース失敗: フォールバック（WARNING, confidence=50）
  # 出力全文を 1 つの WARNING finding として扱う
  ESCAPED_INPUT=$(echo "$INPUT" | jq -Rs .)
  jq -n \
    --arg status "WARN" \
    --argjson message "$ESCAPED_INPUT" \
    --arg parse_error "true" \
    '{
      status: $status,
      findings: [{
        severity: "WARNING",
        confidence: 50,
        file: "unknown",
        line: 0,
        message: ("Parse failed. Raw output: " + $message),
        category: "parse-failure"
      }],
      parse_error: ($parse_error == "true")
    }'
fi
