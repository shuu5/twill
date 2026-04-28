#!/usr/bin/env bats
# budget-detect-1022.bats - Issue #1022 AC1/AC4 TDD RED フェーズ
#
# Issue #1022: tech-debt(observer): budget-detect.sh が cycle reset wall-clock を「残量」と誤認
#
# このファイルは実装前（RED）状態で全テストが fail することを意図している。
# 実装完了後（GREEN）は全テストが PASS すること。
#
# AC1: budget-detect.sh で 2 軸独立判定を実装 (consumption-based + cycle-based)
#   - 軸1 (consumption): budget_remaining_min = cycle_total_min × (100 - pct%) / 100 ≤ BUDGET_THRESHOLD_REMAINING (default: 40分)
#   - 軸2 (cycle): cycle_reset_min ≤ BUDGET_THRESHOLD_CYCLE (default: 5分)
#   - 発火条件: 軸1 OR 軸2
#
# AC4: bats で以下3ケースを検証:
#   入力              remaining       cycle       期待          発火軸
#   5h:9%(0h10m)      273分 (>40)     10分 (>5)   alert なし    両軸不発
#   5h:88%(2h00m)     36分 (≤40)      120分 (>5)  alert OK      軸1 (consumption)
#   5h:50%(0h03m)     150分 (>40)     3分 (≤5)    alert OK      軸2 (cycle)

load '../helpers/common'

BUDGET_DETECT_SCRIPT=""

setup() {
  common_setup
  BUDGET_DETECT_SCRIPT="$REPO_ROOT/skills/su-observer/scripts/budget-detect.sh"

  # tmux をスタブ化（budget-detect.sh は tmux capture-pane を呼ぶ）
  # スタブは FAKE_STATUS_LINE 環境変数から status line を返す
  stub_command "tmux" '
args=("$@")
if [[ "${args[0]}" == "capture-pane" ]]; then
  echo "${FAKE_STATUS_LINE:-}"
elif [[ "${args[0]}" == "list-windows" ]]; then
  echo ""
elif [[ "${args[0]}" == "send-keys" ]]; then
  exit 0
else
  exit 0
fi
'
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: 2 軸独立判定の実装チェック（static grep）
#
# RED 理由: 現在の実装は BUDGET_THRESHOLD (cycle_reset_min との比較) のみで
#           BUDGET_THRESHOLD_REMAINING / BUDGET_THRESHOLD_CYCLE による
#           consumption-based + cycle-based の 2 軸判定が存在しない。
# ===========================================================================

@test "ac1: budget-detect.sh に BUDGET_THRESHOLD_REMAINING 変数が存在する（static grep）" {
  # RED: 現在の実装に BUDGET_THRESHOLD_REMAINING が存在しないため fail する
  # PASS 条件（実装後）: 2 軸判定の consumption 軸閾値変数が存在する
  run grep -E 'BUDGET_THRESHOLD_REMAINING' "$BUDGET_DETECT_SCRIPT"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: BUDGET_THRESHOLD_REMAINING が budget-detect.sh に存在しない"
    echo "現在の実装（閾値変数）:"
    grep -E 'BUDGET_THRESHOLD' "$BUDGET_DETECT_SCRIPT" || true
    return 1
  }
}

@test "ac1: budget-detect.sh に BUDGET_THRESHOLD_CYCLE 変数が存在する（static grep）" {
  # RED: 現在の実装に BUDGET_THRESHOLD_CYCLE が存在しないため fail する
  # PASS 条件（実装後）: 2 軸判定の cycle 軸閾値変数が存在する
  run grep -E 'BUDGET_THRESHOLD_CYCLE' "$BUDGET_DETECT_SCRIPT"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: BUDGET_THRESHOLD_CYCLE が budget-detect.sh に存在しない"
    echo "現在の実装（閾値変数）:"
    grep -E 'BUDGET_THRESHOLD' "$BUDGET_DETECT_SCRIPT" || true
    return 1
  }
}

@test "ac1: budget-detect.sh に consumption-based 残量計算 (remaining_min) が存在する（static grep）" {
  # RED: 現在の実装は BUDGET_RAW (= cycle_reset_min) をそのまま閾値比較しており
  #      cycle_total × (100 - pct%) / 100 の計算が存在しないため fail する
  # PASS 条件（実装後）: 残量計算式 (100 - pct) * cycle_total / 100 などの式が存在する
  run grep -E '(remaining|REMAINING).*pct|pct.*(remaining|REMAINING)|\(\s*100\s*-\s*.*PCT\s*\)|budget_remaining' "$BUDGET_DETECT_SCRIPT"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: consumption-based 残量計算が budget-detect.sh に存在しない"
    echo "現在の判定ロジック部分:"
    grep -n -A2 'BUDGET_ALERT' "$BUDGET_DETECT_SCRIPT" || true
    return 1
  }
}

@test "ac1: budget-detect.sh が bash -n を通過する（syntax check）" {
  # 実装前後ともに syntax は通過すべき
  run bash -n "$BUDGET_DETECT_SCRIPT"
  assert_success
}

# ===========================================================================
# AC4 ケース1: 5h:9%(0h10m) → alert なし（両軸不発）
#
# フォーマット解釈:
#   pct = 9 (消費率)
#   cycle_raw = 0h10m → cycle_reset_min = 10分
#   cycle_total_min = cycle_reset_min / (pct / 100) = 10 / 0.09 ≈ 111分
#   remaining_min = cycle_total_min × (100 - 9) / 100 ≈ 101分
#
# 実際の計算（整数演算）:
#   cycle_reset_min = 10
#   budget_remaining_min = (10 * (100 - 9)) / 9 = (10 * 91) / 9 = 910 / 9 = 101分 (>40)
#   cycle_reset_min = 10 (>5)
#   → 両軸不発 → alert なし
#
# RED 理由: 現在の実装は BUDGET_MIN (= cycle_reset_min = 10) と BUDGET_THRESHOLD (= 15) を比較し、
#           10 <= 15 で alert=true になる（偽陽性）。実装後は alert なし。
# ===========================================================================

@test "ac4-case1: 5h:9%(0h10m) — 両軸不発で alert なし (exit 0)" {
  # RED: 現在の実装は cycle_reset_min=10 <= BUDGET_THRESHOLD=15 で誤って alert になる
  # PASS 条件（実装後）:
  #   軸1 remaining=101分 > 40分 → 不発
  #   軸2 cycle_reset=10分 > 5分 → 不発
  #   → exit 0（alert なし）

  local status_line="Claude [max] 5h:9%(0h10m) 7d:20%(5d14h)"
  export FAKE_STATUS_LINE="$status_line"
  export PILOT_WINDOW="fake-window"
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"

  # budget-detect.sh を sandbox の scripts/ にコピーして実行
  cp "$BUDGET_DETECT_SCRIPT" "$SANDBOX/budget-detect.sh"
  chmod +x "$SANDBOX/budget-detect.sh"

  # 閾値デフォルト値で実行（BUDGET_THRESHOLD_REMAINING=40, BUDGET_THRESHOLD_CYCLE=5）
  run env \
    PILOT_WINDOW="fake-window" \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    FAKE_STATUS_LINE="$status_line" \
    PATH="$STUB_BIN:$PATH" \
    bash "$SANDBOX/budget-detect.sh"

  echo "--- exit status: $status ---"
  echo "--- stdout: $output ---"

  # 期待: exit 0（alert なし）
  # RED: 現在の実装は exit 1（偽陽性 alert）
  [ "$status" -eq 0 ] || {
    echo "FAIL: 5h:9%(0h10m) で誤った alert が発火した（偽陽性）"
    echo "現在の実装は cycle_reset_min=10 を残量と誤認して閾値以下と判断している"
    echo "実装後は consumption-based 残量計算で alert なしになるべき"
    return 1
  }
}

# ===========================================================================
# AC4 ケース2: 5h:88%(2h00m) → alert OK（軸1 consumption-based）
#
# フォーマット解釈:
#   pct = 88 (消費率)
#   cycle_raw = 2h00m → cycle_reset_min = 120分
#   budget_remaining_min = (120 * (100 - 88)) / 88 = (120 * 12) / 88 = 1440 / 88 = 16分
#   cycle_reset_min = 120分 (>5)
#
# 軸1: remaining=16分 ≤ 40分 → 発火
# 軸2: cycle_reset=120分 > 5分 → 不発
# → 軸1 で alert あり → exit 1
#
# RED 理由: 現在の実装は BUDGET_MIN (= cycle_reset_min = 120) と BUDGET_THRESHOLD (= 15) を比較し、
#           120 > 15 → alert=false になる。また PCT=88 < threshold_percent=90 → alert=false。
#           → 合計: exit 0（偽陰性）。実装後は exit 1（consumption-based で発火）。
# ===========================================================================

@test "ac4-case2: 5h:88%(2h00m) — 軸1 consumption で alert あり (exit 1)" {
  # RED: 現在の実装は cycle_reset_min=120 > BUDGET_THRESHOLD=15 で alert=false（偽陰性）
  # PASS 条件（実装後）:
  #   軸1 remaining=16分 ≤ 40分 → 発火 → exit 1

  local status_line="Claude [max] 5h:88%(2h00m) 7d:20%(5d14h)"
  export FAKE_STATUS_LINE="$status_line"

  cp "$BUDGET_DETECT_SCRIPT" "$SANDBOX/budget-detect.sh"
  chmod +x "$SANDBOX/budget-detect.sh"

  run env \
    PILOT_WINDOW="fake-window" \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    FAKE_STATUS_LINE="$status_line" \
    PATH="$STUB_BIN:$PATH" \
    bash "$SANDBOX/budget-detect.sh"

  echo "--- exit status: $status ---"
  echo "--- stdout: $output ---"

  # 期待: exit 1（consumption-based alert）
  # RED: 現在の実装は exit 0（偽陰性）
  [ "$status" -eq 1 ] || {
    echo "FAIL: 5h:88%(2h00m) で consumption-based alert が発火しなかった（偽陰性）"
    echo "軸1: remaining = (120 * 12) / 88 = 16分 ≤ 40分 → alert 必須"
    echo "現在の実装は cycle_reset_min=120 を残量として扱い、閾値15分超でスキップしている"
    return 1
  }
}

# ===========================================================================
# AC4 ケース3: 5h:50%(0h03m) → alert OK（軸2 cycle-based）
#
# フォーマット解釈:
#   pct = 50 (消費率)
#   cycle_raw = 0h03m → cycle_reset_min = 3分
#   budget_remaining_min = (3 * (100 - 50)) / 50 = (3 * 50) / 50 = 3分
#   ※ 実際は remaining も計算するが軸2 が先に発火
#   cycle_reset_min = 3分 (≤5)
#
# 軸1: remaining=3分 ≤ 40分 → 発火（軸1 でも発火するがケース趣旨は軸2）
# 軸2: cycle_reset=3分 ≤ 5分 → 発火
# → OR 発火 → exit 1
#
# RED 理由: 現在の実装は BUDGET_MIN (= cycle_reset_min = 3) と BUDGET_THRESHOLD (= 15) を比較し、
#           3 <= 15 → alert=true（偶然 PASS してしまう可能性あり）。
#           しかし BUDGET_THRESHOLD_CYCLE が存在しないため、軸2 判定として正式に認識されない。
#           正しい実装では BUDGET_THRESHOLD_CYCLE=5 との比較で発火する。
#           （現在の実装は偶然 PASS するが、閾値の意味が間違っている）
# ===========================================================================

@test "ac4-case3: 5h:50%(0h03m) — 軸2 cycle で alert あり (exit 1)" {
  # この ケースは現状の実装でも偶然 exit 1 になる可能性があるが、
  # BUDGET_THRESHOLD_CYCLE が存在しないため「正しい理由で」発火していない。
  # 実装後は軸2 (cycle_reset=3分 ≤ BUDGET_THRESHOLD_CYCLE=5分) で正式発火する。

  local status_line="Claude [max] 5h:50%(0h03m) 7d:20%(5d14h)"

  cp "$BUDGET_DETECT_SCRIPT" "$SANDBOX/budget-detect.sh"
  chmod +x "$SANDBOX/budget-detect.sh"

  run env \
    PILOT_WINDOW="fake-window" \
    AUTOPILOT_DIR="$SANDBOX/.autopilot" \
    FAKE_STATUS_LINE="$status_line" \
    BUDGET_THRESHOLD_CYCLE="5" \
    PATH="$STUB_BIN:$PATH" \
    bash "$SANDBOX/budget-detect.sh"

  echo "--- exit status: $status ---"
  echo "--- stdout: $output ---"

  # 期待: exit 1（cycle-based alert）
  [ "$status" -eq 1 ] || {
    echo "FAIL: 5h:50%(0h03m) で cycle-based alert が発火しなかった"
    echo "軸2: cycle_reset=3分 ≤ BUDGET_THRESHOLD_CYCLE=5分 → alert 必須"
    return 1
  }

  # stdout に BUDGET-LOW マーカーが含まれること
  echo "$output" | grep -q '\[BUDGET-LOW\]' || {
    echo "FAIL: stdout に [BUDGET-LOW] マーカーが含まれない"
    echo "output: $output"
    return 1
  }
}

# ===========================================================================
# AC4 追加: 正しい軸2 判定の意味チェック（BUDGET_THRESHOLD_CYCLE 参照を確認）
#
# RED 理由: 現在の実装は BUDGET_THRESHOLD (cycle_reset との比較) を使用しており
#           BUDGET_THRESHOLD_CYCLE という名前の変数による cycle 軸判定が存在しない。
# ===========================================================================

@test "ac4-extra: budget-detect.sh が BUDGET_THRESHOLD_CYCLE を cycle 軸判定に使用する（static grep）" {
  # RED: 現在の実装には BUDGET_THRESHOLD_CYCLE を参照する行が存在しない
  # PASS 条件（実装後）: cycle_reset_min と BUDGET_THRESHOLD_CYCLE の比較ロジックが存在する
  run grep -E 'BUDGET_THRESHOLD_CYCLE' "$BUDGET_DETECT_SCRIPT"
  [ "${#lines[@]}" -gt 0 ] || {
    echo "FAIL: BUDGET_THRESHOLD_CYCLE を使用した cycle 軸判定が budget-detect.sh に存在しない"
    echo "現在の実装（閾値比較部分）:"
    grep -n -A1 'BUDGET_THRESHOLD\|BUDGET_ALERT' "$BUDGET_DETECT_SCRIPT" || true
    return 1
  }
}

@test "ac4-extra: budget-detect.sh の判定ロジックに 2 軸分の条件分岐が存在する（static grep）" {
  # RED: 現在の実装は 2 条件分岐（BUDGET_MIN と BUDGET_PCT）だが
  #      BUDGET_THRESHOLD_REMAINING / BUDGET_THRESHOLD_CYCLE の 2 軸ではない
  # PASS 条件（実装後）: consumption 軸と cycle 軸の 2 条件が BUDGET_ALERT=true を設定する
  local threshold_cycle_count
  threshold_cycle_count=$(grep -c 'BUDGET_THRESHOLD_CYCLE' "$BUDGET_DETECT_SCRIPT" 2>/dev/null | tail -1 || echo "0")
  [[ "$threshold_cycle_count" =~ ^[0-9]+$ ]] || threshold_cycle_count=0
  local threshold_remaining_count
  threshold_remaining_count=$(grep -c 'BUDGET_THRESHOLD_REMAINING' "$BUDGET_DETECT_SCRIPT" 2>/dev/null | tail -1 || echo "0")
  [[ "$threshold_remaining_count" =~ ^[0-9]+$ ]] || threshold_remaining_count=0

  [ "$threshold_cycle_count" -ge 1 ] && [ "$threshold_remaining_count" -ge 1 ] || {
    echo "FAIL: 2 軸判定の閾値変数が不完全"
    echo "  BUDGET_THRESHOLD_CYCLE 参照数: ${threshold_cycle_count} (期待: >= 1)"
    echo "  BUDGET_THRESHOLD_REMAINING 参照数: ${threshold_remaining_count} (期待: >= 1)"
    return 1
  }
}
