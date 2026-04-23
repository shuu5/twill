#!/usr/bin/env bats
# chain-runner-next-step.bats - unit tests for next-step command
#
# Coverage:
#   1. next-step: 通常 Issue の次ステップ返却 (current_step=init → board-status-update)
#   2. next-step: 全ステップ完了時 (current_step=最終ステップ → done)
#
# Edge cases:
#   - state ファイル不在時の next-step 挙動
#   - CHAIN_STEPS が空でも next-step が done を返す

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # git stub: feat/151 ブランチを返す（issue_num=151 を extract_issue_num で取得させる）
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/151-chain-runnersh-next-step-quick" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  # gh stub: デフォルトは quick ラベルなし (exit 0 + 空出力)
  stub_command "gh" 'exit 0'

  # resolve-project.sh スタブ（chain-runner.sh が source する）
  mkdir -p "$SANDBOX/scripts/lib"
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE_PROJECT'
#!/usr/bin/env bash
resolve_project() {
  echo "3 PVT_project_id shuu5 loom-plugin-dev shuu5/loom-plugin-dev"
}
RESOLVE_PROJECT
  chmod +x "$SANDBOX/scripts/lib/resolve-project.sh"

  # chain-steps.sh は SANDBOX/scripts/ にコピー済み（common_setup で scripts/*.sh をコピー）
  # state-read.sh / state-write.sh も同様
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: issue-N.json を作成
# ---------------------------------------------------------------------------

_create_issue_with_step() {
  local issue_num="$1"
  local status="$2"
  local current_step="$3"

  local file="$SANDBOX/.autopilot/issues/issue-${issue_num}.json"
  mkdir -p "$(dirname "$file")"

  jq -n \
    --argjson issue "$issue_num" \
    --arg status "$status" \
    --arg current_step "$current_step" \
    '{
      issue: $issue,
      status: $status,
      branch: ("feat/" + ($issue | tostring) + "-test"),
      pr: null,
      window: "",
      started_at: "2026-04-04T00:00:00Z",
      current_step: $current_step,
      retry_count: 0,
      fix_instructions: null,
      merged_at: null,
      files_changed: [],
      failure: null
    }' > "$file"
}

# ---------------------------------------------------------------------------
# Requirement: next-step コマンドの追加
# ---------------------------------------------------------------------------

# Scenario: 通常 Issue の次ステップ返却
@test "next-step: current_step=init のとき board-status-update を返す" {
  _create_issue_with_step 151 "running" "init"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "project-board-status-update"
}

# Scenario: 全ステップ完了時
@test "next-step: current_step が最終ステップ (pr-cycle-report) のとき done を返す" {
  _create_issue_with_step 151 "running" "pr-cycle-report"

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "done"
}

# ---------------------------------------------------------------------------
# Edge cases: next-step
# ---------------------------------------------------------------------------

# Edge: state ファイル不在時 → current_step なし → 最初のステップを返す
@test "next-step: state ファイルが存在しない場合は最初のステップ (init) を返す" {
  # issue-151.json を作らない

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "init"
}

# Edge: Issue 番号なし (引数なし) → エラー終了
@test "next-step: Issue 番号を省略した場合はエラー終了する" {
  run bash "$SANDBOX/scripts/chain-runner.sh" next-step

  assert_failure
}

# Edge: current_step 未設定 (初回) のとき init を返す
@test "next-step: current_step 未設定 (初回) のとき init を返す" {
  _create_issue_with_step 151 "running" ""

  run bash "$SANDBOX/scripts/chain-runner.sh" next-step 151

  assert_success
  assert_output "init"
}

# Edge: state ファイル不在時 → 要実行 (exit 0) でも compaction-resume は次ステップを返す
@test "compaction-resume: state ファイルが存在しない場合は要実行 (exit 0)" {
  # issue-151.json を作らない

  run bash "$SANDBOX/scripts/compaction-resume.sh" 151 ac-extract

  assert_success
}

# Edge: issue 番号なしの init は失敗しない
@test "step_init: issue 番号なしで呼んでも異常終了しない" {
  stub_command "gh" 'exit 0'

  run bash "$SANDBOX/scripts/chain-runner.sh" init

  assert_success
}
