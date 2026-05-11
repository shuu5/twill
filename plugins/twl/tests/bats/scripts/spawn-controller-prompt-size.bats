#!/usr/bin/env bats
# spawn-controller-prompt-size.bats - unit tests for spawn-controller.sh prompt size guard
# Generated from: deltaspec/changes/issue-799/specs/spawn-controller-size-guard.md
# Requirement: spawn-controller.sh prompt size guard / --force-large フラグの安全実装
# Coverage: unit + edge-cases

load '../helpers/common'

# ---------------------------------------------------------------------------
# setup / teardown
#
# spawn-controller.sh は plugins/twl/skills/su-observer/scripts/ にある。
# スクリプトが内部で cld-spawn を exec するため、STUB_BIN に cld-spawn mock
# を配置し PATH の先頭に追加する。
#
# spawn-controller.sh は $(readlink -f "$0") 起点で TWILL_ROOT を算出するため、
# 本物のパスを直接実行する。cld-spawn の mock は STUB_BIN に置くことで差し替える。
# ---------------------------------------------------------------------------

SPAWN_CONTROLLER=""
CLD_SPAWN_ARGS_LOG=""

setup() {
  common_setup

  # spawn-controller.sh の本物パス（tests/bats から見て skills/su-observer/scripts/）
  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  # cld-spawn 呼び出し引数を記録するファイル
  CLD_SPAWN_ARGS_LOG="$SANDBOX/cld-spawn-args.log"
  export CLD_SPAWN_ARGS_LOG

  # cld-spawn mock: 引数を記録して正常終了
  cat > "$STUB_BIN/cld-spawn" <<'MOCK'
#!/usr/bin/env bash
# cld-spawn mock: 引数をログに記録して exit 0
echo "$@" >> "${CLD_SPAWN_ARGS_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$STUB_BIN/cld-spawn"

  # plugins/session/scripts/ に向く CLD_SPAWN パスを STUB_BIN の mock にリダイレクトするため
  # spawn-controller.sh はスクリプト位置から TWILL_ROOT を算出して
  # $TWILL_ROOT/plugins/session/scripts/cld-spawn を呼ぶ。
  # そのパスは実 repo に依存するため、STUB_BIN/cld-spawn を PATH 先頭に置く代わりに
  # 実 cld-spawn が存在するディレクトリに mock を一時配置する方式を使う。
  #
  # ただしここでは STUB_BIN を PATH 先頭に置く common_setup の仕組みで
  # exec "$CLD_SPAWN" を stub できるよう、実 cld-spawn をバックアップし
  # STUB_BIN の cld-spawn に差し替える。

  _REAL_SESSION_SCRIPTS="$(cd "$REPO_ROOT/../../../../plugins/session/scripts" 2>/dev/null && pwd || true)"
  export _REAL_SESSION_SCRIPTS

  # Issue #1644: CLD_SPAWN_OVERRIDE env var で mock 切り替え
  MOCK_CLD_SPAWN="$STUB_BIN/cld-spawn"
  export MOCK_CLD_SPAWN

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

# ---------------------------------------------------------------------------
# ヘルパー: N 行の PROMPT_FILE を作成
# ---------------------------------------------------------------------------

make_prompt_file() {
  local lines="$1"
  local path="$2"
  local i
  for i in $(seq 1 "$lines"); do
    echo "line $i of the prompt"
  done > "$path"
}

# ===========================================================================
# Requirement: spawn-controller.sh prompt size guard
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 30 行以下の prompt は警告なし
# WHEN: PROMPT_FILE の行数が 30 行以下で spawn-controller.sh を呼び出す
# THEN: stderr に WARN: prompt size が出力されない
# ---------------------------------------------------------------------------

@test "size-guard: 30 行以下の prompt は stderr に WARN が出力されない" {
  make_prompt_file 30 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-window" 2>&1

  # cld-spawn mock が exit 0 を返す → スクリプト成功
  assert_success
  # WARN: prompt size が stderr（= ここでは merged output）に含まれない
  [[ "$output" != *"WARN: prompt size"* ]] \
    || fail "30 行以下なのに WARN が出力された"
}

@test "size-guard: 1 行の prompt は WARN が出力されない" {
  make_prompt_file 1 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-issue "$SANDBOX/prompt.txt" \
    --window-name "test-window" 2>&1

  assert_success
  [[ "$output" != *"WARN: prompt size"* ]] \
    || fail "1 行なのに WARN が出力された"
}

@test "size-guard: 29 行（threshold-1）の prompt は WARN が出力されない" {
  make_prompt_file 29 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-window" 2>&1

  assert_success
  [[ "$output" != *"WARN: prompt size"* ]] \
    || fail "29 行なのに WARN が出力された"
}

# ---------------------------------------------------------------------------
# Scenario: 31 行以上の prompt は警告を出力
# WHEN: PROMPT_FILE の行数が 31 行以上で spawn-controller.sh を呼び出す
# THEN: stderr に WARN: prompt size <N> lines exceeds recommended 30 lines. が出力される
# ---------------------------------------------------------------------------

@test "size-guard: 31 行の prompt は WARN が stderr に出力される" {
  make_prompt_file 31 "$SANDBOX/prompt.txt"

  # stderr のみキャプチャ
  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-explore '$SANDBOX/prompt.txt' \
    --window-name 'test-window' 2>&1 >/dev/null"

  assert_success
  [[ "$output" == *"WARN: prompt size"* ]] \
    || fail "31 行なのに WARN が出力されなかった"
}

@test "size-guard: 31 行の WARN に行数が含まれる" {
  make_prompt_file 31 "$SANDBOX/prompt.txt"

  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-explore '$SANDBOX/prompt.txt' \
    --window-name 'test-window' 2>&1 >/dev/null"

  assert_success
  [[ "$output" == *"31"* ]] \
    || fail "WARN に行数 31 が含まれていない: $output"
  [[ "$output" == *"exceeds recommended 30"* ]] \
    || fail "WARN に 'exceeds recommended 30' が含まれていない: $output"
}

@test "size-guard: 63 行の prompt は WARN が出力される（実際の障害再現）" {
  make_prompt_file 63 "$SANDBOX/prompt.txt"

  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-autopilot '$SANDBOX/prompt.txt' \
    --window-name 'test-window' 2>&1 >/dev/null"

  assert_success
  [[ "$output" == *"WARN: prompt size"* ]] \
    || fail "63 行なのに WARN が出力されなかった"
  [[ "$output" == *"63"* ]] \
    || fail "WARN に行数 63 が含まれていない: $output"
}

@test "size-guard: threshold 境界（30行）は WARN なし、31行は WARN あり（境界値検証）" {
  # 30 行: no warn
  make_prompt_file 30 "$SANDBOX/prompt-30.txt"
  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-explore '$SANDBOX/prompt-30.txt' \
    --window-name 'test-window-30' 2>&1 >/dev/null"
  [[ "$output" != *"WARN: prompt size"* ]] \
    || fail "30 行で WARN が出力された（境界エラー）"

  # 31 行: warn
  make_prompt_file 31 "$SANDBOX/prompt-31.txt"
  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-explore '$SANDBOX/prompt-31.txt' \
    --window-name 'test-window-31' 2>&1 >/dev/null"
  [[ "$output" == *"WARN: prompt size"* ]] \
    || fail "31 行で WARN が出力されなかった（境界エラー）"
}

# ---------------------------------------------------------------------------
# Scenario: --force-large フラグで警告を suppress
# WHEN: PROMPT_FILE の行数が 31 行以上かつ --force-large フラグを渡して呼び出す
# THEN: stderr に WARN: prompt size が出力されない
# ---------------------------------------------------------------------------

@test "force-large: --force-large で 31 行超の WARN が suppress される" {
  make_prompt_file 31 "$SANDBOX/prompt.txt"

  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-explore '$SANDBOX/prompt.txt' \
    --force-large --window-name 'test-window' 2>&1 >/dev/null"

  assert_success
  [[ "$output" != *"WARN: prompt size"* ]] \
    || fail "--force-large なのに WARN が出力された"
}

@test "force-large: --force-large で 63 行超の WARN も suppress される" {
  make_prompt_file 63 "$SANDBOX/prompt.txt"

  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-autopilot '$SANDBOX/prompt.txt' \
    --force-large --window-name 'test-window' 2>&1 >/dev/null"

  assert_success
  [[ "$output" != *"WARN: prompt size"* ]] \
    || fail "--force-large なのに WARN が出力された"
}

# ---------------------------------------------------------------------------
# Scenario: --force-large は cld-spawn 引数から strip される
# WHEN: --force-large フラグを渡して spawn-controller.sh を呼び出す
# THEN: cld-spawn に渡される引数に --force-large が含まれない（mock で検証）
# ---------------------------------------------------------------------------

@test "force-large-strip: --force-large が cld-spawn への引数から除去される" {
  make_prompt_file 31 "$SANDBOX/prompt.txt"
  # cld-spawn-args.log をクリア
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --force-large --window-name "test-window"

  assert_success
  # cld-spawn に渡った引数に --force-large が含まれないことを確認
  if [[ -f "$CLD_SPAWN_ARGS_LOG" ]]; then
    [[ "$(cat "$CLD_SPAWN_ARGS_LOG")" != *"--force-large"* ]] \
      || fail "cld-spawn の引数に --force-large が残っている"
  fi
}

@test "force-large-strip: --force-large なしの通常引数は cld-spawn に正常に渡される" {
  make_prompt_file 5 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --window-name "my-test-window"

  assert_success
  # cld-spawn が呼ばれ引数ログに何かが記録されている
  [[ -f "$CLD_SPAWN_ARGS_LOG" && -s "$CLD_SPAWN_ARGS_LOG" ]] \
    || fail "cld-spawn が呼ばれなかった"
}

@test "force-large-strip: --force-large が複数引数の中でも正しく strip される" {
  make_prompt_file 35 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-issue "$SANDBOX/prompt.txt" \
    --timeout 90 --force-large --window-name "test-window"

  assert_success
  if [[ -f "$CLD_SPAWN_ARGS_LOG" ]]; then
    local args
    args="$(cat "$CLD_SPAWN_ARGS_LOG")"
    [[ "$args" != *"--force-large"* ]] \
      || fail "cld-spawn の引数に --force-large が残っている: $args"
    # --timeout と --window-name は残っていること
    [[ "$args" == *"--timeout"* ]] \
      || fail "cld-spawn の引数から --timeout が消えた: $args"
  fi
}

# ---------------------------------------------------------------------------
# Scenario: 空の prompt は警告なし
# WHEN: PROMPT_FILE が空（0 行）で spawn-controller.sh を呼び出す
# THEN: stderr に WARN: prompt size が出力されない
#       （printf '%s\n' '' の挙動を明示確認）
# ---------------------------------------------------------------------------

@test "size-guard: 空の prompt ファイル（0 行）は WARN が出力されない" {
  # 空ファイル
  > "$SANDBOX/prompt-empty.txt"

  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-explore '$SANDBOX/prompt-empty.txt' \
    --window-name 'test-window' 2>&1 >/dev/null"

  assert_success
  [[ "$output" != *"WARN: prompt size"* ]] \
    || fail "空ファイルなのに WARN が出力された"
}

@test "size-guard: printf '%s\\\\n' '' で作成した 1 行ファイルは WARN が出力されない" {
  # printf '%s\n' '' は末尾改行のみの1行を生成する
  printf '%s\n' '' > "$SANDBOX/prompt-printf.txt"

  run bash -c "bash '$SANDBOX/run-spawn-controller.sh' co-explore '$SANDBOX/prompt-printf.txt' \
    --window-name 'test-window' 2>&1 >/dev/null"

  assert_success
  [[ "$output" != *"WARN: prompt size"* ]] \
    || fail "printf '%s\\n' '' の1行ファイルで WARN が出力された"
}

# ===========================================================================
# Requirement: --force-large フラグの安全実装
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: set -u 環境での空配列安全性
# WHEN: NEW_ARGS が空配列（--force-large のみの引数）の状態で set -- を実行する
# THEN: unbound variable エラーが発生しない
# ---------------------------------------------------------------------------

@test "set-u-safety: --force-large のみの引数で unbound variable エラーが発生しない" {
  make_prompt_file 35 "$SANDBOX/prompt.txt"

  # --force-large のみ渡す（他の余分な引数なし）
  # → NEW_ARGS が空配列になる経路
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --force-large

  # set -u での unbound variable は "unbound variable" を stderr に出して exit 1 する
  [[ "$output" != *"unbound variable"* ]] \
    || fail "set -u 環境で unbound variable エラーが発生した: $output"
  # exit code が 2 (unbound variable) でないことを確認
  # （mock の exit 0 = success, エラーなし）
  assert_success
}

@test "set-u-safety: --force-large + --window-name 指定でも unbound variable が出ない" {
  make_prompt_file 35 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-issue "$SANDBOX/prompt.txt" \
    --force-large --window-name "test-safe"

  [[ "$output" != *"unbound variable"* ]] \
    || fail "set -u 環境で unbound variable エラーが発生した: $output"
  assert_success
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "[edge] WARN は stdout ではなく stderr に出力される" {
  make_prompt_file 31 "$SANDBOX/prompt.txt"

  # stdout のみキャプチャ（stderr は /dev/null）
  STDOUT_ONLY="$(bash "$SANDBOX/run-spawn-controller.sh" co-explore \
    "$SANDBOX/prompt.txt" --window-name "test-window" 2>/dev/null || true)"

  [[ "$STDOUT_ONLY" != *"WARN: prompt size"* ]] \
    || fail "WARN が stdout に出力された（stderr 専用であるべき）"

  # stderr のみキャプチャ
  STDERR_ONLY="$(bash "$SANDBOX/run-spawn-controller.sh" co-explore \
    "$SANDBOX/prompt.txt" --window-name "test-window" 2>&1 >/dev/null || true)"

  [[ "$STDERR_ONLY" == *"WARN: prompt size"* ]] \
    || fail "WARN が stderr に出力されなかった"
}

@test "[edge] --force-large があっても prompt prepend (/twl:...) は行われる" {
  make_prompt_file 35 "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"

  run bash "$SANDBOX/run-spawn-controller.sh" co-explore "$SANDBOX/prompt.txt" \
    --force-large --window-name "test-window"

  assert_success
  # cld-spawn に渡る最後の引数（FINAL_PROMPT）に /twl:co-explore が含まれる
  if [[ -f "$CLD_SPAWN_ARGS_LOG" ]]; then
    [[ "$(cat "$CLD_SPAWN_ARGS_LOG")" == *"/twl:co-explore"* ]] \
      || fail "cld-spawn への引数に /twl:co-explore が含まれない"
  fi
}

@test "[edge] 無効な skill 名は size guard より前にエラーになる" {
  make_prompt_file 31 "$SANDBOX/prompt.txt"

  run bash "$SANDBOX/run-spawn-controller.sh" co-invalid "$SANDBOX/prompt.txt" \
    --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"invalid skill name"* ]] \
    || fail "無効な skill 名でエラーメッセージが出ない: $output"
}

@test "[edge] prompt file が存在しない場合は size guard より前にエラーになる" {
  run bash "$SANDBOX/run-spawn-controller.sh" co-explore \
    "$SANDBOX/nonexistent-prompt.txt" --window-name "test-window" 2>&1

  assert_failure
  [[ "$output" == *"prompt file not found"* ]] \
    || fail "存在しない prompt file でエラーメッセージが出ない: $output"
}
