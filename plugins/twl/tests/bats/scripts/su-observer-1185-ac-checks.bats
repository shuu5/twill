#!/usr/bin/env bats
# su-observer-1185-ac-checks.bats - Issue #1185 AC 機械的検証テスト（TDD RED フェーズ）
#
# Issue #1185: feat(observer): Step 0 monitor-task 起動 MUST + Step 1 定期 audit MUST
#
# このファイルは実装前（RED）状態で全テストが fail することを意図している。
# 実装完了後（GREEN）は全テストが PASS すること。
#
# Coverage: AC1.1, AC1.2, AC1.3, AC2.1, AC2.2, AC2.3, AC2.4

load '../helpers/common'

SKILL_MD=""
MONITOR_CATALOG=""
PITFALLS_CATALOG=""
BOOTSTRAP_SCRIPT=""

setup() {
  common_setup
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
  MONITOR_CATALOG="$REPO_ROOT/skills/su-observer/refs/monitor-channel-catalog.md"
  PITFALLS_CATALOG="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
  BOOTSTRAP_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/step0-monitor-bootstrap.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1.1: SKILL.md Step 0 に step 6.5 として「Monitor task 起動 MUST」を追加
#         挿入文言: Monitor task 起動 MUST: bash plugins/twl/skills/su-observer/scripts/step0-monitor-bootstrap.sh
# ===========================================================================
# RED 理由: 現在 SKILL.md に step 6.5 と「Monitor task 起動 MUST」が存在しない
# ===========================================================================

@test "ac1.1: SKILL.md に 'Monitor task 起動 MUST' が存在する" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が見つからない: $SKILL_MD"

  grep -q "Monitor task 起動 MUST" "$SKILL_MD" \
    || fail "SKILL.md に 'Monitor task 起動 MUST' が存在しない（AC1.1 未達: step 6.5 追加が必要）"
}

@test "ac1.1: SKILL.md の 'Monitor task 起動 MUST' が step0-monitor-bootstrap.sh を参照している" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が見つからない: $SKILL_MD"

  grep -q "step0-monitor-bootstrap\.sh" "$SKILL_MD" \
    || fail "SKILL.md に 'step0-monitor-bootstrap.sh' への参照がない（AC1.1 未達: 挿入文言に script 参照が必要）"
}

@test "ac1.1: SKILL.md の step 6.5 が step 6 と step 7 の間に存在する（順序チェック）" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が見つからない: $SKILL_MD"

  # step 6 の行番号 < step 6.5 の行番号 < step 7 の行番号 を確認
  local line_step6 line_step65 line_step7

  line_step6=$(grep -n "^6\." "$SKILL_MD" | head -1 | cut -d: -f1)
  line_step65=$(grep -n "^6\.5\." "$SKILL_MD" | head -1 | cut -d: -f1)
  line_step7=$(grep -n "^7\." "$SKILL_MD" | head -1 | cut -d: -f1)

  [[ -n "$line_step6" ]] \
    || fail "SKILL.md に '6.' で始まるステップが見つからない（Step 0 の step 6 が必要）"

  [[ -n "$line_step65" ]] \
    || fail "SKILL.md に '6.5.' で始まるステップが見つからない（AC1.1 未達: step 6.5 追加が必要）"

  [[ -n "$line_step7" ]] \
    || fail "SKILL.md に '7.' で始まるステップが見つからない（Step 0 の step 7 が必要）"

  [[ "$line_step6" -lt "$line_step65" && "$line_step65" -lt "$line_step7" ]] \
    || fail "step 6.5 の順序が不正（step6=${line_step6}, step6.5=${line_step65}, step7=${line_step7}）"
}

# ===========================================================================
# AC1.2: 新規 script step0-monitor-bootstrap.sh を作成
# ===========================================================================
# RED 理由: 現在 step0-monitor-bootstrap.sh が存在しない
# ===========================================================================

@test "ac1.2: step0-monitor-bootstrap.sh が存在する" {
  [[ -f "$BOOTSTRAP_SCRIPT" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: $BOOTSTRAP_SCRIPT（AC1.2 未達: script 作成が必要）"
}

@test "ac1.2: step0-monitor-bootstrap.sh が実行可能である" {
  [[ -f "$BOOTSTRAP_SCRIPT" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: $BOOTSTRAP_SCRIPT（AC1.2 未達: script 作成が必要）"

  [[ -x "$BOOTSTRAP_SCRIPT" ]] \
    || fail "step0-monitor-bootstrap.sh が実行可能でない（AC1.2 未達: chmod +x が必要）"
}

@test "ac1.2: step0-monitor-bootstrap.sh が shebang を持つ" {
  [[ -f "$BOOTSTRAP_SCRIPT" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: $BOOTSTRAP_SCRIPT（AC1.2 未達: script 作成が必要）"

  head -1 "$BOOTSTRAP_SCRIPT" | grep -qE "^#!/" \
    || fail "step0-monitor-bootstrap.sh に shebang がない（AC1.2 未達: #!/usr/bin/env bash 等が必要）"
}

# ===========================================================================
# AC1.3: monitor-channel-catalog.md に「Monitor task 起動テンプレート (起動時 SOP 用)」を追加
#         （§cld-observe-any 標準スニペット L499-558 を補完する差分明示）
# ===========================================================================
# RED 理由: 現在 monitor-channel-catalog.md に「Monitor task 起動テンプレート」が存在しない
# ===========================================================================

@test "ac1.3: monitor-channel-catalog.md に 'Monitor task 起動テンプレート' が存在する" {
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が見つからない: $MONITOR_CATALOG"

  grep -q "Monitor task 起動テンプレート" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md に 'Monitor task 起動テンプレート' が存在しない（AC1.3 未達: 追加が必要）"
}

@test "ac1.3: monitor-channel-catalog.md の Monitor task 起動テンプレートに '起動時 SOP 用' の記載がある" {
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が見つからない: $MONITOR_CATALOG"

  grep -q "起動時 SOP 用" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md に '起動時 SOP 用' の記載がない（AC1.3 未達: 差分明示が必要）"
}

# ===========================================================================
# AC2.1: SKILL.md Step 1 supervise loop に「定期 audit (5 分ごと) MUST」step を追加
# ===========================================================================
# RED 理由: 現在 SKILL.md に「定期 audit MUST」が存在しない
# ===========================================================================

@test "ac2.1: SKILL.md に '定期 audit MUST' が存在する" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が見つからない: $SKILL_MD"

  grep -q "定期 audit MUST" "$SKILL_MD" \
    || fail "SKILL.md に '定期 audit MUST' が存在しない（AC2.1 未達: Step 1 に追加が必要）"
}

@test "ac2.1: SKILL.md の '定期 audit' が '5 分ごと' を含む" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が見つからない: $SKILL_MD"

  grep -qE "定期 audit.{0,20}5 分ごと|5 分ごと.{0,20}定期 audit" "$SKILL_MD" \
    || fail "SKILL.md の '定期 audit' 記述に '5 分ごと' が近接していない（AC2.1 未達: '定期 audit (5 分ごと) MUST' の追加が必要）"
}

@test "ac2.1: SKILL.md の定期 audit が Step 1 セクション内に存在する" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が見つからない: $SKILL_MD"

  # Step 1 のセクション開始行と Step 2 のセクション開始行の間に「定期 audit MUST」が存在するか
  local step1_line step2_line audit_line

  step1_line=$(grep -n "^## Step 1" "$SKILL_MD" | head -1 | cut -d: -f1)
  step2_line=$(grep -n "^## Step 2" "$SKILL_MD" | head -1 | cut -d: -f1)
  audit_line=$(grep -n "定期 audit MUST" "$SKILL_MD" | head -1 | cut -d: -f1)

  [[ -n "$step1_line" ]] \
    || fail "SKILL.md に '## Step 1' セクションが見つからない"

  [[ -n "$step2_line" ]] \
    || fail "SKILL.md に '## Step 2' セクションが見つからない"

  [[ -n "$audit_line" ]] \
    || fail "SKILL.md に '定期 audit MUST' が見つからない（AC2.1 未達）"

  [[ "$audit_line" -gt "$step1_line" && "$audit_line" -lt "$step2_line" ]] \
    || fail "SKILL.md の '定期 audit MUST' が Step 1 セクション外にある（step1=${step1_line}, audit=${audit_line}, step2=${step2_line}）"
}

# ===========================================================================
# AC2.2: 検知 pattern polling 実装
#         tmux capture-pane -p | sed 's/\x1b\[[0-9;]*m//g' | grep -E
#         パターン: Enter to select / ^❯ [1-9]\. / Press up to edit queued
# ===========================================================================
# RED 理由: step0-monitor-bootstrap.sh が存在しないため fail
# ===========================================================================

@test "ac2.2: step0-monitor-bootstrap.sh に 'Enter to select' 検知パターンが存在する" {
  [[ -f "$BOOTSTRAP_SCRIPT" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: $BOOTSTRAP_SCRIPT（AC2.2 未達: script 作成が必要）"

  grep -q "Enter to select" "$BOOTSTRAP_SCRIPT" \
    || fail "step0-monitor-bootstrap.sh に 'Enter to select' パターンがない（AC2.2 未達）"
}

@test "ac2.2: step0-monitor-bootstrap.sh に 'Press up to edit queued' 検知パターンが存在する" {
  [[ -f "$BOOTSTRAP_SCRIPT" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: $BOOTSTRAP_SCRIPT（AC2.2 未達: script 作成が必要）"

  grep -q "Press up to edit queued" "$BOOTSTRAP_SCRIPT" \
    || fail "step0-monitor-bootstrap.sh に 'Press up to edit queued' パターンがない（AC2.2 未達）"
}

@test "ac2.2: step0-monitor-bootstrap.sh が tmux capture-pane を使用している" {
  [[ -f "$BOOTSTRAP_SCRIPT" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: $BOOTSTRAP_SCRIPT（AC2.2 未達: script 作成が必要）"

  grep -q "tmux capture-pane" "$BOOTSTRAP_SCRIPT" \
    || fail "step0-monitor-bootstrap.sh に 'tmux capture-pane' がない（AC2.2 未達: polling 実装が必要）"
}

@test "ac2.2: step0-monitor-bootstrap.sh が ANSI escape コード除去 sed を使用している" {
  [[ -f "$BOOTSTRAP_SCRIPT" ]] \
    || fail "step0-monitor-bootstrap.sh が存在しない: $BOOTSTRAP_SCRIPT（AC2.2 未達: script 作成が必要）"

  grep -qE "sed.*\\\\x1b|sed.*\\\\033" "$BOOTSTRAP_SCRIPT" \
    || fail "step0-monitor-bootstrap.sh に ANSI escape コード除去 sed がない（AC2.2 未達: 's/\\x1b\\[[0-9;]*m//g' が必要）"
}

# ===========================================================================
# AC2.3: pitfalls-catalog.md に「補助 polling Monitor」エントリを追加
#         （既存 §11.1〜§11.5 の連番を維持）
# ===========================================================================
# RED 理由: 現在 pitfalls-catalog.md に「補助 polling Monitor」が存在しない
# ===========================================================================

@test "ac2.3: pitfalls-catalog.md に '補助 polling Monitor' が存在する" {
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が見つからない: $PITFALLS_CATALOG"

  grep -q "補助 polling Monitor" "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md に '補助 polling Monitor' が存在しない（AC2.3 未達: §11.x エントリ追加が必要）"
}

# ===========================================================================
# AC2.4: 完了判定 grep -c 検証
#         grep -c "定期 audit MUST" SKILL.md ≥ 1
#         grep -c "Monitor task 起動 MUST" SKILL.md ≥ 1
# ===========================================================================
# RED 理由: 現在 SKILL.md に両フレーズが存在しないため grep -c が 0 を返す
# ===========================================================================

@test "ac2.4: grep -c '定期 audit MUST' SKILL.md が 1 以上" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が見つからない: $SKILL_MD"

  local count
  count=$(grep -c "定期 audit MUST" "$SKILL_MD" 2>/dev/null) || count="0"

  [[ "$count" =~ ^[0-9]+$ ]] \
    || fail "grep -c の結果が数値でない: '$count'"

  [[ "$count" -ge 1 ]] \
    || fail "grep -c '定期 audit MUST' SKILL.md = ${count}（期待: ≥ 1）（AC2.4 未達: Step 1 への追加が必要）"
}

@test "ac2.4: grep -c 'Monitor task 起動 MUST' SKILL.md が 1 以上" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が見つからない: $SKILL_MD"

  local count
  count=$(grep -c "Monitor task 起動 MUST" "$SKILL_MD" 2>/dev/null) || count="0"

  [[ "$count" =~ ^[0-9]+$ ]] \
    || fail "grep -c の結果が数値でない: '$count'"

  [[ "$count" -ge 1 ]] \
    || fail "grep -c 'Monitor task 起動 MUST' SKILL.md = ${count}（期待: ≥ 1）（AC2.4 未達: step 6.5 への追加が必要）"
}
