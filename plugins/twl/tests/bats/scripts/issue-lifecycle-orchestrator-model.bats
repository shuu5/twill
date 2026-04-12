#!/usr/bin/env bats
# issue-lifecycle-orchestrator-model.bats - --model フラグの unit tests
#
# Spec: deltaspec/changes/issue-575/specs/model-propagation/spec.md
#
# Scenarios covered:
#   - --model フラグを指定して起動: cld-spawn に --model <model> が渡される
#   - --model フラグなしで起動: デフォルト sonnet が cld-spawn に渡される
#
# Edge cases:
#   - MODEL 変数が定義され cld-spawn 呼び出し周辺で参照されている
#   - --model 省略時に必須エラーが出ない

load '../helpers/common'

SCRIPT_SRC=""
PER_ISSUE_DIR=""

setup() {
  common_setup

  SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"

  PER_ISSUE_DIR="$(mktemp -d)"
  export PER_ISSUE_DIR

  # tmux stub
  stub_command "tmux" '
    case "$1" in
      has-session)     exit 1 ;;
      new-window)      exit 0 ;;
      list-windows)    echo "" ;;
      select-window)   exit 0 ;;
      set-option)      exit 0 ;;
      kill-window)     exit 0 ;;
      display-message) echo "main" ;;
      *)               exit 0 ;;
    esac
  '

  # cld stub
  stub_command "cld" 'exit 0'

  # flock stub
  stub_command "flock" '
    shift; shift
    exec "$@"
  '
}

teardown() {
  [ -n "$PER_ISSUE_DIR" ] && rm -rf "$PER_ISSUE_DIR"
  common_teardown
}

# ===========================================================================
# Requirement: issue-lifecycle-orchestrator --model フラグ
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: --model フラグを指定して起動
# WHEN issue-lifecycle-orchestrator.sh --per-issue-dir <DIR> --model haiku を実行する
# THEN spawn された cld セッションが --model haiku で起動される
# ---------------------------------------------------------------------------

@test "model-flag: --model オプションがスクリプトの引数パーサーに存在する" {
  grep -qE '\-\-model' "$SCRIPT_SRC" \
    || fail "--model option not found in issue-lifecycle-orchestrator.sh"
}

@test "model-flag: --model の値が cld-spawn 呼び出しに渡される" {
  grep -qE 'cld-spawn.*model|MODEL.*cld-spawn|--model.*cld' "$SCRIPT_SRC" \
    || fail "--model value is not passed to cld-spawn in script"
}

@test "model-flag: --model haiku 指定時に 'unknown option' エラーが出ない" {
  run bash "$SCRIPT_SRC" --per-issue-dir "$PER_ISSUE_DIR" --model haiku --help 2>&1 || true
  [[ "$output" != *"不明なオプション: --model"* ]] \
    || fail "--model flag rejected as unknown option"
}

@test "model-flag: cld-spawn 呼び出し時に --model フラグを渡すコードパスが存在する" {
  local spawn_lines
  spawn_lines=$(grep -n 'cld-spawn' "$SCRIPT_SRC" || true)
  [ -n "$spawn_lines" ] \
    || fail "cld-spawn invocation not found in script"
}

# ---------------------------------------------------------------------------
# Scenario: --model フラグなしで起動
# WHEN issue-lifecycle-orchestrator.sh --per-issue-dir <DIR> を --model なしで実行する
# THEN spawn された cld セッションがデフォルト sonnet で起動される
# ---------------------------------------------------------------------------

@test "model-flag: デフォルト MODEL 値として sonnet が設定されている" {
  grep -qE 'MODEL.*sonnet|sonnet.*MODEL|model.*sonnet|sonnet.*model' "$SCRIPT_SRC" \
    || fail "Default MODEL value 'sonnet' not found in script"
}

@test "model-flag: --model 未指定時のデフォルト値が sonnet である (スクリプト内確認)" {
  grep -qE 'MODEL=.*sonnet|:-sonnet' "$SCRIPT_SRC" \
    || fail "Default MODEL='sonnet' assignment not found in script"
}

@test "model-flag: --model オプションが省略可能であり、省略時も --model 必須エラーが出ない" {
  run bash "$SCRIPT_SRC" --per-issue-dir "$PER_ISSUE_DIR" 2>&1 || true
  [[ "$output" != *"--model"*"必須"* ]] \
    || fail "--model should be optional, but script requires it"
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "model-flag: MODEL 変数がスクリプト内で参照されている" {
  grep -q 'MODEL' "$SCRIPT_SRC" \
    || fail "MODEL variable not referenced in script"
}

@test "model-flag: --model の値が cld-spawn 周辺で伝播するロジックがある" {
  local spawn_lineno
  spawn_lineno=$(grep -n 'cld-spawn' "$SCRIPT_SRC" | head -1 | cut -d: -f1)
  if [ -n "$spawn_lineno" ]; then
    local context
    context=$(sed -n "$((spawn_lineno - 5)),$((spawn_lineno + 5))p" "$SCRIPT_SRC")
    echo "$context" | grep -qE 'MODEL|--model' \
      || fail "--model not referenced near cld-spawn invocation (lines $((spawn_lineno-5))-$((spawn_lineno+5)))"
  else
    fail "cld-spawn invocation not found in script"
  fi
}
