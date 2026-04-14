#!/usr/bin/env bats
# chain-runner-terminal-guard.bats - quick mode terminal guard (#671)
#
# ac-verify が quick mode の terminal step。以降の merge 系ステップは
# chain-runner がブロックする。Worker LLM が走り抜けても機械的に拒否。

load '../helpers/common'

setup() {
  common_setup

  # python3 stub: state read を模擬
  # デフォルト: is_quick=true, current_step=ac-verify（ガード発火条件）
  stub_command "python3" '
    case "$*" in
      *"--field is_quick"*)  echo "true" ;;
      *"--field current_step"*) echo "ac-verify" ;;
      *) exit 0 ;;
    esac
  '

  # git stub: Issue 番号を返す
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/673-test" ;;
      *) exit 0 ;;
    esac
  '

  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
  export PYTHONPATH="$SANDBOX"
}

teardown() {
  common_teardown
}

# --- ガード発火テスト ---

@test "terminal-guard: quick + ac-verify で all-pass-check をブロック" {
  run bash "$SANDBOX/scripts/chain-runner.sh" all-pass-check PASS
  assert_success
  assert_output --partial "GUARD: quick mode terminal step"
}

@test "terminal-guard: quick + ac-verify で auto-merge をブロック" {
  run bash "$SANDBOX/scripts/chain-runner.sh" auto-merge
  assert_success
  assert_output --partial "GUARD: quick mode terminal step"
}

@test "terminal-guard: quick + ac-verify で pr-cycle-report をブロック" {
  run bash "$SANDBOX/scripts/chain-runner.sh" pr-cycle-report
  assert_success
  assert_output --partial "GUARD: quick mode terminal step"
}

@test "terminal-guard: quick + ac-verify で pr-comment-final をブロック" {
  run bash "$SANDBOX/scripts/chain-runner.sh" pr-comment-final MERGED
  assert_success
  assert_output --partial "GUARD: quick mode terminal step"
}

# --- ガード非発火テスト ---

@test "terminal-guard: non-quick mode では all-pass-check をブロックしない" {
  stub_command "python3" '
    case "$*" in
      *"--field is_quick"*)  echo "false" ;;
      *"--field current_step"*) echo "ac-verify" ;;
      *) exit 0 ;;
    esac
  '
  run bash "$SANDBOX/scripts/chain-runner.sh" all-pass-check PASS
  # ブロックされない（GUARD メッセージが出ない）
  refute_output --partial "GUARD: quick mode terminal step"
}

@test "terminal-guard: quick mode でも current_step が ac-verify 以外なら通過" {
  stub_command "python3" '
    case "$*" in
      *"--field is_quick"*)  echo "true" ;;
      *"--field current_step"*) echo "init" ;;
      *) exit 0 ;;
    esac
  '
  run bash "$SANDBOX/scripts/chain-runner.sh" all-pass-check PASS
  refute_output --partial "GUARD: quick mode terminal step"
}

@test "terminal-guard: Issue 番号なしではガードをスキップ" {
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "main" ;;
      *) exit 0 ;;
    esac
  '
  run bash "$SANDBOX/scripts/chain-runner.sh" all-pass-check PASS
  refute_output --partial "GUARD: quick mode terminal step"
}

# --- 非対象ステップは常に通過 ---

@test "terminal-guard: init は quick+ac-verify でもブロックしない" {
  run bash "$SANDBOX/scripts/chain-runner.sh" init ""
  refute_output --partial "GUARD: quick mode terminal step"
}

@test "terminal-guard: ac-verify 自体はブロックしない" {
  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  refute_output --partial "GUARD: quick mode terminal step"
}

@test "terminal-guard: record-pr はブロックしない" {
  run bash "$SANDBOX/scripts/chain-runner.sh" record-pr
  refute_output --partial "GUARD: quick mode terminal step"
}
