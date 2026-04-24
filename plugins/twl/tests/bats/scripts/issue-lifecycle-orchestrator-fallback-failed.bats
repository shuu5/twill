#!/usr/bin/env bats
# issue-lifecycle-orchestrator-fallback-failed.bats - _generate_fallback_report の
# status:failed 分岐を検証する (#946 B3)
#
# Scenarios covered:
#   - inject_exhausted_* → status: failed
#   - window_lost → status: failed
#   - input_waiting_terminal_* → status: failed
#   - unclassified_input_waiting → status: failed
#   - unclassified_askuserquestion → status: failed
#   - unexpected_permission_prompt → status: failed
#   - 中間ファイルあり (aggregate.yaml) + failed reason → status: failed
#   - 中間ファイルあり (findings.yaml) + failed reason → status: failed
#   - 非 failed reason → status: done (既存動作維持)
#   - 呼び出し元 (結果サマリー) が status:failed を failure として計上する

load '../helpers/common'

SCRIPT_SRC=""

setup() {
  common_setup
  SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"
  export SCRIPTS_ROOT="$SANDBOX/scripts"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: inject_exhausted_* → status: failed
# ---------------------------------------------------------------------------

@test "fallback-failed: inject_exhausted_5 → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "inject_exhausted_5"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for inject_exhausted_5, got: $status"

  rm -rf "$subdir"
}

@test "fallback-failed: inject_exhausted_3 → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "inject_exhausted_3"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for inject_exhausted_3, got: $status"

  rm -rf "$subdir"
}

# ---------------------------------------------------------------------------
# Scenario: window_lost → status: failed
# ---------------------------------------------------------------------------

@test "fallback-failed: window_lost → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "window_lost"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for window_lost, got: $status"

  rm -rf "$subdir"
}

# ---------------------------------------------------------------------------
# Scenario: input_waiting_terminal_* → status: failed
# ---------------------------------------------------------------------------

@test "fallback-failed: input_waiting_terminal_done → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "input_waiting_terminal_done"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for input_waiting_terminal_done, got: $status"

  rm -rf "$subdir"
}

@test "fallback-failed: input_waiting_terminal_failed → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "input_waiting_terminal_failed"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for input_waiting_terminal_failed, got: $status"

  rm -rf "$subdir"
}

# ---------------------------------------------------------------------------
# Scenario: unclassified_* → status: failed
# ---------------------------------------------------------------------------

@test "fallback-failed: unclassified_input_waiting → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "unclassified_input_waiting"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for unclassified_input_waiting, got: $status"

  rm -rf "$subdir"
}

@test "fallback-failed: unclassified_askuserquestion → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "unclassified_askuserquestion"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for unclassified_askuserquestion, got: $status"

  rm -rf "$subdir"
}

@test "fallback-failed: unexpected_permission_prompt → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "unexpected_permission_prompt"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for unexpected_permission_prompt, got: $status"

  rm -rf "$subdir"
}

# ---------------------------------------------------------------------------
# Scenario: aggregate.yaml あり + failed reason → status: failed
# ---------------------------------------------------------------------------

@test "fallback-failed: aggregate.yaml + inject_exhausted_5 → status:done (中間ファイルあり: 部分結果保持)" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"
  cat > "$subdir/OUT/aggregate.yaml" <<'YAML'
findings:
  - id: f1
    severity: high
YAML

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "inject_exhausted_5"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "done" ] \
    || fail "Expected status=done for aggregate.yaml + inject_exhausted_5 (中間ファイルあり維持), got: $status"

  rm -rf "$subdir"
}

# ---------------------------------------------------------------------------
# Scenario: findings.yaml あり + failed reason → status: done (中間ファイルあり維持)
# AC: 「中間ファイルあり (aggregate.yaml/findings.yaml) ケースは status:done のまま維持」
# ---------------------------------------------------------------------------

@test "fallback-failed: findings.yaml + window_lost → status:done (中間ファイルあり: 部分結果保持)" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"
  cat > "$subdir/OUT/findings.yaml" <<'YAML'
finding1:
  severity: medium
YAML

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "window_lost"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "done" ] \
    || fail "Expected status=done for findings.yaml + window_lost (中間ファイルあり維持), got: $status"

  rm -rf "$subdir"
}

# ---------------------------------------------------------------------------
# Scenario: 非 failed reason → status: done (既存動作維持)
# ---------------------------------------------------------------------------

@test "fallback-failed: yn_confirmation_prompt → report.json が status:failed になる" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "yn_confirmation_prompt"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "failed" ] \
    || fail "Expected status=failed for yn_confirmation_prompt, got: $status"

  rm -rf "$subdir"
}

@test "fallback-failed: 非失敗 reason の場合は status:done のまま" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "intentional_skip"

  local status
  status=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d['status'])")
  [ "$status" = "done" ] \
    || fail "Expected status=done for non-failed reason, got: $status"

  rm -rf "$subdir"
}

# ---------------------------------------------------------------------------
# Scenario: 呼び出し元サマリーが status:failed を FAILED として計上する
# WHEN issue-lifecycle-orchestrator.sh の結果サマリーセクションを確認する
# THEN status == "done" 以外は FAILED にカウントするロジックが存在する
# ---------------------------------------------------------------------------

@test "fallback-failed: 結果サマリーで status:done 以外を FAILED 計上するロジックがある" {
  grep -qE '"done"|== "done"' "$SCRIPT_SRC" \
    || fail "Result summary 'done' check not found in script"
}

@test "fallback-failed: 結果サマリーで OVERALL_FAILED または FAILED インクリメントが status:done 以外で発生する" {
  grep -qE 'FAILED\+\+|FAILED=\$\(\(FAILED.*\+.*1\)\)|OVERALL_FAILED' "$SCRIPT_SRC" \
    || fail "FAILED counter increment not found in result summary section"
}

# ---------------------------------------------------------------------------
# Scenario: report.json が fallback:true を含む (既存 invariant 維持)
# ---------------------------------------------------------------------------

@test "fallback-failed: inject_exhausted_5 の report.json が fallback:true を含む" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  source "$SCRIPT_SRC"
  _generate_fallback_report "$subdir" "inject_exhausted_5"

  local fallback
  fallback=$(python3 -c "import json; d=json.load(open('$subdir/OUT/report.json')); print(d.get('fallback', False))")
  [ "$fallback" = "True" ] \
    || fail "Expected fallback=True in report.json, got: $fallback"

  rm -rf "$subdir"
}

# ===========================================================================
# RED tests for Issue #956 AC5 (case 4) + AC3 — 実装前は FAIL する
# AC3: unclassified 初検知は pending debounce、連続2回 (>10s) で failed 化
#      reason: unclassified_input_waiting_confirmed
# ===========================================================================

# ---------------------------------------------------------------------------
# RED AC5 case4 (AC3): unclassified 初検知は pending debounce、連続 2 回で failed 化
# WHEN unclassified を初めて検知
# THEN .unclassified_debounce_ts に timestamp 保存し、即 failed 化しない (pending)
# WHEN 10s 以上経過後も再度 unclassified を検知
# THEN reason=unclassified_input_waiting_confirmed で failed 化する
# TODO: RED - 実装前は fail する（AC3: unclassified debounce 未実装）
# ---------------------------------------------------------------------------

@test "fallback-failed: unclassified 初検知は pending debounce（即 failed 化しない）" {
  export LC_ALL=C.UTF-8

  # AC3実装後: .unclassified_debounce_ts ファイルを使って初回検知は pending 継続する
  # 現在: unclassified → 即 failed 化するため RED
  grep -qE 'unclassified_debounce_ts|\.unclassified_debounce' \
    "$SCRIPT_SRC" \
    && fail "このテストは RED 状態であるべきですが、スクリプトに unclassified_debounce_ts 実装が見つかりました。テストをGREENに更新してください。" \
    || fail "AC3 RED: .unclassified_debounce_ts を使った debounce 処理がスクリプトに存在しない。実装が必要。"
}

@test "fallback-failed: unclassified 連続 2 回検知 (>10s) で reason=unclassified_input_waiting_confirmed で failed 化" {
  export LC_ALL=C.UTF-8

  # AC3実装後: 2回目の unclassified 検知（10s経過後）で unclassified_input_waiting_confirmed reason で failed
  # 現在: unclassified_input_waiting_confirmed reason が存在しないため RED
  grep -qE 'unclassified_input_waiting_confirmed' \
    "$SCRIPT_SRC" \
    && fail "このテストは RED 状態であるべきですが、スクリプトに unclassified_input_waiting_confirmed 実装が見つかりました。テストをGREENに更新してください。" \
    || fail "AC3 RED: unclassified_input_waiting_confirmed reason がスクリプトに存在しない。実装が必要。"
}
