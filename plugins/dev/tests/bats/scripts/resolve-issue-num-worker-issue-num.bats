#!/usr/bin/env bats
# resolve-issue-num-worker-issue-num.bats
# BDD unit tests for WORKER_ISSUE_NUM Priority 0 in resolve_issue_num()
#
# Spec: openspec/changes/fix-resolve-issue-num-parallel-worker/specs/resolve-issue-num/spec.md
#
# Requirement: WORKER_ISSUE_NUM Priority 0 参照
#   Scenario A: WORKER_ISSUE_NUM が設定されている場合
#   Scenario B: WORKER_ISSUE_NUM が未設定の場合
#   Scenario C: 並列 Phase での複数 Worker
#
# Edge cases:
#   - WORKER_ISSUE_NUM=0 (無効値) はフォールバックする
#   - WORKER_ISSUE_NUM が空文字列の場合はフォールバックする
#   - WORKER_ISSUE_NUM が非数値の場合の挙動
#   - WORKER_ISSUE_NUM が設定かつ AUTOPILOT_DIR に running issue が存在する場合は WORKER_ISSUE_NUM 優先
#   - WORKER_ISSUE_NUM が設定かつ AUTOPILOT_DIR が未設定の場合
#   - WORKER_ISSUE_NUM が設定かつ running issue が自分自身でない場合でも返す

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # デフォルト git stub: feat/42-test ブランチ
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/42-feature-name" ;;
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

  mkdir -p "$SANDBOX/scripts/lib"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: resolve_issue_num() を直接テストするためのドライバスクリプトを生成
# ---------------------------------------------------------------------------

_make_driver() {
  cat > "$SANDBOX/scripts/driver.sh" <<'DRIVER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/resolve-issue-num.sh"
resolve_issue_num
DRIVER_EOF
  chmod +x "$SANDBOX/scripts/driver.sh"
}

# ---------------------------------------------------------------------------
# Requirement: WORKER_ISSUE_NUM Priority 0 参照
# ---------------------------------------------------------------------------

# Scenario A: WORKER_ISSUE_NUM が設定されている場合
# WHEN WORKER_ISSUE_NUM=238 が export された状態で resolve_issue_num を呼び出す
# THEN 238 を返し、AUTOPILOT_DIR スキャンおよび git branch フォールバックは実行しない
@test "resolve_issue_num [WORKER_ISSUE_NUM]: WORKER_ISSUE_NUM=238 設定時は 238 を返す" {
  _make_driver
  # AUTOPILOT_DIR に別の running issue を置いて「スキャンされないこと」を確認できるようにする
  create_issue_json 100 "running"

  # git stub が呼ばれた場合は別番号を返す（呼ばれないことを確認）
  local git_call_log="$SANDBOX/git-calls.log"
  stub_command "git" "
    echo \"\$*\" >> '$git_call_log'
    case \"\$*\" in
      *'branch --show-current'*)
        echo 'feat/999-should-not-be-called' ;;
      *)
        exit 0 ;;
    esac
  "

  run env WORKER_ISSUE_NUM=238 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "238"
}

# Scenario A (追加検証): WORKER_ISSUE_NUM 設定時は git branch を呼ばない
@test "resolve_issue_num [WORKER_ISSUE_NUM]: WORKER_ISSUE_NUM 設定時は git branch を呼ばない" {
  _make_driver

  local git_call_log="$SANDBOX/git-calls.log"
  stub_command "git" "
    echo \"\$*\" >> '$git_call_log'
    echo 'feat/999-should-not-be-called'
  "

  run env WORKER_ISSUE_NUM=238 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "238"

  # git branch --show-current が呼ばれていないこと
  if [ -f "$git_call_log" ]; then
    run grep "branch --show-current" "$git_call_log"
    assert_failure
  fi
}

# Scenario B: WORKER_ISSUE_NUM が未設定の場合
# WHEN WORKER_ISSUE_NUM が設定されていない状態で resolve_issue_num を呼び出す
# THEN 既存の Priority 1（AUTOPILOT_DIR スキャン）→ Priority 2（git branch）の順で動作する
@test "resolve_issue_num [WORKER_ISSUE_NUM]: WORKER_ISSUE_NUM 未設定時は Priority 1 (AUTOPILOT_DIR スキャン) で動作する" {
  _make_driver
  # WORKER_ISSUE_NUM を明示的に unset
  unset WORKER_ISSUE_NUM
  create_issue_json 55 "running"

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  # AUTOPILOT_DIR スキャンで 55 を返すこと（git branch の 42 ではない）
  assert_output "55"
}

@test "resolve_issue_num [WORKER_ISSUE_NUM]: WORKER_ISSUE_NUM 未設定かつ running 0件時は git branch にフォールバック" {
  _make_driver
  unset WORKER_ISSUE_NUM

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/77-fallback-test" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "77"
}

# Scenario C: 並列 Phase での複数 Worker
# WHEN issue-227, 228, 229 が全て status=running で WORKER_ISSUE_NUM=229 が設定されている
# THEN 229 を返す（最小番号の 227 は返さない）
@test "resolve_issue_num [WORKER_ISSUE_NUM]: 並列 Phase で複数 running 時も WORKER_ISSUE_NUM=229 を返す（最小の 227 ではない）" {
  _make_driver
  create_issue_json 227 "running"
  create_issue_json 228 "running"
  create_issue_json 229 "running"

  run env WORKER_ISSUE_NUM=229 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  # AUTOPILOT_DIR スキャンなら 227 を返すが、WORKER_ISSUE_NUM=229 が優先される
  assert_output "229"
}

@test "resolve_issue_num [WORKER_ISSUE_NUM]: 並列 Phase で WORKER_ISSUE_NUM=227 の Worker は 227 を返す" {
  _make_driver
  create_issue_json 227 "running"
  create_issue_json 228 "running"
  create_issue_json 229 "running"

  run env WORKER_ISSUE_NUM=227 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "227"
}

@test "resolve_issue_num [WORKER_ISSUE_NUM]: 並列 Phase で WORKER_ISSUE_NUM=228 の Worker は 228 を返す" {
  _make_driver
  create_issue_json 227 "running"
  create_issue_json 228 "running"
  create_issue_json 229 "running"

  run env WORKER_ISSUE_NUM=228 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "228"
}

# ---------------------------------------------------------------------------
# Edge cases: WORKER_ISSUE_NUM の境界値・異常系
# ---------------------------------------------------------------------------

# Edge: WORKER_ISSUE_NUM が空文字列の場合はフォールバックする
@test "resolve_issue_num [WORKER_ISSUE_NUM edge]: WORKER_ISSUE_NUM='' の場合は AUTOPILOT_DIR スキャンにフォールバック" {
  _make_driver
  create_issue_json 33 "running"

  run env WORKER_ISSUE_NUM="" bash "$SANDBOX/scripts/driver.sh"

  assert_success
  # 空文字は未設定扱いとして Priority 1 スキャンにフォールバック
  assert_output "33"
}

# Edge: WORKER_ISSUE_NUM が設定かつ AUTOPILOT_DIR が未設定の場合
@test "resolve_issue_num [WORKER_ISSUE_NUM edge]: AUTOPILOT_DIR 未設定でも WORKER_ISSUE_NUM=238 を返す" {
  _make_driver
  unset AUTOPILOT_DIR

  run env WORKER_ISSUE_NUM=238 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "238"
}

# Edge: WORKER_ISSUE_NUM が設定かつ running issue が存在しない場合
@test "resolve_issue_num [WORKER_ISSUE_NUM edge]: running issue 0件でも WORKER_ISSUE_NUM=238 を返す" {
  _make_driver
  # running issue なし（done のみ）
  create_issue_json 10 "done"

  run env WORKER_ISSUE_NUM=238 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "238"
}

# Edge: WORKER_ISSUE_NUM=1（最小有効値）
@test "resolve_issue_num [WORKER_ISSUE_NUM edge]: WORKER_ISSUE_NUM=1 は 1 を返す" {
  _make_driver
  create_issue_json 500 "running"

  run env WORKER_ISSUE_NUM=1 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "1"
}

# Edge: WORKER_ISSUE_NUM が大きな Issue 番号（issue-9999）
@test "resolve_issue_num [WORKER_ISSUE_NUM edge]: WORKER_ISSUE_NUM=9999 を正しく返す" {
  _make_driver
  create_issue_json 1 "running"

  run env WORKER_ISSUE_NUM=9999 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "9999"
}

# Edge: WORKER_ISSUE_NUM が AUTOPILOT_DIR の running issue と一致しない場合でも WORKER_ISSUE_NUM 優先
@test "resolve_issue_num [WORKER_ISSUE_NUM edge]: WORKER_ISSUE_NUM と AUTOPILOT_DIR が不一致でも WORKER_ISSUE_NUM を優先" {
  _make_driver
  # state file には 100, 200 が running だが Worker 自身は 238
  create_issue_json 100 "running"
  create_issue_json 200 "running"

  run env WORKER_ISSUE_NUM=238 bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "238"
}
