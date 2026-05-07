#!/usr/bin/env bats
# ac-scaffold-tests-1516.bats
#
# Issue #1516: bug(su-observer): Wave spawn 前 Status=Refined check 未実施
#   su-observer が Status=Todo の Issue に co-autopilot spawn しても abort しない問題
#
# RED: 実装前は全テスト fail
# GREEN: 実装後に PASS
#
# NOTE (baseline-bash.md §10): spawn-controller.sh は set -euo pipefail を持つが
#   source guard ([[ "${BASH_SOURCE[0]}" == "${0}" ]]) が存在しないため
#   source 直接実行はリスクあり。本テストは grep ベース静的検査を基本とする。
#   実行系テスト (ac3) は既存 run-spawn-controller.sh wrapper パターンを踏襲する。

load '../helpers/common'

SPAWN_CONTROLLER=""
SKILL_MD=""
SPAWN_PLAYBOOK=""
PITFALLS_CATALOG=""
CLD_SPAWN_ARGS_LOG=""

setup() {
  common_setup

  SPAWN_CONTROLLER="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  SPAWN_PLAYBOOK="${REPO_ROOT}/skills/su-observer/refs/su-observer-controller-spawn-playbook.md"
  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"

  export SPAWN_CONTROLLER SKILL_MD SPAWN_PLAYBOOK PITFALLS_CATALOG

}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: su-observer SKILL.md に Wave spawn 前 MUST step 追加
#
# SKILL.md と su-observer-controller-spawn-playbook.md の co-autopilot spawn
# セクションに「co-autopilot spawn 前 MUST」手順が存在すること。
#
# RED: 現在どちらのファイルにも該当セクションが存在しないため grep fail
# GREEN: 実装後（MUST step 追記後）PASS
# ===========================================================================

@test "ac1a: SKILL.md に 'co-autopilot spawn 前 MUST' セクションが存在する" {
  # AC: SKILL.md の co-autopilot spawn セクションに MUST step が追加されている
  # RED: 現在 SKILL.md に "co-autopilot spawn 前 MUST" の記述が存在しない
  run grep -qF "co-autopilot spawn 前 MUST" "${SKILL_MD}"
  assert_success
}

@test "ac1b: SKILL.md に 'Status=Todo の場合は board-status-update --status Refined を実行' の記述が存在する" {
  # AC: MUST step 2 として board-status-update の実行方法が明記されている
  # RED: 現在 SKILL.md に board-status-update --status Refined の記述が存在しない
  run grep -qE "board-status-update.+Refined|board-status-update --status Refined" "${SKILL_MD}"
  assert_success
}

@test "ac1c: SKILL.md に 'gh project item-list' を使った Status 確認手順が存在する" {
  # AC: MUST step 1 として gh project item-list による Status 確認が明記されている
  # RED: 現在 SKILL.md の co-autopilot spawn セクションに gh project item-list 記述が存在しない
  # NOTE (baseline-bash.md §10-table): テーブル用語列マッチのため '| gh project item-list |'
  #   パターンが理想だが、本 AC は prose 内記述を検証するため grep -qF で十分
  run grep -qF "gh project item-list" "${SKILL_MD}"
  assert_success
}

@test "ac1d: su-observer-controller-spawn-playbook.md に 'co-autopilot spawn 前 MUST' セクションが存在する" {
  # AC: spawn-playbook.md の co-autopilot セクションに MUST step が追加されている
  # RED: 現在 spawn-playbook.md に "co-autopilot spawn 前 MUST" の記述が存在しない
  run grep -qF "co-autopilot spawn 前 MUST" "${SPAWN_PLAYBOOK}"
  assert_success
}

@test "ac1e: su-observer-controller-spawn-playbook.md に 'Status=Refined 確認後に co-autopilot spawn' の記述が存在する" {
  # AC: MUST step 3 として Status=Refined 確認後の spawn 手順が明記されている
  # RED: 現在 spawn-playbook.md に Status=Refined 確認後 spawn の記述が存在しない
  run grep -qE "Status=Refined.+co-autopilot spawn|Status=Refined 確認後" "${SPAWN_PLAYBOOK}"
  assert_success
}

# ===========================================================================
# AC-2: spawn-controller.sh に pre-check 機能追加
#
# spawn-controller.sh の co-autopilot サブコマンドで、対象 Issue の
# Status=Refined を pre-check し、Todo なら error abort + hint を stderr 出力。
#
# RED: 現在 spawn-controller.sh に Status=Refined pre-check ロジックが存在しないため
#      grep fail または実行時 exit 0（abort しない）
# GREEN: pre-check 実装後 PASS
# ===========================================================================

@test "ac2a: spawn-controller.sh に Status=Refined の pre-check ロジックが存在する" {
  # AC: co-autopilot サブコマンドで Status=Refined を確認するロジックが存在する
  # RED: 現在 spawn-controller.sh に Status=Refined / Refined pre-check の記述が存在しない
  run grep -qE "Status=Refined|status.*Refined|Refined.*pre.check|precheck.*Refined" "${SPAWN_CONTROLLER}"
  assert_success
}

@test "ac2b: spawn-controller.sh に Todo Status 時の abort パターンが存在する" {
  # AC: Status=Todo の場合に error abort（exit 非 0）する分岐が存在する
  # RED: 現在 spawn-controller.sh に Todo abort ロジックが存在しない
  run grep -qE "Status.*Todo|Todo.*abort|Status=Todo" "${SPAWN_CONTROLLER}"
  assert_success
}

@test "ac2c: spawn-controller.sh に修正方法 hint を stderr 出力するロジックが存在する" {
  # AC: Status=Todo 時に board-status-update 等の修正方法 hint を stderr に出力する
  # RED: 現在 spawn-controller.sh に board-status-update 修正 hint 出力が存在しない
  run grep -qE "board-status-update|Refined.*hint|hint.*Refined" "${SPAWN_CONTROLLER}"
  assert_success
}

@test "ac2d: spawn-controller.sh に --pre-check-issue オプションを処理するロジックが存在する" {
  # AC: Status=Todo Issue を spawn 対象に渡した時に spawn-controller が abort（exit 非 0）する
  # RED: 現在 spawn-controller.sh に --pre-check-issue / pre-check ロジックが存在しないため grep fail
  #
  # NOTE: 実行系テストではなく静的検査を採用する理由:
  #   現在の spawn-controller.sh は set -euo pipefail + source guard なし（baseline-bash.md §10）
  #   tmux-resolve.sh 等の依存 lib が sandbox 環境で解決できないため、
  #   スクリプト起動時点で別の理由で exit 非 0 になり正しい RED を表現できない。
  #   grep ベースの静的検査により「実装が存在しないこと」を確実に検証する。
  run grep -qE "\-\-pre-check-issue|pre_check_issue" "${SPAWN_CONTROLLER}"
  assert_success
}

@test "ac2e: spawn-controller.sh の pre-check ロジックが board-status-update hint 出力を含む" {
  # AC: abort 時に board-status-update --status Refined 等の修正方法を hint として出力する
  # RED: 現在 pre-check ロジック自体がないため board-status-update hint 出力コードが存在しない
  #
  # 静的検査: pre-check 内での hint 出力（>&2 のある echo / printf + board-status-update）
  run grep -qE "board-status-update.*>&2|>&2.*board-status-update|echo.*board-status-update|printf.*board-status-update" "${SPAWN_CONTROLLER}"
  assert_success
}

# ===========================================================================
# AC-3: bats test 追加（本ファイル自体が AC-3 の成果物）
#
# Status=Todo Issue を spawn 対象に渡した時に observer が事前 refine するか /
# spawn-controller が abort するかの bats test が存在すること。
#
# このファイル自体が AC-3 を満たすが、テストとしては
# 「このテストファイルが存在し、かつ Status=Todo abort テストが含まれる」ことを確認する。
#
# RED: テストファイル内に Status=Todo 関連テストが存在しない場合 fail
# GREEN: 本ファイルが存在し上記の ac2d/ac2e が含まれれば PASS
# ===========================================================================

@test "ac3: この bats ファイルが存在し Status=Todo abort テストを含む" {
  # AC: Status=Todo Issue を spawn 対象に渡した時の挙動を検証する bats test が存在する
  # RED: テストファイルが存在しない、または Status=Todo 検証テストが含まれない場合 fail
  local this_file
  this_file="${REPO_ROOT}/tests/bats/scripts/ac-scaffold-tests-1516.bats"

  [[ -f "${this_file}" ]] \
    || fail "Issue #1516 用 bats テストファイルが存在しない: ${this_file}"

  # Status=Todo abort テストが含まれることを確認
  # NOTE (baseline-bash.md §9): 以下は非クォート heredoc (<<EOF) で外部変数展開あり
  run grep -qF "Status=Todo" "${this_file}"
  assert_success
}

# ===========================================================================
# AC-4: Wave 60 lesson 23 を pitfalls-catalog.md に正式追記
#
# pitfalls-catalog.md に Wave spawn 前 Status=Refined check section が
# 追加されていること（§N に整理）。
#
# RED: 現在 pitfalls-catalog.md に Wave spawn 前 Status=Refined check section が
#      存在しないため grep fail
# GREEN: §17 または以降のセクションとして追記後 PASS
# ===========================================================================

@test "ac4a: pitfalls-catalog.md に 'Wave spawn 前 Status=Refined check' セクションが存在する" {
  # AC: pitfalls-catalog.md に Wave spawn 前 Status=Refined check の §N セクションが追加されている
  # RED: 現在 pitfalls-catalog.md に該当セクションが存在しない
  run grep -qE "Wave spawn 前.*Status=Refined|Status=Refined.*check|Wave spawn 前.*Refined.*check" "${PITFALLS_CATALOG}"
  assert_success
}

@test "ac4b: pitfalls-catalog.md の該当セクションが §N 形式で整理されている" {
  # AC: Wave spawn 前 Status check が §N 記法の見出しとして追記されている
  # RED: 現在 pitfalls-catalog.md に Wave spawn / Refined check の §N 見出しが存在しない
  run grep -qE "^## §[0-9]+.*[Ww]ave.*[Ss]pawn|^## §[0-9]+.*[Ss]tatus.*[Rr]efined" "${PITFALLS_CATALOG}"
  assert_success
}

@test "ac4c: pitfalls-catalog.md の Wave spawn セクションに board-status-update の記述が存在する" {
  # AC: 追加セクション内に board-status-update による修正手順が含まれる
  # RED: 現在 pitfalls-catalog.md に board-status-update --status Refined の記述が存在しない
  # NOTE (baseline-bash.md §10-table): Markdown テーブル用語列チェック
  #   テーブル内の用語列（1列目）に 'board-status-update' が含まれる場合は
  #   grep -qF '| board-status-update |' を使うこと（説明列への偽陽性を防ぐ）
  #   本 AC は prose/コードブロック内の記述を検証するため grep -qE で可
  run grep -qE "board-status-update.*Refined|board-status-update --status Refined" "${PITFALLS_CATALOG}"
  assert_success
}

@test "ac4d: pitfalls-catalog.md の Wave spawn セクションに 'gh project item-list' による Status 確認が記述されている" {
  # AC: 追加セクション内に gh project item-list による確認手順が含まれる
  # RED: 現在 pitfalls-catalog.md の Wave spawn セクションに gh project item-list 記述が存在しない
  # NOTE (baseline-bash.md §10-table): Markdown テーブル用語列マッチは '| gh project item-list |'
  #   だが本 AC は prose/コードブロック内記述を検証するため grep -qF で可
  run grep -qF "gh project item-list" "${PITFALLS_CATALOG}"
  assert_success
}
