#!/usr/bin/env bash
# lib/llm-indicators.sh - LLM thinking indicator SSOT
# Source this file to get LLM_INDICATORS array.
# Usage: source "$(dirname "$0")/lib/llm-indicators.sh"
#
# References: plugins/session/scripts/cld-observe-any
#             plugins/twl/skills/su-observer/scripts/lib/observer-idle-check.sh
#             plugins/twl/scripts/issue-lifecycle-orchestrator.sh

# Guard: do nothing if sourced multiple times
[[ -n "${_LLM_INDICATORS_LOADED:-}" ]] && return 0
_LLM_INDICATORS_LOADED=1

LLM_INDICATORS=(
    # --- existing EN indicators ---
    "Thinking"
    "Brewing"
    "Brewed"
    "Concocting"
    "Ebbing"
    "Proofing"
    "Frosting"
    "Reasoning"
    "Computing"
    "Planning"
    "Composing"
    "Processing"
    "Running .* agents"
    "[0-9]+ tool uses"
    "thinking with max effort"
    "Sautéing"
    "Burrowing"
    "Cerebrating"
    "Spinning"
    "Beboppin"
    "Thundering"
    "Baked"
    "Cooked"
    "Crunched"
    "Churned"
    "Skedaddling"
    "Orchestrating"

    # --- compaction phase indicators: Sonnet 4.6 auto-compaction (#1475) ---
    "Compacting"
    "Snapshotting"
    "Externalizing"
    "Restoring"
    "Summarizing"

    "[A-Z][a-z]+(in'|ing)(…| for [0-9]| \\([0-9])"

    # --- AC: EN 9 new indicators (#1454) ---
    "Newspapering"
    "Fiddle-faddling"
    "Levitating"
    "Cogitating"
    "Bloviating"
    "Vibing"
    "Puttering"
    "Zesting"

    # --- AC5: EN 13 new indicators (#1374) ---
    "Philosophising"
    "Drizzling"
    "Fluttering"
    "Spelunking"
    "Determining"
    "Infusing"
    "Prestidigitating"
    "Cogitated"
    "Frolicking"
    "Marinating"
    "Metamorphosing"
    "Shimmying"
    "Transfiguring"

    # --- AC6: JP 6 indicators (#1374) ---
    "生成中"
    "構築中"
    "処理中"
    "作成中"
    "分析中"
    "検証中"
)

export LLM_INDICATORS
