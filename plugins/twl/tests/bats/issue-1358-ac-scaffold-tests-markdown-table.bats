#!/usr/bin/env bats
# issue-1358-ac-scaffold-tests-markdown-table.bats
# Issue #1358: ac-scaffold-tests.md の bats セクションに「Markdown テーブル用語列マッチ」
# の小節を追加し、grep -qF '| term |' 使用ルールと偽陽性再現例・PR/commit 参照を記述する。
# RED: 実装前は全テストが FAIL する。

load 'helpers/common'

setup() {
  common_setup
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  AGENT_FILE="${REPO_ROOT}/agents/ac-scaffold-tests.md"
  export REPO_ROOT AGENT_FILE
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: bats セクション配下に「Markdown テーブル用語列マッチ」小節が追加されている
# ===========================================================================

@test "issue-1358: AC1 Markdown テーブル用語列マッチ subsection exists" {
  # AC: bats 生成時のチェック観点 の配下に「Markdown テーブル用語列マッチ」見出しが存在する
  # RED: 現在 ac-scaffold-tests.md に当該小節が存在しない
  grep -qF 'Markdown テーブル用語列マッチ' "${AGENT_FILE}"
}

@test "issue-1358: AC1 subsection appears after bats section heading" {
  # AC: 「Markdown テーブル用語列マッチ」は「bats 生成時のチェック観点」より後に存在する
  # RED: 当該小節が存在しないため fail
  local line_bats line_md
  line_bats=$(grep -n "bats 生成時のチェック観点" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  line_md=$(grep -n "Markdown テーブル用語列マッチ" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  [ -n "${line_bats}" ]
  [ -n "${line_md}" ]
  [ "${line_md}" -gt "${line_bats}" ]
}

# ===========================================================================
# AC2: 用語列検証には grep -qF '| term |' を使用するルールが明記されている
# ===========================================================================

@test "issue-1358: AC2 grep -qF with pipe delimiters rule is stated" {
  # AC: grep -qF '| <term> |' パターン（左右のパイプ区切りを含む）の使用ルールが明記されている
  # RED: 現在 ac-scaffold-tests.md にこのルールが存在しない
  grep -qF "grep -qF '|" "${AGENT_FILE}"
}

@test "issue-1358: AC2 rule appears within Markdown テーブル subsection" {
  # AC: grep -qF '| ... |' ルールは当該小節内（禁止事項より前）に存在する
  # RED: 当該小節が存在しないため fail
  local line_md line_rule line_mustnot
  line_md=$(grep -n "Markdown テーブル用語列マッチ" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  line_rule=$(grep -n "grep -qF '|" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  line_mustnot=$(grep -n "禁止事項" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  [ -n "${line_md}" ]
  [ -n "${line_rule}" ]
  [ "${line_rule}" -gt "${line_md}" ]
  [ "${line_rule}" -lt "${line_mustnot}" ]
}

# ===========================================================================
# AC3: 偽陽性 PASS の再現例が 1 件以上記述されている
# ===========================================================================

@test "issue-1358: AC3 false-positive example is present" {
  # AC: 「偽陽性」または "false positive" または「過剰マッチ」相当の記述が 1 件以上
  # RED: 現在 ac-scaffold-tests.md にこの記述が存在しない
  grep -qE "偽陽性|false.positive|過剰マッチ|overmatc" "${AGENT_FILE}"
}

@test "issue-1358: AC3 BAD grep example without pipe delimiters is present" {
  # AC: パイプなし grep（例: grep -qF 'term'）が偽陽性を引き起こす例として記述されている
  # RED: 現在 ac-scaffold-tests.md にこの例が存在しない
  # NOTE: '| term |' パターンではなく 'term' のみのパターンが BAD 例として登場する
  grep -qE "grep -qF '[^|]" "${AGENT_FILE}"
}

@test "issue-1358: AC3 false-positive example within Markdown テーブル subsection" {
  # AC: 偽陽性例は「Markdown テーブル用語列マッチ」小節内（禁止事項より前）に存在する
  # RED: 当該小節が存在しないため fail
  local line_md line_fp line_mustnot
  line_md=$(grep -n "Markdown テーブル用語列マッチ" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  line_fp=$(grep -nE "偽陽性|false.positive|過剰マッチ" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  line_mustnot=$(grep -n "禁止事項" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  [ -n "${line_md}" ]
  [ -n "${line_fp}" ]
  [ "${line_fp}" -gt "${line_md}" ]
  [ "${line_fp}" -lt "${line_mustnot}" ]
}

# ===========================================================================
# AC4: PR #1357 と commit 532d6e20 が参照として記載されている
# ===========================================================================

@test "issue-1358: AC4 PR #1357 reference is present" {
  # AC: 「#1357」または「PR #1357」等の参照が小節内に存在する
  # RED: 現在 ac-scaffold-tests.md に PR #1357 参照が存在しない
  grep -qF '#1357' "${AGENT_FILE}"
}

@test "issue-1358: AC4 commit 532d6e20 reference is present" {
  # AC: commit ハッシュ 532d6e20 が小節内に記載されている
  # RED: 現在 ac-scaffold-tests.md に 532d6e20 が存在しない
  grep -qF '532d6e20' "${AGENT_FILE}"
}

@test "issue-1358: AC4 references within Markdown テーブル subsection" {
  # AC: PR #1357 と 532d6e20 は両方とも当該小節内（禁止事項より前）に存在する
  # RED: 当該小節が存在しないため fail
  local line_md line_pr line_commit line_mustnot
  line_md=$(grep -n "Markdown テーブル用語列マッチ" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  line_pr=$(grep -n '#1357' "${AGENT_FILE}" | head -1 | cut -d: -f1)
  line_commit=$(grep -n '532d6e20' "${AGENT_FILE}" | head -1 | cut -d: -f1)
  line_mustnot=$(grep -n "禁止事項" "${AGENT_FILE}" | head -1 | cut -d: -f1)
  [ -n "${line_md}" ]
  [ -n "${line_pr}" ]
  [ -n "${line_commit}" ]
  [ "${line_pr}" -gt "${line_md}" ]
  [ "${line_pr}" -lt "${line_mustnot}" ]
  [ "${line_commit}" -gt "${line_md}" ]
  [ "${line_commit}" -lt "${line_mustnot}" ]
}

# ===========================================================================
# AC5: 禁止事項（MUST NOT）に矛盾する記述が追加されていない
# ===========================================================================

@test "issue-1358: AC5 MUST NOT section still exists" {
  # AC: 禁止事項セクションが存在し続けること（削除されていないこと）
  grep -qE "^## 禁止事項" "${AGENT_FILE}"
}

@test "issue-1358: AC5 deltaspec prohibition unchanged" {
  # AC: deltaspec/changes/ 参照禁止ルールが維持されていること
  grep -qF 'deltaspec/changes/' "${AGENT_FILE}"
}

@test "issue-1358: AC5 PASS test prohibition unchanged" {
  # AC: PASS するテストを意図的に生成してはならないルールが維持されていること
  grep -qE "PASS する.*テスト|intentionally.*pass|pass する.*生成" "${AGENT_FILE}"
}

@test "issue-1358: AC5 no test deletion prohibition unchanged" {
  # AC: 既存テストを削除・弱化してはならないルールが維持されていること
  grep -qE "削除.*弱化|弱化.*削除|削除・弱化" "${AGENT_FILE}"
}
