#!/usr/bin/env bats
# co-utility-step0-keyword-match.bats
#
# RED-phase tests for Issue #1320:
#   co-utility Step 0 キーワードマッチ強化 + 曖昧時 menu 削減
#
# AC coverage:
#   AC1 - co-utility/SKILL.md Step 0 キーワード辞書追加 (各 category 代表 keyword)
#   AC2 - 引数中 keyword 検出時 → menu skip (matched category 自動選択 + log)
#   AC3 - keyword 不在時のみ既存 menu 表示
#   AC4 - regression bats: keyword 経路で menu skip 確認 (このテストファイル自体)
#
# 全テストは実装前（RED）状態で fail する（AC4 のみ本ファイル作成後即 PASS）。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  CO_UTIL_SKILL="${REPO_ROOT}/skills/co-utility/SKILL.md"
  THIS_BATS="${REPO_ROOT}/tests/bats/co-utility-step0-keyword-match.bats"

  export CO_UTIL_SKILL THIS_BATS
}

# ===========================================================================
# AC1: Step 0 キーワード辞書追加（各 category 代表 keyword）
# ===========================================================================

@test "ac1: co-utility SKILL.md Worktree category keyword column has per-command keywords" {
  # AC: Worktree カテゴリに worktree-list と worktree-delete それぞれを直接指す代表キーワードが追加されている
  #     例: 一覧 → worktree-list (単独マッチ)、削除/rm → worktree-delete (単独マッチ) に分解されている
  # RED: 現状の Step 0 テーブルは Worktree カテゴリ 1行にまとまっており、ls/rm 等の代表キーワードがない
  run grep -qiE '\bls\b|\brm\b|worktree-list のみ|一覧のみ' "${CO_UTIL_SKILL}"
  [ "${status}" -eq 0 ]
}

@test "ac1: co-utility SKILL.md 検証 category keyword column has extended entries" {
  # AC: 検証カテゴリの keyword 列に audit, lint, 整合性 等が追加されている
  # RED: 現状の keyword 列は "validate, 検証, チェック" のみ
  run grep -qiE '整合性|audit|deps.*check|check.*deps' "${CO_UTIL_SKILL}"
  [ "${status}" -eq 0 ]
}

@test "ac1: co-utility SKILL.md 開発 category keyword column has per-command keywords" {
  # AC: 開発カテゴリの keyword 列に ui-capture を指す代表キーワード（スクリーンショット, screenshot 等）が追加されている
  # RED: 現状の keyword 列は "services, サービス, ui, capture, スクショ, schema" のみ — "スクリーンショット" がない
  run grep -qiE 'スクリーンショット|screenshot' "${CO_UTIL_SKILL}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: 引数中 keyword 検出時 → menu skip (matched category 自動選択 + log)
# ===========================================================================

@test "ac2: co-utility SKILL.md Step 0 describes menu skip on keyword match" {
  # AC: キーワード検出時に menu skip する旨が記載されている（"menu skip" or "skip" + "keyword" の文脈）
  # RED: 現状は「カテゴリ内の候補をテーブル表示し AskUserQuestion」のみで skip の記述がない
  run grep -qiE 'menu.*skip|skip.*menu|キーワード.*skip|skip.*キーワード' "${CO_UTIL_SKILL}"
  [ "${status}" -eq 0 ]
}

@test "ac2: co-utility SKILL.md Step 0 describes auto-select on keyword match" {
  # AC: キーワードマッチ時に matched category を自動選択する旨が記載されている
  # RED: 現状は自動選択の記述なし
  run grep -qiE '自動選択|auto.*select|matched.*category|keyword.*自動' "${CO_UTIL_SKILL}"
  [ "${status}" -eq 0 ]
}

@test "ac2: co-utility SKILL.md Step 0 describes log output on keyword match" {
  # AC: キーワードマッチ時に log 出力する旨が記載されている
  # RED: 現状は log の記述なし
  run grep -qiE 'log\|matched.*keyword|keyword.*log|マッチ.*log' "${CO_UTIL_SKILL}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: keyword 不在時のみ既存 menu 表示
# ===========================================================================

@test "ac3: co-utility SKILL.md Step 0 gates menu display to keyword-absent case only" {
  # AC: keyword 不在時のみ menu を表示するという条件分岐が記載されている
  # RED: 現状は「カテゴリは分かるがコマンドが曖昧 → AskUserQuestion」という無条件分岐のみ
  run grep -qiE 'keyword.*不在|不在.*menu|キーワード.*なし.*menu|menu.*キーワード.*なし' "${CO_UTIL_SKILL}"
  [ "${status}" -eq 0 ]
}

@test "ac3: co-utility SKILL.md Step 0 no longer unconditionally invokes AskUserQuestion for ambiguous category" {
  # AC: カテゴリが分かる場合に無条件で AskUserQuestion を呼ぶフローが削除されている
  # RED: 現状は「カテゴリは分かるがコマンドが曖昧 → カテゴリ内の候補をテーブル表示し AskUserQuestion」が存在する
  run grep -qF 'カテゴリは分かるがコマンドが曖昧' "${CO_UTIL_SKILL}"
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC4: regression bats: keyword 経路で menu skip 確認 (このテストファイル自体)
# ===========================================================================

@test "ac4: this bats test file exists at expected path" {
  # AC: regression bats テストが plugins/twl/tests/bats/co-utility-step0-keyword-match.bats として存在する
  # ファイル作成後は即 PASS（本ファイルを作成することが実装である）
  [ -f "${THIS_BATS}" ]
}
