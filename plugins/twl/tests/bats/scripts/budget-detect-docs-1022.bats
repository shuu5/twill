#!/usr/bin/env bats
# budget-detect-docs-1022.bats - Issue #1022 AC2/AC3 TDD RED フェーズ
#
# Issue #1022: tech-debt(observer): budget-detect.sh が cycle reset wall-clock を「残量」と誤認
#
# このファイルは実装前（RED）状態で全テストが fail することを意図している。
# 実装完了後（GREEN）は全テストが PASS すること。
#
# AC2: monitor-channel-catalog.md [BUDGET-LOW] セクションで (YYm) の意味を明記
#      (cycle reset wall-clock であって残量ではない)
#
# AC3: SKILL.md 該当箇所を訂正 (「残量 15 分」と「reset まで 15 分」を区別)

load '../helpers/common'

CATALOG_MD=""
SKILL_MD=""

setup() {
  common_setup
  CATALOG_MD="$REPO_ROOT/skills/su-observer/refs/monitor-channel-catalog.md"
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC2: monitor-channel-catalog.md の [BUDGET-LOW] セクションで (YYm) の意味を明記
#
# 仕様: `5h:XX%(YYm)` の `(YYm)` は cycle reset まで の wall-clock であり、
#       budget 残量ではないことを明記する必要がある。
#
# RED 理由: 現在の catalog には [BUDGET-LOW] セクションで「(YYm) の意味」が
#           明記されていない。"cycle reset" / "wall-clock" の言及が不足している。
# ===========================================================================

@test "ac2: monitor-channel-catalog.md [BUDGET-LOW] セクションに 'cycle reset' の言及が存在する" {
  # RED: 現在の [BUDGET-LOW] セクションには "(YYm) の意味" として
  #      "cycle reset" という語が存在しないため fail する
  # PASS 条件（実装後）: [BUDGET-LOW] セクションまたはその近傍に "cycle reset" が含まれる

  # [BUDGET-LOW] セクションを抽出（次の ## セクションまで）
  local budget_low_section
  budget_low_section=$(sed -n '/^\#\# \[BUDGET-LOW\]/,/^\#\# /p' "$CATALOG_MD" 2>/dev/null || true)

  echo "--- [BUDGET-LOW] セクション（先頭 30 行）---"
  echo "$budget_low_section" | head -30

  echo "$budget_low_section" | grep -qE 'cycle.reset|cycle reset|サイクルリセット' || {
    echo "FAIL: [BUDGET-LOW] セクションに 'cycle reset' の説明が存在しない"
    echo "現在の [BUDGET-LOW] セクション冒頭:"
    echo "$budget_low_section" | head -10
    return 1
  }
}

@test "ac2: monitor-channel-catalog.md [BUDGET-LOW] セクションに 'wall-clock' または '残量ではない' の言及が存在する" {
  # RED: 現在の [BUDGET-LOW] セクションには "(YYm) が残量ではない" という
  #      訂正注記が存在しないため fail する
  # PASS 条件（実装後）: (YYm) が wall-clock / cycle reset であり残量ではないことを明記

  local budget_low_section
  budget_low_section=$(sed -n '/^\#\# \[BUDGET-LOW\]/,/^\#\# /p' "$CATALOG_MD" 2>/dev/null || true)

  echo "--- [BUDGET-LOW] セクション（wall-clock 確認）---"
  echo "$budget_low_section" | head -40

  echo "$budget_low_section" | grep -qE 'wall.clock|wall_clock|残量ではない|残量でない|残量.*誤|誤.*残量|cycle reset' || {
    echo "FAIL: [BUDGET-LOW] セクションに '(YYm) は wall-clock (cycle reset 時刻) であり残量ではない' の旨が記載されていない"
    echo "現在の記述（閾値説明付近）:"
    echo "$budget_low_section" | grep -A3 -B3 'threshold\|閾値\|YYm\|残り' || true
    return 1
  }
}

@test "ac2: monitor-channel-catalog.md [BUDGET-LOW] セクションに '(YYm)' の注記が存在する" {
  # RED: 現在の [BUDGET-LOW] セクションには (YYm) の semantics 注記が存在しない
  # PASS 条件（実装後）: (YYm) の意味（cycle reset wall-clock）を注記する行が存在する

  local budget_low_section
  budget_low_section=$(sed -n '/^\#\# \[BUDGET-LOW\]/,/^\#\# /p' "$CATALOG_MD" 2>/dev/null || true)

  # "(YYm)" という文字列 + その意味説明（cycle / reset / wall-clock / 注意）が含まれること
  echo "$budget_low_section" | grep -qE '\(YYm\).*cycle|\(YYm\).*reset|\(YYm\).*wall|YYm.*注|注.*YYm|cycle.*YYm|reset.*YYm' || {
    echo "FAIL: [BUDGET-LOW] セクションに (YYm) の semantics 注記が存在しない"
    echo "期待: '(YYm) は cycle reset までの wall-clock であり budget 残量ではない' などの注記"
    echo "現在の (YYm) 関連行:"
    echo "$budget_low_section" | grep -E 'YYm' || echo "(なし)"
    return 1
  }
}

# ===========================================================================
# AC3: SKILL.md 該当箇所を訂正 (「残量 15 分」と「reset まで 15 分」を区別)
#
# 現在の SKILL.md / budget-detect.sh の問題:
#   - BUDGET_THRESHOLD=15 が「cycle_reset_min (= YYm の値) ≤ 15分」として使われており
#     「budget 残量」の閾値と混在している
#   - SKILL.md の SU-5 や budget 関連記述で「残量 ≤ 閾値」と記述されているが
#     実際は「cycle reset まで ≤ 閾値」になっていた
#
# RED 理由: SKILL.md の budget 関連記述に「cycle reset wall-clock」と「残量」の
#           明確な区別が存在しない。
# ===========================================================================

@test "ac3: SKILL.md に 'consumption-based' または '消費ベース' の記述が存在する" {
  # RED: 現在の SKILL.md には 2 軸判定（consumption-based / cycle-based）の
  #      説明が存在しないため fail する
  # PASS 条件（実装後）: 2 軸独立判定の説明が SKILL.md に追記されている

  echo "--- SKILL.md budget 関連行 ---"
  grep -n -E 'budget|BUDGET|残量|reset|cycle' "$SKILL_MD" | head -20

  grep -qE 'consumption.based|消費ベース|consumption_based|軸1.*consumption|consumption.*軸1' "$SKILL_MD" || {
    echo "FAIL: SKILL.md に 'consumption-based' 判定軸の記述が存在しない"
    echo "実装後は 2 軸判定（consumption-based + cycle-based）の説明を含むべき"
    echo "現在の budget 関連記述:"
    grep -n -E 'budget|BUDGET|残量' "$SKILL_MD" | head -10 || echo "(なし)"
    return 1
  }
}

@test "ac3: SKILL.md に 'cycle-based' または 'cycle reset' と閾値の区別が存在する" {
  # RED: 現在の SKILL.md には cycle reset wall-clock 閾値の説明が存在しない
  # PASS 条件（実装後）: BUDGET_THRESHOLD_CYCLE など cycle reset 軸の説明が存在する

  grep -qE 'cycle.based|cycle_based|THRESHOLD_CYCLE|cycle.*reset.*閾値|閾値.*cycle.*reset|reset.*まで.*閾値' "$SKILL_MD" || {
    echo "FAIL: SKILL.md に 'cycle-based' 判定軸（cycle reset 閾値）の記述が存在しない"
    echo "現在の budget/cycle 関連行:"
    grep -n -E 'cycle|reset|THRESHOLD' "$SKILL_MD" | head -10 || echo "(なし)"
    return 1
  }
}

@test "ac3: SKILL.md が '残量 15 分' ではなく 2 軸判定の正しい説明を含む" {
  # RED: 現在の SKILL.md には旧仕様の「残量 15 分」相当の記述があり
  #      「(YYm) は cycle reset wall-clock」という訂正がない
  # PASS 条件（実装後）: 2 軸判定の正しい説明（残量軸 + cycle reset 軸）が存在する

  # 「残量 15 分」という旧仕様記述が残っていないこと、または訂正が存在すること
  local old_description_count
  old_description_count=$(grep -cE '残り\s*15\s*分|残量\s*(≤|<=|以下)\s*15' "$SKILL_MD" 2>/dev/null | tail -1 || echo "0")
  # grep -c が "0\n0" 形式で返す場合を防ぐために tail -1 を使用
  [[ "$old_description_count" =~ ^[0-9]+$ ]] || old_description_count=0

  local new_description_count
  new_description_count=$(grep -cE '(THRESHOLD_REMAINING|THRESHOLD_CYCLE|2\s*軸|consumption.based|cycle.based)' "$SKILL_MD" 2>/dev/null | tail -1 || echo "0")
  [[ "$new_description_count" =~ ^[0-9]+$ ]] || new_description_count=0

  echo "旧記述（'残り 15 分' 系）の件数: $old_description_count"
  echo "新記述（2 軸判定）の件数: $new_description_count"

  [ "$new_description_count" -ge 1 ] || {
    echo "FAIL: SKILL.md に 2 軸判定の説明が存在しない"
    echo "期待: BUDGET_THRESHOLD_REMAINING (default: 40分) / BUDGET_THRESHOLD_CYCLE (default: 5分) の説明"
    return 1
  }
}

@test "ac3: SKILL.md に '(YYm) は cycle reset まで の時刻' または同等の訂正注記が存在する" {
  # RED: 現在の SKILL.md には (YYm) の意味（cycle reset wall-clock）の注記がない
  # PASS 条件（実装後）: (YYm) の semantics が正しく説明されている

  grep -qE '\(YYm\).*cycle|\(YYm\).*reset|cycle.*\(YYm\)|reset.*\(YYm\)' "$SKILL_MD" || {
    echo "FAIL: SKILL.md に '(YYm) = cycle reset wall-clock' の注記が存在しない"
    echo "現在の (YYm) 関連行:"
    grep -n -E 'YYm' "$SKILL_MD" || echo "(なし)"
    return 1
  }
}
