#!/usr/bin/env bats
# spawn-controller.bats - spawn-controller.sh の動作確認テスト
# Issue #841: spawn-controller.sh の bats テスト 4+ ケース追加
#
# Coverage:
#   1. /twl:<skill> 自動 prepend
#   2. --help / -h / --version invalid flag reject
#   3. window 名 wt-<skill>-<HHMMSS> 自動生成
#   4. prompt-file が存在しない場合のエラー処理
#   5. invalid skill 名 reject

load '../helpers/common'

SPAWN_CONTROLLER=""
CLD_SPAWN_ARGS_LOG=""

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

  # Issue #1644: CLD_SPAWN_OVERRIDE env var で mock 切り替え（旧 sed-replace + temp script は
  # TWILL_ROOT が誤解決される latent bug があったため env override pattern に移行）
  cat > "$SANDBOX/run-spawn-controller.sh" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec env CLD_SPAWN_OVERRIDE="$MOCK_CLD_SPAWN" \
  SKIP_PARALLEL_CHECK=\${SKIP_PARALLEL_CHECK:-1} \
  SKIP_PARALLEL_REASON="\${SKIP_PARALLEL_REASON:-bats test}" \
  bash "$SPAWN_CONTROLLER" "\$@"
WRAPPER
  chmod +x "$SANDBOX/run-spawn-controller.sh"
}

teardown() {
  common_teardown
}

make_prompt_file() {
  local lines="$1"
  local path="$2"
  local i
  for i in $(seq 1 "$lines"); do
    echo "line $i of the prompt"
  done > "$path"
}

# ===========================================================================
# Requirement 1: /twl:<skill> 自動 prepend
# ===========================================================================

@test "prepend: skill 名が /twl:co-explore として prompt 先頭に prepend される" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-window"

  assert_success
  [[ -f "$CLD_SPAWN_ARGS_LOG" ]] || fail "cld-spawn が呼ばれなかった"
  [[ "$(cat "$CLD_SPAWN_ARGS_LOG")" == *"/twl:co-explore"* ]] \
    || fail "cld-spawn への引数に /twl:co-explore が含まれない"
}

@test "prepend: twl: prefix 付き skill 名でも /twl:<skill> として prepend される" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" twl:co-issue "$SANDBOX/prompt.txt" \
    --window-name "test-window"

  assert_success
  [[ "$(cat "$CLD_SPAWN_ARGS_LOG")" == *"/twl:co-issue"* ]] \
    || fail "cld-spawn への引数に /twl:co-issue が含まれない"
}

@test "prepend: prompt 本文が /twl:<skill> の後ろに続く" {
  echo "my-unique-prompt-content" > "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-window"

  assert_success
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"my-unique-prompt-content"* ]] \
    || fail "cld-spawn への引数に prompt 本文が含まれない: $args"
}

# ===========================================================================
# Requirement 2: --help / -h / --version invalid flag reject
# ===========================================================================

@test "invalid-flag: --help が渡された場合はエラーで終了する" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --help --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"--help"* ]] \
    || fail "--help エラーメッセージが出ない: $output"
}

@test "invalid-flag: -h が渡された場合はエラーで終了する" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    -h --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"-h"* ]] \
    || fail "-h エラーメッセージが出ない: $output"
}

@test "invalid-flag: --version が渡された場合はエラーで終了する" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --version --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"--version"* ]] \
    || fail "--version エラーメッセージが出ない: $output"
}

@test "invalid-flag: エラーメッセージに有効な cld-spawn option のヒントが含まれる" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --help 2>&1

  assert_failure
  [[ "$output" == *"--window-name"* ]] \
    || fail "エラーメッセージに有効な option のヒントが含まれない: $output"
}

# ===========================================================================
# Requirement 3: window 名 wt-<skill>-<HHMMSS> 自動生成
# ===========================================================================

@test "window-name: --window-name 未指定時は wt-<skill>-<HHMMSS> 形式で自動設定される" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt"

  assert_success
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" =~ wt-co-explore-[0-9]{6} ]] \
    || fail "wt-co-explore-HHMMSS 形式の window 名が含まれない: $args"
}

@test "window-name: --window-name 明示時は自動生成されない" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-issue "$SANDBOX/prompt.txt" \
    --window-name "my-custom-window"

  assert_success
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"my-custom-window"* ]] \
    || fail "指定した window 名が cld-spawn に渡らない: $args"
  [[ "$args" != *"wt-co-issue-"* ]] \
    || fail "明示 window 名があるのに自動生成 window 名も渡された: $args"
}

@test "window-name: skill 名が window 名に反映される（co-autopilot の場合）" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-autopilot "$SANDBOX/prompt.txt"

  assert_success
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" =~ wt-co-autopilot-[0-9]{6} ]] \
    || fail "wt-co-autopilot-HHMMSS 形式の window 名が含まれない: $args"
}

# ===========================================================================
# Requirement 4: prompt-file が存在しない場合のエラー処理
# ===========================================================================

@test "prompt-not-found: 存在しない prompt ファイルはエラーで終了する" {
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore \
    "$SANDBOX/nonexistent.txt" --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"prompt file not found"* ]] \
    || fail "存在しない prompt file で適切なエラーが出ない: $output"
}

@test "prompt-not-found: エラーメッセージにファイルパスが含まれる" {
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore \
    "$SANDBOX/no-such-file.txt" --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"no-such-file.txt"* ]] \
    || fail "エラーメッセージに問題ファイルパスが含まれない: $output"
}

@test "prompt-not-found: exit code が 2 である" {
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore \
    "$SANDBOX/nonexistent.txt" --window-name "test-window" 2>&1

  [[ "$status" -eq 2 ]] \
    || fail "exit code が 2 ではない: $status"
}

# ===========================================================================
# Requirement 5: invalid skill 名 reject
# ===========================================================================

@test "skill-validate: 無効な skill 名はエラーで終了する" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-invalid "$SANDBOX/prompt.txt" \
    --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"invalid skill name"* ]] \
    || fail "無効な skill 名でエラーが出ない: $output"
}

@test "skill-validate: エラーメッセージに有効な skill リストが含まれる" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" unknown-skill "$SANDBOX/prompt.txt" \
    --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"co-explore"* ]] \
    || fail "エラーメッセージに有効な skill リストが含まれない: $output"
}

# ===========================================================================
# AC12: SKIP_PARALLEL_CHECK=1 パスで実 .supervisor/intervention-log.md を汚染しない
# Regression fix: SUPERVISOR_DIR=$(mktemp -d) 注入により実ログを保護
# RED: spawn-controller.sh に自動記録実装がないため fail する
# ===========================================================================

@test "skip-parallel-check: SKIP_PARALLEL_CHECK=1 + SUPERVISOR_DIR 注入で実ログを汚染しない（regression fix）" {
  # RED: spawn-controller.sh に自動記録実装がないため fail する
  # （実装後は SUPERVISOR_DIR 指定先にのみ記録され、実 .supervisor は汚染されない）
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  # SUPERVISOR_DIR は相対パスのみ許可 (validate_supervisor_dir)。
  # SANDBOX に cd して相対 ".supervisor-test" を指定。
  local rel_supervisor_dir=".supervisor-test"
  mkdir -p "$SANDBOX/$rel_supervisor_dir"

  cd "$SANDBOX"
  SUPERVISOR_DIR="$rel_supervisor_dir" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="regression-fix test" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-window"

  assert_success

  # 指定した相対 supervisor_dir に intervention-log.md が作成されていること（RED ポイント）
  [[ -f "$SANDBOX/$rel_supervisor_dir/intervention-log.md" ]] \
    || fail "SUPERVISOR_DIR 指定先に intervention-log.md が作成されていない: $SANDBOX/$rel_supervisor_dir/intervention-log.md"
}

@test "skip-parallel-check: SKIP_PARALLEL_CHECK=1 で spawn は継続される" {
  # 実装後も PASS すべき regression guard
  # SKIP_PARALLEL_CHECK=1 設定時に spawn が abort せず cld-spawn が呼ばれること
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  local rel_supervisor_dir=".supervisor-test"
  mkdir -p "$SANDBOX/$rel_supervisor_dir"

  cd "$SANDBOX"
  SUPERVISOR_DIR="$rel_supervisor_dir" \
  SKIP_PARALLEL_CHECK=1 \
  SKIP_PARALLEL_REASON="spawn-continues test" \
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-window"

  assert_success
  [[ -f "$CLD_SPAWN_ARGS_LOG" ]] || fail "cld-spawn が呼ばれなかった"
}
