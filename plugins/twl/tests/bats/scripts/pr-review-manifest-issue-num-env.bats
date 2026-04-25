#!/usr/bin/env bats
# pr-review-manifest-issue-num-env.bats
# AC B-2: ISSUE_NUM 環境変数が pr-review-manifest.sh に上書きされるバグのテスト
#
# RED テスト: B-2-i は現状 line 199 "ISSUE_NUM=" で env を問わずリセットするため FAIL する
# PASS テスト: B-2-ii は現状でも動作するが、テストとして明示する

load '../helpers/common'

setup() {
  common_setup

  # Create a git repo in sandbox (for PROJECT_ROOT resolution)
  git init "$SANDBOX" 2>/dev/null
  (cd "$SANDBOX" && git commit --allow-empty -m "initial" 2>/dev/null) || true
  export PROJECT_ROOT="$SANDBOX"

  # Default codex stub: "Not logged in"
  cat > "$STUB_BIN/codex" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "login" && "$2" == "status" ]]; then
  echo "Not logged in"
  exit 1
fi
exit 0
STUB
  chmod +x "$STUB_BIN/codex"
}

teardown() {
  common_teardown
}

# ===========================================================================
# B-2-i: ISSUE_NUM=964 を export した状態で phase-review → worker-issue-pr-alignment 含む
# RED: 現状 line 199 が ISSUE_NUM="" で env を上書きするため、
#      caller から ISSUE_NUM を渡しても pr-review-manifest.sh 内でリセットされてしまう。
#      修正後は ISSUE_NUM を外部から受け取って resolve_issue_num の代わりに使えるようになるべき。
# 注意: WORKER_ISSUE_NUM は設定しない（resolve_issue_num Priority 0 を使わず、
#       ISSUE_NUM 環境変数のみで worker-issue-pr-alignment が追加されることを確認する）
# ===========================================================================

@test "B-2-i: ISSUE_NUM=964 exported (no WORKER_ISSUE_NUM, no AUTOPILOT_DIR) + phase-review + dummy.sh → worker-issue-pr-alignment included (RED)" {
  # AUTOPILOT_DIR をアンセットして resolve_issue_num の Priority 1 を無効化する。
  # 2>/dev/null で stderr を除外: WARNING メッセージに "worker-issue-pr-alignment" が含まれる false-positive を防ぐ。
  # 現状 line 199 が ISSUE_NUM="" でリセットするため、stdout には worker-issue-pr-alignment が出力されない (RED)。
  run bash -c "export ISSUE_NUM=964; unset WORKER_ISSUE_NUM AUTOPILOT_DIR; cd '$SANDBOX' && (git checkout -b plain-branch 2>/dev/null || true); echo 'dummy.sh' | bash scripts/pr-review-manifest.sh --mode phase-review 2>/dev/null"
  assert_success
  assert_output --partial "worker-issue-pr-alignment"
}

# ===========================================================================
# B-2-ii: ISSUE_NUM 未設定 + branch=plain-branch + resolve_issue_num 失敗
#         → worker-issue-pr-alignment 含まない かつ WARNING が stderr に出る
# 現状でも動作するが、テストとして明示する
# ===========================================================================

@test "B-2-ii: ISSUE_NUM unset + plain-branch → worker-issue-pr-alignment not included + WARNING to stderr" {
  run bash -c "unset WORKER_ISSUE_NUM AUTOPILOT_DIR ISSUE_NUM; cd '$SANDBOX' && (git checkout -b plain-branch 2>/dev/null || true); echo '' | bash scripts/pr-review-manifest.sh --mode phase-review 2>&1 1>/dev/null"
  assert_success
  assert_output --partial "WARNING: pr-review-manifest"
}

@test "B-2-ii stdout: ISSUE_NUM unset + plain-branch → worker-issue-pr-alignment not in stdout" {
  run bash -c "unset WORKER_ISSUE_NUM AUTOPILOT_DIR ISSUE_NUM; cd '$SANDBOX' && (git checkout -b plain-branch 2>/dev/null || true); echo '' | bash scripts/pr-review-manifest.sh --mode phase-review 2>/dev/null"
  assert_success
  refute_output --partial "worker-issue-pr-alignment"
}
