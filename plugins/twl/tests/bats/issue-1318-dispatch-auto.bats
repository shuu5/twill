#!/usr/bin/env bats
# issue-1318-dispatch-auto.bats
#
# RED-phase tests for Issue #1318:
#   feat(co-issue): Step 2a-5 dispatch 自動化（AskUserQuestion 削除）
#
# AC coverage:
#   AC1 - co-issue-phase2-bundles.md L80-89 の AskUserQuestion ブロックが削除されている
#   AC2 - co-issue-phase2-bundles.md に自動 dispatch ログパターンが追加され
#          AskUserQuestion が含まれない
#   AC3 - regression: dispatch が自動進行する（ユーザー入力待ちが発生しない）
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  PHASE2_BUNDLES="${REPO_ROOT}/skills/co-issue/refs/co-issue-phase2-bundles.md"
  export PHASE2_BUNDLES
}

# ===========================================================================
# AC1: co-issue-phase2-bundles.md L80-89 の AskUserQuestion ブロックが
#      削除されている
# ===========================================================================

@test "ac1: co-issue-phase2-bundles.md contains no 'AskUserQuestion' references" {
  # AC: "AskUserQuestion" の出現件数が 0 件になっている
  # RED: 現在 L80, L89 に "AskUserQuestion" が存在するため fail
  local count
  count=$(grep -c "AskUserQuestion" "${PHASE2_BUNDLES}" 2>/dev/null || true)
  count=${count:-0}
  [ "${count}" -eq 0 ]
}

@test "ac1: Step 2a-5 section heading does not reference AskUserQuestion" {
  # AC: "Step 2a-5" のセクション見出しに "AskUserQuestion" または
  #     "Dispatch 確認" の文言が含まれない
  # RED: 現在 "#### Step 2a-5: Dispatch 確認（AskUserQuestion）" という
  #      見出しが存在するため fail
  run bash -c "
    grep -E '^#{1,6}.*Step 2a-5' '${PHASE2_BUNDLES}' | grep -q 'AskUserQuestion\|Dispatch 確認' && exit 1 || exit 0
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: dispatch option block '[dispatch | adjust | cancel]' is absent" {
  # AC: "[dispatch | adjust | cancel]" 形式の選択肢記述が存在しない
  # RED: 現在 L89 に "AskUserQuestion: \`[dispatch | adjust | cancel]\`" が存在するため fail
  local count
  count=$(grep -cF "dispatch | adjust | cancel" "${PHASE2_BUNDLES}" 2>/dev/null || true)
  count=${count:-0}
  [ "${count}" -eq 0 ]
}

# ===========================================================================
# AC2: co-issue-phase2-bundles.md に自動 dispatch ログパターンが含まれ、
#      かつ AskUserQuestion が含まれない
# ===========================================================================

@test "ac2: co-issue-phase2-bundles.md contains auto dispatch log pattern" {
  # AC: ">>> Phase 2a-5 dispatch (auto)" 相当のログパターンが含まれている
  # RED: 現在このパターンが存在しないため fail
  grep -qE '>>> Phase 2a-5 dispatch \(auto\)' "${PHASE2_BUNDLES}"
}

@test "ac2: auto dispatch log includes level count placeholder" {
  # AC: 自動 dispatch ログに "N levels" 相当のプレースホルダーが含まれる
  #     (例: ">>> Phase 2a-5 dispatch (auto): N levels")
  # RED: 現在このパターンが存在しないため fail
  grep -qE '>>> Phase 2a-5 dispatch \(auto\).*level' "${PHASE2_BUNDLES}"
}

@test "ac2: AskUserQuestion is absent (AC2 combined with AC1)" {
  # AC: 自動 dispatch 実装後、AskUserQuestion が 0 件になっている
  # RED: 現在 AskUserQuestion が存在するため fail
  local count
  count=$(grep -c "AskUserQuestion" "${PHASE2_BUNDLES}" 2>/dev/null || true)
  count=${count:-0}
  [ "${count}" -eq 0 ]
}

@test "ac2: Step 2a-5 section describes automatic dispatch (not user confirmation)" {
  # AC: Step 2a-5 セクションが自動実行を記述している
  #     (auto/自動 のキーワードが含まれる)
  # RED: 現在のセクションはユーザー確認（AskUserQuestion）のため fail
  run bash -c "
    section_start=\$(grep -n 'Step 2a-5' '${PHASE2_BUNDLES}' | head -1 | cut -d: -f1)
    [ -n \"\${section_start}\" ] || exit 1
    # セクション先頭 10 行以内に 'auto' または '自動' が含まれること
    awk -v s=\"\${section_start}\" 'NR >= s && NR <= s+10' '${PHASE2_BUNDLES}' \
      | grep -qiE 'auto|自動'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: regression — dispatch が自動進行する
#      (ユーザー入力待ちが発生しない)
# ===========================================================================

@test "ac3: refs file does not contain any interactive prompt patterns" {
  # AC: refs ファイル内にインタラクティブなプロンプトパターンが存在しない
  #     対象パターン: AskUserQuestion, read -p, select コマンド相当
  # RED: 現在 AskUserQuestion が存在するため fail
  run bash -c "
    count=\$(grep -cE 'AskUserQuestion|\bread\b.*-p|^\s*select\b' '${PHASE2_BUNDLES}' 2>/dev/null || true)
    count=\${count:-0}
    [ \"\${count}\" -eq 0 ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: regression - Step 2a-5 section heading exists (section not deleted)" {
  # AC: Step 2a-5 セクション自体は残っている（AskUserQuestion ブロックのみ削除）
  # RED: セクション見出しが更新されていないため、現在の状態では
  #      "Dispatch 確認（AskUserQuestion）" という旧見出しが存在する
  #      → 実装後は "Dispatch（自動）" 等の新見出しに変わる
  # このテストは Step 2a-5 セクション見出しが存在することを確認するのみ
  grep -q "Step 2a-5" "${PHASE2_BUNDLES}"
}

@test "ac3: regression - co-issue-phase2-bundles.md file exists and is readable" {
  # AC: refs ファイルが存在し、読み取り可能である
  # GREEN: このテストは現時点で pass する（regression guard）
  [ -f "${PHASE2_BUNDLES}" ]
  [ -r "${PHASE2_BUNDLES}" ]
}
