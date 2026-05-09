#!/usr/bin/env bash
# record-feature-dev-fallback.sh - feature-dev fallback 完了後の InterventionRecord 記録
#
# Usage:
#   record-feature-dev-fallback.sh --issue <N> [--output-dir <dir>] [--trigger <type>] [--result <success|failure>]
#
# 動作:
#   1. .observation/interventions/<ts>-feature-dev-fallback.json に InterventionRecord を書き出す
#   2. doobidoo に feature-dev-fallback タグで lesson 保存コマンドを出力（ユーザー手動実行）
#
# Issue #1620: feature-dev fallback path 正規化 (AC-5)

set -euo pipefail

ISSUE_NUM=""
OUTPUT_DIR="${OBSERVATION_DIR:-.observation}/interventions"
TRIGGER="${TRIGGER:-manual}"
RESULT="${RESULT:-success}"
BRANCH="$(git branch --show-current 2>/dev/null || echo "unknown")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)            ISSUE_NUM="$2"; shift 2 ;;
    --output-dir)       OUTPUT_DIR="$2"; shift 2 ;;
    --intervention-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --trigger)          TRIGGER="$2"; shift 2 ;;
    --result)           RESULT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$ISSUE_NUM" ]]; then
  echo "Error: --issue <N> required" >&2
  exit 2
fi

# 入力バリデーション（baseline-bash.md §11 準拠）
if [[ ! "$ISSUE_NUM" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --issue の値は正整数である必要があります: ${ISSUE_NUM}" >&2
  exit 2
fi

VALID_TRIGGERS=(red-only-merge specialist-needs-work worker-chain-failure p0-urgent manual manual-override)
TRIGGER_VALID=false
for t in "${VALID_TRIGGERS[@]}"; do
  [[ "$TRIGGER" == "$t" ]] && TRIGGER_VALID=true && break
done
if [[ "$TRIGGER_VALID" == "false" ]]; then
  echo "Error: invalid trigger '${TRIGGER}'. Valid: ${VALID_TRIGGERS[*]}" >&2
  exit 2
fi

# OUTPUT_DIR パストラバーサル防止（'..' を拒否）
if [[ "$OUTPUT_DIR" == *".."* ]]; then
  echo "Error: OUTPUT_DIR に '..' を含めることはできません: ${OUTPUT_DIR}" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
RECORD_FILE="${OUTPUT_DIR}/${TIMESTAMP}-feature-dev-fallback.json"

cat > "$RECORD_FILE" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "type": "intervention",
  "pattern_id": "pattern-14-feature-dev-fallback",
  "layer": "escalate",
  "issue": ${ISSUE_NUM},
  "issue_num": ${ISSUE_NUM},
  "branch": "${BRANCH}",
  "trigger": "${TRIGGER}",
  "action_taken": "feature-dev fallback spawn (Layer 2 Escalate, user-approved)",
  "result": "${RESULT}",
  "tags": ["feature-dev-fallback"],
  "notes": "co-autopilot 失敗後に feature-dev plugin による実装。SU-10 準拠。"
}
EOF

echo "✓ InterventionRecord を書き出しました: ${RECORD_FILE}"

# doobidoo lesson 保存コマンドをユーザーに提示（手動実行）
cat <<MSG

次のコマンドで doobidoo に lesson を保存してください（手動実行）:
---
mcp__doobidoo__memory_store \\
  --content "Issue #${ISSUE_NUM}: co-autopilot 失敗後に feature-dev fallback で実装完了。trigger=${TRIGGER}。結果=${RESULT}" \\
  --tags "feature-dev-fallback,wave,intervention" \\
  --source "record-feature-dev-fallback.sh"
---
MSG

exit 0
