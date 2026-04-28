#!/usr/bin/env bats
# autopilot-launch-label-fallback-dry.bats
#
# Issue #1004: _check_refined_status の label fallback ブロック DRY 化
# Board 取得失敗 path と Board 未登録 path の label fallback ロジックが
# _check_label_fallback ヘルパーに集約されていることを検証する。
#
# AC1: _check_label_fallback 関数が autopilot-launch.sh に定義されていること
# AC2: label fallback のインライン重複ロジックが解消されていること（2 → ≤ 1 箇所）
# AC3: _check_label_fallback が DENY_API_FAILURE トークンで正しく動作すること
# AC4: _check_label_fallback が DENY_NOT_ON_BOARD トークンで正しく動作すること
#
# RED: 全テストは _check_label_fallback 未抽出状態で fail する

load '../helpers/common'

SCRIPT=""

# _run_label_fallback <issue_num> <deny_log_token> <deny_msg>
# autopilot-launch.sh から _check_label_fallback を動的抽出して呼び出す
_run_label_fallback() {
  local issue_num="$1"
  local deny_log_token="$2"
  local deny_msg="$3"

  local func_def
  func_def=$(sed -n '/^_check_label_fallback()/,/^}/p' "$SCRIPT")

  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:/usr/bin:/bin'
export _STATUS_GATE_LOG='${SANDBOX}/gate.log'

${func_def}

_check_label_fallback '${issue_num}' '${deny_log_token}' '${deny_msg}'
"
}

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/autopilot-launch.sh"
  : > "$SANDBOX/gate.log"
  stub_command "git" 'echo "stub-git"'
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: _check_label_fallback 関数が autopilot-launch.sh に定義されていること
# RED: 現在の実装には _check_label_fallback が存在しないため grep が失敗する
# ===========================================================================

@test "ac1: _check_label_fallback 関数が autopilot-launch.sh に定義されている" {
  # RED: 関数定義がまだ存在しない
  run grep -n '^_check_label_fallback()' "$SCRIPT"
  assert_success
}

# ===========================================================================
# AC2: label fallback インラインロジックの重複が解消されていること
# RED: 現在は Board 取得失敗 path と Board 未登録 path の両方に
#      labels=$(gh issue view ...) が存在する（count=2）
# PASS 条件（実装後）: count が ≤ 1（helper 内に集約）
# ===========================================================================

@test "ac2: label fallback インライン取得ロジックが重複していない（2 箇所 → ≤ 1 箇所）" {
  local inline_count
  inline_count=$(grep -c 'labels=\$(gh issue view.*--json labels' "$SCRIPT" 2>/dev/null || echo "0")
  # RED: 現在は 2 箇所存在するためこのチェックが fail する
  [ "$inline_count" -le 1 ] || {
    echo "FAIL: label fallback インライン重複が ${inline_count} 箇所あります（期待: ≤ 1）"
    grep -n 'labels=\$(gh issue view.*--json labels' "$SCRIPT"
    return 1
  }
}

# ===========================================================================
# AC3: _check_label_fallback が DENY_API_FAILURE トークンで正しく動作すること
# ===========================================================================

@test "ac3: _check_label_fallback — refined label なし → DENY_API_FAILURE をログに記録して return 1" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json labels"*)
    echo ""
    exit 0 ;;
  *)
    exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  _run_label_fallback "1004" "DENY_API_FAILURE" "Error: API 障害"

  # RED: 関数未定義のため exit 127、[ "$status" -eq 1 ] で fail する
  # PASS 条件（実装後）: exit 1 で DENY
  assert_failure
  [ "$status" -eq 1 ]
  run grep -F "DENY_API_FAILURE issue=#1004" "$SANDBOX/gate.log"
  assert_success
}

@test "ac3: _check_label_fallback — refined label あり → ALLOW_LABEL_FALLBACK をログに記録して return 0" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json labels"*)
    printf 'bug\nrefined\n'
    exit 0 ;;
  *)
    exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  _run_label_fallback "1004" "DENY_API_FAILURE" "Error: API 障害"

  # RED: 関数未定義のため exit 127、assert_success が fail する
  # PASS 条件（実装後）: exit 0 で ALLOW
  assert_success
  run grep -F "ALLOW_LABEL_FALLBACK issue=#1004" "$SANDBOX/gate.log"
  assert_success
}

# ===========================================================================
# AC4: _check_label_fallback が DENY_NOT_ON_BOARD トークンで正しく動作すること
# ===========================================================================

@test "ac4: _check_label_fallback — refined label なし → DENY_NOT_ON_BOARD をログに記録して return 1" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json labels"*)
    echo ""
    exit 0 ;;
  *)
    exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  _run_label_fallback "1004" "DENY_NOT_ON_BOARD" "Error: Board 未登録"

  # RED: 関数未定義のため exit 127、[ "$status" -eq 1 ] で fail する
  # PASS 条件（実装後）: exit 1 で DENY
  assert_failure
  [ "$status" -eq 1 ]
  run grep -F "DENY_NOT_ON_BOARD issue=#1004" "$SANDBOX/gate.log"
  assert_success
}

@test "ac4: _check_label_fallback — refined label あり → ALLOW_LABEL_FALLBACK をログに記録して return 0" {
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json labels"*)
    printf 'bug\nrefined\n'
    exit 0 ;;
  *)
    exit 1 ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  _run_label_fallback "1004" "DENY_NOT_ON_BOARD" "Error: Board 未登録"

  # RED: 関数未定義のため exit 127、assert_success が fail する
  # PASS 条件（実装後）: exit 0 で ALLOW
  assert_success
  run grep -F "ALLOW_LABEL_FALLBACK issue=#1004" "$SANDBOX/gate.log"
  assert_success
}
