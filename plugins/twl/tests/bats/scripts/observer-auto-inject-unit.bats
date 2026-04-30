#!/usr/bin/env bats
# observer-auto-inject-unit.bats - Issue #1145 AC 機械的検証テスト（TDD RED フェーズ）
#
# Issue #1145: feat(observer): AskUserQuestion menu 自動 inject 機構
#
# このファイルは実装前（RED）状態で全テストが fail することを意図している。
# 実装完了後（GREEN）は全テストが PASS すること。
#
# Coverage: AC1〜AC8（bats unit test 8 ケース）

export LC_ALL=C.UTF-8

load '../helpers/common'

# 実装対象スクリプト（REPO_ROOT = plugins/）
AUTO_INJECT_LIB=""
CLD_OBSERVE_ANY=""

setup() {
  common_setup

  AUTO_INJECT_LIB="$REPO_ROOT/../session/scripts/lib/observer-auto-inject.sh"
  CLD_OBSERVE_ANY="$REPO_ROOT/../session/scripts/cld-observe-any"

  # tmux spy ファイル: tmux send-keys の呼び出し記録
  TMUX_SPY_FILE="$SANDBOX/tmux-spy.log"
  export TMUX_SPY_FILE

  # tmux stub: send-keys を spy ファイルに記録（実際には送信しない）
  stub_command "tmux" "
if [[ \"\$*\" == *send-keys* ]]; then
  echo \"\$@\" >> '$TMUX_SPY_FILE'
  exit 0
fi
# その他の tmux コマンドは no-op
exit 0
"

  # flock stub: ロック取得を常に成功させる（flock -n <fd> 形式に対応）
  stub_command "flock" "exit 0"

  # audit trail ディレクトリ
  mkdir -p "$SANDBOX/.supervisor/events"
  export SUPERVISOR_EVENTS_DIR="$SANDBOX/.supervisor/events"

  # OBSERVER_AUTO_INJECT_ENABLE をデフォルト無効にする
  unset OBSERVER_AUTO_INJECT_ENABLE

  # cycle ファイル・flock ファイルを SANDBOX に隔離（残留防止）
  export TMPDIR="$SANDBOX"

  # 残留 cycle ファイルをクリーンアップ
  rm -f /tmp/cld-auto-inject-cycle-* 2>/dev/null || true
}

teardown() {
  common_teardown
}

# ===========================================================================
# テスト前提確認ヘルパー
# ===========================================================================

# 実装ファイル（lib or cld-observe-any 内定義）が存在するかチェック
_require_auto_inject_impl() {
  if [[ -f "$AUTO_INJECT_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$AUTO_INJECT_LIB"
  elif [[ -f "$CLD_OBSERVE_ANY" ]]; then
    # cld-observe-any 内に auto_inject_menu が定義されている場合
    # set -euo pipefail の影響を避けるため関数定義部分のみ source
    local fn_start fn_end
    fn_start=$(grep -n "^auto_inject_menu()" "$CLD_OBSERVE_ANY" | head -1 | cut -d: -f1)
    if [[ -z "$fn_start" ]]; then
      fail "auto_inject_menu() が未実装 (RED): $CLD_OBSERVE_ANY"
    fi
    # 関数が定義されている場合は cld-observe-any を source（実行しない）
    # _TEST_MODE で main ループを skip する
    export _TEST_MODE=1
    export CLD_OBSERVE_ANY_SCRIPT_DIR="$(dirname "$CLD_OBSERVE_ANY")"
    source "$CLD_OBSERVE_ANY"
  else
    fail "auto_inject_menu() 実装ファイルが存在しない。期待パス: $AUTO_INJECT_LIB"
  fi

  command -v auto_inject_menu &>/dev/null \
    || fail "auto_inject_menu() 関数が定義されていない"
}

# ===========================================================================
# AC1: 番号付き menu (1. Foo) → 番号 1 を inject
# ===========================================================================
# RED 理由: auto_inject_menu() が未実装のため fail する

@test "ac1: numbered menu (1. Foo) → injects number 1" {
  # AC: 番号付き menu (1. Foo) が表示されているとき、deny-pattern 非該当の最小番号 1 を inject する
  # RED: 実装前は auto_inject_menu() が存在しないため fail する
  _require_auto_inject_impl

  export OBSERVER_AUTO_INJECT_ENABLE=1

  # pane 内容: 2 選択肢、どちらも deny 非該当
  local pane_content
  pane_content="$(printf '1. Continue workflow\n2. Show summary\n> Enter to select, Esc to cancel')"

  local window="wt-test-abc12345"

  run auto_inject_menu "$window" "$pane_content"
  assert_success

  # tmux send-keys で "1" が送信されたことを確認
  grep -q "send-keys" "$TMUX_SPY_FILE" \
    || fail "tmux send-keys が呼ばれなかった"
  grep -qE "send-keys.*\b1\b" "$TMUX_SPY_FILE" \
    || fail "番号 1 が inject されなかった（spy: $(cat "$TMUX_SPY_FILE")）"
}

# ===========================================================================
# AC2: cursor marker ❯ 2. Bar (deny 非該当) → 番号 2 を inject
# ===========================================================================
# RED 理由: auto_inject_menu() が未実装のため fail する

@test "ac2: cursor marker ❯ 2. Bar (non-deny) → injects number 2" {
  # AC: cursor marker ❯ が 2. Bar 行を指している（deny 非該当）場合、番号 2 を inject する
  # RED: 実装前は auto_inject_menu() が存在しないため fail する
  _require_auto_inject_impl

  export OBSERVER_AUTO_INJECT_ENABLE=1

  # pane 内容: cursor が 2 を指している、どちらも deny 非該当
  local pane_content
  pane_content="$(printf '  1. Show status\n❯ 2. Bar baz action\n  3. List items\n> Enter to select, Esc to cancel')"

  local window="wt-test-abc12345"

  run auto_inject_menu "$window" "$pane_content"
  assert_success

  grep -q "send-keys" "$TMUX_SPY_FILE" \
    || fail "tmux send-keys が呼ばれなかった"
  grep -qE "send-keys.*\b2\b" "$TMUX_SPY_FILE" \
    || fail "番号 2 が inject されなかった（spy: $(cat "$TMUX_SPY_FILE")）"
}

# ===========================================================================
# AC3: specialist_handoff_menu + [D] label → [D] 番号を inject
# ===========================================================================
# RED 理由: auto_inject_menu() が未実装のため fail する

@test "ac3: specialist_handoff_menu with [D] label → injects [D] number" {
  # AC: pane に specialist/PASS/NEEDS_WORK + [D] label が同時存在する specialist_handoff_menu では
  #     [D] 番号を最優先で inject する
  # RED: 実装前は auto_inject_menu() が存在しないため fail する
  _require_auto_inject_impl

  export OBSERVER_AUTO_INJECT_ENABLE=1

  # specialist_handoff_menu を模したコンテンツ
  # Phase 4 に specialist と [D] label が存在する
  local pane_content
  pane_content="$(printf 'Phase 4: specialist review complete\nPASS - all checks passed\n1. Continue to next phase\n2. [D] Deploy now\n3. Show report\n> Enter to select, Esc to cancel')"

  local window="wt-test-abc12345"

  run auto_inject_menu "$window" "$pane_content"
  assert_success

  grep -q "send-keys" "$TMUX_SPY_FILE" \
    || fail "tmux send-keys が呼ばれなかった"
  # [D] 付き選択肢は 2 番なので、2 が inject されること
  grep -qE "send-keys.*\b2\b" "$TMUX_SPY_FILE" \
    || fail "[D] 番号 2 が inject されなかった（spy: $(cat "$TMUX_SPY_FILE")）"
}

# ===========================================================================
# AC4: 全選択肢 deny-pattern 該当 → inject せず warning（stderr）
# ===========================================================================
# RED 理由: auto_inject_menu() が未実装のため fail する

@test "ac4: all options match deny-pattern → no inject, warning on stderr" {
  # AC: 全選択肢が deny-pattern に該当する場合は inject せず、stderr に warning を出力する
  # RED: 実装前は auto_inject_menu() が存在しないため fail する
  _require_auto_inject_impl

  export OBSERVER_AUTO_INJECT_ENABLE=1

  # 全選択肢に deny-pattern が含まれる
  local pane_content
  pane_content="$(printf '1. Delete all files\n2. Remove project\n3. Force reset\n> Enter to select, Esc to cancel')"

  local window="wt-test-abc12345"

  run auto_inject_menu "$window" "$pane_content"
  # inject しない（exit 0 or 1 どちらでも可）が tmux send-keys は呼ばれない
  [[ ! -f "$TMUX_SPY_FILE" ]] || ! grep -q "send-keys" "$TMUX_SPY_FILE" \
    || fail "全選択肢 deny 時に send-keys が呼ばれた（inject してはならない）"

  # stderr に warning が出力されていること
  echo "${output}${stderr}" | grep -iqE "deny|warn|skip|all.*deny|deny.*all" \
    || [[ "${lines[*]}" =~ deny|warn|skip ]] \
    || fail "deny-pattern 全該当時に warning が stderr に出力されなかった（output: $output）"
}

# ===========================================================================
# AC5: cursor marker 行が deny + 他に non-deny → minimum-number に fallback
# ===========================================================================
# RED 理由: auto_inject_menu() が未実装のため fail する

@test "ac5: cursor marker row is deny, other rows non-deny → fallback to minimum number" {
  # AC: cursor marker 行が deny-pattern に該当し、他に non-deny 行が存在する場合は
  #     non-deny の最小番号に fallback する
  # RED: 実装前は auto_inject_menu() が存在しないため fail する
  _require_auto_inject_impl

  export OBSERVER_AUTO_INJECT_ENABLE=1

  # cursor が deny 行（3. delete）を指しているが、1. Continue は non-deny
  local pane_content
  pane_content="$(printf '  1. Continue workflow\n  2. Show summary\n❯ 3. Delete temporary files\n> Enter to select, Esc to cancel')"

  local window="wt-test-abc12345"

  run auto_inject_menu "$window" "$pane_content"
  assert_success

  grep -q "send-keys" "$TMUX_SPY_FILE" \
    || fail "tmux send-keys が呼ばれなかった（fallback inject が期待される）"
  # fallback として最小番号 1 が inject されること
  grep -qE "send-keys.*\b1\b" "$TMUX_SPY_FILE" \
    || fail "minimum-number 1 への fallback inject がなかった（spy: $(cat "$TMUX_SPY_FILE")）"
}

# ===========================================================================
# AC6: OBSERVER_AUTO_INJECT_ENABLE 未設定 → no-op (event emit のみ、inject しない)
# ===========================================================================
# RED 理由: auto_inject_menu() が未実装のため fail する

@test "ac6: OBSERVER_AUTO_INJECT_ENABLE unset → no-op, no inject" {
  # AC: OBSERVER_AUTO_INJECT_ENABLE 未設定（または =0）の場合は inject しない（opt-in モデル）
  # RED: 実装前は auto_inject_menu() が存在しないため fail する
  _require_auto_inject_impl

  # OBSERVER_AUTO_INJECT_ENABLE を未設定にする（setup で unset 済みだが明示）
  unset OBSERVER_AUTO_INJECT_ENABLE

  local pane_content
  pane_content="$(printf '1. Continue workflow\n2. Show summary\n> Enter to select, Esc to cancel')"

  local window="wt-test-abc12345"

  run auto_inject_menu "$window" "$pane_content"
  # ENABLE 未設定なので inject してはならない
  [[ ! -f "$TMUX_SPY_FILE" ]] || ! grep -q "send-keys" "$TMUX_SPY_FILE" \
    || fail "OBSERVER_AUTO_INJECT_ENABLE 未設定時に send-keys が呼ばれた（inject してはならない）"
}

# ===========================================================================
# AC7: A2 thinking indicator 出現中 → no-op
# ===========================================================================
# RED 理由: auto_inject_menu() が未実装のため fail する

@test "ac7: A2 thinking indicator present → no-op, no inject" {
  # AC: LLM thinking indicator（例: "Thinking..."）が pane に存在する場合は inject しない
  # RED: 実装前は auto_inject_menu() が存在しないため fail する
  _require_auto_inject_impl

  export OBSERVER_AUTO_INJECT_ENABLE=1

  # thinking indicator が存在する pane 内容
  local pane_content
  pane_content="$(printf 'Thinking...\n1. Continue workflow\n2. Show summary\n> Enter to select, Esc to cancel')"

  local window="wt-test-abc12345"

  # A2 guard を有効にするフラグ（thinking indicator あり）
  run auto_inject_menu "$window" "$pane_content" "thinking=Thinking..."

  # thinking 中なので inject してはならない
  [[ ! -f "$TMUX_SPY_FILE" ]] || ! grep -q "send-keys" "$TMUX_SPY_FILE" \
    || fail "A2 thinking 中に send-keys が呼ばれた（inject してはならない）"
}

# ===========================================================================
# AC8: audit trail JSON ファイルが生成され schema を満たす
# ===========================================================================
# RED 理由: auto_inject_menu() が未実装のため fail する

@test "ac8: audit trail JSON is generated with required schema fields" {
  # AC: auto-inject 実行後に .supervisor/events/auto-inject-<window_safe>-<ISO8601>.json が生成され、
  #     必須フィールドを含む schema を満たす
  # RED: 実装前は auto_inject_menu() が存在しないため fail する
  _require_auto_inject_impl

  export OBSERVER_AUTO_INJECT_ENABLE=1

  local pane_content
  pane_content="$(printf '1. Continue workflow\n2. Show summary\n> Enter to select, Esc to cancel')"

  local window="wt-test-abc12345"

  # audit trail ディレクトリを設定
  export AUTO_INJECT_AUDIT_DIR="$SUPERVISOR_EVENTS_DIR"

  run auto_inject_menu "$window" "$pane_content"

  # audit trail ファイルが生成されていること
  local audit_file
  audit_file=$(find "$SUPERVISOR_EVENTS_DIR" -name "auto-inject-*.json" | head -1)
  [[ -n "$audit_file" ]] \
    || fail "audit trail JSON ファイルが生成されなかった（dir: $SUPERVISOR_EVENTS_DIR）"

  # JSON として valid であること
  run jq empty "$audit_file"
  assert_success

  # 必須フィールドの存在確認
  local required_fields=(
    "window"
    "timestamp"
    "menu_pattern"
    "selected_option"
    "selected_text"
    "deny_pattern_matched"
    "skip_reason"
    "safe_mode"
    "trigger_event"
    "session_id"
  )

  for field in "${required_fields[@]}"; do
    run jq --exit-status "has(\"$field\")" "$audit_file"
    assert_success \
      "audit trail JSON にフィールド '$field' が存在しない（file: $audit_file）"
  done
}
