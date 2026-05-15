#!/usr/bin/env bash
# PreToolUse hook (tier 1): phase-gate 粗フィルタ + fast path (50ms 以内)
#
# 仕様: gate-hook.html §4 template (公式 verified hook schema)
#   matcher: "Skill" + if: "Skill(phaser-*)" の SKILL invoke を gate 対象
#   exit 0 + JSON で deny/allow signal (gate-hook.html §1.1 / §3)
#
# Phase 1 PoC C1 (2026-05-15、本 file): tier 1 fast path のみ
#   - tier 2 (twl_phase_gate_check MCP tool) は Phase 1 PoC C3/C5 で wire 予定
#   - 現状 tier 2 未接続 = 全 phaser-* skill を allow (status check なし、設置のみ)
#   - EXP-041 verify 待ち: hooks.json "if: Skill(phaser-*)" ワイルドカード動作の empirical verify (Phase 2 smoke 予定)
#
# bypass: TWL_PHASE_GATE_BYPASS=1 (user 手動指定、debug 用、"=1" 厳格 check)
#   Bug #1660/1662/1663 の SKIP_*_REASON env bypass は禁止 (gate-hook.html §10、Inv W)
#
# script 構造: set -uo pipefail のみ (host-safety/spec-write-boundary と統一、no-op 維持のため set -e 不在)

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")
if ! echo "$payload" | jq empty 2>/dev/null; then
    exit 0
fi

SKILL_NAME=$(echo "$payload" | jq -r '.tool_input.skill // ""')
TOOL_NAME=$(echo "$payload" | jq -r '.tool_name // ""')

# 粗フィルタ: Skill 以外 or phaser-* 以外は素通り
if [[ "$TOOL_NAME" != "Skill" ]]; then
    exit 0
fi
if [[ "$SKILL_NAME" != phaser-* ]]; then
    exit 0
fi

# bypass policy: TWL_PHASE_GATE_BYPASS=1 厳格 check (=0/false/任意非空 string で誤発火回避)
if [[ "${TWL_PHASE_GATE_BYPASS:-}" == "1" ]]; then
    jq -nc --arg s "$SKILL_NAME" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: ("user-bypass via TWL_PHASE_GATE_BYPASS=1 (skill=" + $s + ")")
      }
    }'
    exit 0
fi

# tier 1 fast path: tier 2 未接続のため allow のみ (JSON 出力なし = 素通り、LLM context 汚染回避)
# tier 2 wire 後 (Phase 1 PoC C3/C5): additionalContext で issue 番号等を tier 2 に受け渡し
exit 0
