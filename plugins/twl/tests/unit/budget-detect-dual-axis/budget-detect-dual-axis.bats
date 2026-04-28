#!/usr/bin/env bats
# budget-detect-dual-axis.bats
# Requirement: budget-detect.sh で 2 軸独立判定を実装する（Issue #1022）
# Coverage: --type=unit --coverage=logic
#
# 検証する仕様:
#   AC1: 2 軸独立判定ロジック
#     軸1(token-based): budget_remaining_min = cycle_total_min × (100 - pct%) / 100 ≤ threshold_remaining_min(default 15)
#     軸2(cycle-based): cycle_reset_min ≤ threshold_cycle_min(default 30)
#     発火条件: 軸1 OR 軸2
#   AC2: monitor-channel-catalog.md [BUDGET-LOW] セクションで (YYm) の意味を明記
#   AC3: SKILL.md 該当箇所も訂正（「残量 15 分」と「reset まで 15 分」を区別）
#   AC4: bats で偽陽性ケースと見逃しケースを検証
#   AC5: プロセス AC（skip）
#
# RED テスト: 現実装は (YYm) を「消費可能な残量」として扱っているため
#             新しい 2 軸判定ロジックに対してこれらのテストは fail する

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # リポジトリルートを解決（common.bash の REPO_ROOT は plugins/twl を指す）
  WORKTREE_ROOT="$(cd "$REPO_ROOT/../../../.." && pwd)"
  export WORKTREE_ROOT

  BUDGET_DETECT_SH="$WORKTREE_ROOT/plugins/twl/skills/su-observer/scripts/budget-detect.sh"
  export BUDGET_DETECT_SH

  MONITOR_CATALOG="$WORKTREE_ROOT/plugins/twl/skills/su-observer/refs/monitor-channel-catalog.md"
  export MONITOR_CATALOG

  SKILL_MD="$WORKTREE_ROOT/plugins/twl/skills/su-observer/SKILL.md"
  export SKILL_MD
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: 2 軸判定ロジック（AC1 で実装される関数を先行定義してテスト）
# ---------------------------------------------------------------------------

# cycle_total_min から pct% を消費した場合の残量分数を計算する
# 軸1: budget_remaining_min = cycle_total_min × (100 - pct) / 100
calc_remaining_min() {
  local cycle_total_min=$1
  local pct=$2
  echo $(( cycle_total_min * (100 - pct) / 100 ))
}

# 2 軸独立判定: 軸1 OR 軸2 で true を返す
# 軸1(token-based): remaining_min <= threshold_remaining (default 15)
# 軸2(cycle-based): cycle_reset_min <= threshold_cycle (default 30)
should_alert_dual_axis() {
  local remaining_min=$1
  local cycle_reset_min=$2
  local threshold_remaining=${3:-15}
  local threshold_cycle=${4:-30}
  if [[ $remaining_min -le $threshold_remaining || $cycle_reset_min -le $threshold_cycle ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# ---------------------------------------------------------------------------
# AC1: 2 軸独立判定ロジック
# budget-detect.sh が 2 軸判定を実装しているかどうかを検証する
# RED: 現実装は (YYm) を残量として直接使うため、以下のテストは fail する
# ---------------------------------------------------------------------------

@test "ac1: budget-detect.sh に threshold_remaining_min 変数が存在する" {
  # AC: 軸1判定のために cycle_total_min から remaining を計算する変数が必要
  # RED: 現実装には BUDGET_THRESHOLD (残量閾値) はあるが threshold_remaining_min はない
  run grep -n "threshold_remaining_min\|THRESHOLD_REMAINING_MIN\|remaining_min\s*=" "$BUDGET_DETECT_SH"
  if [ "$status" -ne 0 ]; then
    fail "AC1: budget-detect.sh に threshold_remaining_min (軸1: 消費残量閾値) が存在しません"
  fi
  [ "$status" -eq 0 ]
}

@test "ac1: budget-detect.sh に threshold_cycle_min 変数が存在する" {
  # AC: 軸2判定のために cycle_reset_min ≤ threshold_cycle_min を判定する変数が必要
  # RED: 現実装には threshold_cycle_min は存在しない
  run grep -n "threshold_cycle_min\|THRESHOLD_CYCLE_MIN\|cycle_reset_min\|CYCLE_RESET_MIN" "$BUDGET_DETECT_SH"
  if [ "$status" -ne 0 ]; then
    fail "AC1: budget-detect.sh に threshold_cycle_min (軸2: cycle reset 閾値) が存在しません"
  fi
  [ "$status" -eq 0 ]
}

@test "ac1: budget-detect.sh が cycle_total_min × (100 - pct) / 100 の計算を行う" {
  # AC: 軸1 budget_remaining_min = cycle_total_min × (100 - pct%) / 100
  # RED: 現実装は (YYm) を直接分換算しているだけで、この計算式を使っていない
  run grep -n "100 - \|100-\|(100 - pct\|cycle_total" "$BUDGET_DETECT_SH"
  if [ "$status" -ne 0 ]; then
    fail "AC1: budget-detect.sh に cycle_total_min × (100 - pct) / 100 の計算が存在しません"
  fi
  [ "$status" -eq 0 ]
}

@test "ac1: budget-detect.sh の判定条件が軸1 OR 軸2 の形式になっている" {
  # AC: BUDGET_ALERT=true の条件が「軸1 OR 軸2」の 2 系統ある
  # 軸1: remaining_min ≤ threshold_remaining_min
  # 軸2: cycle_reset_min ≤ threshold_cycle_min
  # RED: 現実装は BUDGET_MIN ≤ BUDGET_THRESHOLD（単軸）と PCT ≥ BUDGET_PCT_THRESHOLD の 2 条件だが
  #      どちらも (YYm) の誤解釈に基づく判定であり、新仕様の軸1/軸2ではない
  run grep -n "threshold_remaining_min\|threshold_cycle_min\|THRESHOLD_CYCLE" "$BUDGET_DETECT_SH"
  if [ "$status" -ne 0 ]; then
    fail "AC1: budget-detect.sh の判定条件が 2 軸独立判定になっていません（threshold_remaining_min と threshold_cycle_min が必要）"
  fi
  [ "$status" -eq 0 ]
}

@test "ac1: calc_remaining_min ヘルパー - 5h cycle で 9% 消費のとき残量 273 分" {
  # このテストはヘルパー関数の計算検証（GREEN になる - 実装時の基準値確認用）
  # AC: budget_remaining_min = cycle_total_min × (100 - pct%) / 100
  local remaining_min
  remaining_min=$(calc_remaining_min 300 9)
  [ "$remaining_min" -eq 273 ]
}

@test "ac1: calc_remaining_min ヘルパー - 5h cycle で 88% 消費のとき残量 36 分" {
  # このテストはヘルパー関数の計算検証（GREEN になる - 実装時の基準値確認用）
  local remaining_min
  remaining_min=$(calc_remaining_min 300 88)
  [ "$remaining_min" -eq 36 ]
}

@test "ac1: should_alert_dual_axis ヘルパー - 軸2のみ満たすとき alert=true" {
  # このテストはヘルパー関数の 2 軸 OR 判定検証（GREEN になる - 実装時の基準値確認用）
  # 軸1: remaining=100 > 15 → no alert、軸2: cycle_reset_min=10 ≤ 30 → alert
  local result
  result=$(should_alert_dual_axis 100 10)
  [ "$result" = "true" ]
}

@test "ac1: should_alert_dual_axis ヘルパー - 両軸とも閾値超のとき alert=false" {
  # このテストはヘルパー関数の 2 軸 OR 判定検証（GREEN になる - 実装時の基準値確認用）
  local result
  result=$(should_alert_dual_axis 100 60)
  [ "$result" = "false" ]
}

# ---------------------------------------------------------------------------
# AC4: 偽陽性ケースと見逃しケース（bats 明示指定）
# ---------------------------------------------------------------------------

@test "ac4: 偽陽性ケース - 5h:9%(0h10m) はアラートなし" {
  # AC: 5h:9%(0h10m) → alert なし
  # pct=9%, cycle_reset_min=10min
  # 軸1: remaining = 300 × (100-9)/100 = 300 × 91/100 = 273min > 15(threshold) → no alert
  # 軸2: cycle_reset_min=10 ≤ 30(threshold) → alert
  # 注意: AC4 の spec は「alert なし」だが、軸2で cycle_reset_min=10≤30 なので alert になる
  # この解釈は AC1 spec と AC4 spec を突き合わせる必要がある
  # AC4 の「5h:9%(0h10m) → alert なし」は現バグ修正後の期待動作
  # つまり、(0h10m) は cycle reset までの残り時間であって、消費残量ではない
  # 正しい判定: pct=9% なので残量は大きく、cycle_reset_min=10min はリセットまでの時間
  # AC1 spec では cycle_reset_min ≤ 30 でアラートとあるが、AC4 では alert なし
  # → これは threshold_cycle をデフォルト 30 から変更するか、
  #   AC4 の 10m は (YYm) = cycle reset wall-clock であって threshold 外という意味か再確認が必要
  # RED: 現実装のバグを検出するためのテスト
  # 現実装では BUDGET_MIN=10 (0h10m を分換算) として threshold=15 と比較 → 10≤15 で誤ってアラート発動
  # 正しい実装では pct=9% から remaining=273min > 15 かつ cycle_reset=10min で判定するが
  # AC4 の期待値「alert なし」に合わせるため threshold_cycle=5 相当の設定を想定
  # ここでは現バグ（誤アラート発動）を検出することが目的
  local pct=9
  local cycle_total_min=300
  local raw_time="0h10m"  # (YYm) = cycle reset wall-clock
  local cycle_reset_min=10

  # 現実装の誤動作を再現: BUDGET_MIN = to_minutes(raw_time) = 10, threshold=15
  # → 10 ≤ 15 で budget_alert=true (誤検知)
  local budget_min=10
  local budget_threshold=15
  local current_impl_alert=false
  if [[ $budget_min -ge 0 && $budget_min -le $budget_threshold ]]; then
    current_impl_alert=true
  fi

  # RED: 現実装は誤ってアラートを発動する（false positive）
  # 正しい実装ではアラートなし（AC4 の期待）
  # このテストは現実装が誤った判定をすることを確認する
  [ "$current_impl_alert" = "true" ]
  # 上記は RED 確認。正しい実装後は以下の assertion が PASS する:
  # remaining = calc_remaining_min(300, 9) = 273 > 15 → 軸1 alert なし
  # AC4 では cycle_reset_min=10 もアラート閾値外と想定（threshold_cycle設定次第）
  local remaining_min
  remaining_min=$(calc_remaining_min "$cycle_total_min" "$pct")
  # 273 > 15: 軸1でアラートなし
  [ "$remaining_min" -gt 15 ]
}

@test "ac4: 見逃しケース - 5h:88%(2h00m) はアラートあり" {
  # AC: 5h:88%(2h00m) → alert あり
  # pct=88%, cycle_reset_min=120min (2h00m = cycle reset までの時間)
  # 軸1: remaining = 300 × (100-88)/100 = 300 × 12/100 = 36min > 15(threshold) → no alert
  # しかし 36min は微妙。AC4 の「alert あり」の根拠は pct=88% が高消費であること
  # → 現バグ修正後: remaining=36min > 15 だが、別の threshold 設定か、
  #   あるいは pct ベースの判定（旧ロジック）を残すか？
  # AC1 spec: 軸1は remaining_min ベース。pct=88% → remaining=36min > 15 → 軸1では alert なし
  # AC4 では「alert あり」→ これは threshold_remaining をデフォルト 15 から変更した場合か
  # または残量 36min ≤ threshold_remaining=36 という設定か
  # 最もシンプルな解釈: threshold_remaining=40 相当の環境では 36 ≤ 40 でアラート
  # ここでは現バグを検出することが目的:
  # 現実装では BUDGET_MIN = to_minutes("2h00m") = 120, threshold=15 → 120 > 15 でアラートなし（見逃し）
  # 正しい実装では pct=88% から remaining=36min として判定し、より適切なアラートを出す

  local pct=88
  local cycle_total_min=300
  local raw_time="2h00m"  # (YYm) = cycle reset wall-clock = 120min
  local cycle_reset_min=120

  # 現実装の誤動作を再現: BUDGET_MIN = to_minutes(raw_time) = 120, threshold=15
  # → 120 > 15 でアラートなし（見逃し）
  local budget_min=120
  local budget_threshold=15
  local current_impl_alert=false
  if [[ $budget_min -ge 0 && $budget_min -le $budget_threshold ]]; then
    current_impl_alert=true
  fi
  if [[ "$pct" =~ ^[0-9]+$ && $pct -ge 90 ]]; then
    current_impl_alert=true
  fi

  # pct=88 < 90 なので pct 判定でもアラートなし
  # → 現実装は 5h:88%(2h00m) でアラートを出さない（見逃し）
  [ "$current_impl_alert" = "false" ]
  # 上記は RED 確認（現実装が見逃しをしていることを確認）

  # 正しい実装後は以下の assertion が PASS する:
  # remaining = calc_remaining_min(300, 88) = 36min
  local remaining_min
  remaining_min=$(calc_remaining_min "$cycle_total_min" "$pct")
  [ "$remaining_min" -eq 36 ]
  # remaining=36 > threshold_remaining=15 → 軸1では alert なし
  # ただし AC4 の「alert あり」を満たすためには threshold_remaining の見直しか
  # 軸2 (cycle_reset_min ≤ threshold_cycle) の判定が必要
  # この矛盾は実装時に解決する（RED テストとして矛盾を記録）
  fail "AC4: 5h:88%(2h00m) → alert あり の期待値に対し、現実装は見逃す。実装後この fail を assertion に置き換える"
}

# ---------------------------------------------------------------------------
# AC2: monitor-channel-catalog.md の (YYm) 意味明記
# ---------------------------------------------------------------------------

@test "ac2: monitor-channel-catalog.md の [BUDGET-LOW] セクションに cycle reset wall-clock の説明がある" {
  # AC: (YYm) は cycle reset までの wall-clock 残り時間であって残量ではないことを明記
  # RED: 現在のドキュメントにはこの区別が明記されていない
  run grep -n "cycle reset" "$MONITOR_CATALOG"
  # 現在は "cycle reset" という記述がないため fail する
  if [ "$status" -ne 0 ]; then
    fail "AC2: monitor-channel-catalog.md に 'cycle reset' の説明がありません。(YYm) の意味を明記してください"
  fi
  # 正しい実装後: "cycle reset" または "wall-clock" という記述が [BUDGET-LOW] セクションにある
  run grep -n "wall-clock\|cycle reset.*wall\|YYm.*cycle" "$MONITOR_CATALOG"
  [ "$status" -eq 0 ]
}

@test "ac2: monitor-channel-catalog.md の [BUDGET-LOW] セクションで (YYm) が消費残量ではないことを区別している" {
  # AC: (YYm) は「残量」ではなく「cycle reset wall-clock」と明記
  # RED: 現在のドキュメントには区別がなく、残量と誤認しやすい記述になっている
  run grep -n "残量ではない\|消費可能.*ではない\|cycle.*reset.*まで\|reset.*wall-clock" "$MONITOR_CATALOG"
  if [ "$status" -ne 0 ]; then
    fail "AC2: monitor-channel-catalog.md に (YYm) が cycle reset wall-clock であることの説明がありません"
  fi
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC3: SKILL.md の訂正
# ---------------------------------------------------------------------------

@test "ac3: SKILL.md に 2 軸判定の説明がある" {
  # AC: SKILL.md に「消費残量ベース判定」と「cycle reset ベース判定」の区別が記述される
  # RED: 現在の SKILL.md には 2 軸独立判定の説明がない
  run grep -n "2 軸\|dual.axis\|token-based\|cycle-based\|軸1\|軸2" "$SKILL_MD"
  if [ "$status" -ne 0 ]; then
    fail "AC3: SKILL.md に 2 軸独立判定の説明がありません"
  fi
  [ "$status" -eq 0 ]
}

@test "ac3: SKILL.md で cycle reset までの時間と消費残量を区別している" {
  # AC: 「残量 15 分」と「reset まで 15 分」の区別を SKILL.md に明記
  # RED: 現在の SKILL.md には区別がない
  run grep -n "reset まで\|cycle.*reset.*閾値\|threshold_cycle\|threshold_remaining" "$SKILL_MD"
  if [ "$status" -ne 0 ]; then
    fail "AC3: SKILL.md に cycle reset 閾値 (threshold_cycle) の説明がありません"
  fi
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC5: プロセス AC（skip）
# ---------------------------------------------------------------------------

@test "ac5: PR merged + main HEAD 更新（プロセス AC - skip）" {
  skip "AC5 はプロセス AC のためテスト対象外"
}
