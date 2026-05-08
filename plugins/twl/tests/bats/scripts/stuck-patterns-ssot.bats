#!/usr/bin/env bats
# stuck-patterns-ssot.bats
# Issue #1582: stuck pattern SSoT 化 + consumer 統合 + doc 更新
#
# AC1 (SSoT): plugins/twl/refs/stuck-patterns.yaml 新設 + スキーマ検証
# AC2 (consumer 統合): stuck-patterns-lib.sh 新設 + 各 consumer が SSoT 参照
# AC6 (doc): pitfalls-catalog.md §2.1 SSoT 参照化 + SKILL.md default=1 更新 + ADR-037 新設
#
# RED: 実装前は全テストが fail
# GREEN: 実装後に全テスト PASS

load '../helpers/common'

REFS_DIR=""
SCRIPTS_LIB_DIR=""
ORCHESTRATOR_SH=""
OBSERVER_AUTO_INJECT_SH=""
CLD_OBSERVE_ANY=""
STEP0_MONITOR_SH=""
PITFALLS_CATALOG=""
CO_AUTOPILOT_SKILL=""
ADR_037=""

setup() {
  common_setup

  REFS_DIR="${REPO_ROOT}/refs"
  SCRIPTS_LIB_DIR="${REPO_ROOT}/scripts/lib"
  ORCHESTRATOR_SH="${REPO_ROOT}/scripts/autopilot-orchestrator.sh"

  # Resolve monorepo root (5 levels up from BATS_TEST_DIRNAME)
  local _monorepo_root
  _monorepo_root="$(cd "${BATS_TEST_DIRNAME}" && cd ../../../../../ && pwd)"

  OBSERVER_AUTO_INJECT_SH="${_monorepo_root}/plugins/session/scripts/lib/observer-auto-inject.sh"
  CLD_OBSERVE_ANY="${_monorepo_root}/plugins/session/scripts/cld-observe-any"
  STEP0_MONITOR_SH="${_monorepo_root}/plugins/twl/skills/su-observer/scripts/step0-monitor-bootstrap.sh"
  PITFALLS_CATALOG="${_monorepo_root}/plugins/twl/skills/su-observer/refs/pitfalls-catalog.md"
  CO_AUTOPILOT_SKILL="${_monorepo_root}/plugins/twl/skills/co-autopilot/SKILL.md"
  ADR_037="${_monorepo_root}/plugins/twl/architecture/decisions/ADR-037-stuck-pattern-ssot.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1 (SSoT): stuck-patterns.yaml の新設とスキーマ検証
# ===========================================================================

@test "ac1: plugins/twl/refs/stuck-patterns.yaml が存在する" {
  # RED: 実装前は stuck-patterns.yaml が未作成のため fail
  [[ -f "${REFS_DIR}/stuck-patterns.yaml" ]]
}

@test "ac1: stuck-patterns.yaml に patterns キーが存在する" {
  # RED: ファイル未作成のため fail
  run grep -qF "patterns:" "${REFS_DIR}/stuck-patterns.yaml"
  assert_success
}

@test "ac1: stuck-patterns.yaml に queued_message_residual パターンが定義されている" {
  # RED: ファイル未作成のため fail
  run grep -qF "queued_message_residual" "${REFS_DIR}/stuck-patterns.yaml"
  assert_success
}

@test "ac1: stuck-patterns.yaml に menu_enter_select パターンが定義されている" {
  # RED: ファイル未作成のため fail
  run grep -qF "menu_enter_select" "${REFS_DIR}/stuck-patterns.yaml"
  assert_success
}

@test "ac1: stuck-patterns.yaml に freeform_kaishi パターンが定義されている" {
  # RED: ファイル未作成のため fail
  run grep -qF "freeform_kaishi" "${REFS_DIR}/stuck-patterns.yaml"
  assert_success
}

@test "ac1: stuck-patterns.yaml に必須フィールド id/regex/recovery_action/owner_layer/confidence が含まれる" {
  # RED: ファイル未作成のため fail
  local yaml="${REFS_DIR}/stuck-patterns.yaml"
  run grep -qF "regex:" "$yaml"
  assert_success
  run grep -qF "recovery_action:" "$yaml"
  assert_success
  run grep -qF "owner_layer:" "$yaml"
  assert_success
  run grep -qF "confidence:" "$yaml"
  assert_success
}

@test "ac1: plugins/twl/refs/stuck-patterns.md が存在する（Markdown rendering）" {
  # RED: 実装前は stuck-patterns.md が未作成のため fail
  [[ -f "${REFS_DIR}/stuck-patterns.md" ]]
}

# ===========================================================================
# AC2 (consumer 統合): stuck-patterns-lib.sh 新設 + 各 consumer が SSoT 参照
# ===========================================================================

@test "ac2: plugins/twl/scripts/lib/stuck-patterns-lib.sh が存在する" {
  # RED: 実装前は stuck-patterns-lib.sh が未作成のため fail
  [[ -f "${SCRIPTS_LIB_DIR}/stuck-patterns-lib.sh" ]]
}

@test "ac2: stuck-patterns-lib.sh に _load_stuck_patterns 関数が定義されている" {
  # RED: ファイル未作成のため fail
  run grep -qF "_load_stuck_patterns" "${SCRIPTS_LIB_DIR}/stuck-patterns-lib.sh"
  assert_success
}

@test "ac2: consumer1 — autopilot-orchestrator.sh が stuck-patterns-lib.sh を source する" {
  # RED: 実装前は orchestrator が stuck-patterns-lib.sh を source していないため fail
  run grep -qE "source.*stuck-patterns-lib\.sh|\..*stuck-patterns-lib\.sh" "$ORCHESTRATOR_SH"
  assert_success
}

@test "ac2: consumer2 — observer-auto-inject.sh が stuck-patterns-lib.sh を source する" {
  # RED: 実装前は observer-auto-inject.sh が stuck-patterns-lib.sh を source していないため fail
  run grep -qE "source.*stuck-patterns-lib\.sh|\..*stuck-patterns-lib\.sh" "$OBSERVER_AUTO_INJECT_SH"
  assert_success
}

@test "ac2: consumer3 — cld-observe-any が stuck-patterns-lib.sh を source する" {
  # RED: 実装前は cld-observe-any が stuck-patterns-lib.sh を source していないため fail
  run grep -qE "source.*stuck-patterns-lib\.sh|\..*stuck-patterns-lib\.sh" "$CLD_OBSERVE_ANY"
  assert_success
}

@test "ac2: consumer4 — step0-monitor-bootstrap.sh が _load_stuck_patterns を参照する" {
  # RED: 実装前は step0-monitor-bootstrap.sh が _load_stuck_patterns を参照していないため fail
  run grep -qF "_load_stuck_patterns" "$STEP0_MONITOR_SH"
  assert_success
}

# ===========================================================================
# AC6 (doc): ドキュメント更新確認
# ===========================================================================

@test "ac6: pitfalls-catalog.md §2.1 に stuck-patterns.yaml への参照が含まれる" {
  # RED: 実装前は pitfalls-catalog.md が SSoT 参照に短縮されていないため fail
  run grep -qF "stuck-patterns.yaml" "$PITFALLS_CATALOG"
  assert_success
}

@test "ac6: co-autopilot/SKILL.md の AUTOPILOT_AUTO_UNSTUCK 説明が default=1 になっている" {
  # RED: 実装前は default=0 またはデフォルト記述がないため fail
  run grep -qE "AUTOPILOT_AUTO_UNSTUCK.*default.?=.?1|default.*1.*AUTOPILOT_AUTO_UNSTUCK" "$CO_AUTOPILOT_SKILL"
  assert_success
}

@test "ac6: ADR-037-stuck-pattern-ssot.md が新設されている" {
  # RED: 実装前は ADR-037 が存在しないため fail
  [[ -f "${ADR_037}" ]]
}

@test "ac6: ADR-037 に決定理由の記述がある（背景/決定/影響 の各セクション）" {
  # RED: ADR-037 未作成のため fail
  run grep -qE "^## (背景|コンテキスト|Background|Context)" "${ADR_037}"
  assert_success
}
