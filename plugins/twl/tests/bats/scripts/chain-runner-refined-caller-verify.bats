#!/usr/bin/env bats
# chain-runner-refined-caller-verify.bats
# Requirement: Issue #1567 — chain-runner.sh step_board_status_update に
#              _verify_refined_caller を追加し、Refined ステータスへの遷移を
#              認可 caller のみに制限する
# Coverage: --type=integration --coverage=chain-runner

load '../helpers/common'

setup() {
  common_setup

  CR="$SANDBOX/scripts/chain-runner.sh"
  export CR

  # REFINED_STATUS_GATE_LOG を bats テスト用パスに override
  REFINED_STATUS_GATE_LOG="$SANDBOX/refined-status-gate.log"
  export REFINED_STATUS_GATE_LOG
  : > "$REFINED_STATUS_GATE_LOG"

  GH_LOG="$SANDBOX/gh-calls.log"
  export GH_LOG
  : > "$GH_LOG"

  PYTHON_REAL=$(command -v python3)
  export PYTHON_REAL

  _setup_stubs
}

teardown() {
  common_teardown
}

# python3 + gh の共通スタブ（board-status-update の gh 呼び出しを通過させる）
_setup_stubs() {
  # python3 stub: resolve-project のみモック。他は実体に委譲
  cat > "$STUB_BIN/python3" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"twl.autopilot.github resolve-project"*)
    cat <<'JSON'
{"project_num":"99","project_id":"PVT_mock","owner":"shuu5","repo_name":"twill","repo_fullname":"shuu5/twill"}
JSON
    exit 0
    ;;
  *)
    exec "$PYTHON_REAL" "\$@"
    ;;
esac
EOF
  chmod +x "$STUB_BIN/python3"

  # gh stub: 正常系を返す（board-status-update の gh 呼び出しを通過させる）
  cat > "$STUB_BIN/gh" <<EOF
#!/usr/bin/env bash
echo "gh: \$*" >> "$GH_LOG"
case "\$*" in
  "project list"*)
    echo '[]'
    exit 0
    ;;
  "project item-add"*)
    echo '{"id":"PVTI_mock_item"}'
    exit 0
    ;;
  "project field-list"*)
    cat <<'JSON'
{"fields":[{"name":"Status","id":"PVTSSF_mock","options":[{"name":"Refined","id":"opt_refined"},{"name":"In Progress","id":"opt_in_progress"},{"name":"Todo","id":"opt_todo"}]}]}
JSON
    exit 0
    ;;
  "project item-edit"*)
    exit 0
    ;;
  "project item-list"*)
    cat <<'JSON'
{"items":[]}
JSON
    exit 0
    ;;
  "issue view"*)
    echo '{"body":"","number":9001}'
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
}

# ===========================================================================
# Structural RED: _verify_refined_caller が chain-runner.sh に定義されている
# ===========================================================================

@test "structural: chain-runner.sh に _verify_refined_caller 関数が定義されている" {
  # RED: 実装前は関数が存在しないため grep が失敗する
  grep -q "_verify_refined_caller()" "$CR"
}

# ===========================================================================
# AC1: target_status != "Refined" のとき caller verify を skip する
# ===========================================================================

@test "ac1: target_status=In Progress のとき caller verify は skip される（log エントリなし）" {
  TWL_CALLER_AUTHZ="" \
    run bash "$CR" board-status-update 9001 "In Progress"

  assert_success
  # Refined ではないので DENY log は書かれない
  if [[ -s "$REFINED_STATUS_GATE_LOG" ]]; then
    run grep "chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
    assert_failure
  fi
}

@test "ac1-regression: target_status=Done のとき caller verify は skip される" {
  TWL_CALLER_AUTHZ="" \
    run bash "$CR" board-status-update 9001 "Done"

  assert_success
  if [[ -s "$REFINED_STATUS_GATE_LOG" ]]; then
    run grep "chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
    assert_failure
  fi
}

# ===========================================================================
# AC2+AC6 scenarios 1-4: 認可 caller → allow（DENY log なし）
# ===========================================================================

@test "ac2-s1: TWL_CALLER_AUTHZ=workflow-issue-refine + Refined → allow" {
  # RED: _verify_refined_caller 未実装のため、この経路が正しく認可されているか検証不可
  # 実装後: DENY log なし + exit 0
  TWL_CALLER_AUTHZ="workflow-issue-refine" \
    run bash "$CR" board-status-update 9001 "Refined"

  assert_success
  # 認可 caller なので DENY は記録されない
  run grep -F "DENY chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
  assert_failure
}

@test "ac2-s2: TWL_CALLER_AUTHZ=workflow-issue-lifecycle + Refined → allow" {
  TWL_CALLER_AUTHZ="workflow-issue-lifecycle" \
    run bash "$CR" board-status-update 9001 "Refined"

  assert_success
  run grep -F "DENY chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
  assert_failure
}

@test "ac2-s3: TWL_CALLER_AUTHZ=co-autopilot + Refined → allow" {
  TWL_CALLER_AUTHZ="co-autopilot" \
    run bash "$CR" board-status-update 9001 "Refined"

  assert_success
  run grep -F "DENY chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
  assert_failure
}

@test "ac2-s4: TWL_CALLER_AUTHZ=manual-override + Refined → allow" {
  TWL_CALLER_AUTHZ="manual-override" \
    run bash "$CR" board-status-update 9001 "Refined"

  assert_success
  run grep -F "DENY chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
  assert_failure
}

# ===========================================================================
# AC3+AC4+AC6 scenario 5: TWL_CALLER_AUTHZ="" → deny + chain 継続 + log
# ===========================================================================

@test "ac3-s5: TWL_CALLER_AUTHZ=空 + Refined → deny, chain 継続 (exit 0), stderr エラー, log 記録" {
  # RED: _verify_refined_caller 未実装のため log が記録されず assert_failure
  TWL_CALLER_AUTHZ="" \
    run bash "$CR" board-status-update 9001 "Refined"

  # chain は中断しない（step 全体は return 0 = exit 0）
  assert_success

  # log に DENY が記録される（RED: 記録されないため fail）
  run grep -F "DENY chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
  assert_success
}

@test "ac4-s5: DENY log フォーマット検証（ISO8601 UTC + issue + caller_authz + pid + ppid）" {
  # RED: ログ自体が存在しないため fail
  TWL_CALLER_AUTHZ="" \
    run bash "$CR" board-status-update 9001 "Refined"

  # ログに ISO8601 UTC タイムスタンプ + issue=#9001 + caller_authz="" が含まれる
  run grep -E "\[20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\] DENY chain-runner-caller-verify issue=#9001" \
    "$REFINED_STATUS_GATE_LOG"
  assert_success

  # pid= と ppid= フィールドが存在する
  run grep -F "pid=" "$REFINED_STATUS_GATE_LOG"
  assert_success
  run grep -F "ppid=" "$REFINED_STATUS_GATE_LOG"
  assert_success
}

# ===========================================================================
# AC3+AC6 scenario 6: TWL_CALLER_AUTHZ=unknown-caller → deny + chain 継続
# ===========================================================================

@test "ac3-s6: TWL_CALLER_AUTHZ=unknown-caller + Refined → deny, chain 継続, log 記録" {
  # RED: _verify_refined_caller 未実装のため log が記録されず fail
  TWL_CALLER_AUTHZ="unknown-caller" \
    run bash "$CR" board-status-update 9001 "Refined"

  assert_success  # chain は中断しない

  run grep -F "DENY chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
  assert_success

  # caller_authz="unknown-caller" が記録される
  run grep -F 'caller_authz="unknown-caller"' "$REFINED_STATUS_GATE_LOG"
  assert_success
}

@test "ac3-stderr: 非認可 caller の場合 stderr に actionable error message が出力される" {
  # RED: _verify_refined_caller 未実装のため stderr が空
  TWL_CALLER_AUTHZ="" \
    run bash "$CR" board-status-update 9001 "Refined"

  # stderr に 4 認可 caller の値が含まれる
  assert_output --partial "workflow-issue-refine"
  assert_output --partial "workflow-issue-lifecycle"
  assert_output --partial "co-autopilot"
  assert_output --partial "manual-override"
}

# ===========================================================================
# AC5+AC6 scenario 7: SKIP_REFINED_CALLER_VERIFY=1 + SKIP_REFINED_REASON → BYPASS
# ===========================================================================

@test "ac5-s7: SKIP_REFINED_CALLER_VERIFY=1 + SKIP_REFINED_REASON='test reason' → BYPASS allow + log" {
  # RED: bypass ロジック未実装のため BYPASS log が記録されず fail
  SKIP_REFINED_CALLER_VERIFY=1 SKIP_REFINED_REASON="test reason" TWL_CALLER_AUTHZ="" \
    run bash "$CR" board-status-update 9001 "Refined"

  assert_success

  # BYPASS が log に記録される
  run grep -F "BYPASS" "$REFINED_STATUS_GATE_LOG"
  assert_success
}

# ===========================================================================
# AC5+AC6 scenario 8: SKIP_REFINED_CALLER_VERIFY=1 のみ (reason 欠落) → deny
# ===========================================================================

@test "ac5-s8: SKIP_REFINED_CALLER_VERIFY=1 のみ (SKIP_REFINED_REASON 欠落) → deny (BYPASS 不可)" {
  # RED: bypass ロジック未実装のため DENY が log されず fail
  # reason 欠落の場合は bypass を許可せず DENY する（不変条件 P と同 form factor）
  SKIP_REFINED_CALLER_VERIFY=1 TWL_CALLER_AUTHZ="" \
    run bash "$CR" board-status-update 9001 "Refined"

  assert_success  # chain は継続する

  # BYPASS は記録されない（DENY が記録される）
  run grep -F "BYPASS" "$REFINED_STATUS_GATE_LOG"
  assert_failure

  run grep -F "DENY chain-runner-caller-verify" "$REFINED_STATUS_GATE_LOG"
  assert_success
}
