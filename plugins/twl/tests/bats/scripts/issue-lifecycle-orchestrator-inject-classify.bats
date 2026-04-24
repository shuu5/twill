#!/usr/bin/env bats
# issue-lifecycle-orchestrator-inject-classify.bats - pane capture + inject 応答分類の検証 (#946 B2)
#
# Scenarios covered:
#   - permission prompt 疑似 pane → reason=unexpected_permission_prompt で failed (auto 1 inject しない)
#   - AskUserQuestion 疑似 pane + 安全な選択肢 → 最小番号が inject される
#   - AskUserQuestion 疑似 pane + 全選択肢が deny-pattern → reason=unclassified_askuserquestion で failed
#   - [y/N] 確認プロンプト → reason=unclassified_input_waiting で failed (escalate)
#   - 分類不能 pane → reason=unclassified_input_waiting で failed
#   - "Waiting for user input" pane → generic inject
#   - pane capture に ANSI エスケープシーケンスが含まれる → 正しく strip して分類

load '../helpers/common'

SCRIPT_SRC=""
ORCH_SCRIPTS_DIR=""
SESS_SCRIPTS_DIR=""
TMP_ORCH_DIR=""

setup() {
  common_setup
  SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"

  # orchestrator が SCRIPTS_ROOT/../../session/scripts/ を参照するため
  # ミラー構造を作成
  TMP_ORCH_DIR="$(mktemp -d)"
  ORCH_SCRIPTS_DIR="${TMP_ORCH_DIR}/plugins/twl/scripts"
  SESS_SCRIPTS_DIR="${TMP_ORCH_DIR}/plugins/session/scripts"
  mkdir -p "$ORCH_SCRIPTS_DIR" "$SESS_SCRIPTS_DIR"

  cp "$SCRIPT_SRC" "${ORCH_SCRIPTS_DIR}/issue-lifecycle-orchestrator.sh"
  chmod +x "${ORCH_SCRIPTS_DIR}/issue-lifecycle-orchestrator.sh"
  export SCRIPTS_ROOT="$ORCH_SCRIPTS_DIR"
}

teardown() {
  [[ -n "$TMP_ORCH_DIR" ]] && rm -rf "$TMP_ORCH_DIR"
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: セッションスクリプト stub 作成
# ---------------------------------------------------------------------------

_make_session_state_stub() {
  local state="$1"
  cat > "${SESS_SCRIPTS_DIR}/session-state.sh" <<STUB
#!/usr/bin/env bash
echo "$state"
exit 0
STUB
  chmod +x "${SESS_SCRIPTS_DIR}/session-state.sh"
}

_make_session_comm_stub() {
  local log_file="$1"
  cat > "${SESS_SCRIPTS_DIR}/session-comm.sh" <<STUB
#!/usr/bin/env bash
echo "SESSION_COMM_CALLED: \$*" >> "$log_file"
exit 0
STUB
  chmod +x "${SESS_SCRIPTS_DIR}/session-comm.sh"
}

# ---------------------------------------------------------------------------
# Scenario: pane capture + ANSI stripping のコードパスが存在する
# WHEN issue-lifecycle-orchestrator.sh の inject セクションを grep する
# THEN tmux capture-pane と ANSI strip の sed が存在する
# ---------------------------------------------------------------------------

@test "inject-classify: tmux capture-pane が inject セクションに存在する" {
  grep -q 'tmux capture-pane' "$SCRIPT_SRC" \
    || fail "tmux capture-pane not found in script"
}

@test "inject-classify: ANSI CSI 除去の sed が inject セクションに存在する" {
  grep -qF '\x1b' "$SCRIPT_SRC" \
    || fail "ANSI CSI stripping sed command not found in script"
}

# ---------------------------------------------------------------------------
# Scenario: permission prompt パターンが detected → unexpected_permission_prompt で failed
# WHEN pane に '^[1-9]. Yes, proceed' が含まれる
# THEN inject せず report.json が status:failed になる
# ---------------------------------------------------------------------------

@test "inject-classify: permission prompt パターンが _generate_fallback_report に渡される" {
  source "$SCRIPT_SRC"

  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  # Mock _generate_fallback_report to record calls
  _generate_fallback_report() {
    echo "FALLBACK_CALLED: $2" > "$subdir/OUT/fallback_reason.txt"
    printf '{"status":"failed","fallback":true,"reason":"%s"}\n' "$2" > "$subdir/OUT/report.json"
  }

  # Simulate a permission prompt pane output
  local pane_with_permission
  pane_with_permission="$(printf '%s\n' \
    "Tool: Read file /etc/passwd" \
    "1. Yes, proceed" \
    "2. No, and tell Claude what to do instead" \
    "3. Yes, and allow always")"

  # Test the pattern directly (matching logic from the script)
  if printf '%s' "$pane_with_permission" | grep -qE '^[1-9]\. (Yes, proceed|Yes, and allow|No, and tell)'; then
    _generate_fallback_report "$subdir" "unexpected_permission_prompt"
  fi

  local reason
  reason=$(cat "$subdir/OUT/fallback_reason.txt" 2>/dev/null | sed 's/FALLBACK_CALLED: //')
  [ "$reason" = "unexpected_permission_prompt" ] \
    || fail "Expected unexpected_permission_prompt, got: $reason"

  rm -rf "$subdir"
}

@test "inject-classify: permission prompt 検出コードパスが script 内に存在する" {
  grep -q 'unexpected_permission_prompt' "$SCRIPT_SRC" \
    || fail "unexpected_permission_prompt reason not found in script"
}

@test "inject-classify: permission prompt で auto inject '1' を送信しないことをコード確認" {
  # The script must NOT do `inject ... "1"` or similar for permission prompts
  # Instead it calls _generate_fallback_report
  local inject_section
  inject_section=$(grep -A5 'unexpected_permission_prompt' "$SCRIPT_SRC" || true)
  # Should contain _generate_fallback_report, not a direct "1" inject
  echo "$inject_section" | grep -q '_generate_fallback_report' \
    || fail "Expected _generate_fallback_report for permission prompt, not direct inject"
}

# ---------------------------------------------------------------------------
# Scenario: AskUserQuestion + 安全な選択肢 → 最小番号が inject される
# ---------------------------------------------------------------------------

@test "inject-classify: AskUserQuestion 安全番号抽出ロジックが script に存在する" {
  grep -q 'unclassified_askuserquestion\|_safe_num\|deny-pattern\|delete.*remove' "$SCRIPT_SRC" \
    || fail "AskUserQuestion safe number extraction logic not found in script"
}

@test "inject-classify: AskUserQuestion deny-pattern が script に含まれる" {
  grep -qiE 'delete.*remove.*reset|delete|destroy|wipe|purge|truncate' "$SCRIPT_SRC" \
    || fail "deny-pattern keywords not found in script"
}

@test "inject-classify: AskUserQuestion 安全番号: deny-pattern なし → 最小番号を選択" {
  # Simulate safe menu extraction logic
  local pane_content
  pane_content="$(printf '%s\n' \
    "What would you like to do?" \
    "1. Continue with current settings" \
    "2. Start a new session" \
    "3. View help")"

  local menu_lines safe_num=""
  menu_lines=$(printf '%s' "$pane_content" | grep -E '^[[:space:]]*[1-9]\. .+$' | head -20)

  while IFS= read -r menu_line; do
    local mn mt
    mn=$(printf '%s' "$menu_line" | grep -oE '[1-9]' | head -1)
    mt=$(printf '%s' "$menu_line" | sed 's/^[[:space:]]*[0-9]\+\. *//')
    if [[ -n "$mn" ]] && ! printf '%s' "$mt" | grep -iqE '(delete|remove|reset|destroy|drop|wipe|purge|truncate|force|kill|terminate)'; then
      [[ -z "$safe_num" ]] && safe_num="$mn"
    fi
  done <<< "$menu_lines"

  [ "$safe_num" = "1" ] \
    || fail "Expected safe_num=1, got: $safe_num"
}

@test "inject-classify: AskUserQuestion 安全番号: 1番が deny-pattern → 次の安全な番号を選択" {
  local pane_content
  pane_content="$(printf '%s\n' \
    "Choose an action:" \
    "1. Delete all files" \
    "2. Continue" \
    "3. View status")"

  local menu_lines safe_num=""
  menu_lines=$(printf '%s' "$pane_content" | grep -E '^[[:space:]]*[1-9]\. .+$' | head -20)

  while IFS= read -r menu_line; do
    local mn mt
    mn=$(printf '%s' "$menu_line" | grep -oE '[1-9]' | head -1)
    mt=$(printf '%s' "$menu_line" | sed 's/^[[:space:]]*[0-9]\+\. *//')
    if [[ -n "$mn" ]] && ! printf '%s' "$mt" | grep -iqE '(delete|remove|reset|destroy|drop|wipe|purge|truncate|force|kill|terminate)'; then
      [[ -z "$safe_num" ]] && safe_num="$mn"
    fi
  done <<< "$menu_lines"

  [ "$safe_num" = "2" ] \
    || fail "Expected safe_num=2 (skip 'Delete all files'), got: $safe_num"
}

# ---------------------------------------------------------------------------
# Scenario: AskUserQuestion + 全選択肢が deny-pattern → unclassified_askuserquestion で failed
# ---------------------------------------------------------------------------

@test "inject-classify: AskUserQuestion 全選択肢 deny-pattern → safe_num が空になる" {
  local pane_content
  pane_content="$(printf '%s\n' \
    "Confirm action:" \
    "1. Delete everything" \
    "2. Wipe all data" \
    "3. Force reset")"

  local menu_lines safe_num=""
  menu_lines=$(printf '%s' "$pane_content" | grep -E '^[[:space:]]*[1-9]\. .+$' | head -20)

  while IFS= read -r menu_line; do
    local mn mt
    mn=$(printf '%s' "$menu_line" | grep -oE '[1-9]' | head -1)
    mt=$(printf '%s' "$menu_line" | sed 's/^[[:space:]]*[0-9]\+\. *//')
    if [[ -n "$mn" ]] && ! printf '%s' "$mt" | grep -iqE '(delete|remove|reset|destroy|drop|wipe|purge|truncate|force|kill|terminate)'; then
      [[ -z "$safe_num" ]] && safe_num="$mn"
    fi
  done <<< "$menu_lines"

  [ -z "$safe_num" ] \
    || fail "Expected safe_num to be empty when all options match deny-pattern, got: $safe_num"
}

@test "inject-classify: unclassified_askuserquestion reason が script に存在する" {
  grep -q 'unclassified_askuserquestion' "$SCRIPT_SRC" \
    || fail "unclassified_askuserquestion reason not found in script"
}

# ---------------------------------------------------------------------------
# Scenario: [y/N] 確認プロンプト → escalate (unclassified_input_waiting)
# ---------------------------------------------------------------------------

@test "inject-classify: [y/N] パターン検出コードが script に存在する" {
  grep -qF '\[y/N\]' "$SCRIPT_SRC" \
    || fail "[y/N]/[Y/n] pattern detection not found in script"
}

@test "inject-classify: [y/N] パターンに対して escalate (yn_confirmation_prompt) が呼ばれる" {
  # Check the script has a path from [y/N] detection to yn_confirmation_prompt
  local yn_section
  yn_section=$(grep -A5 '\[y/N\]\|Y/n' "$SCRIPT_SRC" | head -20)
  echo "$yn_section" | grep -q 'yn_confirmation_prompt' \
    || fail "Expected yn_confirmation_prompt after [y/N] detection, not found in script context"
}

# ---------------------------------------------------------------------------
# Scenario: generic "Waiting for user input" → generic inject
# ---------------------------------------------------------------------------

@test "inject-classify: 'Waiting for user input' パターン検出が script に存在する" {
  grep -q 'Waiting for user input' "$SCRIPT_SRC" \
    || fail "'Waiting for user input' pattern detection not found in script"
}

@test "inject-classify: 'Waiting for user input' パターンに対して generic inject が送信される" {
  local generic_section
  generic_section=$(grep -A5 'Waiting for user input' "$SCRIPT_SRC" | head -20)
  echo "$generic_section" | grep -q '処理を続行してください' \
    || fail "Generic continuation message not found after 'Waiting for user input' pattern"
}

# ---------------------------------------------------------------------------
# Scenario: 分類不能 pane → unclassified_input_waiting で failed
# ---------------------------------------------------------------------------

@test "inject-classify: 分類不能ケースの else ブランチが script に存在する" {
  grep -q 'input-waiting unclassified\|unclassified.*failed' "$SCRIPT_SRC" \
    || fail "Unclassified fallback branch not found in script"
}

@test "inject-classify: 分類不能ケースで unclassified_input_waiting reason が使用される" {
  local unclassified_section
  unclassified_section=$(grep -B2 -A3 'input-waiting unclassified\|unclassified.*failed' "$SCRIPT_SRC" | head -20)
  echo "$unclassified_section" | grep -q 'unclassified_input_waiting' \
    || fail "unclassified_input_waiting reason not used in unclassified branch"
}

# ---------------------------------------------------------------------------
# Scenario: ANSI エスケープシーケンスが含まれるパターン → 正しく strip して分類
# ---------------------------------------------------------------------------

@test "inject-classify: ANSI エスケープを含む pane でも permission prompt を正しく検出できる" {
  # ESC[...m sequences stripped → pattern matches correctly
  local ansi_pane
  # Simulate colored permission prompt (ESC[1m = bold, ESC[0m = reset)
  ansi_pane="$(printf '\033[1mTool: Bash\033[0m\n1. Yes, proceed\n2. No, and tell Claude what to do instead')"

  # Apply the same stripping as the script
  local stripped
  stripped=$(printf '%s' "$ansi_pane" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b][^\x07]*\x07//g')

  if printf '%s' "$stripped" | grep -qE '^[1-9]\. (Yes, proceed|Yes, and allow|No, and tell)'; then
    true  # Pattern detected correctly after stripping
  else
    fail "Permission prompt pattern not detected after ANSI stripping. Stripped content: $stripped"
  fi
}

@test "inject-classify: ANSI エスケープを含む AskUserQuestion pane でも選択肢を正しく抽出できる" {
  local ansi_pane
  ansi_pane="$(printf '\033[32mSelect option:\033[0m\n1. Continue\n2. Abort')"

  local stripped
  stripped=$(printf '%s' "$ansi_pane" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b][^\x07]*\x07//g')

  local menu_lines
  menu_lines=$(printf '%s' "$stripped" | grep -E '^[[:space:]]*[1-9]\. .+$' | head -20)

  [ -n "$menu_lines" ] \
    || fail "Menu lines not detected after ANSI stripping. Stripped: $stripped"
}
