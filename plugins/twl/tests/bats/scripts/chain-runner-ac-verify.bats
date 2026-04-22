#!/usr/bin/env bats
# chain-runner-ac-verify.bats - unit tests for chain-runner.sh ac-verify step
#
# Spec: Issue #134 — ac-verify を chain に正しく接続し AC↔diff 整合性チェックを実装する
#
# Coverage:
#   1. ac-verify: ヘルプ出力に含まれる
#   2. ac-verify: dispatcher が認識する（未知ステップエラーを返さない）
#   3. ac-verify: Issue 番号があれば current_step を記録し ok 出力
#   4. ac-verify: Issue 番号がなければ skip
#   5. CHAIN_STEPS に ac-verify が pr-test と all-pass-check の間に存在する
#   6. ac-verify は QUICK_SKIP_STEPS に含まれない（quick path でも実行される）

load '../helpers/common'

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/134-ac-verify" ;;
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

  stub_command "gh" 'exit 0'

  mkdir -p "$SANDBOX/scripts/lib"
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE_PROJECT'
#!/usr/bin/env bash
resolve_project() {
  echo "3 PVT_project_id shuu5 loom-plugin-dev shuu5/loom-plugin-dev"
}
RESOLVE_PROJECT
  chmod +x "$SANDBOX/scripts/lib/resolve-project.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Help / dispatcher
# ---------------------------------------------------------------------------

@test "chain-runner help に ac-verify が含まれる" {
  run bash "$SANDBOX/scripts/chain-runner.sh"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ac-verify"
}

@test "chain-runner: ac-verify は未知ステップエラーにならない" {
  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  # Issue 番号があれば成功（skip でも exit 0）
  assert_success
  ! echo "$output" | grep -q "未知のステップ"
}

# ---------------------------------------------------------------------------
# step_ac_verify behaviour
# ---------------------------------------------------------------------------

@test "ac-verify: Issue 番号があれば current_step を記録し ok を返す" {
  local file="$SANDBOX/.autopilot/issues/issue-134.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 134,
    status: "running",
    branch: "feat/134-ac-verify",
    pr: null,
    window: "",
    started_at: "2026-04-07T00:00:00Z",
    current_step: "pr-test",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null
  }' > "$file"

  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  assert_success
  echo "$output" | grep -q "ac-verify"

  # current_step が ac-verify に更新される
  local current
  current="$(jq -r '.current_step' "$file")"
  [ "$current" = "ac-verify" ]
}

@test "ac-verify: Issue 番号が解決できなければ skip" {
  # main ブランチを返す stub
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "main" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  assert_success
  echo "$output" | grep -q "ac-verify"
}

# ---------------------------------------------------------------------------
# CHAIN_STEPS 配列の確認
# ---------------------------------------------------------------------------

@test "chain-steps.sh: ac-verify が CHAIN_STEPS に含まれる（pr-test と all-pass-check の間）" {
  run bash -c "
    source '$SANDBOX/scripts/chain-steps.sh'
    pr_test_idx=-1
    ac_verify_idx=-1
    all_pass_idx=-1
    for i in \"\${!CHAIN_STEPS[@]}\"; do
      case \"\${CHAIN_STEPS[\$i]}\" in
        pr-test)        pr_test_idx=\$i ;;
        ac-verify)      ac_verify_idx=\$i ;;
        all-pass-check) all_pass_idx=\$i ;;
      esac
    done
    [[ \$pr_test_idx -lt \$ac_verify_idx ]] || { echo 'FAIL: pr-test must precede ac-verify'; exit 1; }
    [[ \$ac_verify_idx -lt \$all_pass_idx ]] || { echo 'FAIL: ac-verify must precede all-pass-check'; exit 1; }
    echo OK
  "
  assert_success
  assert_output "OK"
}

@test "chain-steps.sh: ac-verify は QUICK_SKIP_STEPS に含まれない（quick path でも必須実行）" {
  run bash -c "
    source '$SANDBOX/scripts/chain-steps.sh'
    for s in \"\${QUICK_SKIP_STEPS[@]}\"; do
      if [[ \"\$s\" == \"ac-verify\" ]]; then
        echo 'FAIL: ac-verify must NOT be in QUICK_SKIP_STEPS'
        exit 1
      fi
    done
    echo OK
  "
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# #891: ac-verify LLM timeout retry safety net
# - 1 回目呼出: ac_verify_call_count 0 → 1、正常に ok 返却
# - 2 回目呼出: 1 → 2 (retry 許容範囲)、正常に ok 返却
# - 3 回目呼出: 2 → 3 (max+1 超過)、status=failed + failure.reason=ac_verify_llm_timeout
# ---------------------------------------------------------------------------

@test "ac-verify[#891]: 初回呼出は ac_verify_call_count を 1 に更新して ok" {
  local file="$SANDBOX/.autopilot/issues/issue-134.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 134, status: "running", branch: "feat/134-ac-verify",
    pr: null, window: "", started_at: "2026-04-07T00:00:00Z",
    current_step: "pr-test", retry_count: 0, ac_verify_call_count: 0,
    fix_instructions: null, merged_at: null, files_changed: [], failure: null
  }' > "$file"

  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  assert_success
  echo "$output" | grep -q "call_count=1"

  local count status
  count="$(jq -r '.ac_verify_call_count' "$file")"
  status="$(jq -r '.status' "$file")"
  [ "$count" = "1" ]
  [ "$status" = "running" ]
}

@test "ac-verify[#891]: 2 回目呼出は call_count=2 で retry 許容範囲 (ok)" {
  local file="$SANDBOX/.autopilot/issues/issue-134.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 134, status: "running", branch: "feat/134-ac-verify",
    pr: null, window: "", started_at: "2026-04-07T00:00:00Z",
    current_step: "pr-test", retry_count: 0, ac_verify_call_count: 1,
    fix_instructions: null, merged_at: null, files_changed: [], failure: null
  }' > "$file"

  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  assert_success

  local count status
  count="$(jq -r '.ac_verify_call_count' "$file")"
  status="$(jq -r '.status' "$file")"
  [ "$count" = "2" ]
  [ "$status" = "running" ]
}

@test "ac-verify[#891]: 3 回目呼出 (max+1 超過) で status=failed + ac_verify_llm_timeout" {
  local file="$SANDBOX/.autopilot/issues/issue-134.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 134, status: "running", branch: "feat/134-ac-verify",
    pr: null, window: "", started_at: "2026-04-07T00:00:00Z",
    current_step: "pr-test", retry_count: 0, ac_verify_call_count: 2,
    fix_instructions: null, merged_at: null, files_changed: [], failure: null
  }' > "$file"

  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  # exit 2 (force-exit): err 関数が非 0 exit を返す
  [ "$status" -ne 0 ]

  local count state reason
  count="$(jq -r '.ac_verify_call_count' "$file")"
  state="$(jq -r '.status' "$file")"
  reason="$(jq -r '.failure.reason' "$file")"
  [ "$count" = "3" ]
  [ "$state" = "failed" ]
  [ "$reason" = "ac_verify_llm_timeout" ]
}

@test "ac-verify[#891]: DEV_AUTOPILOT_AC_VERIFY_MAX_RETRY=2 で上限拡張される" {
  local file="$SANDBOX/.autopilot/issues/issue-134.json"
  mkdir -p "$(dirname "$file")"
  jq -n '{
    issue: 134, status: "running", branch: "feat/134-ac-verify",
    pr: null, window: "", started_at: "2026-04-07T00:00:00Z",
    current_step: "pr-test", retry_count: 0, ac_verify_call_count: 2,
    fix_instructions: null, merged_at: null, files_changed: [], failure: null
  }' > "$file"

  DEV_AUTOPILOT_AC_VERIFY_MAX_RETRY=2 run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  # max=2 → max+1=3、call_count=3 は上限内 → ok
  assert_success

  local count state
  count="$(jq -r '.ac_verify_call_count' "$file")"
  state="$(jq -r '.status' "$file")"
  [ "$count" = "3" ]
  [ "$state" = "running" ]
}
