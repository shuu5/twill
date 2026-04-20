#!/usr/bin/env bats
# su-observer-budget-regex.bats
# Requirement: BUDGET-LOW regex が実 tmux status line フォーマット（5h:XX%(YYm)）に一致する
# Issue: #777 — observer BUDGET-LOW 検知 regex が実 format に不一致で自動 pause 発動不能
# Coverage: --type=unit --coverage=edge-cases
#
# 検証する仕様:
#   1. BUDGET_PCT regex が 5h:XX%(YYm) フォーマットから % 消費値を正しく抽出する
#   2. BUDGET_RAW regex が 5h:XX%(YYm) フォーマットから残量時間を正しく抽出する
#   3. 旧フォーマット（budget: 15m 形式）は一致しない（実フォーマットに特化）
#   4. 分換算ロジックが 4h21m、1h、15m を正しく変換する
#   5. 複数フォーマット混在行でも正しく抽出できる

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: BUDGET_PCT 抽出 (5h:\K[0-9]+(?=%))
# ---------------------------------------------------------------------------

extract_budget_pct() {
  local line="$1"
  echo "$line" | grep -oP '5h:\K[0-9]+(?=%)' | tail -1
}

# ---------------------------------------------------------------------------
# Helper: BUDGET_RAW 抽出 (5h:[0-9]+%\(\K[^\)]+)
# ---------------------------------------------------------------------------

extract_budget_raw() {
  local line="$1"
  echo "$line" | grep -oP '5h:[0-9]+%\(\K[^\)]+' | tail -1
}

# ---------------------------------------------------------------------------
# Helper: 分換算ロジック（SKILL.md の bash ロジックを再現）
# ---------------------------------------------------------------------------

to_minutes() {
  local raw="$1"
  local result=-1
  if [[ "$raw" =~ ^([0-9]+)h([0-9]+)m$ ]]; then
    result=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
  elif [[ "$raw" =~ ^([0-9]+)h$ ]]; then
    result=$(( ${BASH_REMATCH[1]} * 60 ))
  elif [[ "$raw" =~ ^([0-9]+)m$ ]]; then
    result=${BASH_REMATCH[1]}
  fi
  echo "$result"
}

# ---------------------------------------------------------------------------
# Tests: BUDGET_PCT 抽出
# ---------------------------------------------------------------------------

@test "BUDGET_PCT: 5h:10%(4h21m) から 10 を抽出する" {
  local line="shuu5@ipatho-server-2 36% 360k/1M Opus 4.7 [max] 5h:10%(4h21m) 7d:37%(6d1h)"
  run extract_budget_pct "$line"
  assert_success
  assert_output "10"
}

@test "BUDGET_PCT: 5h:98%(6m) から 98 を抽出する（高消費ケース）" {
  local line="shuu5@ipatho-server-2 5h:98%(6m) 7d:20%(5d14h)"
  run extract_budget_pct "$line"
  assert_success
  assert_output "98"
}

@test "BUDGET_PCT: 5h:0%(5h) から 0 を抽出する（残量最大ケース）" {
  local line="Claude [max] 5h:0%(5h) 7d:10%(6d7h)"
  run extract_budget_pct "$line"
  assert_success
  assert_output "0"
}

@test "BUDGET_PCT: 旧フォーマット（budget: 15m）では空を返す" {
  local line="budget: 15m remaining"
  run extract_budget_pct "$line"
  assert_success
  assert_output ""
}

@test "BUDGET_PCT: budget 情報のない行では空を返す" {
  local line="shuu5@ipatho-server-2 some other status"
  run extract_budget_pct "$line"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# Tests: BUDGET_RAW 抽出
# ---------------------------------------------------------------------------

@test "BUDGET_RAW: 5h:10%(4h21m) から 4h21m を抽出する" {
  local line="shuu5@ipatho-server-2 36% 360k/1M Opus 4.7 [max] 5h:10%(4h21m) 7d:37%(6d1h)"
  run extract_budget_raw "$line"
  assert_success
  assert_output "4h21m"
}

@test "BUDGET_RAW: 5h:98%(6m) から 6m を抽出する（分のみ残量）" {
  local line="shuu5@ipatho-server-2 5h:98%(6m) 7d:20%(5d14h)"
  run extract_budget_raw "$line"
  assert_success
  assert_output "6m"
}

@test "BUDGET_RAW: 5h:50%(2h30m) から 2h30m を抽出する" {
  local line="Claude [max] 5h:50%(2h30m)"
  run extract_budget_raw "$line"
  assert_success
  assert_output "2h30m"
}

@test "BUDGET_RAW: 旧フォーマット（budget: 15m）では空を返す" {
  local line="budget: 15m remaining"
  run extract_budget_raw "$line"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# Tests: 分換算ロジック
# ---------------------------------------------------------------------------

@test "分換算: 4h21m → 261 分" {
  run to_minutes "4h21m"
  assert_success
  assert_output "261"
}

@test "分換算: 15m → 15 分" {
  run to_minutes "15m"
  assert_success
  assert_output "15"
}

@test "分換算: 1h → 60 分" {
  run to_minutes "1h"
  assert_success
  assert_output "60"
}

@test "分換算: 6m → 6 分（高消費ケース）" {
  run to_minutes "6m"
  assert_success
  assert_output "6"
}

@test "分換算: 不一致フォーマットは -1 を返す（スキップ）" {
  run to_minutes "invalid"
  assert_success
  assert_output "-1"
}

# ---------------------------------------------------------------------------
# Tests: 閾値判定ロジック（threshold_percent=90, threshold_minutes=15）
# ---------------------------------------------------------------------------

@test "閾値判定: PCT=98 >= 90 でアラート発動する" {
  local pct=98
  local pct_threshold=90
  local budget_alert=false
  if [[ "$pct" =~ ^[0-9]+$ && $pct -ge $pct_threshold ]]; then
    budget_alert=true
  fi
  [[ "$budget_alert" == "true" ]]
}

@test "閾値判定: PCT=89 < 90 でアラート発動しない" {
  local pct=89
  local pct_threshold=90
  local budget_alert=false
  if [[ "$pct" =~ ^[0-9]+$ && $pct -ge $pct_threshold ]]; then
    budget_alert=true
  fi
  [[ "$budget_alert" == "false" ]]
}

@test "閾値判定: BUDGET_MIN=6 <= 15 でアラート発動する" {
  local budget_min=6
  local budget_threshold=15
  local budget_alert=false
  if [[ $budget_min -ge 0 && $budget_min -le $budget_threshold ]]; then
    budget_alert=true
  fi
  [[ "$budget_alert" == "true" ]]
}

@test "閾値判定: BUDGET_MIN=30 > 15 でアラート発動しない" {
  local budget_min=30
  local budget_threshold=15
  local budget_alert=false
  if [[ $budget_min -ge 0 && $budget_min -le $budget_threshold ]]; then
    budget_alert=true
  fi
  [[ "$budget_alert" == "false" ]]
}
