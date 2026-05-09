#!/usr/bin/env bats
# ac-test-1626-pre-bash-hook.bats
#
# Issue #1626: bug(merge-gate): red-only label-based bypass
#
# AC3.1: pre-bash-merge-gate-block.sh を新設
#         （既存 merge-gate-check-merge-override-block.sh のロジックを hook script として再利用 or symlink）
# AC3.2: tool_input.command が regex \bgh\s+pr\s+merge\b にマッチで起動
# AC3.3: 該当 PR の <autopilot-dir>/checkpoints/merge-gate.json を読み:
#         status=PASS のみ通過、FAIL/未存在は REJECT
# AC3.4: TWL_MERGE_GATE_OVERRIDE='<理由>' 設定時のみ通過 + merge-override-audit.log に記録
# AC3.5: bypass 条件は不変条件 R に従い stall recovery のみ許可（content-REJECT override は禁止文書化）
# AC3.6: hook スクリプト不在時の graceful degradation —
#         pre-bash-merge-gate-block.sh が実行できない場合は fail-closed（exit 1）でブロックし、
#         全 Bash tool 呼び出しには影響しないこと
# AC3.8: AC3.7 GREEN 確認後に .claude/settings.json の PreToolUse Bash matcher に登録
# AC3.9: settings.json 登録後の smoke test — gh pr merge を dry-run で実行し hook 発火を確認
#
# RED: 全テストは実装前に fail する

load 'helpers/common'

SCRIPTS_DIR=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC3.1: pre-bash-merge-gate-block.sh 新設
#
# RED: ファイルが存在しないため [ -f ] が fail する
# ===========================================================================

@test "ac3.1: pre-bash-merge-gate-block.sh が存在する" {
  # AC: pre-bash-merge-gate-block.sh を新設
  # RED: ファイルが未作成のため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]
}

@test "ac3.1b: pre-bash-merge-gate-block.sh は merge-gate-check-merge-override-block.sh のロジックを再利用する（静的確認）" {
  # AC: 既存スクリプトのロジックを hook script として再利用 or symlink
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  # symlink か、または merge-gate-check-merge-override-block.sh を source/呼び出すか
  local is_symlink=0
  local references_parent=0
  [ -L "$script" ] && is_symlink=1
  grep -qF 'merge-gate-check-merge-override-block.sh' "$script" 2>/dev/null && references_parent=1

  [ "$is_symlink" -eq 1 ] || [ "$references_parent" -eq 1 ]
}

# ===========================================================================
# AC3.2: tool_input.command が regex \bgh\s+pr\s+merge\b にマッチで起動
#
# RED: スクリプトが存在しないため fail
# ===========================================================================

@test "ac3.2: pre-bash-merge-gate-block.sh は gh pr merge コマンドにマッチするロジックを含む（静的確認）" {
  # AC: tool_input.command が \bgh\s+pr\s+merge\b regex にマッチで起動
  # RED: スクリプトが存在しないため grep fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  run grep -qE 'gh.+pr.+merge|pr merge|gh pr merge' "$script"
  assert_success
}

@test "ac3.2b: pre-bash-merge-gate-block.sh は gh pr merge 以外のコマンドでは起動しない" {
  # AC: gh pr merge 以外（例: gh pr view）では block しないこと
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  # merge-gate.json FAIL 状態でも gh pr view は通過すること
  local mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"FAIL","result":"REJECTED"}\n' > "$mg_json"

  # gh pr view を hook 対象コマンドとして渡す
  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot" --command "gh pr view 1234"
  assert_success
}

# ===========================================================================
# AC3.3: merge-gate.json を読み: status=PASS のみ通過、FAIL/未存在は REJECT
#
# RED: スクリプトが存在しないため fail
# ===========================================================================

@test "ac3.3: pre-bash-merge-gate-block.sh は merge-gate.json status=PASS で通過する" {
  # AC: status=PASS のみ通過
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  local mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"PASS","result":"MERGED"}\n' > "$mg_json"

  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot" --command "gh pr merge 1234"
  assert_success
}

@test "ac3.3b: pre-bash-merge-gate-block.sh は merge-gate.json status=FAIL で REJECT（exit 1）" {
  # AC: FAIL は REJECT
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  local mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"FAIL","result":"REJECTED"}\n' > "$mg_json"

  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot" --command "gh pr merge 1234"
  assert_failure
  [ "$status" -eq 1 ]
}

@test "ac3.3c: pre-bash-merge-gate-block.sh は merge-gate.json 未存在で REJECT（exit 1）" {
  # AC: merge-gate.json 未存在は REJECT（fail-closed）
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  # merge-gate.json を配置しない
  mkdir -p "${SANDBOX}/.autopilot/checkpoints"

  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot" --command "gh pr merge 1234"
  assert_failure
  [ "$status" -eq 1 ]
}

# ===========================================================================
# AC3.4: TWL_MERGE_GATE_OVERRIDE='<理由>' 設定時のみ通過 + audit log に記録
#
# RED: スクリプトが存在しないため fail
# ===========================================================================

@test "ac3.4: pre-bash-merge-gate-block.sh は TWL_MERGE_GATE_OVERRIDE 設定時に通過する" {
  # AC: override 設定時のみ通過
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  local mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"FAIL","result":"REJECTED"}\n' > "$mg_json"

  run bash -c "TWL_MERGE_GATE_OVERRIDE='stall-recovery' bash '$script' --autopilot-dir '${SANDBOX}/.autopilot' --command 'gh pr merge 1234'"
  assert_success
}

@test "ac3.4b: pre-bash-merge-gate-block.sh は override 時に merge-override-audit.log に記録する" {
  # AC: override 通過時に audit log に理由・時刻・user を記録
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  local mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"FAIL","result":"REJECTED"}\n' > "$mg_json"

  run bash -c "TWL_MERGE_GATE_OVERRIDE='stall-recovery' bash '$script' --autopilot-dir '${SANDBOX}/.autopilot' --command 'gh pr merge 1234'"
  assert_success

  local audit_log="${SANDBOX}/.autopilot/merge-override-audit.log"
  [ -f "$audit_log" ]
  run grep -qF 'stall-recovery' "$audit_log"
  assert_success
}

# ===========================================================================
# AC3.5: bypass 条件は不変条件 R に従い stall recovery のみ許可（禁止文書化）
#
# RED: スクリプトにコメント/ドキュメントが存在しないため fail
# ===========================================================================

@test "ac3.5: pre-bash-merge-gate-block.sh に content-REJECT override 禁止の文書化が存在する（静的確認）" {
  # AC: bypass 条件の禁止文書化（stall recovery のみ許可）
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  run grep -qE 'content-REJECT|stall.recovery|REJECT.*override.*禁止|不変条件.*R' "$script"
  assert_success
}

# ===========================================================================
# AC3.6: hook スクリプト不在時の graceful degradation
#         — 実行できない場合は fail-closed（exit 1）でブロック
#         — 全 Bash tool 呼び出しには影響しないこと
#
# RED: スクリプトが存在しないため fail
# ===========================================================================

@test "ac3.6: settings.json の hook 登録は pre-bash-merge-gate-block.sh 存在チェックを含む（静的確認）" {
  # AC: hook スクリプト不在時の graceful degradation
  # RED: settings.json にまだ hook が登録されていない
  local settings="${REPO_ROOT}/../.claude/settings.json"
  # worktree では .claude が REPO_ROOT の上位に存在する可能性がある
  local settings_alt
  settings_alt="$(cd "${REPO_ROOT}" && git rev-parse --show-toplevel 2>/dev/null)/.claude/settings.json"

  local found_settings=""
  for s in "$settings" "$settings_alt"; do
    if [ -f "$s" ]; then
      found_settings="$s"
      break
    fi
  done
  [ -n "$found_settings" ]

  # pre-bash-merge-gate-block.sh が settings.json に登録されていること
  run grep -qF 'pre-bash-merge-gate-block.sh' "$found_settings"
  assert_success
}

@test "ac3.6b: pre-bash-merge-gate-block.sh は gh pr merge にのみ発火し他の Bash コマンドには影響しない" {
  # AC: 全 Bash tool 呼び出しには影響しないこと
  # RED: スクリプトが存在しないため fail
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  local mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"FAIL","result":"REJECTED"}\n' > "$mg_json"

  # gh pr merge 以外のコマンドは通過すること
  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot" --command "ls -la"
  assert_success

  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot" --command "git status"
  assert_success

  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot" --command "echo hello"
  assert_success
}

# ===========================================================================
# AC3.8: .claude/settings.json の PreToolUse Bash matcher に pre-bash-merge-gate-block.sh を登録
#
# RED: AC3.7 GREEN 前なので未登録
# ===========================================================================

@test "ac3.8: .claude/settings.json の PreToolUse hooks に pre-bash-merge-gate-block.sh が登録されている" {
  # AC: settings.json の PreToolUse Bash matcher に登録
  # RED: AC3.7 GREEN 確認前のため未登録
  local settings_candidates=(
    "${REPO_ROOT}/../.claude/settings.json"
    "${REPO_ROOT}/../../.claude/settings.json"
    "${HOME}/.claude/settings.json"
  )

  local found_settings=""
  for s in "${settings_candidates[@]}"; do
    if [ -f "$s" ]; then
      found_settings="$s"
      break
    fi
  done

  [ -n "$found_settings" ]
  run grep -qF 'pre-bash-merge-gate-block.sh' "$found_settings"
  assert_success
}

# ===========================================================================
# AC3.9: settings.json 登録後の smoke test — gh pr merge を dry-run で hook 発火を確認
#
# RED: 登録前のため hook が発火しない
# ===========================================================================

@test "ac3.9: pre-bash-merge-gate-block.sh は REJECT 状態で gh pr merge コマンドを block する（smoke test）" {
  # AC: settings.json 登録後の smoke test — hook 発火確認
  # RED: 登録前のため hook が発火しない
  local script="${SCRIPTS_DIR}/pre-bash-merge-gate-block.sh"
  [ -f "$script" ]

  local mg_json="${SANDBOX}/.autopilot/checkpoints/merge-gate.json"
  mkdir -p "$(dirname "$mg_json")"
  printf '{"status":"FAIL","result":"REJECTED"}\n' > "$mg_json"

  # hook スクリプト単体で gh pr merge コマンドを block することを確認
  run bash "$script" --autopilot-dir "${SANDBOX}/.autopilot" --command "gh pr merge --merge -R shuu5/twill 1234"
  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "BLOCK"
}
