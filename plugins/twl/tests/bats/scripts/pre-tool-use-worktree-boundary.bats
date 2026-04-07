#!/usr/bin/env bats
# pre-tool-use-worktree-boundary.bats
#
# Tests for plugins/twl/scripts/hooks/pre-tool-use-worktree-boundary.sh
#
# Spec: Issue #133 — Worker worktree 境界 pre-edit guard
#
# Scenarios:
#   1. AUTOPILOT_DIR 未設定 → no-op (exit 0, stdout 空)
#   2. AUTOPILOT_DIR 設定 + worktree 内 absolute path → allow (exit 0, stdout 空)
#   3. AUTOPILOT_DIR 設定 + worktree 外 absolute path → deny JSON
#   4. worktree 内 → 外への symlink → deny
#   5. 未存在ファイルの Write (worktree 内, 新規) → allow (realpath -m)
#   6. NotebookEdit (notebook_path) → 同様に判定
#   7. worktree root と完全一致するパス → 誤 deny しない
#   8. prefix 末尾スラッシュ誤マッチ回避 (/foo vs /foobar)
#   9. 対象外 tool (Read など) → no-op
#  10. JSON パース失敗 → no-op
#  11. file_path 空 → no-op

load '../helpers/common'

HOOK_SRC=""

setup() {
  common_setup

  # Resolve absolute path to the hook under test
  HOOK_SRC="$(cd "$REPO_ROOT" && pwd)/scripts/hooks/pre-tool-use-worktree-boundary.sh"

  # SANDBOX を仮想 worktree root として扱うため git stub を仕込む
  # rev-parse --show-toplevel が SANDBOX を返すようにする
  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*)
        echo "'"$SANDBOX"'" ;;
      *)
        exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# Helper: invoke hook with given JSON payload
_run_hook() {
  local payload="$1"
  echo "$payload" | bash "$HOOK_SRC"
}

# ---------------------------------------------------------------------------
# Scenario 1: AUTOPILOT_DIR 未設定 → no-op
# ---------------------------------------------------------------------------
@test "no-op when AUTOPILOT_DIR is unset" {
  unset AUTOPILOT_DIR
  local payload
  payload=$(jq -nc --arg p "/etc/passwd" '{tool_name:"Edit", tool_input:{file_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 2: worktree 内 absolute path → allow (no output)
# ---------------------------------------------------------------------------
@test "allow when target is inside worktree (absolute path)" {
  local target="$SANDBOX/src/foo.txt"
  mkdir -p "$(dirname "$target")"
  : > "$target"
  local payload
  payload=$(jq -nc --arg p "$target" '{tool_name:"Edit", tool_input:{file_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 3: worktree 外 absolute path → deny
# ---------------------------------------------------------------------------
@test "deny when target is outside worktree (absolute path)" {
  local outside
  outside="$(mktemp -d)/outside.txt"
  : > "$outside"
  local payload
  payload=$(jq -nc --arg p "$outside" '{tool_name:"Write", tool_input:{file_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("不変条件 B")'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("target=")'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("resolved=")'
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("worktree=")'
  rm -f "$outside"
}

# ---------------------------------------------------------------------------
# Scenario 4: symlink within worktree pointing outside → deny
# ---------------------------------------------------------------------------
@test "deny when symlink inside worktree resolves outside" {
  local outside_dir
  outside_dir="$(mktemp -d)"
  : > "$outside_dir/secret.txt"
  local link="$SANDBOX/link-to-secret"
  ln -s "$outside_dir/secret.txt" "$link"

  local payload
  payload=$(jq -nc --arg p "$link" '{tool_name:"Edit", tool_input:{file_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "$outside_dir"
}

# ---------------------------------------------------------------------------
# Scenario 5: 未存在ファイル (新規 Write, worktree 内) → allow
# ---------------------------------------------------------------------------
@test "allow new (non-existent) file inside worktree (realpath -m)" {
  local target="$SANDBOX/new/dir/never-created.txt"
  local payload
  payload=$(jq -nc --arg p "$target" '{tool_name:"Write", tool_input:{file_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 6: NotebookEdit uses notebook_path
# ---------------------------------------------------------------------------
@test "NotebookEdit: deny when notebook_path is outside worktree" {
  local outside
  outside="$(mktemp -d)/nb.ipynb"
  : > "$outside"
  local payload
  payload=$(jq -nc --arg p "$outside" '{tool_name:"NotebookEdit", tool_input:{notebook_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -f "$outside"
}

@test "NotebookEdit: allow when notebook_path is inside worktree" {
  local target="$SANDBOX/notebook.ipynb"
  : > "$target"
  local payload
  payload=$(jq -nc --arg p "$target" '{tool_name:"NotebookEdit", tool_input:{notebook_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 7: worktree root と完全一致 (誤 deny しない)
# ---------------------------------------------------------------------------
@test "allow target equal to worktree root itself" {
  local payload
  payload=$(jq -nc --arg p "$SANDBOX" '{tool_name:"Edit", tool_input:{file_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 8: prefix 末尾スラッシュ誤マッチ回避
# ---------------------------------------------------------------------------
@test "deny when target shares string prefix but is sibling dir (slash boundary)" {
  # Sibling dir whose name starts with the worktree root's basename
  local sibling="${SANDBOX}-sibling/file.txt"
  mkdir -p "$(dirname "$sibling")"
  : > "$sibling"
  local payload
  payload=$(jq -nc --arg p "$sibling" '{tool_name:"Edit", tool_input:{file_path:$p}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  rm -rf "${SANDBOX}-sibling"
}

# ---------------------------------------------------------------------------
# Scenario 9: 対象外 tool → no-op
# ---------------------------------------------------------------------------
@test "no-op for non-target tools (Read)" {
  local payload
  payload=$(jq -nc '{tool_name:"Read", tool_input:{file_path:"/etc/passwd"}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 10: 不正 JSON → no-op
# ---------------------------------------------------------------------------
@test "no-op when payload is invalid JSON" {
  run _run_hook "not-a-json{"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 11: file_path empty → no-op
# ---------------------------------------------------------------------------
@test "no-op when file_path is empty" {
  local payload
  payload=$(jq -nc '{tool_name:"Edit", tool_input:{}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
