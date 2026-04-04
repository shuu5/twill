#!/usr/bin/env bats
# autopilot-launch-worker-issue-num.bats
# BDD unit tests for WORKER_ISSUE_NUM injection in autopilot-launch.sh
#
# Spec: openspec/changes/fix-resolve-issue-num-parallel-worker/specs/resolve-issue-num/spec.md
#
# Requirement: autopilot-launch.sh の WORKER_ISSUE_NUM export
#   Scenario D: Worker 起動時の環境変数注入
#   Scenario E: 既存環境変数との共存
#
# Edge cases:
#   - WORKER_ISSUE_NUM が tmux env の env コマンドに含まれる
#   - REPO_OWNER/REPO_NAME が設定される場合も WORKER_ISSUE_NUM が追加される
#   - --worktree-dir 指定時も WORKER_ISSUE_NUM が渡される
#   - WORKER_ISSUE_NUM の値が --issue 引数と一致する

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # autopilot-launch.sh が必要とする外部コマンドをスタブ化
  # tmux: 起動コマンドをログファイルに記録する
  stub_command "tmux" "
    echo \"TMUX_CALL: \$*\" >> '$SANDBOX/tmux-calls.log'
    exit 0
  "

  # cld: コマンドが存在することだけ確認
  stub_command "cld" 'exit 0'

  # gh: issue にラベルなし（quick ではない）
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*)
        echo "{\"labels\": []}" ;;
      *)
        exit 0 ;;
    esac
  '

  # state-write.sh スタブ
  cat > "$SANDBOX/scripts/state-write.sh" <<'STUB_EOF'
#!/usr/bin/env bash
exit 0
STUB_EOF
  chmod +x "$SANDBOX/scripts/state-write.sh"

  # crash-detect.sh スタブ
  cat > "$SANDBOX/scripts/crash-detect.sh" <<'STUB_EOF'
#!/usr/bin/env bash
exit 0
STUB_EOF
  chmod +x "$SANDBOX/scripts/crash-detect.sh"

  # プロジェクトディレクトリとして SANDBOX を使用
  mkdir -p "$SANDBOX/project"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: autopilot-launch.sh を実行し tmux-calls.log を検証するヘルパー
# ---------------------------------------------------------------------------

# _assert_tmux_env_contains <var_pattern>
# tmux new-window コマンドに env VAR=... が含まれていることを確認
_assert_tmux_env_contains() {
  local pattern="$1"
  run grep -E "$pattern" "$SANDBOX/tmux-calls.log"
  assert_success
}

# _assert_tmux_env_not_contains <var_pattern>
_assert_tmux_env_not_contains() {
  local pattern="$1"
  if [ -f "$SANDBOX/tmux-calls.log" ]; then
    run grep -E "$pattern" "$SANDBOX/tmux-calls.log"
    assert_failure
  fi
}

# _run_launch <issue_num> [extra args...]
# autopilot-launch.sh を実行する
_run_launch() {
  local issue_num="$1"
  shift
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue "$issue_num" \
    --project-dir "$SANDBOX/project" \
    --autopilot-dir "$SANDBOX/.autopilot" \
    "$@"
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-launch.sh の WORKER_ISSUE_NUM export
# ---------------------------------------------------------------------------

# Scenario D: Worker 起動時の環境変数注入
# WHEN autopilot-launch.sh --issue 238 で Worker を起動する
# THEN tmux の Worker プロセスに WORKER_ISSUE_NUM=238 が環境変数として設定される
@test "autopilot-launch [WORKER_ISSUE_NUM]: --issue 238 起動時に WORKER_ISSUE_NUM=238 が env に含まれる" {
  _run_launch 238

  assert_success
  # tmux new-window コマンドに WORKER_ISSUE_NUM=238 が含まれること
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=238"
}

@test "autopilot-launch [WORKER_ISSUE_NUM]: WORKER_ISSUE_NUM の値が --issue 引数と一致する" {
  _run_launch 100

  assert_success
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=100"
  # 別の issue 番号が混入しないこと
  _assert_tmux_env_not_contains "WORKER_ISSUE_NUM=238"
}

# Scenario E: 既存環境変数との共存
# WHEN AUTOPILOT_DIR・REPO_OWNER・REPO_NAME が既に設定される Worker 起動コマンドに WORKER_ISSUE_NUM を追加する
# THEN 既存の環境変数が維持され、WORKER_ISSUE_NUM が追加される
@test "autopilot-launch [WORKER_ISSUE_NUM]: AUTOPILOT_DIR が tmux env に含まれる（既存変数維持）" {
  _run_launch 238

  assert_success
  # 既存の AUTOPILOT_DIR が維持されること
  _assert_tmux_env_contains "AUTOPILOT_DIR="
  # WORKER_ISSUE_NUM も追加されること
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=238"
}

@test "autopilot-launch [WORKER_ISSUE_NUM]: クロスリポジトリ起動時も REPO_OWNER・REPO_NAME・WORKER_ISSUE_NUM が共存する" {
  # REPO_PATH 用に別ディレクトリを作成
  local repo_path="$SANDBOX/external-repo"
  mkdir -p "$repo_path"

  _run_launch 238 \
    --repo-owner "shuu5" \
    --repo-name "loom" \
    --repo-path "$repo_path"

  assert_success
  # 既存変数が維持されること
  _assert_tmux_env_contains "AUTOPILOT_DIR="
  _assert_tmux_env_contains "REPO_OWNER="
  _assert_tmux_env_contains "REPO_NAME="
  # WORKER_ISSUE_NUM が追加されること
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=238"
}

@test "autopilot-launch [WORKER_ISSUE_NUM]: REPO_OWNER/REPO_NAME なし起動でも WORKER_ISSUE_NUM が含まれる" {
  _run_launch 42

  assert_success
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=42"
}

# ---------------------------------------------------------------------------
# Edge cases: WORKER_ISSUE_NUM 注入の境界値・異常系
# ---------------------------------------------------------------------------

# Edge: --worktree-dir 指定時も WORKER_ISSUE_NUM が渡される
@test "autopilot-launch [WORKER_ISSUE_NUM edge]: --worktree-dir 指定時も WORKER_ISSUE_NUM が環境変数に含まれる" {
  local worktree_dir="$SANDBOX/worktrees/feat-238"
  mkdir -p "$worktree_dir"

  _run_launch 238 --worktree-dir "$worktree_dir"

  assert_success
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=238"
}

# Edge: --model 指定時も WORKER_ISSUE_NUM が渡される
@test "autopilot-launch [WORKER_ISSUE_NUM edge]: --model sonnet 指定時も WORKER_ISSUE_NUM が含まれる" {
  _run_launch 238 --model "sonnet"

  assert_success
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=238"
}

# Edge: Issue 番号が1桁でも WORKER_ISSUE_NUM に正しく注入される
@test "autopilot-launch [WORKER_ISSUE_NUM edge]: --issue 1 で WORKER_ISSUE_NUM=1 が注入される" {
  _run_launch 1

  assert_success
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=1"
}

# Edge: Issue 番号が大きい値でも WORKER_ISSUE_NUM に正しく注入される
@test "autopilot-launch [WORKER_ISSUE_NUM edge]: --issue 9999 で WORKER_ISSUE_NUM=9999 が注入される" {
  _run_launch 9999

  assert_success
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=9999"
}

# Edge: WORKER_ISSUE_NUM が tmux コマンド文字列で env の適切な位置に配置される
@test "autopilot-launch [WORKER_ISSUE_NUM edge]: WORKER_ISSUE_NUM は env コマンドの引数として渡される（tmux new-window 内）" {
  _run_launch 238

  assert_success
  # tmux new-window コールが記録されていること
  run grep "new-window" "$SANDBOX/tmux-calls.log"
  assert_success
  # WORKER_ISSUE_NUM=238 が tmux new-window 呼び出しに含まれること
  run grep "WORKER_ISSUE_NUM=238" "$SANDBOX/tmux-calls.log"
  assert_success
}

# Edge: quick ラベル付き Issue 起動時も WORKER_ISSUE_NUM が注入される
@test "autopilot-launch [WORKER_ISSUE_NUM edge]: quick ラベル付き Issue でも WORKER_ISSUE_NUM が含まれる" {
  # gh stub を quick ラベルを返すように上書き
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*)
        echo "{\"labels\": [{\"name\": \"quick\"}]}" ;;
      *)
        exit 0 ;;
    esac
  '

  _run_launch 238

  assert_success
  _assert_tmux_env_contains "WORKER_ISSUE_NUM=238"
}
