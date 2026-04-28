#!/usr/bin/env bats
# e2e/su-precompact-hook-1020-e2e.bats
#
# Issue #1020: tech-debt(observer): PreCompact hook が working-memory を退避せず cat のみ
#
# AC5: PR merged + main HEAD 更新 + working-memory.md auto-update が e2e で動作
#
# このテストは e2e レベルの動作確認を行う。
# PreCompact hook (su-precompact.sh) が HookEvent として登録されており、
# 実際に実行されたときに working-memory.md が更新されることを確認する。
#
# RED: 現在の実装は working-memory.md を write しないため fail する

load '../helpers/common'

PRECOMPACT_SCRIPT=""

setup() {
  common_setup

  local helpers_dir
  helpers_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_dir
  bats_dir="$(cd "${helpers_dir}/.." && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  local repo_root
  repo_root="$(cd "${tests_dir}/.." && pwd)"

  PRECOMPACT_SCRIPT="${repo_root}/scripts/su-precompact.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC5: e2e — working-memory.md auto-update が動作すること
#
# PreCompact hook 経路の e2e 動作確認:
#   1. .supervisor/session.json に現在の状態が存在する
#   2. su-precompact.sh を HookEvent として実行
#   3. working-memory.md が session.json の状態を反映した内容で更新される
#
# RED: 現在の実装は cat のみで write しないため fail する
# ===========================================================================

@test "ac5(e2e): PreCompact hook 実行後に working-memory.md が session 状態を反映して更新される" {
  # RED: 現在の su-precompact.sh は working-memory.md を write しないため fail する
  # PASS 条件（実装後）:
  #   - working-memory.md が更新タイムスタンプ付きで書き込まれる
  #   - 内容に session.json 由来の状態（session_id 等）が含まれる

  local supervisor_dir="${SANDBOX}/.supervisor"
  mkdir -p "$supervisor_dir"

  # e2e シナリオ: 実際のユースケースを模したセッション状態を用意
  local test_session_id="e2e-session-1020"
  local test_task="Issue #1020 PreCompact write 実装の検証"

  jq -n \
    --arg sid "$test_session_id" \
    --arg task "$test_task" \
    '{
      session_id: $sid,
      claude_session_id: "e2e-claude-session-id",
      observer_window: "e2e-observer",
      status: "active",
      current_task: $task,
      started_at: "2026-04-28T00:00:00Z",
      wave: "Wave-Q",
      current_issue: 1020
    }' > "${supervisor_dir}/session.json"

  # 既存の working-memory.md がある場合のシナリオ（前回のコンテンツ）
  cat > "${supervisor_dir}/working-memory.md" <<'WMEOF'
# Working Memory (previous)

## 前回の状態
- Wave-P 完了済み
- Issue #1019 merge 完了
WMEOF

  local before_mtime
  before_mtime=$(stat -c '%Y' "${supervisor_dir}/working-memory.md" 2>/dev/null || echo "0")

  # PreCompact hook を実行（HookEvent: PreCompact）
  run env SUPERVISOR_DIR="${supervisor_dir}" bash "$PRECOMPACT_SCRIPT"

  echo "--- PreCompact stdout ---"
  echo "$output"
  echo "--- status: $status ---"

  # 1. スクリプトが正常終了すること
  assert_success

  # 2. working-memory.md が存在すること
  [ -f "${supervisor_dir}/working-memory.md" ] || {
    echo "FAIL: working-memory.md が存在しない"
    ls -la "$supervisor_dir"
    return 1
  }

  local after_content
  after_content=$(cat "${supervisor_dir}/working-memory.md")
  echo "--- working-memory.md after PreCompact ---"
  echo "$after_content"

  # 3. working-memory.md の内容が更新されている（session 情報が含まれる）こと
  # RED: 現在の実装は cat のみで write しないため、内容は前回のままか存在しない
  echo "$after_content" | grep -qE "(${test_session_id}|current_task|Issue #1020|Wave-Q)" || {
    echo "FAIL: working-memory.md に session.json の最新状態が反映されていない"
    echo "期待: ${test_session_id} または current_task 等の session 情報"
    echo "実際:"
    echo "$after_content"
    return 1
  }
}

@test "ac5(e2e): PreCompact hook — session.json が存在しない場合でも working-memory.md を保持/生成する" {
  # RED: 現在の実装は session.json を参照しないため、この動作保証が存在しない
  # PASS 条件（実装後）:
  #   session.json がなくても working-memory.md に最低限のスナップショット情報が書かれる

  local supervisor_dir="${SANDBOX}/.supervisor"
  mkdir -p "$supervisor_dir"
  # session.json は作成しない

  # 既存の working-memory.md を用意
  cat > "${supervisor_dir}/working-memory.md" <<'WMEOF'
# Working Memory

## タスク状態
- Issue #1020 対応中
WMEOF

  run env SUPERVISOR_DIR="${supervisor_dir}" bash "$PRECOMPACT_SCRIPT"

  assert_success

  # working-memory.md が引き続き存在すること（削除されないこと）
  [ -f "${supervisor_dir}/working-memory.md" ] || {
    echo "FAIL: working-memory.md が削除されてしまった"
    return 1
  }

  local content
  content=$(cat "${supervisor_dir}/working-memory.md")
  [ -n "$content" ] || {
    echo "FAIL: working-memory.md が空になってしまった"
    return 1
  }

  # タイムスタンプ付きスナップショットが書き込まれていること
  echo "$content" | grep -qE '(timestamp|PRE-COMPACT|[0-9]{4}-[0-9]{2}-[0-9]{2})' || {
    echo "FAIL: working-memory.md にタイムスタンプ情報が含まれない（スナップショット未更新）"
    echo "内容:"
    echo "$content"
    return 1
  }
}

@test "ac5(e2e): PreCompact hook 実行後に su-postcompact.sh が Skill(twl:su-compact) 誘導を出力する" {
  # RED: 現在の su-postcompact.sh に Skill(twl:su-compact) 誘導が存在しないため fail する
  # PASS 条件（実装後）: postcompact stdout に Skill(twl:su-compact) 誘導が含まれる

  local helpers_dir
  helpers_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_dir
  bats_dir="$(cd "${helpers_dir}/.." && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  local repo_root
  repo_root="$(cd "${tests_dir}/.." && pwd)"

  local postcompact_script="${repo_root}/scripts/su-postcompact.sh"

  local supervisor_dir="${SANDBOX}/.supervisor"
  mkdir -p "$supervisor_dir"
  cat > "${supervisor_dir}/working-memory.md" <<'WMEOF'
# Working Memory (e2e test)

## 状態
- e2e テスト実行中
WMEOF

  run env SUPERVISOR_DIR="${supervisor_dir}" bash "$postcompact_script"

  echo "--- PostCompact stdout ---"
  echo "$output"
  echo "--- status: $status ---"

  assert_success

  # Skill(twl:su-compact) 誘導が含まれること
  echo "$output" | grep -qF 'Skill(twl:su-compact)' || {
    echo "FAIL: su-postcompact.sh の stdout に 'Skill(twl:su-compact)' の誘導が含まれない"
    return 1
  }
}
