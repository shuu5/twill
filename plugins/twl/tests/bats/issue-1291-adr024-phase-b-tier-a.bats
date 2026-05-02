#!/usr/bin/env bats
# issue-1291-adr024-phase-b-tier-a.bats
#
# TDD RED テスト: ADR-024 Phase B Tier A — pre-bash-refined-label-gate 削除
# Issue #1291
#
# 全テストは実装前に FAIL（RED）する。
# 実装完了後に GREEN になることを意図している。
#
# AC 対応:
#   AC1: pre-bash-refined-label-gate.sh が削除されている
#   AC2: pre-bash-phase3-gate.sh から refined キーワードが消えている
#   AC3: .claude/settings.json から pre-bash-refined-label-gate.sh の hook 登録が消えている
#   AC4: pre-bash-phase3-gate.sh の Phase 3 gate 本体ロジックは機能維持
#   AC5: layer-d-refined-gate.bats が deprecate / skip / 削除されている
#   AC6: gh issue edit --add-label refined が deny されない
#   AC7: deps.yaml から pre-bash-refined-label-gate エントリが削除され twl check が PASS する

load 'helpers/common'

HOOK_GATE_SRC=""
GIT_ROOT=""

setup() {
  common_setup
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  GIT_ROOT="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel)"
  HOOK_GATE_SRC="${REPO_ROOT}/scripts/hooks/pre-bash-phase3-gate.sh"
  export REPO_ROOT GIT_ROOT HOOK_GATE_SRC
}

teardown() {
  common_teardown
}

# Build a Bash tool JSON payload
_bash_payload() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}'
}

# ---------------------------------------------------------------------------
# AC1: pre-bash-refined-label-gate.sh が削除されている
# WHEN plugins/twl/scripts/hooks/pre-bash-refined-label-gate.sh を参照する
# THEN ファイルが存在しない
# RED: 現在ファイルが存在するため FAIL する
# ---------------------------------------------------------------------------
@test "ac1: pre-bash-refined-label-gate.sh が存在しない" {
  # AC: scripts/hooks/pre-bash-refined-label-gate.sh が削除されている
  # RED: 現在ファイルが存在するため FAIL する
  local target="${REPO_ROOT}/scripts/hooks/pre-bash-refined-label-gate.sh"
  if [[ -f "$target" ]]; then
    echo "FAIL: pre-bash-refined-label-gate.sh が存在する（削除されていない）: $target" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC2: pre-bash-phase3-gate.sh から refined キーワードが消えている
# WHEN grep -n refined plugins/twl/scripts/hooks/pre-bash-phase3-gate.sh を実行する
# THEN 0 件である
# RED: 現在 refined キーワードが存在するため FAIL する
# ---------------------------------------------------------------------------
@test "ac2: pre-bash-phase3-gate.sh に refined キーワードが存在しない" {
  # AC: grep -n refined pre-bash-phase3-gate.sh が 0 件
  # RED: 現在 refined キーワードが複数行に存在するため FAIL する
  [[ -f "$HOOK_GATE_SRC" ]] || { echo "pre-bash-phase3-gate.sh not found: $HOOK_GATE_SRC" >&2; return 1; }
  local count
  count=$(grep -c "refined" "$HOOK_GATE_SRC" 2>/dev/null || echo "0")
  if [[ "$count" -gt 0 ]]; then
    echo "FAIL: pre-bash-phase3-gate.sh に refined キーワードが ${count} 件残存している" >&2
    grep -n "refined" "$HOOK_GATE_SRC" >&2
    return 1
  fi
}

@test "ac2: pre-bash-phase3-gate.sh の refined 条件分岐ロジックが消えている" {
  # AC: --add-label.*refined のパターンマッチが消えている
  # RED: 現在このパターンが存在するため FAIL する
  [[ -f "$HOOK_GATE_SRC" ]] || { echo "pre-bash-phase3-gate.sh not found" >&2; return 1; }
  if grep -qE "(--add-label|--label)[^;|&]*\\brefined\\b" "$HOOK_GATE_SRC"; then
    echo "FAIL: pre-bash-phase3-gate.sh に refined ラベルマッチングロジックが残存している" >&2
    grep -n "refined" "$HOOK_GATE_SRC" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC3: .claude/settings.json から pre-bash-refined-label-gate.sh の hook 登録が消えている
# WHEN .claude/settings.json を参照する
# THEN pre-bash-refined-label-gate.sh の登録エントリが存在しない
# RED: 現在 L51-53 付近にエントリが存在するため FAIL する
# ---------------------------------------------------------------------------
@test "ac3: settings.json に pre-bash-refined-label-gate.sh エントリが存在しない" {
  # AC: .claude/settings.json から pre-bash-refined-label-gate.sh の hook 登録が消えている
  # RED: 現在エントリが存在するため FAIL する
  local settings="${GIT_ROOT}/.claude/settings.json"
  [[ -f "$settings" ]] || { echo "settings.json not found: $settings" >&2; return 1; }
  if grep -q "pre-bash-refined-label-gate" "$settings"; then
    echo "FAIL: settings.json に pre-bash-refined-label-gate.sh エントリが残存している" >&2
    grep -n "pre-bash-refined-label-gate" "$settings" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC4: pre-bash-phase3-gate.sh の Phase 3 gate 本体ロジックは機能維持
# WHEN pre-bash-phase3-gate.sh を実行する（refined なし、SESSION_ID なし）
#   AND gh issue create コマンドを渡す
#   AND SESSION_ID が空の場合（gate state ファイルなし）
# THEN exit 0 で通過する（SESSION_ID なし → co-issue 外 → allow）
#
# AND gh issue create に SESSION_ID + gate state ファイルあり（phase3_completed=false）
# THEN deny が発生する
#
# RED: AC2 が未実装（refined が残存）のため、refined 関連コードが存在する状態での動作確認
#      実装後は refined キーワードが消えた状態で phase3 gate の deny ロジックのみ維持されることを確認
# ---------------------------------------------------------------------------
@test "ac4: phase3-gate が refined なしかつ SESSION_ID なし環境で gh issue create を allow する" {
  # AC: AC2 実装済み（refined 削除済み）かつ SESSION_ID 不在時（co-issue 外）は通過する
  # RED: AC2 未実装のため refined ロジックが残存している — この前提チェックで FAIL する
  [[ -f "$HOOK_GATE_SRC" ]] || { echo "pre-bash-phase3-gate.sh not found" >&2; return 1; }

  # AC2 が未実装（refined が残存）の場合は FAIL とする
  if grep -q "refined" "$HOOK_GATE_SRC"; then
    echo "FAIL: AC2 未実装 — pre-bash-phase3-gate.sh に refined キーワードが残存している。" >&2
    echo "      AC4 は AC2 実装完了後に GREEN になる。" >&2
    return 1
  fi

  # AC2 実装後のみ到達するロジック
  local payload
  payload=$(_bash_payload "gh issue create --title 'test' --body 'body'")
  run bash -c "echo '$payload' | CLAUDE_SESSION_ID='' SESSION_ID='' bash '$HOOK_GATE_SRC'"
  [ "$status" -eq 0 ]
}

@test "ac4: phase3-gate が refined なし状態で gh issue create の deny ロジックを保持する" {
  # AC: SESSION_ID + gate state ファイル（phase3_completed=false）で deny が発生する
  # RED: AC2 未実装（refined が残存）のため現在は refined 付き実装が存在する
  #      実装後は refined ロジックが消えた状態で phase3 gate の deny ロジックのみが機能すること
  [[ -f "$HOOK_GATE_SRC" ]] || { echo "pre-bash-phase3-gate.sh not found" >&2; return 1; }

  # AC2 が実装済みである（refined が消えている）ことを前提にする
  # 現在 refined が残存しているため、この前提チェックで FAIL する
  if grep -q "refined" "$HOOK_GATE_SRC"; then
    echo "FAIL: AC2 未実装 — pre-bash-phase3-gate.sh に refined キーワードが残存している。" >&2
    echo "      AC4 は AC2 実装完了後に GREEN になる。" >&2
    return 1
  fi

  # AC2 実装後のみ到達するロジック
  # SESSION_ID + phase3 gate ファイル（phase3_completed=false）で deny が発生することを確認
  local test_session_id="test-session-ac4-1291"
  local cksum
  cksum=$(printf '%s' "$test_session_id" | cksum | awk '{print $1}')
  local gate_file="/tmp/.co-issue-phase3-gate-${cksum}.json"
  echo '{"phase3_completed":false}' > "$gate_file"

  local payload
  payload=$(_bash_payload "gh issue create --title 'test'")
  local output
  output=$(echo "$payload" | CLAUDE_SESSION_ID="$test_session_id" bash "$HOOK_GATE_SRC")
  local exit_code=$?

  rm -f "$gate_file"

  [ "$exit_code" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    || { echo "FAIL: phase3 gate が deny しなかった: $output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# AC5: layer-d-refined-gate.bats が deprecate / skip / 削除されている
# WHEN plugins/twl/tests/bats/layer-d-refined-gate.bats を確認する
# THEN ファイルが削除されている、またはファイル内に skip/deprecated 宣言がある
# RED: 現在 layer-d-refined-gate.bats が通常の active テストとして存在するため FAIL する
# ---------------------------------------------------------------------------
@test "ac5: layer-d-refined-gate.bats が削除またはskip/deprecate されている" {
  # AC: layer-d-refined-gate.bats が deprecate / skip / 削除されているいずれかの状態
  # RED: 現在 layer-d-refined-gate.bats が active テストとして存在するため FAIL する
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_file="${this_dir}/layer-d-refined-gate.bats"

  # ファイルが削除されている場合はこのテストを PASS
  if [[ ! -f "$bats_file" ]]; then
    return 0
  fi

  # ファイルが存在する場合は、skip または deprecated 宣言を確認する
  # skip_all, BATS_TEST_SKIP, # DEPRECATED, # SKIP などのいずれかが含まれることを期待する
  if grep -qE "^[[:space:]]*(skip_all|BATS_TEST_SKIP|# DEPRECATED|# SKIP|# deprecated|# skip)" "$bats_file"; then
    return 0
  fi

  echo "FAIL: layer-d-refined-gate.bats が active テストとして存在する（削除/skip/deprecate されていない）" >&2
  echo "      ファイルパス: $bats_file" >&2
  return 1
}

# ---------------------------------------------------------------------------
# AC6: gh issue edit --add-label refined が deny されない
# WHEN pre-bash-phase3-gate.sh に gh issue edit --add-label refined を渡す
#   AND SESSION_ID が空の場合（co-issue 外）
# THEN deny されない（exit 0、permissionDecision != deny）
# RED: 現在 pre-bash-phase3-gate.sh に refined ロジックが残存しているため、
#      SESSION_ID なしでも deny されない（通過する）ことになる — ただし AC2 実装後に
#      refined ロジックが消えた状態での確認が必要
#      AC2 未実装を RED 条件として組み込む
# ---------------------------------------------------------------------------
@test "ac6: SESSION_ID なし環境で gh issue edit --add-label refined が deny されない" {
  # AC: pre-bash-phase3-gate.sh の refined チェックが消えた後、
  #     SESSION_ID なし環境で gh issue edit --add-label refined が通過する
  # RED: AC2 未実装のため refined ロジックが残存している
  #      このテストは AC2 実装完了（refined ロジック削除）を前提にする
  [[ -f "$HOOK_GATE_SRC" ]] || { echo "pre-bash-phase3-gate.sh not found" >&2; return 1; }

  # AC2 が未実装（refined が残存）の場合は FAIL とする
  if grep -q "refined" "$HOOK_GATE_SRC"; then
    echo "FAIL: AC2 未実装 — pre-bash-phase3-gate.sh に refined キーワードが残存している。" >&2
    echo "      AC6 の前提条件（refined ロジック削除）が満たされていない。" >&2
    return 1
  fi

  # AC2 実装後のみ到達するロジック
  # SESSION_ID なしで gh issue edit --add-label refined を実行し、deny されないことを確認
  local payload
  payload=$(_bash_payload "gh issue edit 1291 --add-label refined")
  local output
  output=$(echo "$payload" | CLAUDE_SESSION_ID='' SESSION_ID='' bash "$HOOK_GATE_SRC")
  local exit_code=$?

  [ "$exit_code" -eq 0 ]
  # deny 出力がないことを確認
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "FAIL: gh issue edit --add-label refined が deny された（通過すべき）: $output" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC7: deps.yaml から pre-bash-refined-label-gate エントリが削除されている
# WHEN plugins/twl/deps.yaml を確認する
# THEN pre-bash-refined-label-gate エントリが存在しない
# RED: 現在エントリが存在するため FAIL する
# ---------------------------------------------------------------------------
@test "ac7: deps.yaml に pre-bash-refined-label-gate エントリが存在しない" {
  # AC: deps.yaml から pre-bash-refined-label-gate エントリが削除されている
  # RED: 現在エントリが存在するため FAIL する
  local deps_yaml="${REPO_ROOT}/deps.yaml"
  [[ -f "$deps_yaml" ]] || { echo "deps.yaml not found: $deps_yaml" >&2; return 1; }
  if grep -q "pre-bash-refined-label-gate" "$deps_yaml"; then
    echo "FAIL: deps.yaml に pre-bash-refined-label-gate エントリが残存している" >&2
    grep -n "pre-bash-refined-label-gate" "$deps_yaml" >&2
    return 1
  fi
}
