#!/usr/bin/env bats
# spawn-controller-skip-parallel-log.bats - Issue #1135 AC11 RED テスト
#
# AC11: SKIP_PARALLEL_CHECK=1 時の intervention-log 自動記録
#
# C1: SKIP_PARALLEL_CHECK=1 + SKIP_PARALLEL_REASON="test reason" → ログ append
# C2: SKIP_PARALLEL_CHECK=1 のみ → (reason not provided) で記録
# C3: SUPERVISOR_DIR=$(mktemp -d) で実 .supervisor/intervention-log.md を汚染しない
# C4: SUPERVISOR_DIR 不在ディレクトリでも mkdir -p が成功し append される
# C5: append 失敗時（SUPERVISOR_DIR=/dev/null/x 等）に WARN 出力 + spawn 継続（fail-open）
# C6: SKIP_PARALLEL_REASON=$'line1\nline2' の場合、ログ行が 1 行に保たれる (\n/\r → 空白 (helper 化後は制御文字全般))

load '../helpers/common'

SPAWN_CONTROLLER=""
CLD_SPAWN_ARGS_LOG=""
MOCK_CLD_SPAWN=""

setup() {
  common_setup

  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  CLD_SPAWN_ARGS_LOG="$SANDBOX/cld-spawn-args.log"
  export CLD_SPAWN_ARGS_LOG

  cat > "$STUB_BIN/cld-spawn" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${CLD_SPAWN_ARGS_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$STUB_BIN/cld-spawn"

  MOCK_CLD_SPAWN="$STUB_BIN/cld-spawn"
  export MOCK_CLD_SPAWN

  # Issue #1644: CLD_SPAWN_OVERRIDE env var で mock 切り替え（旧 sed-replace 方式は廃止）
  # NOTE: SKIP_PARALLEL_CHECK は本テストの ASSERTION 対象のため wrapper で default 設定しない
  cat > "$SANDBOX/run-spawn-controller.sh" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec env CLD_SPAWN_OVERRIDE="$MOCK_CLD_SPAWN" bash "$SPAWN_CONTROLLER" "\$@"
WRAPPER
  chmod +x "$SANDBOX/run-spawn-controller.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# C1: SKIP_PARALLEL_CHECK=1 + SKIP_PARALLEL_REASON="test reason"
#     → intervention-log.md に "<UTC>Z SKIP_PARALLEL_CHECK=1: test reason" が append
# RED: spawn-controller.sh に自動記録実装がないため fail する
# ---------------------------------------------------------------------------

@test "C1: SKIP_PARALLEL_CHECK=1 + REASON が intervention-log に append される" {
  # RED: spawn-controller.sh に自動記録実装がないため fail する

  local log_dir
  log_dir_rel="_log_1_$$"; log_dir="$SANDBOX/$log_dir_rel"; mkdir -p "$log_dir"; pushd "$SANDBOX" >/dev/null

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"
  > "$CLD_SPAWN_ARGS_LOG"

  SUPERVISOR_DIR="$log_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="test reason" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$prompt_file" \
    --window-name "test-window"

  # spawn 自体は成功すること
  assert_success

  # intervention-log.md が作成されていること
  local log_file="$log_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "intervention-log.md が作成されていない: $log_file"

  # ログ行に "SKIP_PARALLEL_CHECK=1: test reason" が含まれること
  grep -q "SKIP_PARALLEL_CHECK=1: test reason" "$log_file" \
    || fail "intervention-log.md に期待する記録がない。内容: $(cat "$log_file" 2>/dev/null || echo '(empty)')"

  rm -rf "$log_dir"
}

# ---------------------------------------------------------------------------
# C2: SKIP_PARALLEL_CHECK=1 のみ（SKIP_PARALLEL_REASON 未指定）
#     → "(reason not provided)" で記録
# RED: 自動記録実装がないため fail する
# ---------------------------------------------------------------------------

@test "C2: SKIP_PARALLEL_REASON 未指定時は (reason not provided) で記録される" {
  # RED: spawn-controller.sh に自動記録実装がないため fail する

  local log_dir
  log_dir_rel="_log_2_$$"; log_dir="$SANDBOX/$log_dir_rel"; mkdir -p "$log_dir"; pushd "$SANDBOX" >/dev/null

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"
  > "$CLD_SPAWN_ARGS_LOG"

  SUPERVISOR_DIR="$log_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$prompt_file" \
    --window-name "test-window"

  assert_success

  local log_file="$log_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "intervention-log.md が作成されていない: $log_file"

  grep -q "(reason not provided)" "$log_file" \
    || fail "REASON 未指定時に '(reason not provided)' が記録されていない。内容: $(cat "$log_file" 2>/dev/null || echo '(empty)')"

  rm -rf "$log_dir"
}

# ---------------------------------------------------------------------------
# C3: SUPERVISOR_DIR=$(mktemp -d) で実 .supervisor/intervention-log.md を汚染しない
#     → 実プロジェクトの .supervisor/intervention-log.md に変更がないこと
# RED: 自動記録実装がないため fail する（ただし環境汚染防止の観点では副次的 RED）
# ---------------------------------------------------------------------------

@test "C3: SUPERVISOR_DIR 指定時に実 .supervisor/intervention-log.md を汚染しない" {
  # RED: spawn-controller.sh に自動記録実装がないため、ログが作成されないため fail する
  # （ただしこのテスト自体は実 .supervisor 汚染がないことを確認する）

  local log_dir
  log_dir_rel="_log_3_$$"; log_dir="$SANDBOX/$log_dir_rel"; mkdir -p "$log_dir"; pushd "$SANDBOX" >/dev/null

  # 実 .supervisor のパスを記録しておく（汚染確認用）
  local real_supervisor_dir
  real_supervisor_dir="$(pwd)/.supervisor"
  local real_log="$real_supervisor_dir/intervention-log.md"

  # 実ログが事前に存在する場合、タイムスタンプを記録
  local pre_mtime=""
  if [[ -f "$real_log" ]]; then
    pre_mtime="$(stat -c %Y "$real_log" 2>/dev/null || echo "")"
  fi

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"
  > "$CLD_SPAWN_ARGS_LOG"

  SUPERVISOR_DIR="$log_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="isolation test" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$prompt_file" \
    --window-name "test-window"

  assert_success

  # 指定した log_dir に記録されていること（RED ポイント）
  local log_file="$log_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "SUPERVISOR_DIR 指定先に intervention-log.md が作成されていない: $log_file"

  # 実 .supervisor/intervention-log.md が変更されていないこと
  if [[ -n "$pre_mtime" ]]; then
    local post_mtime
    post_mtime="$(stat -c %Y "$real_log" 2>/dev/null || echo "")"
    [[ "$pre_mtime" == "$post_mtime" ]] \
      || fail "実 .supervisor/intervention-log.md が変更されてしまった（汚染）"
  else
    [[ ! -f "$real_log" ]] \
      || fail "実 .supervisor/intervention-log.md が新規作成されてしまった（汚染）"
  fi

  rm -rf "$log_dir"
}

# ---------------------------------------------------------------------------
# C4: SUPERVISOR_DIR が存在しないディレクトリを指定しても mkdir -p が成功し append される
# RED: 自動記録実装がないため fail する
# ---------------------------------------------------------------------------

@test "C4: SUPERVISOR_DIR 不在ディレクトリでも mkdir -p が成功し append される" {
  # RED: spawn-controller.sh に自動記録実装がないため fail する

  local base_dir
  base_dir_rel="_base_1_$$"; base_dir="$SANDBOX/$base_dir_rel"; mkdir -p "$base_dir"; pushd "$SANDBOX" >/dev/null
  local log_dir="$base_dir/non-existent/nested/supervisor"
  # log_dir は事前作成しない

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"
  > "$CLD_SPAWN_ARGS_LOG"

  SUPERVISOR_DIR="$log_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="mkdir-p test" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$prompt_file" \
    --window-name "test-window"

  assert_success

  local log_file="$log_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "mkdir -p 後に intervention-log.md が作成されていない: $log_file"

  grep -q "SKIP_PARALLEL_CHECK=1: mkdir-p test" "$log_file" \
    || fail "mkdir -p 成功後のログ内容が期待と異なる。内容: $(cat "$log_file" 2>/dev/null || echo '(empty)')"

  rm -rf "$base_dir"
}

# ---------------------------------------------------------------------------
# C5: append 失敗時（SUPERVISOR_DIR=/dev/null/x 等）に WARN 出力 + spawn 継続（fail-open）
# RED: 自動記録実装がないため fail する（WARN が出ないため）
# ---------------------------------------------------------------------------

@test "C5: append 失敗時に WARN 出力 + spawn 継続（fail-open）" {
  # RED: spawn-controller.sh に自動記録実装がないため fail する
  # fail-open WARN は実装後に '[spawn-controller] WARN: intervention-log append failed' として出力される

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"
  > "$CLD_SPAWN_ARGS_LOG"

  # /dev/null/x は書き込み不可なディレクトリ（mkdir -p も失敗する）
  SUPERVISOR_DIR="/dev/null/x" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="fail-open test" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$prompt_file" \
    --window-name "test-window" 2>&1

  # spawn 自体は継続して成功すること（fail-open）
  assert_success

  # WARN メッセージが出力されていること
  echo "$output" | grep -q "\[spawn-controller\] WARN: intervention-log append failed" \
    || fail "fail-open WARN が出力されていない。出力: $output"
}

# ---------------------------------------------------------------------------
# C6: SKIP_PARALLEL_REASON=$'line1\nline2' の場合、ログ行が 1 行に保たれる (\n/\r → 空白 (helper 化後は制御文字全般))
# RED: 自動記録実装がないため fail する（サニタイズ実装なし）
# ---------------------------------------------------------------------------

@test "C6: 改行を含む REASON はサニタイズされてログ 1 行に収まる" {
  # RED: spawn-controller.sh に自動記録実装がないため fail する

  local log_dir
  log_dir_rel="_log_4_$$"; log_dir="$SANDBOX/$log_dir_rel"; mkdir -p "$log_dir"; pushd "$SANDBOX" >/dev/null

  local prompt_file
  prompt_file="$SANDBOX/prompt.txt"
  echo "test prompt" > "$prompt_file"
  > "$CLD_SPAWN_ARGS_LOG"

  SUPERVISOR_DIR="$log_dir_rel" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON=$'line1\nline2' \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$prompt_file" \
    --window-name "test-window"

  assert_success

  local log_file="$log_dir/intervention-log.md"
  [[ -f "$log_file" ]] \
    || fail "intervention-log.md が作成されていない: $log_file"

  # SKIP_PARALLEL_CHECK=1: を含む行数が 1 であること（改行が除去または空白置換されていること）
  local matching_lines
  matching_lines="$(grep -c "SKIP_PARALLEL_CHECK=1:" "$log_file" 2>/dev/null || echo "0")"
  [[ "$matching_lines" -eq 1 ]] \
    || fail "SKIP_PARALLEL_CHECK=1: を含む行が $matching_lines 行（期待: 1 行）。ログ内容: $(cat "$log_file" 2>/dev/null || echo '(empty)')"

  # "line1" と "line2" が別行にならず同一行に収まっていること
  local log_content
  log_content="$(grep "SKIP_PARALLEL_CHECK=1:" "$log_file")"
  [[ "$log_content" == *"line1"* && "$log_content" == *"line2"* ]] \
    || fail "サニタイズ後のログ行に line1/line2 両方が含まれていない: $log_content"

  rm -rf "$log_dir"
}
