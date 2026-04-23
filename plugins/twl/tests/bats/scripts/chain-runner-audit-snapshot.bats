#!/usr/bin/env bats
# chain-runner-audit-snapshot.bats - #897-C audit snapshot hook
#
# Spec: Issue #897 — autopilot-launch.sh で Worker 起動時に cross-repo audit + pipe-pane を自動 bootstrap
#   Scope C: checkpoint snapshot hook (auto-merge 完了時に twl audit snapshot 発火)
#
# Coverage:
#   (C1) step_auto_merge 成功時に audit snapshot が呼ばれる
#   (C2) step_auto_merge 失敗時は snapshot を呼ばない
#   (C3) .autopilot dir 不在時は snapshot skip (no-op)

load '../helpers/common'

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/897-test" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"worktree list --porcelain"*)
        printf "worktree %s\nbranch refs/heads/main\n" "$SANDBOX" ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "gh" 'exit 0'

  # auto-merge.sh を成功 stub に置換
  cat > "$SANDBOX/scripts/auto-merge.sh" <<'AMSTUB'
#!/usr/bin/env bash
echo "[auto-merge-stub] merge 完了 ok"
exit 0
AMSTUB
  chmod +x "$SANDBOX/scripts/auto-merge.sh"

  # python3 stub: audit snapshot と state write/read を record
  AUDIT_SNAPSHOT_LOG="$SANDBOX/audit-snapshot.log"
  export AUDIT_SNAPSHOT_LOG
  : > "$AUDIT_SNAPSHOT_LOG"

  cat > "$STUB_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
case "$*" in
  *"audit snapshot"*)
    echo "$*" >> "$AUDIT_SNAPSHOT_LOG"
    exit 0 ;;
  *"state write"*|*"state read"*)
    # chain-runner.sh の record_current_step や resolve_issue_num で呼ばれる
    exit 0 ;;
  *)
    exit 0 ;;
esac
PYSTUB
  chmod +x "$STUB_BIN/python3"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario (C1): step_auto_merge 成功時に audit snapshot hook 発火
# ---------------------------------------------------------------------------

@test "#897-C (C1): auto-merge 成功時に audit snapshot が呼ばれる" {
  create_issue_json 897 "running"

  run bash "$SANDBOX/scripts/chain-runner.sh" auto-merge --issue 897 --pr 900 --branch feat/897-test
  assert_success

  # snapshot 呼出記録を確認
  [ -f "$AUDIT_SNAPSHOT_LOG" ]
  # snapshot コマンドラインに "issue-897" label が含まれる
  grep -qF "audit snapshot" "$AUDIT_SNAPSHOT_LOG"
  grep -qF "issue-897" "$AUDIT_SNAPSHOT_LOG"
  # chain-runner 出力に snapshot メッセージ
  echo "$output" | grep -qF "audit snapshot"
}

# ---------------------------------------------------------------------------
# Scenario (C2): auto-merge.sh 失敗時は snapshot を呼ばない
# ---------------------------------------------------------------------------

@test "#897-C (C2): auto-merge 失敗時は snapshot hook が発火しない" {
  # auto-merge.sh を失敗 stub に置換
  cat > "$SANDBOX/scripts/auto-merge.sh" <<'AMSTUB'
#!/usr/bin/env bash
echo "[auto-merge-stub] merge 失敗" >&2
exit 1
AMSTUB
  chmod +x "$SANDBOX/scripts/auto-merge.sh"

  create_issue_json 897 "running"

  run bash "$SANDBOX/scripts/chain-runner.sh" auto-merge --issue 897 --pr 900 --branch feat/897-test
  assert_failure

  # snapshot は呼ばれていない
  if [[ -s "$AUDIT_SNAPSHOT_LOG" ]]; then
    ! grep -qF "audit snapshot" "$AUDIT_SNAPSHOT_LOG"
  fi
}

# ---------------------------------------------------------------------------
# Scenario (C3): .autopilot dir 不在時は snapshot skip
# ---------------------------------------------------------------------------

@test "#897-C (C3): .autopilot dir 不在時は snapshot skip (no-op、regression 防止)" {
  # .autopilot dir を削除
  rm -rf "$SANDBOX/.autopilot"

  run bash "$SANDBOX/scripts/chain-runner.sh" auto-merge --issue 897 --pr 900 --branch feat/897-test

  # auto-merge 自体は成功
  assert_success
  # snapshot は skip (no record)
  if [[ -s "$AUDIT_SNAPSHOT_LOG" ]]; then
    ! grep -qF "audit snapshot" "$AUDIT_SNAPSHOT_LOG"
  fi
}
