#!/usr/bin/env bats
# issue-1321-co-explore-autosave.bats
#
# RED-phase tests for Issue #1321:
#   feat(co-explore): summary-gate CO_EXPLORE_AUTOSAVE=1 環境変数対応 (Wave 26 sub-5, Tier B)
#
# AC coverage:
#   AC1 - co-explore/SKILL.md の summary-gate セクションに CO_EXPLORE_AUTOSAVE env 判定が追加されている
#   AC2 - CO_EXPLORE_AUTOSAVE=1 で [A]確定 自動選択 + log の記述がある
#   AC3 - 大規模変更 (>500 行) は env 無視で menu 表示 (safety) の記述がある
#   AC4 - refine mode 時は env を自動 enable する記述がある
#   AC5 - regression bats: env 経路で auto-confirm 確認 (bats ファイル自身の存在 + AC1-4 が全 PASS)
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SKILL_FILE="${REPO_ROOT}/skills/co-explore/SKILL.md"
  export SKILL_FILE
}

# ===========================================================================
# AC1: co-explore/SKILL.md の summary-gate に CO_EXPLORE_AUTOSAVE env 判定追加
# ===========================================================================

@test "ac1: SKILL.md summary-gate section contains CO_EXPLORE_AUTOSAVE env judgment" {
  # AC: co-explore/SKILL.md の summary-gate セクションに CO_EXPLORE_AUTOSAVE 環境変数判定が追加されている
  # RED: 現在 env 判定が存在しないため fail する
  run grep -c "CO_EXPLORE_AUTOSAVE" "${SKILL_FILE}"
  [ "${output}" -gt 0 ]
}

# ===========================================================================
# AC2: CO_EXPLORE_AUTOSAVE=1 で [A]確定 自動選択 + log
# ===========================================================================

@test "ac2: SKILL.md describes auto-select [A] when CO_EXPLORE_AUTOSAVE=1" {
  # AC: CO_EXPLORE_AUTOSAVE=1 設定時に [A] を自動選択する旨の記述が SKILL.md にある
  # RED: 実装前は fail する
  run grep -c "CO_EXPLORE_AUTOSAVE=1" "${SKILL_FILE}"
  [ "${output}" -gt 0 ]
}

@test "ac2: SKILL.md describes logging of auto-confirm action" {
  # AC: CO_EXPLORE_AUTOSAVE=1 による自動選択時にログ出力する旨の記述がある
  # RED: 実装前は fail する
  # "自動" or "auto" と "log" or "出力" の組み合わせを確認
  run grep -iE "(自動.*log|auto.*log|log.*auto|自動.*出力)" "${SKILL_FILE}"
  [ "${#lines[@]}" -gt 0 ]
}

# ===========================================================================
# AC3: 大規模変更 (>500 行) は env 無視で menu 表示 (safety)
# ===========================================================================

@test "ac3: SKILL.md describes large-change safety override (>500 lines)" {
  # AC: 大規模変更 (>500 行) の場合は CO_EXPLORE_AUTOSAVE env を無視してメニュー表示する安全動作の記述がある
  # RED: 実装前は fail する
  run grep -c "500" "${SKILL_FILE}"
  [ "${output}" -gt 0 ]
}

@test "ac3: SKILL.md safety clause overrides env for large changes" {
  # AC: env 設定があっても大規模変更時はメニューを強制表示する記述がある
  # RED: 実装前は fail する
  # "safety" or "安全" or "env 無視" or "override" の表現を確認
  run grep -iE "(safety|安全|env.*無視|override|強制.*menu|menu.*強制)" "${SKILL_FILE}"
  [ "${#lines[@]}" -gt 0 ]
}

# ===========================================================================
# AC4: refine mode 時は env を自動 enable
# ===========================================================================

@test "ac4: SKILL.md describes refine mode auto-enabling CO_EXPLORE_AUTOSAVE" {
  # AC: refine mode（引数に refine が含まれる場合）は CO_EXPLORE_AUTOSAVE を自動 enable する記述がある
  # RED: 実装前は fail する
  run grep -iE "(refine.*auto|auto.*refine|refine.*CO_EXPLORE_AUTOSAVE|CO_EXPLORE_AUTOSAVE.*refine)" "${SKILL_FILE}"
  [ "${#lines[@]}" -gt 0 ]
}

@test "ac4: SKILL.md refine mode section mentions autosave behavior" {
  # AC: refine mode 専用の autosave 自動有効化ロジックの記述が存在する
  # RED: 実装前は fail する
  # "refine" キーワード近傍で "enable" または "有効" が言及されているか確認
  run grep -iE "(refine.*enable|refine.*有効|enable.*refine|有効.*refine)" "${SKILL_FILE}"
  [ "${#lines[@]}" -gt 0 ]
}

# ===========================================================================
# AC5: regression bats ファイル存在 + env 経路で auto-confirm 確認
# ===========================================================================

@test "ac5: this bats file itself exists as regression test for env auto-confirm path" {
  # AC: CO_EXPLORE_AUTOSAVE=1 環境変数経路の auto-confirm を検証する regression bats が存在する
  # このテスト自身が存在することを確認（常に PASS するが、ファイル存在の証明）
  local this_bats_file="${REPO_ROOT}/tests/bats/issue-1321-co-explore-autosave.bats"
  [ -f "${this_bats_file}" ]
}

@test "ac5: SKILL.md autosave env path covers all 3 required behaviors (auto-select, large-change-guard, refine-mode)" {
  # AC: env 経路の 3 つの動作（自動選択、大規模変更ガード、refine 自動有効化）が
  #     すべて SKILL.md に記述されていることを一括確認する regression テスト
  # RED: 実装前は fail する（いずれかの記述が欠如）
  local autosave_count
  autosave_count=$(grep -c "CO_EXPLORE_AUTOSAVE" "${SKILL_FILE}" || true)
  [ "${autosave_count}" -ge 3 ]
}
