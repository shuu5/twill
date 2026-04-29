#!/usr/bin/env bash
# observer-idle-check.sh — IDLE-COMPLETED 検知ライブラリ (Issue #1117)
#
# Usage (source):
#   source observer-idle-check.sh
#   _check_idle_completed "$pane_content" "$first_seen_ts" "$now_ts" [debounce_sec=60]
#
# Returns:
#   exit 0  → IDLE-COMPLETED 条件全満足 (cleanup-trigger)
#   exit 1  → 条件未満 (継続観察)

# COMPLETION_PHRASE_REGEX — SSOT (AC-1)
# 行単位 grep -qE で機能する。A2+A3+A4 の他条件 AND により false positive を抑制。
readonly IDLE_COMPLETED_PHRASE_REGEX='(refined ラベル付与|Status=Refined|nothing pending|recap: Goal|>>> 実装完了|Phase 4 完了|merge-gate.*成功|spec-review marker cleanup|explore-summary saved|\.explore/[0-9]+/summary\.md|次のステップ:)'

# IDLE_COMPLETED_DEBOUNCE_SEC — デフォルト 60s、env var で override 可能 (AC-2)
IDLE_COMPLETED_DEBOUNCE_SEC="${IDLE_COMPLETED_DEBOUNCE_SEC:-60}"

# _check_idle_completed pane_content first_seen_ts now_ts [debounce_sec]
#
# Stateless 純粋関数 (AC-8)。グローバル state (IDLE_COMPLETED_TS 等) に依存しない。
# cld-observe-any のメインループスコープで IDLE_COMPLETED_TS 連想配列を管理し、
# この関数に first_seen_ts / now_ts として渡すこと。
#
# 判定条件 (5条件 AND):
#   C1: pane_content が空でない
#   C2: completion phrase regex にマッチする行が存在する (行単位 grep -qE)
#   C3: A2 LLM indicator が不在 (thinking 中は cleanup 不可)
#   C4: first_seen_ts が設定済み (> 0)
#   C5: now_ts - first_seen_ts >= debounce_sec (60s 安定)
_check_idle_completed() {
    local pane_content="${1:-}"
    local first_seen_ts="${2:-0}"
    local now_ts="${3:-0}"
    local debounce_sec="${4:-${IDLE_COMPLETED_DEBOUNCE_SEC}}"

    # C1: pane_content 非空
    [[ -n "$pane_content" ]] || return 1

    # C2: completion phrase regex マッチ (行単位)
    echo "$pane_content" | grep -qE "$IDLE_COMPLETED_PHRASE_REGEX" || return 1

    # C3: LLM indicator 不在 (Thinking/Brewing 等の現在進行形)
    # pitfalls-catalog.md §4.10 A2 定義準拠: 現在進行形のみ THINKING 扱い
    local llm_indicators='Thinking|Brewing|Concocting|Ebbing|Proofing|Frosting|Reasoning|Computing|Planning|Composing|Processing|Burrowing|Cerebrating|Spinning|Orchestrating'
    if echo "$pane_content" | tail -15 | grep -qE "($llm_indicators)"; then
        return 1
    fi

    # C4+C5: debounce 経過（first_seen_ts は Unix timestamp として扱う; elapsed >= debounce_sec）
    local elapsed=$(( now_ts - first_seen_ts ))
    [[ "$elapsed" -ge "$debounce_sec" ]] || return 1

    return 0
}
