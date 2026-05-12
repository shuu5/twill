#!/usr/bin/env bats
# spawn-controller-skip-reason-sanitize.bats - Issue #1660 RED テスト
#
# Coverage (AC1-AC5):
#   S1: SKIP_PARALLEL_REASON=$'reason\twith\ttab' → intervention-log にタブが含まれない
#   S2: SKIP_PARALLEL_REASON=$'reason\x1b[31mred\x1b[0m' → intervention-log に ESC (0x1b) が含まれない
#   S3: SKIP_LAYER2_REASON=$'tab\there\nnewline\rcr' + SKIP_LAYER2=1 (feature-dev) → log に 1 行で append (タブなし)
#   S4: SKIP_LAYER2_REASON=$'\x07bell\x08bs' + SKIP_LAYER2=1 (feature-dev) → 制御文字なしで append
#   S5: SKIP_PILOT_REASON=$'multi\nline\twith\rcontrol' → 1行・タブ/制御文字なしで append (回帰テスト)
#   S6: _sanitize_skip_reason "" → 空文字を返す (引数なし時の安全動作)
#
# RED フェーズ設計:
#   S1: 現在 L249-250 は \n/\r のみ置換、タブは残る → log にタブが含まれる → FAIL
#   S2: 現在 ESC 文字は置換されない → log に ESC が含まれる → FAIL
#   S3: 現在 SKIP_LAYER2 ブロックはタブを置換しない + echo 使用 → FAIL
#   S4: 現在 BEL/BS は置換されない → FAIL
#   S5: 現在 L516 で [^[:print:]] 置換済み → PASS (回帰テスト、実装前から GREEN)
#   S6: _sanitize_skip_reason 関数未定義 → FAIL

load '../helpers/common'

SPAWN_CONTROLLER=""
CLD_SPAWN_ARGS_LOG=""
MOCK_CLD_SPAWN=""
AUTOPILOT_LAUNCH_LOG=""

setup() {
  common_setup

  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  CLD_SPAWN_ARGS_LOG="$SANDBOX/cld-spawn-args.log"
  export CLD_SPAWN_ARGS_LOG

  # cld-spawn stub
  MOCK_CLD_SPAWN="$STUB_BIN/cld-spawn"
  cat > "$MOCK_CLD_SPAWN" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${CLD_SPAWN_ARGS_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$MOCK_CLD_SPAWN"
  export MOCK_CLD_SPAWN

  # run-spawn-controller.sh wrapper (CLD_SPAWN_OVERRIDE inject)
  # NOTE: 非クォート heredoc を使用。$MOCK_CLD_SPAWN/$SPAWN_CONTROLLER は parent shell で展開
  cat > "$SANDBOX/run-spawn-controller.sh" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec env CLD_SPAWN_OVERRIDE="$MOCK_CLD_SPAWN" bash "$SPAWN_CONTROLLER" "\$@"
WRAPPER
  chmod +x "$SANDBOX/run-spawn-controller.sh"

  # tmux stub
  cat > "$STUB_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "test-session"; exit 0 ;;
  list-panes) echo "12345"; exit 0 ;;
  show-options) echo "0"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"

  # autopilot-launch.sh stub（S5: co-autopilot --with-chain bypass で必要）
  AUTOPILOT_LAUNCH_LOG="$SANDBOX/autopilot-launch.log"
  cat > "$STUB_BIN/autopilot-launch.sh" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "${AUTOPILOT_LAUNCH_LOG}"
exit 0
STUB
  chmod +x "$STUB_BIN/autopilot-launch.sh"
  export AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh"
  export AUTOPILOT_LAUNCH_LOG
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# S1: SKIP_PARALLEL_REASON にタブが含まれる場合 → intervention-log にタブが含まれないこと
# RED: 現在 L249-250 は \n/\r のみ置換。タブ (\t) は _sanitize_skip_reason() に移動後に除去される
# ---------------------------------------------------------------------------

@test "S1: tab in SKIP_PARALLEL_REASON is replaced in intervention-log" {
  local log_dir log_dir_rel
  log_dir_rel="_log_s1_$$"
  log_dir="$SANDBOX/$log_dir_rel"
  mkdir -p "$log_dir"

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"
  > "$CLD_SPAWN_ARGS_LOG"

  pushd "$SANDBOX" >/dev/null
  SUPERVISOR_DIR="$log_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON=$'reason\twith\ttab' \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$prompt_file" --window-name "test-window"
  assert_success

  local log_file="$log_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "intervention-log.md が作成されていない: $log_file"

  # タブ文字 (0x09) が含まれていないこと
  if grep -Pq '\t' "$log_file" 2>/dev/null; then
    fail "intervention-log にタブ文字が含まれている (S1 FAIL: _sanitize_skip_reason 未実装)"
  fi

  rm -rf "$log_dir"
}

# ---------------------------------------------------------------------------
# S2: SKIP_PARALLEL_REASON に ESC 文字が含まれる場合 → intervention-log に ESC が含まれないこと
# RED: 現在 ESC (0x1b) は置換されない → log に ESC が残る → FAIL
# ---------------------------------------------------------------------------

@test "S2: ESC char in SKIP_PARALLEL_REASON is replaced in intervention-log" {
  local log_dir log_dir_rel
  log_dir_rel="_log_s2_$$"
  log_dir="$SANDBOX/$log_dir_rel"
  mkdir -p "$log_dir"

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"
  > "$CLD_SPAWN_ARGS_LOG"

  pushd "$SANDBOX" >/dev/null
  SUPERVISOR_DIR="$log_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON=$'reason\x1b[31mred\x1b[0m' \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$prompt_file" --window-name "test-window"
  assert_success

  local log_file="$log_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "intervention-log.md が作成されていない: $log_file"

  # ESC 文字 (0x1b) が含まれていないこと
  if grep -Pq '\x1b' "$log_file" 2>/dev/null; then
    fail "intervention-log に ESC 文字 (0x1b) が含まれている (S2 FAIL: _sanitize_skip_reason 未実装)"
  fi

  rm -rf "$log_dir"
}

# ---------------------------------------------------------------------------
# S3: SKIP_LAYER2_REASON にタブ/改行/CR が含まれる場合 → log に 1 行で append (タブなし)
# RED: 現在 SKIP_LAYER2 ブロックは \n/\r のみ置換し、タブは残る + echo 使用 → FAIL
# ---------------------------------------------------------------------------

@test "S3: tab+newline+CR in SKIP_LAYER2_REASON → single line append without tab in log" {
  local sup_dir_rel sup_dir
  sup_dir_rel="_sup_s3_$$"
  sup_dir="$SANDBOX/$sup_dir_rel"
  mkdir -p "$sup_dir"

  # feature-dev はプロンプトファイル不要、ISSUE_NUMBER を直接渡す
  # --cd $SANDBOX で worktree auto-create をスキップ
  # SUPERVISOR_DIR は相対パスで指定（validate_supervisor_dir が絶対パスを拒否するため）
  cd "$SANDBOX"
  SUPERVISOR_DIR="$sup_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="bats test" \
  SKIP_LAYER2=1 \
  SKIP_LAYER2_REASON=$'tab\there\nnewline\rcr' \
  CLD_SPAWN_OVERRIDE="$MOCK_CLD_SPAWN" \
  run bash "$SPAWN_CONTROLLER" feature-dev 1660 --cd "$SANDBOX"
  assert_success

  local log_file="$sup_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "intervention-log.md が作成されていない: $log_file (S3 FAIL: SKIP_LAYER2 ブロック未修正)"

  # SKIP_LAYER2 を含む行数が 1 であること
  local matching_lines
  matching_lines="$(grep -c "SKIP_LAYER2" "$log_file" 2>/dev/null || echo "0")"
  [[ "$matching_lines" -eq 1 ]] \
    || fail "SKIP_LAYER2 を含む行が $matching_lines 行（期待: 1 行）。ログ内容: $(cat "$log_file" 2>/dev/null || echo '(empty)')"

  # タブ文字が含まれていないこと
  if grep -Pq '\t' "$log_file" 2>/dev/null; then
    fail "intervention-log にタブ文字が含まれている (S3 FAIL: タブ置換未実装)"
  fi
}

# ---------------------------------------------------------------------------
# S4: SKIP_LAYER2_REASON に BEL/BS 制御文字が含まれる場合 → 制御文字なしで append
# RED: 現在 BEL (0x07)/BS (0x08) は置換されない → FAIL
# ---------------------------------------------------------------------------

@test "S4: BEL+BS in SKIP_LAYER2_REASON are stripped in intervention-log" {
  local sup_dir_rel sup_dir
  sup_dir_rel="_sup_s4_$$"
  sup_dir="$SANDBOX/$sup_dir_rel"
  mkdir -p "$sup_dir"

  # SUPERVISOR_DIR は相対パスで指定（validate_supervisor_dir が絶対パスを拒否するため）
  cd "$SANDBOX"
  SUPERVISOR_DIR="$sup_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="bats test" \
  SKIP_LAYER2=1 \
  SKIP_LAYER2_REASON=$'\x07bell\x08bs' \
  CLD_SPAWN_OVERRIDE="$MOCK_CLD_SPAWN" \
  run bash "$SPAWN_CONTROLLER" feature-dev 1660 --cd "$SANDBOX"
  assert_success

  local log_file="$sup_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "intervention-log.md が作成されていない: $log_file (S4 FAIL: SKIP_LAYER2 ブロック未修正)"

  # BEL (0x07) が含まれていないこと
  if grep -Pq '\x07' "$log_file" 2>/dev/null; then
    fail "intervention-log に BEL 文字 (0x07) が含まれている (S4 FAIL: _sanitize_skip_reason 未実装)"
  fi

  # BS (0x08) が含まれていないこと
  if grep -Pq '\x08' "$log_file" 2>/dev/null; then
    fail "intervention-log に BS 文字 (0x08) が含まれている (S4 FAIL: _sanitize_skip_reason 未実装)"
  fi
}

# ---------------------------------------------------------------------------
# S5: SKIP_PILOT_REASON に改行/タブ/CR が含まれる場合 → 1行・タブ/制御文字なしで append (回帰テスト)
# GREEN: 現在 L516 で ${_skip_pilot_reason//[^[:print:]]/ } 置換済み → PASS
# ---------------------------------------------------------------------------

@test "S5: multiline+tab+CR in SKIP_PILOT_REASON → sanitized in intervention-log (regression)" {
  local sup_dir
  sup_dir="$SANDBOX/.supervisor"
  mkdir -p "$sup_dir"

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"

  pushd "$SANDBOX" >/dev/null
  SUPERVISOR_DIR=".supervisor" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="bats test" \
  SKIP_PILOT_GATE=1 \
  SKIP_PILOT_REASON=$'multi\nline\twith\rcontrol' \
  run bash "$SANDBOX/run-spawn-controller.sh" co-autopilot "$prompt_file" \
    --with-chain --issue 1660
  assert_success

  local log_file="$sup_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "intervention-log.md が作成されていない: $log_file"

  # SKIP_PILOT_GATE を含む行数が 1 であること（改行が除去されていること）
  local matching_lines
  matching_lines="$(grep -c "SKIP_PILOT_GATE" "$log_file" 2>/dev/null || echo "0")"
  [[ "$matching_lines" -eq 1 ]] \
    || fail "SKIP_PILOT_GATE を含む行が $matching_lines 行（期待: 1 行）。ログ内容: $(cat "$log_file" 2>/dev/null || echo '(empty)')"

  # タブ文字が含まれていないこと
  if grep -Pq '\t' "$log_file" 2>/dev/null; then
    fail "intervention-log にタブ文字が含まれている"
  fi

  # 制御文字 (0x00-0x1f) が含まれていないこと（改行は除く: grep -P で確認）
  if LC_ALL=C grep -Pq '[\x00-\x08\x0b-\x0c\x0e-\x1f\x7f]' "$log_file" 2>/dev/null; then
    fail "intervention-log に制御文字が含まれている"
  fi
}

# ---------------------------------------------------------------------------
# S6: _sanitize_skip_reason "" → 空文字を返す (引数なし時の安全動作)
# RED: _sanitize_skip_reason 関数が未定義 → FAIL
# ---------------------------------------------------------------------------

@test "S6: _sanitize_skip_reason empty string returns empty" {
  # spawn-controller.sh にはソースガードがないため直接 source できない。
  # awk で関数定義のみを取り出し eval する。
  local fn_def
  fn_def=$(awk '/_sanitize_skip_reason\(\)/{found=1} found{print; if(/^\}/){exit}}' "$SPAWN_CONTROLLER" 2>/dev/null || echo "")

  if [[ -z "$fn_def" ]]; then
    fail "_sanitize_skip_reason() not found in spawn-controller.sh (AC1 not yet implemented)"
  fi

  eval "$fn_def"

  local result
  result="$(_sanitize_skip_reason "" 2>/dev/null || echo "FUNCTION_ERROR")"
  [[ -z "$result" ]] || fail "Expected empty string, got: '$result'"
}
