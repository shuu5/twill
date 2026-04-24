#!/usr/bin/env bats
# spec-review-orchestrator-model.bats - --model フラグの unit tests (#946 B4)
#
# Scenarios covered:
#   - --model オプションが引数パーサーに存在する
#   - デフォルト WORKER_MODEL が sonnet である
#   - --model の値が cld-spawn 呼び出しに渡される
#   - --model 未指定でエラーが出ない

load '../helpers/common'

SCRIPT_SRC=""

setup() {
  common_setup
  SCRIPT_SRC="$REPO_ROOT/scripts/spec-review-orchestrator.sh"

  stub_command "tmux" '
    case "$1" in
      has-session)     exit 1 ;;
      new-window)      exit 0 ;;
      list-windows)    echo "" ;;
      set-option)      exit 0 ;;
      kill-window)     exit 0 ;;
      *)               exit 0 ;;
    esac
  '
  stub_command "cld" 'exit 0'
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: spec-review-orchestrator --model フラグ (#946 B4)
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: --model オプションが引数パーサーに存在する
# ---------------------------------------------------------------------------

@test "spec-review-model: --model オプションがスクリプトの引数パーサーに存在する" {
  grep -qE '\-\-model' "$SCRIPT_SRC" \
    || fail "--model option not found in spec-review-orchestrator.sh"
}

@test "spec-review-model: --model haiku 指定時に 'unknown option' エラーが出ない" {
  run bash "$SCRIPT_SRC" --model haiku --help 2>&1 || true
  [[ "$output" != *"不明なオプション: --model"* ]] \
    || fail "--model flag rejected as unknown option"
}

# ---------------------------------------------------------------------------
# Scenario: デフォルト WORKER_MODEL が sonnet
# ---------------------------------------------------------------------------

@test "spec-review-model: デフォルト WORKER_MODEL として sonnet が設定されている" {
  grep -qE 'WORKER_MODEL.*sonnet|sonnet.*WORKER_MODEL|WORKER_MODEL=.*sonnet' "$SCRIPT_SRC" \
    || fail "Default WORKER_MODEL='sonnet' not found in spec-review-orchestrator.sh"
}

@test "spec-review-model: --model 未指定時のデフォルト値が sonnet である" {
  grep -qE 'WORKER_MODEL=.*"sonnet"|WORKER_MODEL=.*'"'"'sonnet'"'"'' "$SCRIPT_SRC" \
    || fail "Default WORKER_MODEL='sonnet' assignment not found in spec-review-orchestrator.sh"
}

# ---------------------------------------------------------------------------
# Scenario: --model の値が cld-spawn 呼び出しに渡される
# ---------------------------------------------------------------------------

@test "spec-review-model: --model の値が cld-spawn に渡されるコードパスが存在する" {
  grep -qE 'cld-spawn.*model|MODEL.*cld-spawn|--model.*WORKER' "$SCRIPT_SRC" \
    || fail "--model value is not passed to cld-spawn in spec-review-orchestrator.sh"
}

@test "spec-review-model: cld-spawn 呼び出し行に --model \${WORKER_MODEL} が含まれる" {
  local spawn_line
  spawn_line=$(grep 'cld-spawn' "$SCRIPT_SRC" | grep -v '^#')
  echo "$spawn_line" | grep -q 'WORKER_MODEL' \
    || fail "WORKER_MODEL not referenced in cld-spawn invocation. Found: $spawn_line"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "spec-review-model: WORKER_MODEL 変数がスクリプト内で参照されている" {
  grep -q 'WORKER_MODEL' "$SCRIPT_SRC" \
    || fail "WORKER_MODEL variable not referenced in spec-review-orchestrator.sh"
}

@test "spec-review-model: issue-lifecycle-orchestrator.sh と同様の --model 伝播パターンである" {
  local srco_spawn
  srco_spawn=$(grep 'cld-spawn' "$SCRIPT_SRC" | grep -v '^#')
  echo "$srco_spawn" | grep -q 'model' \
    || fail "--model not referenced in spec-review-orchestrator.sh cld-spawn call. Line: $srco_spawn"
}
