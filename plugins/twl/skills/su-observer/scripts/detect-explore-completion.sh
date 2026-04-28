#!/usr/bin/env bash
# detect-explore-completion.sh
#
# co-explore 完遂検知スクリプト（Issue #1085 AC5 実装）
#
# Usage:
#   bash detect-explore-completion.sh --wave-dir <dir> --phase <phase>
#   bash detect-explore-completion.sh --wave-dir <dir>  # 全フェーズをスキャン
#
# Output:
#   SPAWN_NEXT_STEP: <phase> が complete の場合 exit 0 + "SPAWN_NEXT_STEP" を出力
#   nothing: complete でない場合 exit 1

set -euo pipefail

WAVE_DIR=""
PHASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wave-dir) WAVE_DIR="$2"; shift 2 ;;
    --phase)    PHASE="$2";    shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$PHASE" && ! "$PHASE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: invalid --phase value: ${PHASE}" >&2
  exit 1
fi

if [[ -z "$WAVE_DIR" ]]; then
  echo "ERROR: --wave-dir is required" >&2
  exit 1
fi

EXPLORE_DIR="${WAVE_DIR}/.explore"

if [[ ! -d "$EXPLORE_DIR" ]]; then
  echo "WARN: .explore dir not found: ${EXPLORE_DIR}" >&2
  exit 1
fi

if [[ -n "$PHASE" ]]; then
  # 特定フェーズの summary.md を確認
  SUMMARY="${EXPLORE_DIR}/${PHASE}/summary.md"
  if [[ -f "$SUMMARY" ]]; then
    echo "SPAWN_NEXT_STEP: co-explore 完遂検知 (phase=${PHASE}, summary=${SUMMARY})"
    exit 0
  fi
  exit 1
else
  # 全フェーズをスキャン
  FOUND=$(find "${EXPLORE_DIR}" -name "summary.md" 2>/dev/null | head -1)
  if [[ -n "$FOUND" ]]; then
    PHASE_DIR=$(dirname "$FOUND")
    PHASE_NAME=$(basename "$PHASE_DIR")
    echo "SPAWN_NEXT_STEP: co-explore 完遂検知 (phase=${PHASE_NAME}, summary=${FOUND})"
    exit 0
  fi
  exit 1
fi
