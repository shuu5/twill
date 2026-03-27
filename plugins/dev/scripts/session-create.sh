#!/usr/bin/env bash
# session-create.sh - session.json の新規作成
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOPILOT_DIR="$PROJECT_ROOT/.autopilot"
SESSION_FILE="$AUTOPILOT_DIR/session.json"

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") --plan-path <path> --phase-count N

session.json を新規作成する。autopilot-init.sh で排他制御済みであること。

Options:
  --plan-path <path>    plan.yaml のパス（必須）
  --phase-count N       全 Phase 数（必須）
  -h, --help            このヘルプを表示
EOF
}

plan_path=""
phase_count=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-path) plan_path="$2"; shift 2 ;;
    --phase-count) phase_count="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$plan_path" ]]; then
  echo "ERROR: --plan-path は必須です" >&2
  exit 1
fi

if [[ -z "$phase_count" ]]; then
  echo "ERROR: --phase-count は必須です" >&2
  exit 1
fi

# phase_count の数値バリデーション
if [[ ! "$phase_count" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --phase-count は正の整数を指定してください: $phase_count" >&2
  exit 1
fi

if [[ -f "$SESSION_FILE" ]]; then
  echo "ERROR: session.json は既に存在します。autopilot-init.sh で排他制御を確認してください" >&2
  exit 1
fi

# session_id 生成（8文字のランダム hex、xxd 非依存）
session_id=$(od -A n -t x1 -N 4 /dev/urandom | tr -d ' \n')
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$AUTOPILOT_DIR"

jq -n \
  --arg session_id "$session_id" \
  --arg plan_path "$plan_path" \
  --argjson phase_count "$phase_count" \
  --arg started_at "$now" \
  '{
    session_id: $session_id,
    plan_path: $plan_path,
    current_phase: 1,
    phase_count: $phase_count,
    started_at: $started_at,
    cross_issue_warnings: [],
    phase_insights: [],
    patterns: {},
    self_improve_issues: []
  }' > "$SESSION_FILE"

echo "OK: session.json を作成しました (session_id=$session_id)"
