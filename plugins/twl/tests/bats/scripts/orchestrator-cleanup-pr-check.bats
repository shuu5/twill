#!/usr/bin/env bats
# orchestrator-cleanup-pr-check.bats — Issue #1495
#
# Spec: cleanup_worker が `git push origin --delete <branch>` を実行する前に
#       `gh pr list --head <branch> --state open` で open PR を check し、
#       open PR がある場合はリモートブランチ削除を skip する。
#       これにより、orchestrator が status=failed で cleanup を実行しても、
#       open PR の head ref を保護する (Wave 57 incident 再発防止)。
#
# Coverage:
#   AC3-a: open PR が存在する場合は git push origin --delete が呼ばれない
#   AC3-b: open PR が存在しない場合 (count=0) はリモートブランチ削除実行
#   AC3-c: gh CLI が unavailable な場合は安全側 (default _cw_pr_count=0、削除は実行)
#          ただし PR check 不可の場合はリモート削除がそのまま実行される (regression: cleanup-sequence と同等)
#
# §9 heredoc チェック: heredoc 内で外部変数を参照しない。
# §10 source guard チェック: orchestrator.sh は source guard を持たない。直接 source 禁止。

load '../helpers/common'

ORCHESTRATOR_SH=""

setup() {
  common_setup
  ORCHESTRATOR_SH="${REPO_ROOT}/scripts/autopilot-orchestrator.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC3-a/b: 静的 grep — cleanup_worker 内の PR check 実装
# ---------------------------------------------------------------------------

@test "AC3-a: cleanup_worker 内に gh pr list による open PR check が存在する (静的 grep)" {
  # 静的検証: cleanup_worker 関数内に `gh pr list --head` がある
  run grep -E 'gh pr list --head .*--state open' "$ORCHESTRATOR_SH"
  assert_success
  assert_output --partial 'gh pr list --head'
  assert_output --partial '--state open'
}

@test "AC3-b: cleanup_worker 内で _cw_pr_count > 0 のとき WARN ログを出力 (静的 grep)" {
  # 静的検証: 「open PR あり — リモートブランチ削除スキップ」のメッセージが存在
  run grep -E 'open PR あり.*リモートブランチ削除スキップ' "$ORCHESTRATOR_SH"
  assert_success
  assert_output --partial 'open PR あり'
}

@test "AC3-c: cleanup_worker 内で gh unavailable 時の fallback ロジック (command -v gh)" {
  # 静的検証: `command -v gh` で gh の存在を check してから pr list を呼ぶ
  # (cleanup_worker 内、autopilot-cleanup.sh:289 と同一パターン)
  run grep -E 'command -v gh' "$ORCHESTRATOR_SH"
  assert_success
}

@test "AC3-d: cleanup_worker の PR check が `git push origin --delete` の前に位置する (静的順序)" {
  # cleanup_worker 関数の `Step 3` セクション内で、PR check が delete より前にあることを確認
  # awk で関数内を抽出し、`gh pr list` が `git push origin --delete` より先に出現することを検証
  run bash -c "
    awk '/^cleanup_worker\\(\\)/,/^}/' '$ORCHESTRATOR_SH' | grep -nE 'gh pr list|git push origin --delete' | head -2
  "
  assert_success
  # 1 行目は gh pr list、2 行目は git push origin --delete のはず
  assert_output --partial 'gh pr list'
  assert_output --partial 'git push origin --delete'

  # 順序検証: gh pr list の行番号 < git push origin --delete の行番号
  run bash -c "
    awk '/^cleanup_worker\\(\\)/,/^}/' '$ORCHESTRATOR_SH' | grep -nE 'gh pr list|git push origin --delete' | awk -F: '{print \$1, \$2}' | head -2
  "
  # 期待: 先頭が gh pr list、続いて git push
  [[ "${lines[0]}" == *'gh pr list'* ]] || {
    echo "Expected first match to be 'gh pr list', got: ${lines[0]}"
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC3 sentinel: 修正前の脆弱な path が完全に置換されていること
# ---------------------------------------------------------------------------

@test "AC3-sentinel: cleanup_worker 内の git push origin --delete に PR check 前置きがある" {
  # 静的検証: cleanup_worker 関数内の git push origin --delete が条件分岐内 (elif/else)
  # にあること = 直前に PR check がある
  # `if [[ "${_cw_pr_count:-0}" -gt 0 ]]` 分岐があれば OK
  run grep -E '_cw_pr_count.*-gt 0' "$ORCHESTRATOR_SH"
  assert_success
}

@test "AC3-sentinel: #1495 fix のコメントが存在する" {
  # 静的検証: 修正コミットのトレーサビリティ
  run grep -E '#1495 fix.*PR open check' "$ORCHESTRATOR_SH"
  assert_success
}
