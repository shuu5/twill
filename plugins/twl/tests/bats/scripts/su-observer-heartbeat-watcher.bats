#!/usr/bin/env bats
# su-observer-heartbeat-watcher.bats - Issue #948 AC4 RED テスト
#
# AC4: scripts/heartbeat-watcher.sh 新規作成 + su-observer spawn 直後 default 起動
#      5 min silence → 自動 tmux capture-pane
#      SKILL.md Step 0 末尾に default 起動を明記
#
# Coverage: unit（スクリプト存在確認 + 基本動作）

load '../helpers/common'

HEARTBEAT_WATCHER=""
SKILL_MD=""

setup() {
  common_setup
  HEARTBEAT_WATCHER="$REPO_ROOT/skills/su-observer/scripts/heartbeat-watcher.sh"
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC4: heartbeat-watcher.sh 存在確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: heartbeat-watcher.sh が新規作成されている
# WHEN: su-observer/scripts/heartbeat-watcher.sh を参照する
# THEN: ファイルが存在する
# ---------------------------------------------------------------------------

@test "AC4: heartbeat-watcher.sh が存在する" {
  # RED: 実装前は fail する（スクリプト未作成）
  [[ -f "$HEARTBEAT_WATCHER" ]] \
    || fail "heartbeat-watcher.sh が存在しない: $HEARTBEAT_WATCHER"
}

# ---------------------------------------------------------------------------
# Scenario: heartbeat-watcher.sh が実行可能
# WHEN: heartbeat-watcher.sh のパーミッションを確認する
# THEN: 実行ビットが立っている
# ---------------------------------------------------------------------------

@test "AC4: heartbeat-watcher.sh が実行可能パーミッションを持つ" {
  # RED: スクリプト未作成のため fail する
  [[ -f "$HEARTBEAT_WATCHER" ]] \
    || fail "heartbeat-watcher.sh が存在しない（前提条件 AC4 未実装）"

  [[ -x "$HEARTBEAT_WATCHER" ]] \
    || fail "heartbeat-watcher.sh が実行可能ではない（chmod +x が必要）"
}

# ---------------------------------------------------------------------------
# Scenario: heartbeat-watcher.sh が bash 文法として正しい
# WHEN: bash -n で構文チェックする
# THEN: syntax error なし（exit 0）
# ---------------------------------------------------------------------------

@test "AC4: heartbeat-watcher.sh が bash syntax として valid" {
  # RED: スクリプト未作成のため fail する
  [[ -f "$HEARTBEAT_WATCHER" ]] \
    || fail "heartbeat-watcher.sh が存在しない（前提条件 AC4 未実装）"

  run bash -n "$HEARTBEAT_WATCHER"
  assert_success
}

# ---------------------------------------------------------------------------
# Scenario: heartbeat-watcher.sh が 5 分 silence 閾値を持つ
# WHEN: heartbeat-watcher.sh の内容を確認する
# THEN: 300 秒（5 分）相当の silence 閾値が定義されている
# ---------------------------------------------------------------------------

@test "AC4: heartbeat-watcher.sh に 5 分 (300s) silence 閾値が定義されている" {
  # RED: スクリプト未作成のため fail する
  [[ -f "$HEARTBEAT_WATCHER" ]] \
    || fail "heartbeat-watcher.sh が存在しない（前提条件 AC4 未実装）"

  grep -qE '300|5.*min|SILENCE_SEC|HEARTBEAT_INTERVAL' "$HEARTBEAT_WATCHER" \
    || fail "heartbeat-watcher.sh に 5 分 silence 閾値 (300s) が定義されていない"
}

# ---------------------------------------------------------------------------
# Scenario: heartbeat-watcher.sh が tmux capture-pane を呼び出す
# WHEN: heartbeat-watcher.sh の内容を確認する
# THEN: tmux capture-pane が silence 検出時に呼び出される実装がある
# ---------------------------------------------------------------------------

@test "AC4: heartbeat-watcher.sh が tmux capture-pane を使用する" {
  # RED: スクリプト未作成のため fail する
  [[ -f "$HEARTBEAT_WATCHER" ]] \
    || fail "heartbeat-watcher.sh が存在しない（前提条件 AC4 未実装）"

  grep -q 'capture-pane' "$HEARTBEAT_WATCHER" \
    || fail "heartbeat-watcher.sh に 'tmux capture-pane' の呼び出しが存在しない"
}

# ===========================================================================
# AC4: SKILL.md Step 0 への heartbeat-watcher.sh 起動明記確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: SKILL.md Step 0 末尾に heartbeat-watcher.sh の default 起動が明記されている
# WHEN: SKILL.md Step 0 セクションを参照する
# THEN: heartbeat-watcher.sh の default 起動手順が記載されている
# ---------------------------------------------------------------------------

@test "AC4: SKILL.md Step 0 に heartbeat-watcher.sh の起動記述が存在する" {
  # RED: SKILL.md 未更新のため fail する
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"

  grep -q 'heartbeat-watcher' "$SKILL_MD" \
    || fail "SKILL.md に heartbeat-watcher.sh の起動記述が存在しない"
}
