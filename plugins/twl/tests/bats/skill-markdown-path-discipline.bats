#!/usr/bin/env bats
# skill-markdown-path-discipline.bats
#
# RED-phase tests for Issue #1244:
#   skill markdown の script 参照パス統一（${CLAUDE_PLUGIN_ROOT} 形式）
#
# AC coverage:
#   AC1 - A. 完全 unmigrated skill の ${CLAUDE_PLUGIN_ROOT}/... 形式統一
#         (co-architect/SKILL.md, su-observer/SKILL.md, workflow-self-improve/SKILL.md,
#          su-observer/refs/su-observer-wave-management.md,
#          su-observer/refs/su-observer-controller-spawn-playbook.md)
#   AC2 - B. 取り残し完遂（co-issue/refs/co-issue-phase3-dispatch.md,
#              co-issue/refs/co-issue-phase4-aggregate.md）
#   AC3 - C. cross-plugin 統一（su-observer/refs/monitor-channel-catalog.md を
#              "$(git rev-parse --show-toplevel)/plugins/<other>/scripts/..." 形式 + # cross-plugin reference コメント）
#   AC4 - bats lint test 自身が plugins/twl/tests/bats/skill-markdown-path-discipline.bats として存在
#   AC5 - CHANGELOG / Wave 記録に「skill markdown の path 記載統一（#1244）」と修正前後 grep count が含まれる
#   AC6 - pitfalls-catalog.md に「skill markdown の relative path 落とし穴」セクションと
#          mitigation note が追記されている
#
# 全テストは実装前（RED）状態で fail する（AC4 のみ本ファイル作成後即 PASS）。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  CO_ARCH_SKILL="${REPO_ROOT}/skills/co-architect/SKILL.md"
  SU_OBS_SKILL="${REPO_ROOT}/skills/su-observer/SKILL.md"
  WF_SELF_SKILL="${REPO_ROOT}/skills/workflow-self-improve/SKILL.md"
  CO_ISSUE_PHASE3="${REPO_ROOT}/skills/co-issue/refs/co-issue-phase3-dispatch.md"
  CO_ISSUE_PHASE4="${REPO_ROOT}/skills/co-issue/refs/co-issue-phase4-aggregate.md"
  SU_OBS_WAVE="${REPO_ROOT}/skills/su-observer/refs/su-observer-wave-management.md"
  SU_OBS_SPAWN="${REPO_ROOT}/skills/su-observer/refs/su-observer-controller-spawn-playbook.md"
  MONITOR_CATALOG="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"
  PITFALLS="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  THIS_BATS="${REPO_ROOT}/tests/bats/skill-markdown-path-discipline.bats"
  AUTOPILOT_WAVES="${REPO_ROOT}/../../.autopilot/waves"

  export CO_ARCH_SKILL SU_OBS_SKILL WF_SELF_SKILL CO_ISSUE_PHASE3 CO_ISSUE_PHASE4
  export SU_OBS_WAVE SU_OBS_SPAWN MONITOR_CATALOG PITFALLS THIS_BATS AUTOPILOT_WAVES
}

# ===========================================================================
# AC1: A. 完全 unmigrated skill の ${CLAUDE_PLUGIN_ROOT}/... 形式統一
# ===========================================================================

@test "ac1: co-architect/SKILL.md uses CLAUDE_PLUGIN_ROOT for worktree-delete.sh" {
  # AC: bash plugins/twl/scripts/worktree-delete.sh → \${CLAUDE_PLUGIN_ROOT}/scripts/worktree-delete.sh
  # RED: 旧形式がまだ残っている
  run grep -qF 'plugins/twl/scripts/worktree-delete.sh' "${CO_ARCH_SKILL}"
  # 旧形式が存在すれば fail（status=0 → grep match → 旧形式残存）
  [ "${status}" -ne 0 ]
}

@test "ac1: co-architect/SKILL.md CLAUDE_PLUGIN_ROOT form present for worktree-delete.sh" {
  # AC: 新形式が存在する
  run grep -qE '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/worktree-delete\.sh' "${CO_ARCH_SKILL}"
  [ "${status}" -eq 0 ]
}

@test "ac1: su-observer/SKILL.md no bare skill-relative scripts/ references" {
  # AC: `scripts/session-init.sh`, `scripts/step0-memory-ambient.sh` 等の bare 参照が消えている
  # RED: まだ残っている（grep で検出される）
  run bash -c "grep -cE '\`scripts/[a-zA-Z0-9_.-]+\.sh\`' '${SU_OBS_SKILL}'"
  [ "${output}" -eq 0 ]
}

@test "ac1: su-observer/SKILL.md no repo-relative long-form scripts/ references" {
  # AC: bash plugins/twl/skills/su-observer/scripts/... 形式が消えている
  # RED: L40 の古い形式がまだ残っている
  run grep -qF 'bash plugins/twl/skills/su-observer/scripts/' "${SU_OBS_SKILL}"
  [ "${status}" -ne 0 ]
}

@test "ac1: su-observer/SKILL.md no skills/ prefix form references" {
  # AC: bash skills/su-observer/scripts/... 形式（skills/ prefix）が消えている
  # RED: L63 の古い形式がまだ残っている
  run grep -qE 'bash skills/su-observer/scripts/' "${SU_OBS_SKILL}"
  [ "${status}" -ne 0 ]
}

@test "ac1: workflow-self-improve/SKILL.md CLAUDE_PLUGIN_ROOT form for resolve-issue-num.sh" {
  # AC: broken $(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh
  #     → ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh
  # RED: 新形式がまだ存在しない
  run grep -qE '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/resolve-issue-num\.sh' "${WF_SELF_SKILL}"
  [ "${status}" -eq 0 ]
}

@test "ac1: workflow-self-improve/SKILL.md no broken repo-root scripts/ reference" {
  # AC: $(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh (broken path) が消えている
  # RED: まだ残っている
  run grep -qF '$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh' "${WF_SELF_SKILL}"
  [ "${status}" -ne 0 ]
}

@test "ac1: su-observer-wave-management.md no bare skill-relative scripts/ references" {
  # AC: `scripts/externalize-state-exit-gate.sh` 等の bare 参照が消えている
  # RED: L43 の古い形式がまだ残っている
  run bash -c "grep -cE '\`scripts/[a-zA-Z0-9_.-]+\.sh\`' '${SU_OBS_WAVE}'"
  [ "${output}" -eq 0 ]
}

@test "ac1: su-observer-controller-spawn-playbook.md no bare scripts/ references" {
  # AC: scripts/spawn-controller.sh (bare) が ${CLAUDE_PLUGIN_ROOT}/skills/su-observer/scripts/spawn-controller.sh に置換済み
  # RED: L5, L9 の古い形式がまだ残っている
  run bash -c "grep -cE '^scripts/spawn-controller\.sh|^\`scripts/spawn-controller\.sh\`' '${SU_OBS_SPAWN}'"
  [ "${output}" -eq 0 ]
}

# ===========================================================================
# AC2: B. 取り残し完遂（co-issue refs）
# ===========================================================================

@test "ac2: co-issue-phase3-dispatch.md no bare scripts/ reference for issue-lifecycle-orchestrator.sh" {
  # AC: bash scripts/issue-lifecycle-orchestrator.sh → bash "\${CLAUDE_PLUGIN_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
  # RED: 旧形式が L27 に残っている
  run grep -qE 'bash scripts/issue-lifecycle-orchestrator\.sh' "${CO_ISSUE_PHASE3}"
  [ "${status}" -ne 0 ]
}

@test "ac2: co-issue-phase4-aggregate.md no bare scripts/ reference for issue-lifecycle-orchestrator.sh" {
  # AC: bash scripts/issue-lifecycle-orchestrator.sh → bash "\${CLAUDE_PLUGIN_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
  # RED: 旧形式が L60 に残っている
  run grep -qE 'bash scripts/issue-lifecycle-orchestrator\.sh' "${CO_ISSUE_PHASE4}"
  [ "${status}" -ne 0 ]
}

@test "ac2: co-issue-phase3-dispatch.md CLAUDE_PLUGIN_ROOT form for issue-lifecycle-orchestrator.sh" {
  # AC: 新形式が存在する
  # RED: 新形式がまだ存在しない
  run grep -qE '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/issue-lifecycle-orchestrator\.sh' "${CO_ISSUE_PHASE3}"
  [ "${status}" -eq 0 ]
}

@test "ac2: co-issue-phase4-aggregate.md CLAUDE_PLUGIN_ROOT form for issue-lifecycle-orchestrator.sh" {
  # AC: 新形式が存在する
  # RED: 新形式がまだ存在しない
  run grep -qE '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/issue-lifecycle-orchestrator\.sh' "${CO_ISSUE_PHASE4}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: C. cross-plugin 統一（monitor-channel-catalog.md）
# ===========================================================================

@test "ac3: monitor-channel-catalog.md no bare plugins/session/scripts/ references" {
  # AC: plugins/session/scripts/... → "$(git rev-parse --show-toplevel)/plugins/session/scripts/..."
  # RED: 旧形式（bare plugins/session/scripts/）がまだ残っている
  run bash -c "grep -cE '(^|[^/])plugins/session/scripts/' '${MONITOR_CATALOG}'"
  [ "${output}" -eq 0 ]
}

@test "ac3: monitor-channel-catalog.md has git-rev-parse form for cross-plugin session scripts" {
  # AC: 新形式が存在する
  # RED: 新形式がまだ存在しない
  run grep -qF '$(git rev-parse --show-toplevel)/plugins/session/scripts/' "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac3: monitor-channel-catalog.md cross-plugin references have inline comment" {
  # AC: 修正行に # cross-plugin reference コメントが付いている
  # RED: コメントがまだ存在しない
  run grep -qF '# cross-plugin reference' "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: bats テスト自身が skill-markdown-path-discipline.bats として存在
# ===========================================================================

@test "ac4: this bats test file exists at expected path" {
  # AC: bats テストが plugins/twl/tests/bats/skill-markdown-path-discipline.bats として存在する
  # ファイル作成後は即 PASS（本ファイルを作成することが実装である）
  [ -f "${THIS_BATS}" ]
}

# ===========================================================================
# AC5: CHANGELOG / Wave 記録に「skill markdown の path 記載統一（#1244）」と
#      修正前後 grep count が含まれる
# ===========================================================================

@test "ac5: wave summary mentions skill markdown path 統一 for #1244" {
  # AC: いずれかの wave summary が #1244 の path 統一作業を記録している
  # RED: まだ記録されていない
  run bash -c "grep -rl '#1244' '${AUTOPILOT_WAVES}' 2>/dev/null | xargs grep -l 'path\|CLAUDE_PLUGIN_ROOT\|skill.*markdown\|markdown.*path' 2>/dev/null | head -1"
  [ -n "${output}" ]
}

@test "ac5: wave summary includes grep count (before/after) for path migration" {
  # AC: 修正前後の grep count（例: before: 12件, after: 0件）が記録されている
  # RED: まだ記録されていない
  run bash -c "grep -rl '#1244' '${AUTOPILOT_WAVES}' 2>/dev/null | xargs grep -lE 'before.*[0-9]+|after.*[0-9]+|grep.*count|[0-9]+.*件' 2>/dev/null | head -1"
  [ -n "${output}" ]
}

# ===========================================================================
# AC6: pitfalls-catalog.md に「skill markdown の relative path 落とし穴」セクション
#      と mitigation note が追記されている
# ===========================================================================

@test "ac6: pitfalls-catalog.md has 'skill markdown' relative path pitfall section" {
  # AC: 新セクションが追記されている
  # RED: まだ追記されていない
  run grep -qiE 'skill markdown.*relative path|relative path.*skill markdown|skill.*markdown.*path.*落とし穴|skill.*markdown.*pitfall' "${PITFALLS}"
  [ "${status}" -eq 0 ]
}

@test "ac6: pitfalls-catalog.md mitigation note mentions CLAUDE_PLUGIN_ROOT migration" {
  # AC: mitigation note に 'bash scripts/...' 形式を見たら CLAUDE_PLUGIN_ROOT migration 漏れの可能性 という旨が記録されている
  # RED: まだ記録されていない
  run grep -qiE 'bash scripts/.*CLAUDE_PLUGIN_ROOT|CLAUDE_PLUGIN_ROOT.*migration|migration.*漏れ|migration.*leak' "${PITFALLS}"
  [ "${status}" -eq 0 ]
}
