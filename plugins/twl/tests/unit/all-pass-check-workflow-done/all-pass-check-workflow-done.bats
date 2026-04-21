#!/usr/bin/env bats
# all-pass-check-workflow-done.bats
# Requirement: step_all_pass_check() — merge-ready 時に status=merge-ready を書き込む
# Coverage: --type=unit --coverage=edge-cases
#
# step_all_pass_check() は chain-runner.sh の終端ステップ。
# overall_result=PASS で status=merge-ready を書き込む（ADR-018: workflow_done 廃止済み）。
#
# テスト対象: plugins/twl/scripts/chain-runner.sh
#   - bash "$CR" all-pass-check PASS → status=merge-ready
#   - bash "$CR" all-pass-check FAIL → status=failed
#   - state write 失敗 (read-only dir) → exit 1
#
# 環境変数:
#   WORKER_ISSUE_NUM=494  - resolve_issue_num の Priority 0 による issue 番号固定
#   AUTOPILOT_DIR         - common_setup が $SANDBOX/.autopilot に設定

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # WORKER_ISSUE_NUM で issue 番号を固定（git branch fallback を回避）
  export WORKER_ISSUE_NUM=494

  # gh stub: all-pass-check 内の `gh pr view --json number -q '.number'` を無害化
  stub_command "gh" 'echo ""'

  # chain-runner.sh へのパス
  CR="$SANDBOX/scripts/chain-runner.sh"
  export CR
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: 正常終了時に status=merge-ready が書かれる
# WHEN step_all_pass_check() が overall_result=PASS で実行される
# THEN state に status=merge-ready が書き込まれ exit 0
# ---------------------------------------------------------------------------

@test "all-pass-check[PASS]: status=merge-ready が書き込まれる" {
  # issue state を running で初期化
  create_issue_json 494 "running"

  run bash "$CR" all-pass-check PASS

  assert_success

  # state から status を読む
  local status
  status=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$AUTOPILOT_DIR" \
    --type issue --issue 494 --field status 2>/dev/null)
  [ "$status" = "merge-ready" ]
}

# ---------------------------------------------------------------------------
# Scenario: FAIL 時は status=failed が書かれる
# WHEN step_all_pass_check() が overall_result=FAIL で実行される
# THEN state に status=failed が書き込まれ exit 1
# ---------------------------------------------------------------------------

@test "all-pass-check[FAIL]: status=failed が書かれる" {
  create_issue_json 494 "running"

  run bash "$CR" all-pass-check FAIL

  assert_failure

  # status=failed が書かれている
  local status
  status=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$AUTOPILOT_DIR" \
    --type issue --issue 494 --field status 2>/dev/null)
  [ "$status" = "failed" ]
}

# ---------------------------------------------------------------------------
# Scenario: state write 失敗時は exit 非ゼロで終了する
# WHEN python3 -m twl.autopilot.state write コマンドが非ゼロで終了する
# THEN step_all_pass_check() は err を出力して return 1 する
# ---------------------------------------------------------------------------

@test "all-pass-check[state-write-fail]: state write 失敗時は exit 1 で終了する" {
  create_issue_json 494 "running"

  # issues ディレクトリを read-only にして state write を強制失敗させる
  chmod -w "$AUTOPILOT_DIR/issues"

  run bash "$CR" all-pass-check PASS

  # 権限を戻す（teardown で SANDBOX ごと削除されるが明示的に復元）
  chmod +w "$AUTOPILOT_DIR/issues"

  assert_failure
}

# ---------------------------------------------------------------------------
# Scenario: smoke — PASS 後に status=merge-ready を state から読み出せる
# WHEN all-pass-check PASS を実行する smoke テストが走る
# THEN テスト完了後に state から status を読み取ると merge-ready が返る
# ---------------------------------------------------------------------------

@test "smoke[all-pass-check]: PASS 後に state.status=merge-ready が確認できる" {
  create_issue_json 494 "running"

  # 実行（run 経由でアサーション到達を保証）
  run bash "$CR" all-pass-check PASS
  assert_success

  # 直接 state ファイルを jq で確認（python モジュール不使用の二重確認）
  local state_file="$AUTOPILOT_DIR/issues/issue-494.json"
  [ -f "$state_file" ]

  local status_val
  status_val=$(jq -r '.status // empty' "$state_file")
  [ "$status_val" = "merge-ready" ]
}
