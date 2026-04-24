#!/usr/bin/env bats
# su-observer-pilot-signals.bats - Issue #948 AC1/AC2/AC3 RED テスト
#
# AC1: pilot-completion-signals.md 新規作成（Pilot 完了 signal 一覧、controller 別表 + regex snippet）
# AC2: monitor-channel-catalog.md に PILOT-PHASE-COMPLETE / PILOT-ISSUE-MERGED / PILOT-WAVE-COLLECTED 追記
# AC3: cld-observe-any 起動推奨 pattern を '(ap-|wt-co-).*' に変更
#      （SKILL.md §supervise 1 iteration + refs/pitfalls-catalog.md §4.1 更新）
#
# Coverage: unit（ドキュメント内容の機械的固定テスト）

load '../helpers/common'

PILOT_SIGNALS_MD=""
MONITOR_CATALOG_MD=""
SKILL_MD=""
PITFALLS_CATALOG_MD=""

setup() {
  common_setup
  PILOT_SIGNALS_MD="$REPO_ROOT/skills/su-observer/refs/pilot-completion-signals.md"
  MONITOR_CATALOG_MD="$REPO_ROOT/skills/su-observer/refs/monitor-channel-catalog.md"
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
  PITFALLS_CATALOG_MD="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: pilot-completion-signals.md 存在確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: pilot-completion-signals.md が新規作成されている
# WHEN: refs/pilot-completion-signals.md を参照する
# THEN: ファイルが存在する
# ---------------------------------------------------------------------------

@test "AC1: pilot-completion-signals.md が存在する" {
  # RED: 実装前は fail する（ファイル未作成）
  [[ -f "$PILOT_SIGNALS_MD" ]] \
    || fail "pilot-completion-signals.md が存在しない: $PILOT_SIGNALS_MD"
}

# ---------------------------------------------------------------------------
# Scenario: pilot-completion-signals.md に controller 別表が存在する
# WHEN: pilot-completion-signals.md を参照する
# THEN: controller 別の完了 signal 一覧表が存在する
# ---------------------------------------------------------------------------

@test "AC1: pilot-completion-signals.md に controller 別表が存在する" {
  # RED: ファイル未作成のため fail する
  [[ -f "$PILOT_SIGNALS_MD" ]] \
    || fail "pilot-completion-signals.md が存在しない（前提条件 AC1 未実装）"

  grep -qiE 'controller|co-autopilot|co-issue' "$PILOT_SIGNALS_MD" \
    || fail "pilot-completion-signals.md に controller 別表が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: pilot-completion-signals.md に regex snippet が存在する
# WHEN: pilot-completion-signals.md を参照する
# THEN: 完了 signal を検知するための regex snippet が記載されている
# ---------------------------------------------------------------------------

@test "AC1: pilot-completion-signals.md に regex snippet が存在する" {
  # RED: ファイル未作成のため fail する
  [[ -f "$PILOT_SIGNALS_MD" ]] \
    || fail "pilot-completion-signals.md が存在しない（前提条件 AC1 未実装）"

  grep -qiE 'regex|pattern|\.\*' "$PILOT_SIGNALS_MD" \
    || fail "pilot-completion-signals.md に regex snippet が存在しない"
}

# ===========================================================================
# AC2: monitor-channel-catalog.md に 3 チャネル追記確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: PILOT-PHASE-COMPLETE チャネルが登録されている
# WHEN: monitor-channel-catalog.md を参照する
# THEN: PILOT-PHASE-COMPLETE チャネルが存在する
# ---------------------------------------------------------------------------

@test "AC2: monitor-channel-catalog.md に PILOT-PHASE-COMPLETE チャネルが存在する" {
  # RED: チャネル未追記のため fail する
  [[ -f "$MONITOR_CATALOG_MD" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG_MD"

  grep -q 'PILOT-PHASE-COMPLETE' "$MONITOR_CATALOG_MD" \
    || fail "monitor-channel-catalog.md に PILOT-PHASE-COMPLETE チャネルが存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: PILOT-ISSUE-MERGED チャネルが登録されている
# WHEN: monitor-channel-catalog.md を参照する
# THEN: PILOT-ISSUE-MERGED チャネルが存在する
# ---------------------------------------------------------------------------

@test "AC2: monitor-channel-catalog.md に PILOT-ISSUE-MERGED チャネルが存在する" {
  # RED: チャネル未追記のため fail する
  [[ -f "$MONITOR_CATALOG_MD" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG_MD"

  grep -q 'PILOT-ISSUE-MERGED' "$MONITOR_CATALOG_MD" \
    || fail "monitor-channel-catalog.md に PILOT-ISSUE-MERGED チャネルが存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: PILOT-WAVE-COLLECTED チャネルが登録されている
# WHEN: monitor-channel-catalog.md を参照する
# THEN: PILOT-WAVE-COLLECTED チャネルが存在する
# ---------------------------------------------------------------------------

@test "AC2: monitor-channel-catalog.md に PILOT-WAVE-COLLECTED チャネルが存在する" {
  # RED: チャネル未追記のため fail する
  [[ -f "$MONITOR_CATALOG_MD" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG_MD"

  grep -q 'PILOT-WAVE-COLLECTED' "$MONITOR_CATALOG_MD" \
    || fail "monitor-channel-catalog.md に PILOT-WAVE-COLLECTED チャネルが存在しない"
}

# ===========================================================================
# AC3: cld-observe-any 起動推奨 pattern 変更確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: SKILL.md の cld-observe-any pattern が '(ap-|wt-co-).*' に変更されている
# WHEN: SKILL.md §supervise 1 iteration を参照する
# THEN: --pattern '(ap-|wt-co-).*' の記述が存在する
# ---------------------------------------------------------------------------

@test "AC3: SKILL.md に cld-observe-any pattern '(ap-|wt-co-).*' が記載されている" {
  # RED: pattern 未更新のため fail する
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"

  grep -qE "ap-\|wt-co-|\(ap-\|wt-co-\)" "$SKILL_MD" \
    || fail "SKILL.md に cld-observe-any pattern '(ap-|wt-co-).*' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §4.1 が '(ap-|wt-co-).*' pattern に更新されている
# WHEN: pitfalls-catalog.md §4 を参照する
# THEN: §4.1 に '(ap-|wt-co-).*' pattern が記載されている
# ---------------------------------------------------------------------------

@test "AC3: pitfalls-catalog.md §4.1 に cld-observe-any pattern '(ap-|wt-co-).*' が記載されている" {
  # RED: pitfalls-catalog.md §4.1 未更新のため fail する
  [[ -f "$PITFALLS_CATALOG_MD" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG_MD"

  grep -qE "ap-\|wt-co-|\(ap-\|wt-co-\)" "$PITFALLS_CATALOG_MD" \
    || fail "pitfalls-catalog.md §4.1 に cld-observe-any pattern '(ap-|wt-co-).*' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: SKILL.md の旧 pattern 'ap-.*' が単独では残っていない
# WHEN: SKILL.md §supervise 1 iteration を参照する
# THEN: 'ap-.*' 単独記述（wt-co- なし）が cld-observe-any オプションとして使われていない
# ---------------------------------------------------------------------------

@test "AC3: SKILL.md の cld-observe-any が旧 pattern 'ap-.*' 単独を使用していない" {
  # RED: SKILL.md の pattern が未更新で 'ap-.*' 単独のため fail する
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"

  # 'ap-.*' のみで 'wt-co-' を含まない cld-observe-any の --pattern 記述が残っていないことを確認
  local old_pattern_count
  old_pattern_count=$(grep -c "pattern 'ap-\.\*'" "$SKILL_MD" 2>/dev/null; true)
  old_pattern_count="${old_pattern_count:-0}"

  [[ "$old_pattern_count" -eq 0 ]] \
    || fail "SKILL.md に旧 pattern 'ap-.*' 単独の cld-observe-any 記述が ${old_pattern_count} 件残っている"
}
