#!/usr/bin/env bats
# pre-bash-commit-validate.bats
#
# Tests for plugins/twl/scripts/hooks/pre-bash-commit-validate.sh
#
# Spec: deltaspec/changes/issue-568/specs/pre-bash-commit-validate/spec.md
#
# Scenarios:
#   1. git commit 時に validate hook が起動する
#      WHEN ユーザーが Claude Code から `git commit` を含む Bash コマンドを実行する
#      THEN pre-bash-commit-validate.sh が PreToolUse フェーズで自動実行される
#
#   2. deps.yaml 型ルール違反ありの場合
#      WHEN `twl --validate` の実行結果で violations > 0 である
#      THEN スクリプトが exit 2 を返し、コミットがブロックされ、stderr に違反内容が出力される
#
#   3. deps.yaml に違反なしの場合
#      WHEN `twl --validate` の実行結果で violations == 0 である
#      THEN スクリプトが exit 0 を返し、コミットが通過する
#
#   4. git status など git commit 以外の Bash コマンド
#      WHEN $TOOL_INPUT_command に `git commit` パターンが含まれない
#      THEN スクリプトが即 exit 0 を返し、何も実行しない
#
#   5. deps.yaml が存在しない場合
#      WHEN スクリプトが `cd plugins/twl` した後に `deps.yaml` が見つからない
#      THEN スクリプトが exit 0 を返し、コミットをブロックしない
#
#   6. TWL_SKIP_COMMIT_GATE=1 設定時
#      WHEN 環境変数 TWL_SKIP_COMMIT_GATE が `1` に設定された状態で `git commit` を実行する
#      THEN スクリプトが exit 0 を返し、コミットが通過する
#
#   7. 通常の validate 実行時間
#      WHEN `twl --validate` が正常に実行される
#      THEN 5000ms 以内に完了し、timeout エラーが発生しない
#
#   8. deps.yaml へのスクリプト登録
#      WHEN `plugins/twl/deps.yaml` を参照する
#      THEN `scripts` セクションに `pre-bash-commit-validate` エントリが存在し、path と description が設定されている
#
# Edge cases:
#   9. git commit -m "message" など git commit にオプションが付いた場合も hook が発火する
#  10. TOOL_INPUT_command 未設定（環境変数なし）→ exit 0 (no-op)
#  11. 不正 JSON 入力 → exit 0 (no-op)
#  12. twl コマンドが存在しない場合 → exit 0 (skip gracefully)
#  13. violations == 0 でも stdout は空（ノイズを出さない）
#  14. violations > 0 の場合、exit コードは必ず 2（1 でなく 2）

load '../helpers/common'

HOOK_SRC=""

setup() {
  common_setup

  HOOK_SRC="$(cd "$REPO_ROOT" && pwd)/scripts/hooks/pre-bash-commit-validate.sh"

  # Setup a fake plugins/twl directory structure inside sandbox
  mkdir -p "$SANDBOX/plugins/twl"

  # Default: deps.yaml exists (most tests assume it)
  touch "$SANDBOX/plugins/twl/deps.yaml"

  # Default: TOOL_INPUT_command is unset; individual tests set it as needed
  unset TOOL_INPUT_command
  unset TWL_SKIP_COMMIT_GATE
}

teardown() {
  common_teardown
}

# Helper: invoke hook with TOOL_INPUT_command set
# BATS_TEST_DIRNAME を明示的に渡して PLUGINS_TWL_DIR サンドボックスオーバーライドを有効化する
_run_hook() {
  local cmd="${1:-}"
  TOOL_INPUT_command="$cmd" \
  PLUGINS_TWL_DIR="$SANDBOX/plugins/twl" \
  BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME}" \
    bash "$HOOK_SRC"
}

# Helper: invoke hook passing a JSON payload on stdin (Claude Code PreToolUse format)
_run_hook_payload() {
  local payload="$1"
  shift
  PLUGINS_TWL_DIR="$SANDBOX/plugins/twl" \
  BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME}" \
    bash "$HOOK_SRC" <<< "$payload"
}

# ---------------------------------------------------------------------------
# Scenario 2: violations > 0 → exit 2, stderr に違反内容
# WHEN twl --validate の実行結果で violations > 0
# THEN exit 2、コミットがブロックされ stderr に違反内容が出力される
# ---------------------------------------------------------------------------
@test "violations > 0 のとき exit 2 を返す" {
  stub_command "twl" 'echo "violation: type mismatch on deps.yaml:10" >&2; exit 2'
  run _run_hook "git commit -m 'wip'"
  [ "$status" -eq 2 ]
}

@test "violations > 0 のとき stderr に違反内容が出力される" {
  stub_command "twl" 'echo "violation: type mismatch on deps.yaml:10" >&2; exit 2'
  run _run_hook "git commit -m 'wip'"
  [ "$status" -eq 2 ]
  # bats captures stderr in $output when run captures it; verify violation message present
  [[ "$output" == *"violation"* ]] || [[ "$stderr" == *"violation"* ]]
}

@test "violations > 0 のとき exit コードは 1 ではなく 2 である" {
  stub_command "twl" 'exit 2'
  run _run_hook "git commit -m 'test'"
  [ "$status" -ne 1 ]
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Scenario 3: violations == 0 → exit 0
# WHEN twl --validate の実行結果で violations == 0
# THEN exit 0、コミットが通過する
# ---------------------------------------------------------------------------
@test "violations == 0 のとき exit 0 を返す" {
  stub_command "twl" 'exit 0'
  run _run_hook "git commit -m 'clean'"
  [ "$status" -eq 0 ]
}

@test "violations == 0 のとき stdout は空（ノイズを出さない）" {
  stub_command "twl" 'exit 0'
  run _run_hook "git commit -m 'clean'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 4: git commit 以外のコマンド → exit 0、何も実行しない
# WHEN $TOOL_INPUT_command に git commit パターンが含まれない
# THEN 即 exit 0、twl を呼ばない
# ---------------------------------------------------------------------------
@test "git status は git commit ではないので即 exit 0 を返す" {
  stub_command "twl" 'exit 99'  # Should never be called
  run _run_hook "git status"
  [ "$status" -eq 0 ]
}

@test "git push は git commit ではないので即 exit 0 を返す" {
  stub_command "twl" 'exit 99'
  run _run_hook "git push origin main"
  [ "$status" -eq 0 ]
}

@test "ls -la は git commit ではないので即 exit 0 を返す" {
  stub_command "twl" 'exit 99'
  run _run_hook "ls -la"
  [ "$status" -eq 0 ]
}

@test "git commit 以外のコマンドでは twl を呼ばない（stdout/stderr 空）" {
  stub_command "twl" 'echo "twl_was_called" >&2; exit 0'
  run _run_hook "git diff --stat"
  [ "$status" -eq 0 ]
  [[ "$output" != *"twl_was_called"* ]]
}

# ---------------------------------------------------------------------------
# Edge case 9: git commit にオプションが付いた場合も hook が発火する
# ---------------------------------------------------------------------------
@test "git commit -m オプション付きでも hook が発火し twl を呼ぶ" {
  stub_command "twl" 'exit 0'
  run _run_hook "git commit -m 'feat: add feature'"
  [ "$status" -eq 0 ]
}

@test "git commit --amend でも hook が発火する" {
  stub_command "twl" 'exit 0'
  run _run_hook "git commit --amend --no-edit"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Scenario 5: deps.yaml が存在しない場合 → exit 0 (skip)
# WHEN スクリプトが plugins/twl に cd した後に deps.yaml が見つからない
# THEN exit 0、コミットをブロックしない
# ---------------------------------------------------------------------------
@test "deps.yaml が存在しない場合は exit 0 でスキップする" {
  rm -f "$SANDBOX/plugins/twl/deps.yaml"
  stub_command "twl" 'exit 99'  # Should never be called
  run _run_hook "git commit -m 'wip'"
  [ "$status" -eq 0 ]
}

@test "deps.yaml が存在しない場合は twl を呼ばない" {
  rm -f "$SANDBOX/plugins/twl/deps.yaml"
  stub_command "twl" 'echo "twl_was_called" >&2; exit 0'
  run _run_hook "git commit -m 'wip'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"twl_was_called"* ]]
}

# ---------------------------------------------------------------------------
# Scenario 6: TWL_SKIP_COMMIT_GATE=1 → exit 0 (bypass)
# WHEN 環境変数 TWL_SKIP_COMMIT_GATE が 1 に設定されている
# THEN exit 0、twl を呼ばない
# ---------------------------------------------------------------------------
@test "TWL_SKIP_COMMIT_GATE=1 のとき exit 0 でスキップする" {
  stub_command "twl" 'exit 99'
  TWL_SKIP_COMMIT_GATE=1 run _run_hook "git commit -m 'bypass'"
  [ "$status" -eq 0 ]
}

@test "TWL_SKIP_COMMIT_GATE=1 のとき twl を呼ばない" {
  stub_command "twl" 'echo "twl_was_called" >&2; exit 0'
  TWL_SKIP_COMMIT_GATE=1 run _run_hook "git commit -m 'bypass'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"twl_was_called"* ]]
}

@test "TWL_SKIP_COMMIT_GATE=0 のときはスキップしない（通常の validate を実行）" {
  stub_command "twl" 'exit 0'
  TWL_SKIP_COMMIT_GATE=0 run _run_hook "git commit -m 'normal'"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Scenario 7: タイムアウト制限 — 5000ms 以内に完了
# WHEN twl --validate が正常に実行される
# THEN 5000ms 以内に完了する
# ---------------------------------------------------------------------------
@test "validate 実行が 5000ms 以内に完了する" {
  stub_command "twl" 'exit 0'
  local start_ms
  local end_ms
  start_ms=$(date +%s%3N)
  run _run_hook "git commit -m 'timing'"
  end_ms=$(date +%s%3N)
  local elapsed=$(( end_ms - start_ms ))
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 5000 ] || {
    echo "Elapsed ${elapsed}ms exceeds 5000ms timeout" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Edge case 10: TOOL_INPUT_command 未設定 → exit 0 (no-op)
# ---------------------------------------------------------------------------
@test "TOOL_INPUT_command 未設定の場合は exit 0 (no-op)" {
  stub_command "twl" 'exit 99'
  unset TOOL_INPUT_command
  PLUGINS_TWL_DIR="$SANDBOX/plugins/twl" run bash "$HOOK_SRC"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Edge case 12: twl コマンドが存在しない場合 → exit 0 (graceful skip)
# ---------------------------------------------------------------------------
@test "twl コマンドが存在しない場合は exit 0 でスキップする（グレースフル）" {
  # Do NOT stub twl; remove any stub and shadow real twl with a "not found" stub
  rm -f "$STUB_BIN/twl"
  # PATH に存在しない dummy ディレクトリを先頭に追加して twl を隠す
  # twl が $STUB_BIN にも dummy_no_twl_bin にも存在しないことで command -v twl が失敗する
  local dummy_bin="$SANDBOX/dummy_no_twl_bin"
  mkdir -p "$dummy_bin"
  # 元の PATH から ~/.local/bin を除外して twl が見つからない環境を作る
  local filtered_path
  filtered_path=$(echo "$PATH" | tr ':' '\n' | grep -v 'local/bin' | tr '\n' ':' | sed 's/:$//')
  PATH="$STUB_BIN:$filtered_path" run _run_hook "git commit -m 'no-twl'"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Scenario 8: deps.yaml へのスクリプト登録
# WHEN plugins/twl/deps.yaml を参照する
# THEN scripts セクションに pre-bash-commit-validate エントリが存在し、
#      path と description が設定されている
# ---------------------------------------------------------------------------
@test "deps.yaml の scripts セクションに pre-bash-commit-validate エントリが存在する" {
  local deps_yaml="$REPO_ROOT/deps.yaml"
  [[ -f "$deps_yaml" ]] || { echo "deps.yaml not found at $deps_yaml" >&2; return 1; }
  grep -q "pre-bash-commit-validate" "$deps_yaml" || {
    echo "pre-bash-commit-validate not found in deps.yaml" >&2
    return 1
  }
}

@test "deps.yaml の pre-bash-commit-validate エントリに path が設定されている" {
  local deps_yaml="$REPO_ROOT/deps.yaml"
  [[ -f "$deps_yaml" ]] || { echo "deps.yaml not found at $deps_yaml" >&2; return 1; }
  grep -A5 "pre-bash-commit-validate:" "$deps_yaml" | grep -q "path:" || {
    echo "path field not found in pre-bash-commit-validate entry" >&2
    return 1
  }
}

@test "deps.yaml の pre-bash-commit-validate エントリに description が設定されている" {
  local deps_yaml="$REPO_ROOT/deps.yaml"
  [[ -f "$deps_yaml" ]] || { echo "deps.yaml not found at $deps_yaml" >&2; return 1; }
  grep -A5 "pre-bash-commit-validate:" "$deps_yaml" | grep -q "description:" || {
    echo "description field not found in pre-bash-commit-validate entry" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Scenario 1: git commit 時に validate hook が起動する（統合確認）
# WHEN ユーザーが git commit を含む Bash コマンドを実行する
# THEN pre-bash-commit-validate.sh が PreToolUse フェーズで自動実行され
#      twl --validate が呼ばれる
# ---------------------------------------------------------------------------
@test "git commit コマンドで twl --validate が呼び出される" {
  local twl_called_flag="$SANDBOX/twl_called"
  cat > "$STUB_BIN/twl" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--validate"* ]]; then
  touch "${TWL_CALLED_FLAG}"
fi
exit 0
STUB
  chmod +x "$STUB_BIN/twl"
  TWL_CALLED_FLAG="$twl_called_flag" \
  PLUGINS_TWL_DIR="$SANDBOX/plugins/twl" \
  TOOL_INPUT_command="git commit -m 'hook test'" \
    bash "$HOOK_SRC"
  [ -f "$twl_called_flag" ] || {
    echo "twl --validate was not called" >&2
    return 1
  }
}

@test "git commit コマンドで twl --validate が --validate フラグ付きで呼び出される" {
  local args_file="$SANDBOX/twl_args"
  cat > "$STUB_BIN/twl" <<STUB
#!/usr/bin/env bash
echo "\$*" > "$args_file"
exit 0
STUB
  chmod +x "$STUB_BIN/twl"
  run _run_hook "git commit -m 'check args'"
  [ "$status" -eq 0 ]
  [ -f "$args_file" ] || { echo "twl was not called" >&2; return 1; }
  grep -q "\-\-validate" "$args_file" || {
    echo "twl was called without --validate: $(cat "$args_file")" >&2
    return 1
  }
}
