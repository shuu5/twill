#!/usr/bin/env bash
# checkpoint-read.sh
# checkpoint ファイルを読み取り、要約または findings を返す。
#
# Usage:
#   bash checkpoint-read.sh --step <step_name> --field <field>
#   bash checkpoint-read.sh --step <step_name> --critical-findings
#
# Options:
#   --step <name>         読み取る checkpoint のステップ名
#   --field <name>        特定フィールドを返す（status, findings_summary, critical_count）
#   --critical-findings   severity=CRITICAL の findings のみを JSON 配列で返す
#
# Exit codes:
#   0  成功
#   1  checkpoint ファイルが存在しない
#   2  引数エラー

set -euo pipefail

# ── 引数パース ──
STEP=""
FIELD=""
CRITICAL_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)
      STEP="$2"
      shift 2
      ;;
    --field)
      FIELD="$2"
      shift 2
      ;;
    --critical-findings)
      CRITICAL_ONLY=true
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# ── バリデーション ──
if [[ -z "$STEP" ]]; then
  echo "ERROR: --step is required" >&2
  exit 2
fi

if [[ ! "$STEP" =~ ^[a-z0-9-]+$ ]]; then
  echo "ERROR: --step contains invalid characters: $STEP" >&2
  exit 2
fi

if [[ "$CRITICAL_ONLY" == "false" && -z "$FIELD" ]]; then
  echo "ERROR: --field or --critical-findings is required" >&2
  exit 2
fi

# ── checkpoint ファイル読み取り ──
CHECKPOINT_FILE=".autopilot/checkpoints/${STEP}.json"

if [[ ! -f "$CHECKPOINT_FILE" ]]; then
  echo "ERROR: checkpoint not found: $CHECKPOINT_FILE" >&2
  exit 1
fi

# ── 出力 ──
if [[ "$CRITICAL_ONLY" == "true" ]]; then
  jq '[.findings[] | select(.severity == "CRITICAL")]' "$CHECKPOINT_FILE"
elif [[ -n "$FIELD" ]]; then
  jq -r ".${FIELD}" "$CHECKPOINT_FILE"
fi
