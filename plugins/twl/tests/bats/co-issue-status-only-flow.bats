#!/usr/bin/env bats
# co-issue-status-only-flow.bats
#
# RED-phase static content tests for Issue #1292: ADR-024 Phase B — refined label 廃止
#
# AC coverage:
#   AC1 - co-issue-phase4-aggregate.md から gh label create refined / gh issue edit --add-label refined
#          行が消えている（grep で 0 件）
#   AC3 - refine-processing-flow.md から labels_hint += ["refined"] が消えている
#   AC4 - lifecycle-processing-flow.md から labels_hint += ["refined"] が消えている
#   AC5 - co-issue SKILL.md の MUST NOT 注意書きが「Status=Refined 遷移 MUST」に縮約されている
#   AC7 - co-issue-phase4-aggregate.md に WARN label_add_failed / OK dual_write が存在しない
#
# RED 状態の根拠:
#   AC1: co-issue-phase4-aggregate.md L66,L69 に gh label create refined / gh issue edit --add-label refined が存在する
#   AC3: refine-processing-flow.md L155 に labels_hint += ["refined"] が存在する
#   AC4: lifecycle-processing-flow.md L141 に policies.labels_hint ← policies.labels_hint + ["refined"] が存在する
#   AC5: SKILL.md L87 に長い注意書き（"refined label + Status=Refined 遷移を skip してはならない"）が存在し
#        縮約された形式（"Status=Refined 遷移 MUST"）になっていない
#   AC7: co-issue-phase4-aggregate.md L73-87 に WARN label_add_failed / OK dual_write が存在する

load 'helpers/common'

PHASE4_AGGREGATE=""
REFINE_FLOW=""
LIFECYCLE_FLOW=""
CO_ISSUE_SKILL=""

setup() {
  common_setup

  # REPO_ROOT は plugins/twl/ を指す（helpers/common.bash の定義に準拠）
  PHASE4_AGGREGATE="${REPO_ROOT}/skills/co-issue/refs/co-issue-phase4-aggregate.md"
  REFINE_FLOW="${REPO_ROOT}/refs/refine-processing-flow.md"
  LIFECYCLE_FLOW="${REPO_ROOT}/refs/lifecycle-processing-flow.md"
  CO_ISSUE_SKILL="${REPO_ROOT}/skills/co-issue/SKILL.md"

  export PHASE4_AGGREGATE REFINE_FLOW LIFECYCLE_FLOW CO_ISSUE_SKILL
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: co-issue-phase4-aggregate.md に gh label create refined / gh issue edit --add-label refined が存在しない
# ===========================================================================

@test "ac1: co-issue-phase4-aggregate.md が存在すること" {
  # 前提確認: ファイルが存在する
  [ -f "${PHASE4_AGGREGATE}" ]
}

@test "ac1: co-issue-phase4-aggregate.md に gh label create refined が存在しないこと（RED: 現状 L66 に存在する）" {
  # AC: `grep -nE 'gh (label create|issue edit.*refined)' ...co-issue-phase4-aggregate.md` で 0 件
  # RED: 現在 L66 に `gh label create refined` が存在するため fail
  run grep -nE 'gh label create.*refined' "${PHASE4_AGGREGATE}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に以下の行が存在する（Phase B では削除必須）:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac1: co-issue-phase4-aggregate.md に gh issue edit.*--add-label refined が存在しないこと（RED: 現状 L69 に存在する）" {
  # AC: AC1 の一部 — gh issue edit --add-label refined 行が削除される
  # RED: 現在 L69 に当該行が存在するため fail
  run grep -nE 'gh issue edit.*--add-label refined|gh issue edit.*refined' "${PHASE4_AGGREGATE}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に以下の label 付与行が存在する:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac1: grep -nE 'gh (label create|issue edit.*refined)' が 0 件（RED: 現状は 2 件以上）" {
  # AC: Issue body 記載の grep コマンドで 0 件
  # RED: 現在は L66 + L69 で 2 件以上ヒットするため fail
  local match_count
  match_count=$(grep -cE 'gh (label create|issue edit.*refined)' "${PHASE4_AGGREGATE}" 2>/dev/null || echo "0")
  if [ "${match_count}" -gt 0 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に ${match_count} 件の label 操作行が存在する" >&2
    grep -nE 'gh (label create|issue edit.*refined)' "${PHASE4_AGGREGATE}" >&2 || true
    return 1
  fi
}

# ===========================================================================
# AC3: refine-processing-flow.md から labels_hint += ["refined"] が消えている
# ===========================================================================

@test "ac3: refine-processing-flow.md が存在すること" {
  [ -f "${REFINE_FLOW}" ]
}

@test "ac3: refine-processing-flow.md に labels_hint += [\"refined\"] が存在しないこと（RED: 現状 L155 に存在する）" {
  # AC: jq '.labels_hint += ["refined"]' の行が削除される
  # RED: 現在 L155 に存在するため fail
  run grep -n 'labels_hint += \["refined"\]' "${REFINE_FLOW}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: refine-processing-flow.md に以下の行が存在する（Phase B では削除必須）:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac3: refine-processing-flow.md に labels_hint.*refined の追加コードが存在しないこと（RED）" {
  # AC: Step 4.5 の refined ラベル追加ロジックが削除される
  # RED: 現在 L155-157 の jq コードブロックが存在するため fail
  local count
  count=$(grep -cE 'labels_hint.*\+.*\[.*"refined".*\]|labels_hint.*refined' "${REFINE_FLOW}" 2>/dev/null || echo "0")
  if [ "${count}" -gt 0 ]; then
    echo "FAIL: refine-processing-flow.md に labels_hint + refined 追加コードが ${count} 件存在する" >&2
    grep -nE 'labels_hint.*\+.*\[.*"refined".*\]|labels_hint.*refined' "${REFINE_FLOW}" >&2 || true
    return 1
  fi
}

# ===========================================================================
# AC4: lifecycle-processing-flow.md から labels_hint += ["refined"] が消えている
# ===========================================================================

@test "ac4: lifecycle-processing-flow.md が存在すること" {
  [ -f "${LIFECYCLE_FLOW}" ]
}

@test "ac4: lifecycle-processing-flow.md に policies.labels_hint + refined 追加コードが存在しないこと（RED: 現状 L141 に存在する）" {
  # AC: Step 4.5 の labels_hint ← labels_hint + ["refined"] が削除される
  # RED: 現在 L141 に `policies.labels_hint ← policies.labels_hint + ["refined"]` が存在するため fail
  run grep -n 'labels_hint.*\+.*\["refined"\]\|labels_hint.*+.*refined' "${LIFECYCLE_FLOW}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: lifecycle-processing-flow.md に以下の labels_hint 追加行が存在する（Phase B では削除必須）:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac4: lifecycle-processing-flow.md の Step 4.5 に refined ラベル判定コードが存在しないこと（RED）" {
  # AC: Step 4.5 refined ラベル判定セクション自体が削除される
  # RED: 現在 L135-145 のブロックが存在するため fail
  local count
  count=$(grep -cE 'labels_hint.*refined|refined.*labels_hint' "${LIFECYCLE_FLOW}" 2>/dev/null || echo "0")
  # L156, L184, L188 は labels_hint に refined が含まれる場合の参照として残る可能性があるが
  # L141 の追加コードは削除必須。2 件を超える場合は削除が不完全
  # Phase B 移行後は labels_hint に refined が含まれないため、参照記述自体も 0 件を期待
  if [ "${count}" -gt 0 ]; then
    echo "FAIL: lifecycle-processing-flow.md に labels_hint refined 参照が ${count} 件存在する" >&2
    grep -nE 'labels_hint.*refined|refined.*labels_hint' "${LIFECYCLE_FLOW}" >&2 || true
    return 1
  fi
}

# ===========================================================================
# AC5: co-issue SKILL.md の MUST NOT 注意書きが縮約されていること
# ===========================================================================

@test "ac5: co-issue SKILL.md が存在すること" {
  [ -f "${CO_ISSUE_SKILL}" ]
}

@test "ac5: SKILL.md に縮約済み形式 'Status=Refined 遷移 MUST' が存在すること（RED: 現状は長い注意書き形式）" {
  # AC: 長い注意書き（"refined label + Status=Refined 遷移を skip してはならない（ADR-024 dual-write 義務..."）
  #     が「Status=Refined 遷移 MUST」のみに縮約される
  # RED: 現在は縮約前の長い形式のため、縮約後のキーフレーズが存在せず fail
  #      縮約後は独立した注意書きとして「Status=Refined 遷移 MUST」が存在することを検証
  run grep -c 'Status=Refined 遷移 MUST' "${CO_ISSUE_SKILL}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: SKILL.md に縮約済みフレーズ 'Status=Refined 遷移 MUST' が存在しない" >&2
    echo "  現状のL87: $(grep -n 'Phase 4 manual fix' "${CO_ISSUE_SKILL}" || echo '(見つからない)')" >&2
    return 1
  fi
}

@test "ac5: SKILL.md に旧 dual-write 義務の長い注意書きが存在しないこと（RED: 現状 L87 に存在する）" {
  # AC: 旧形式 "dual-write 義務: label 先 → Status 後" の注意書きが削除される
  # RED: 現在 L87 に旧形式が存在するため fail
  run grep -n 'dual-write 義務.*label 先.*Status 後\|label 先 → Status 後' "${CO_ISSUE_SKILL}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: SKILL.md に旧 dual-write 義務の注意書きが残存している（Phase B では縮約必須）:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac5: SKILL.md に 'ADR-024 Phase B 移行後は' 注記が存在しないこと（RED: 現状は存在する）" {
  # AC: 「Note: ADR-024 Phase B 移行後は...縮約される予定」の注記が削除される（移行完了のため）
  # RED: 現在 L87 に "Note: ADR-024 Phase B 移行後は" が存在するため fail
  run grep -n 'ADR-024 Phase B 移行後は.*縮約される予定\|Phase B 移行後は.*縮約' "${CO_ISSUE_SKILL}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: SKILL.md に 'Phase B 移行後は縮約' 予定注記が残存している（移行完了後は削除必須）:" >&2
    echo "${output}" >&2
    return 1
  fi
}

# ===========================================================================
# AC7: co-issue-phase4-aggregate.md に WARN label_add_failed / OK dual_write が存在しない
# ===========================================================================

@test "ac7: co-issue-phase4-aggregate.md に WARN label_add_failed が存在しないこと（RED: 現状 L73,L80 に存在する）" {
  # AC: Phase B 移行後、label_add_failed log event が削除される
  # RED: 現在 L73,L80 に当該文字列が存在するため fail
  run grep -n 'label_add_failed' "${PHASE4_AGGREGATE}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に以下の label_add_failed 行が存在する（Phase B では削除必須）:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac7: co-issue-phase4-aggregate.md に OK dual_write が存在しないこと（RED: 現状 L85-87 に存在する）" {
  # AC: Phase B 移行後、OK dual_write log event が削除される
  # RED: 現在 L85-87 に当該文字列が存在するため fail
  run grep -n 'OK dual_write\|dual_write_log OK' "${PHASE4_AGGREGATE}"
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に以下の dual_write 行が存在する（Phase B では削除必須）:" >&2
    echo "${output}" >&2
    return 1
  fi
}

@test "ac7: co-issue-phase4-aggregate.md に dual-write observability コードブロックが存在しないこと（RED）" {
  # AC: dual-write observability セクション（_label_exit 記録+分岐）が削除される
  # RED: 現在 L70-90 のコードブロックが存在するため fail
  local count
  count=$(grep -cE '_label_exit|dual_write_log|refined-dual-write-log' "${PHASE4_AGGREGATE}" 2>/dev/null || echo "0")
  if [ "${count}" -gt 0 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に dual-write observability コードが ${count} 件存在する" >&2
    grep -nE '_label_exit|dual_write_log|refined-dual-write-log' "${PHASE4_AGGREGATE}" >&2 || true
    return 1
  fi
}

@test "ac7: co-issue-phase4-aggregate.md に WARN status_update_failed のみが残ること（実装後の最終形確認）" {
  # AC: 整理後は WARN status_update_failed が残る（board-status-update 失敗時の警告）
  # NOTE: このテストは実装後に GREEN になる。現状は WARN status_update_failed が存在しないため fail。
  # RED: 現在のファイルに status_update_failed が存在しないため fail
  run grep -c 'status_update_failed\|WARN.*status_update_failed' "${PHASE4_AGGREGATE}"
  local count="${output:-0}"
  if [ "${count}" -lt 1 ]; then
    echo "FAIL: co-issue-phase4-aggregate.md に WARN status_update_failed が存在しない（Phase B では残存必須）" >&2
    return 1
  fi
}
