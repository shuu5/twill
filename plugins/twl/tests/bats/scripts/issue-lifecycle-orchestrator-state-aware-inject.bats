#!/usr/bin/env bats
# issue-lifecycle-orchestrator-state-aware-inject.bats
# Issue #1246: feat(orchestrator): co-issue Worker の stop 検知と STATE-aware auto-inject
#
# TDD RED フェーズ — 全テストは実装前に fail し、実装後に PASS する。
#
# AC coverage:
#   AC1 - STATE=reviewing + findings.yaml 存在 → session-comm.sh inject /twl:issue-review-aggregate
#   AC2 - STATE=fixing → session-comm.sh inject 次 round prompt (resume-from-fixing 相当)
#   AC3 - inject_count==5 → inject_exhausted_state_aware（または同等 reason）fallback
#   AC4 - STATE-aware inject elif は AskUserQuestion パターン後 + unclassified debounce 確認後に配置
#
# 実装ファイル: plugins/twl/scripts/issue-lifecycle-orchestrator.sh
# （wait_for_batch 内 if/elif チェーンに新 elif を追加）

load '../helpers/common'

SCRIPT_SRC=""

setup() {
  common_setup
  SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: STATE=reviewing → issue-review-aggregate inject ロジック
# ===========================================================================

@test "ac1: script contains STATE=reviewing check in wait loop" {
  # AC1: wait loop 内に STATE=reviewing の条件分岐が存在する
  # RED: 実装前はパターンが存在しないため fail する
  run grep -nE '"reviewing"|\breviewing\b' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC1: STATE=reviewing チェックがスクリプトに存在しない"
}

@test "ac1: reviewing inject includes issue-review-aggregate command" {
  # AC1: reviewing 時の inject テキストに issue-review-aggregate が含まれる
  # RED: 実装前は存在しないため fail する
  run grep -qE 'issue-review-aggregate' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC1: inject テキストに issue-review-aggregate が含まれていない"
}

@test "ac1: reviewing inject is conditioned on findings.yaml existence" {
  # AC1: findings.yaml 存在チェックと reviewing inject が同一ブロックに存在する
  # RED: 実装前はパターンが存在しないため fail する
  local reviewing_line findings_line
  reviewing_line=$(grep -n '"reviewing"' "$SCRIPT_SRC" | grep -v "^#" | tail -1 | cut -d: -f1)
  findings_line=$(grep -n 'findings\.yaml.*reviewing\|reviewing.*findings\.yaml\|_findings_path.*findings\.yaml' "$SCRIPT_SRC" | head -1 | cut -d: -f1)

  [[ -n "$reviewing_line" ]] \
    || fail "AC1: reviewing 条件チェックがスクリプトに存在しない"
  [[ -n "$findings_line" ]] \
    || fail "AC1: findings.yaml 存在チェック (_findings_path) がスクリプトに存在しない"
}

@test "ac1: session-comm.sh inject is called in reviewing state path" {
  # AC1: reviewing パスで session-comm.sh inject が呼ばれる
  # RED: 実装前は存在しないため fail する
  local reviewing_line comm_after_reviewing

  reviewing_line=$(grep -n '"reviewing"' "$SCRIPT_SRC" | grep -v "^#" | tail -1 | cut -d: -f1)
  [[ -n "$reviewing_line" ]] \
    || fail "AC1: reviewing 条件がスクリプトに存在しない"

  # reviewing ブロック直後（50行以内）に session-comm.sh inject があること
  comm_after_reviewing=$(awk "NR>=$reviewing_line && NR<=$((reviewing_line + 50)) && /session-comm\.sh.*inject/" "$SCRIPT_SRC" | head -1)
  [[ -n "$comm_after_reviewing" ]] \
    || fail "AC1: reviewing ブロック内に session-comm.sh inject 呼び出しが存在しない"
}

# ===========================================================================
# AC2: STATE=fixing → 次 round prompt inject ロジック
# ===========================================================================

@test "ac2: script contains STATE=fixing check in wait loop" {
  # AC2: wait loop 内に STATE=fixing の条件分岐が存在する
  # RED: 実装前はパターンが存在しないため fail する
  run grep -nE '"fixing"|\bfixing\b' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC2: STATE=fixing チェックがスクリプトに存在しない"
}

@test "ac2: fixing inject includes resume-from-fixing in inject command string" {
  # AC2: fixing inject の session-comm.sh inject 呼び出しに resume-from-fixing が含まれる
  # RED: 実装前は session-comm.sh inject と resume-from-fixing が同行/隣接して存在しないため fail する
  run grep -qE 'resume-from-fixing' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC2: inject コマンド文字列に resume-from-fixing が含まれていない"
}

@test "ac2: session-comm.sh inject is called in fixing state path" {
  # AC2: fixing パスで session-comm.sh inject が呼ばれる
  # RED: 実装前は存在しないため fail する
  local fixing_line comm_after_fixing

  fixing_line=$(grep -n '"fixing"' "$SCRIPT_SRC" | grep -v "^#" | tail -1 | cut -d: -f1)
  [[ -n "$fixing_line" ]] \
    || fail "AC2: fixing 条件がスクリプトに存在しない"

  comm_after_fixing=$(awk "NR>=$fixing_line && NR<=$((fixing_line + 30)) && /session-comm\.sh.*inject/" "$SCRIPT_SRC" | head -1)
  [[ -n "$comm_after_fixing" ]] \
    || fail "AC2: fixing ブロック内に session-comm.sh inject 呼び出しが存在しない"
}

# ===========================================================================
# AC3: inject_count=5 → inject_exhausted_state_aware fallback
# ===========================================================================

@test "ac3: script contains inject_exhausted_state_aware or state-aware exhausted pattern" {
  # AC3: inject 5 回上限到達時に inject_exhausted_state_aware（または同等 reason）で fallback する
  # RED: 実装前はパターンが存在しないため fail する
  run grep -qE 'inject_exhausted_state_aware|state_aware.*exhausted|exhausted.*state_aware' "$SCRIPT_SRC"
  [ "$status" -eq 0 ] \
    || fail "AC3: inject_exhausted_state_aware / 同等パターンがスクリプトに存在しない"
}

# ===========================================================================
# AC4: 配置順序 — AskUserQuestion → unclassified debounce → STATE-aware inject
# ===========================================================================

@test "ac4: STATE=reviewing elif appears AFTER unclassified debounce confirmation" {
  # AC4: STATE=reviewing の elif は unclassified debounce 確認 (DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC) より後の行に配置
  # RED: reviewing パターンが存在しない or 順序が逆の場合 fail する
  local debounce_line reviewing_line

  debounce_line=$(grep -n 'DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC\|unclassified_debounce_ts_file' "$SCRIPT_SRC" \
    | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1)
  reviewing_line=$(grep -n '"reviewing"' "$SCRIPT_SRC" | grep -v "^#" | tail -1 | cut -d: -f1)

  [[ -n "$debounce_line" ]] \
    || fail "AC4: unclassified debounce ロジックがスクリプトに存在しない (DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC)"
  [[ -n "$reviewing_line" ]] \
    || fail "AC4: reviewing 条件がスクリプトに存在しない"
  [[ "$reviewing_line" -gt "$debounce_line" ]] \
    || fail "AC4: reviewing inject (L$reviewing_line) が unclassified debounce (L$debounce_line) より前に配置されている — 配置順序違反"
}

@test "ac4: AskUserQuestion check appears BEFORE STATE=reviewing check (priority)" {
  # AC4: AskUserQuestion パターン検出は STATE=reviewing より手前に配置（AskUserQuestion が優先）
  # RED: reviewing パターンが存在しない場合 fail する
  local askuserquestion_line reviewing_line

  askuserquestion_line=$(grep -n 'AskUserQuestion' "$SCRIPT_SRC" | grep -v "^#" | head -1 | cut -d: -f1)
  reviewing_line=$(grep -n '"reviewing"' "$SCRIPT_SRC" | grep -v "^#" | tail -1 | cut -d: -f1)

  [[ -n "$askuserquestion_line" ]] \
    || fail "AC4: AskUserQuestion パターンチェックがスクリプトに存在しない"
  [[ -n "$reviewing_line" ]] \
    || fail "AC4: reviewing 条件がスクリプトに存在しない"
  [[ "$askuserquestion_line" -lt "$reviewing_line" ]] \
    || fail "AC4: AskUserQuestion check (L$askuserquestion_line) が reviewing check (L$reviewing_line) より後に配置されている — AskUserQuestion 優先順序違反"
}
