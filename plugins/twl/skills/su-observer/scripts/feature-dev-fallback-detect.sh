#!/usr/bin/env bash
# feature-dev-fallback-detect.sh - co-autopilot 失敗時の feature-dev fallback 提案検知
#
# Usage:
#   feature-dev-fallback-detect.sh --trigger <trigger-type> --issue <N> [--count N] [--log-dir <dir>]
#
# Trigger types:
#   red-only-merge         RED-only merge が 1 回発生（test only PR が merged）
#   specialist-needs-work  specialist NEEDS_WORK が N 回連続（--count 3）
#   worker-chain-failure   Worker chain failure が N 回連続（--count 3）
#   p0-urgent              P0 緊急（ユーザー判断）
#
# 動作:
#   1. trigger を検知し Layer 2 Escalate を intervention-catalog.md パターン 14 に従い記録
#   2. --log-dir に Layer 2 Escalate イベントログを書き出す
#   3. ユーザーへ feature-dev fallback 提案メッセージを stdout に出力
#
# Issue #1620: feature-dev fallback path 正規化 (SU-10)

set -euo pipefail

TRIGGER=""
ISSUE_NUM=""
COUNT="1"
LOG_DIR="${LOG_DIR:-.observation/events}"
OBSERVATION_DIR="${OBSERVATION_DIR:-.observation}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger)         TRIGGER="$2"; shift 2 ;;
    --issue)           ISSUE_NUM="$2"; shift 2 ;;
    --count)           COUNT="$2"; shift 2 ;;
    --log-dir)         LOG_DIR="$2"; shift 2 ;;
    --observation-dir) OBSERVATION_DIR="$2"; LOG_DIR="${OBSERVATION_DIR}/events"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TRIGGER" ]]; then
  echo "Error: --trigger required (red-only-merge|specialist-needs-work|worker-chain-failure|p0-urgent)" >&2
  exit 2
fi

VALID_TRIGGERS=(red-only-merge specialist-needs-work worker-chain-failure p0-urgent)
TRIGGER_FOUND=false
for t in "${VALID_TRIGGERS[@]}"; do
  [[ "$TRIGGER" == "$t" ]] && TRIGGER_FOUND=true && break
done
if [[ "$TRIGGER_FOUND" == "false" ]]; then
  echo "Error: invalid trigger '$TRIGGER'. Valid: ${VALID_TRIGGERS[*]}" >&2
  exit 2
fi

# COUNT は正整数のみ許可（JSON インジェクション防止）
if [[ ! "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "Error: --count は非負整数である必要があります: ${COUNT}" >&2
  exit 2
fi

# LOG_DIR パストラバーサル防止（'..' を拒否）
if [[ "$LOG_DIR" == *".."* ]]; then
  echo "Error: --log-dir に '..' を含めることはできません: ${LOG_DIR}" >&2
  exit 2
fi

TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")

# Layer 2 Escalate 記録（--log-dir に記録）
mkdir -p "$LOG_DIR"
EVENT_FILE="${LOG_DIR}/${TIMESTAMP}-feature-dev-fallback-detect.json"
cat > "$EVENT_FILE" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "event_type": "feature-dev-fallback-detect",
  "trigger": "${TRIGGER}",
  "count": ${COUNT},
  "issue_num": ${ISSUE_NUM:-null},
  "layer": "escalate",
  "layer_label": "Layer 2 Escalate",
  "pattern_id": "pattern-14-feature-dev-fallback",
  "action": "propose-to-user",
  "notes": "Layer 2 Escalate — ユーザー承認なしに feature-dev spawn 禁止 (SU-10)"
}
EOF

# ユーザーへの fallback 提案メッセージ
cat <<MSG
================================================================================
[FEATURE-DEV FALLBACK PROPOSAL] Layer 2 Escalate (パターン 14)
================================================================================
トリガー: ${TRIGGER} (count=${COUNT})
Issue: ${ISSUE_NUM:-不明}

co-autopilot が失敗状態を検知しました。
feature-dev plugin による別実装ルートを提案します。

【実行手順 (Layer 2 Escalate — ユーザー手動実行 MUST)】

1. worktree 作成:
   twl worktree create wt-fd-${ISSUE_NUM:-N} --branch "wt-fd-${ISSUE_NUM:-N}-<short>"

2. cld セッション起動:
   tmux new-window -n "wt-fd-${ISSUE_NUM:-N}"
   cd worktrees/wt-fd-${ISSUE_NUM:-N}-<short>
   cld

3. /feature-dev を実行し feature-dev plugin の guided flow に従って実装

4. 完了後 InterventionRecord を保存:
   record-feature-dev-fallback.sh --issue ${ISSUE_NUM:-N}

※ observer は feature-dev を自律 spawn しません (SU-10)
   SKIP_LAYER2=1 SKIP_LAYER2_REASON='<reason>' で override 可能

イベントログ: ${EVENT_FILE}
================================================================================
MSG

exit 0
