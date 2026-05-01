#!/usr/bin/env bats
# su-observer-session-init-mode-extraction.bats - Issue #1223 AC1/AC2/AC3 RED テスト
#
# AC1: --dangerously-skip-permissions のみ含む cmdline mock で session.json の mode=bypass が記録される
# AC2: --permission-mode bypassPermissions が cmdline に含まれる場合、normalize により mode=bypass が記録される
# AC3: --permission-mode auto または acceptEdits で mode=auto が記録される
#
# テスト戦略: SESSION_INIT_CMDLINE_OVERRIDE env var でcmdline をモック
#   - RED: session-init.sh が SESSION_INIT_CMDLINE_OVERRIDE を未サポート + --dangerously-skip-permissions 検出なし
#   - GREEN: 実装後、env var サポート + normalize ロジック追加で全 AC PASS
#
# 前提:
#   - SUPERVISOR_DIR を tmpdir に設定（session.json 出力先の制御）
#   - tmux/twl audit 等の外部コマンドは stub で無害化

load '../helpers/common'

SCRIPT_SRC=""

setup() {
  common_setup

  SCRIPT_SRC="$REPO_ROOT/skills/su-observer/scripts/session-init.sh"

  # SUPERVISOR_DIR をサンドボックス内に設定
  export SUPERVISOR_DIR="$SANDBOX/.supervisor"
  mkdir -p "$SUPERVISOR_DIR"

  # 外部コマンド stub（session-init.sh が呼ぶが AC と無関係なもの）
  stub_command "tmux" 'echo "test-window"'
  stub_command "twl" 'exit 0'
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: --dangerously-skip-permissions → mode=bypass
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario AC1-dangerously-skip: cmdline に --dangerously-skip-permissions のみ
# GIVEN: SESSION_INIT_CMDLINE_OVERRIDE="node /path/to/cld --dangerously-skip-permissions"
# WHEN: session-init.sh を実行する
# THEN: session.json の mode フィールドが "bypass" である
# RED: session-init.sh が SESSION_INIT_CMDLINE_OVERRIDE を未サポート かつ
#      --dangerously-skip-permissions 検出ロジックが未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC1-dangerously-skip: --dangerously-skip-permissions のみで mode=bypass が記録される" {
  export SESSION_INIT_CMDLINE_OVERRIDE="node /path/to/cld --dangerously-skip-permissions"
  export SUPERVISOR_DIR="$SANDBOX/.supervisor"

  run bash "$SCRIPT_SRC"

  assert_success

  local session_file="$SUPERVISOR_DIR/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: $session_file"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "$session_file" 2>/dev/null || echo "")

  [[ "$actual_mode" == "bypass" ]] \
    || fail "mode は 'bypass' であるべきだが '$actual_mode' だった（--dangerously-skip-permissions 検出未実装 or SESSION_INIT_CMDLINE_OVERRIDE 未サポート）"
}

# ---------------------------------------------------------------------------
# Scenario AC1-dangerously-skip-extra-args: 他フラグと共存する cmdline
# GIVEN: SESSION_INIT_CMDLINE_OVERRIDE="node cld --dangerously-skip-permissions --model claude-sonnet-4"
# WHEN: session-init.sh を実行する
# THEN: session.json の mode フィールドが "bypass" である
# ---------------------------------------------------------------------------

@test "AC1-dangerously-skip-extra-args: 他フラグと共存しても mode=bypass が記録される" {
  export SESSION_INIT_CMDLINE_OVERRIDE="node cld --dangerously-skip-permissions --model claude-sonnet-4"
  export SUPERVISOR_DIR="$SANDBOX/.supervisor"

  run bash "$SCRIPT_SRC"

  assert_success

  local session_file="$SUPERVISOR_DIR/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: $session_file"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "$session_file" 2>/dev/null || echo "")

  [[ "$actual_mode" == "bypass" ]] \
    || fail "mode は 'bypass' であるべきだが '$actual_mode' だった（他フラグ共存時の --dangerously-skip-permissions 検出未実装）"
}

# ===========================================================================
# AC2: --permission-mode bypassPermissions → mode=bypass（normalize）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario AC2-bypass-permissions-normalize: bypassPermissions → bypass
# GIVEN: SESSION_INIT_CMDLINE_OVERRIDE="node cld --permission-mode bypassPermissions"
# WHEN: session-init.sh を実行する
# THEN: session.json の mode フィールドが "bypass" である（normalize 済み）
# RED: session-init.sh に normalize ロジック（bypassPermissions→bypass）が未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC2-bypass-permissions-normalize: --permission-mode bypassPermissions → mode=bypass" {
  export SESSION_INIT_CMDLINE_OVERRIDE="node cld --permission-mode bypassPermissions"
  export SUPERVISOR_DIR="$SANDBOX/.supervisor"

  run bash "$SCRIPT_SRC"

  assert_success

  local session_file="$SUPERVISOR_DIR/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: $session_file"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "$session_file" 2>/dev/null || echo "")

  [[ "$actual_mode" == "bypass" ]] \
    || fail "mode は 'bypass' であるべきだが '$actual_mode' だった（bypassPermissions→bypass normalize 未実装）"
}

# ===========================================================================
# AC3: --permission-mode auto/acceptEdits → mode=auto（normalize）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario AC3-auto-acceptEdits-normalize (auto): --permission-mode auto → mode=auto
# GIVEN: SESSION_INIT_CMDLINE_OVERRIDE="node cld --permission-mode auto"
# WHEN: session-init.sh を実行する
# THEN: session.json の mode フィールドが "auto" である
# RED: SESSION_INIT_CMDLINE_OVERRIDE 未サポートのため fail する
# ---------------------------------------------------------------------------

@test "AC3-auto-acceptEdits-normalize: --permission-mode auto → mode=auto が記録される" {
  export SESSION_INIT_CMDLINE_OVERRIDE="node cld --permission-mode auto"
  export SUPERVISOR_DIR="$SANDBOX/.supervisor"

  run bash "$SCRIPT_SRC"

  assert_success

  local session_file="$SUPERVISOR_DIR/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: $session_file"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "$session_file" 2>/dev/null || echo "")

  [[ "$actual_mode" == "auto" ]] \
    || fail "mode は 'auto' であるべきだが '$actual_mode' だった（--permission-mode auto 記録未実装）"
}

# ---------------------------------------------------------------------------
# Scenario AC3-auto-acceptEdits-normalize (acceptEdits): --permission-mode acceptEdits → mode=auto
# GIVEN: SESSION_INIT_CMDLINE_OVERRIDE="node cld --permission-mode acceptEdits"
# WHEN: session-init.sh を実行する
# THEN: session.json の mode フィールドが "auto" である（normalize 済み）
# RED: normalize ロジック（acceptEdits→auto）が未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC3-auto-acceptEdits-normalize: --permission-mode acceptEdits → mode=auto が記録される" {
  export SESSION_INIT_CMDLINE_OVERRIDE="node cld --permission-mode acceptEdits"
  export SUPERVISOR_DIR="$SANDBOX/.supervisor"

  run bash "$SCRIPT_SRC"

  assert_success

  local session_file="$SUPERVISOR_DIR/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: $session_file"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "$session_file" 2>/dev/null || echo "")

  [[ "$actual_mode" == "auto" ]] \
    || fail "mode は 'auto' であるべきだが '$actual_mode' だった（acceptEdits→auto normalize 未実装）"
}

# ---------------------------------------------------------------------------
# Regression: cmdline に該当 flag 完全不在 → mode="" のまま（fail-loud 維持）
# GIVEN: SESSION_INIT_CMDLINE_OVERRIDE="node cld"（関連フラグなし）
# WHEN: session-init.sh を実行する
# THEN: session.json の mode フィールドが "" のまま（WARN が出力される）
# このテストは現行挙動の regression 保護（GREEN 後も PASS すること）
# ---------------------------------------------------------------------------

@test "regression: 関連フラグ不在なら mode=empty で記録される（fail-loud 維持）" {
  export SESSION_INIT_CMDLINE_OVERRIDE="node cld"
  export SUPERVISOR_DIR="$SANDBOX/.supervisor"

  run bash "$SCRIPT_SRC"

  assert_success

  local session_file="$SUPERVISOR_DIR/session.json"
  [[ -f "$session_file" ]] \
    || fail "session.json が作成されていない: $session_file"

  local actual_mode
  actual_mode=$(jq -r '.mode // empty' "$session_file" 2>/dev/null || echo "MISSING")

  # mode は空文字（fail-loud: spawn-controller 側で DENY する）
  [[ "$actual_mode" == "" ]] \
    || fail "関連フラグ不在時は mode=empty であるべきだが '$actual_mode' だった（fail-loud regression）"
}
