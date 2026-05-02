#!/usr/bin/env bats
# issue-1245-observer-checklist.bats
#
# RED-phase tests for Issue #1245:
#   tech-debt(observer): observer supervise checklist 新規作成
#     - observer-supervise-checklist.md 新規作成
#     - SKILL.md Step 1 supervise loop に checklist への reference 追加
#     - su-observer-supervise-channels.md に checklist への reference 追加
#     - deps.yaml に observer-supervise-checklist エントリ登録（type=reference）
#     - bats テスト追加（本ファイル）
#
# AC coverage:
#   AC1 - plugins/twl/skills/su-observer/refs/observer-supervise-checklist.md が新規作成されている
#   AC2 - SKILL.md Step 1 supervise loop から checklist への reference が追加されている
#   AC3 - su-observer-supervise-channels.md から checklist への reference が追加されている
#   AC4 - deps.yaml に observer-supervise-checklist エントリが登録されている（type=reference）
#   AC5 - bats テスト自身が存在し、5 件以上のテストを含む（self-referential）
#
# 全テストは実装前（RED）状態で fail する（AC5 を除く）。
# AC5 のみ self-referential のため、このファイルが書き出された時点で GREEN になる。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  CHECKLIST_MD="${REPO_ROOT}/skills/su-observer/refs/observer-supervise-checklist.md"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  CHANNELS_MD="${REPO_ROOT}/skills/su-observer/refs/su-observer-supervise-channels.md"
  DEPS_YAML="${REPO_ROOT}/deps.yaml"
  THIS_BATS="${REPO_ROOT}/tests/bats/issue-1245-observer-checklist.bats"

  export CHECKLIST_MD SKILL_MD CHANNELS_MD DEPS_YAML THIS_BATS
}

# ===========================================================================
# AC1: observer-supervise-checklist.md が新規作成されている
# ===========================================================================

@test "ac1: observer-supervise-checklist.md exists at expected path" {
  # AC: skills/su-observer/refs/observer-supervise-checklist.md が存在する
  # RED: ファイルがまだ作成されていないため fail
  [ -f "${CHECKLIST_MD}" ]
}

@test "ac1: observer-supervise-checklist.md is non-empty" {
  # AC: checklist ファイルが空でない（実装内容を含む）
  # RED: ファイルが存在しないため fail
  [ -s "${CHECKLIST_MD}" ]
}

@test "ac1: observer-supervise-checklist.md contains checklist items (at least one checkbox or list item)" {
  # AC: checklist ファイルにチェックリスト項目（チェックボックスまたはリスト）が含まれる
  # RED: ファイルが存在しないため fail
  run grep -qE '^\s*[-*]\s+\[[ xX]\]|^\s*[-*]\s+.+|^[0-9]+\.\s+' "${CHECKLIST_MD}"
  [ "${status}" -eq 0 ]
}

@test "ac1: observer-supervise-checklist.md has a markdown heading" {
  # AC: checklist ファイルに Markdown 見出し（# で始まる行）が含まれる
  # RED: ファイルが存在しないため fail
  run grep -qE '^#+ ' "${CHECKLIST_MD}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: SKILL.md Step 1 supervise loop から checklist への reference が追加されている
# ===========================================================================

@test "ac2: SKILL.md contains reference to observer-supervise-checklist" {
  # AC: SKILL.md に observer-supervise-checklist への参照が含まれる
  # RED: reference がまだ追加されていないため fail
  run grep -qE 'observer-supervise-checklist' "${SKILL_MD}"
  [ "${status}" -eq 0 ]
}

@test "ac2: SKILL.md reference to checklist is in Step 1 supervise loop section" {
  # AC: checklist への参照が Step 1 supervise loop のセクション内に存在する
  # RED: reference がまだ追加されていないため fail
  run bash -c "
    step1_line=\$(grep -n '^## Step 1' '${SKILL_MD}' | head -1 | cut -d: -f1)
    [ -n \"\${step1_line}\" ] || exit 1
    # Step 2 以降の行番号を取得
    next_section_line=\$(awk -v s=\"\${step1_line}\" 'NR > s && /^## Step [2-9]/ {print NR; exit}' '${SKILL_MD}')
    if [ -z \"\${next_section_line}\" ]; then
      next_section_line=\$(wc -l < '${SKILL_MD}')
    fi
    # Step 1 セクション内に observer-supervise-checklist への参照がある
    awk -v s=\"\${step1_line}\" -v e=\"\${next_section_line}\" \
      'NR >= s && NR <= e && /observer-supervise-checklist/ {found=1; exit} END {exit !found}' \
      '${SKILL_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2: SKILL.md checklist reference uses Read directive or link format" {
  # AC: checklist への参照が「Read」指示またはリンク形式で記述されている
  # RED: reference がまだ追加されていないため fail
  run bash -c "
    # 'Read' + 'observer-supervise-checklist' が近接して存在する、またはリンク形式
    grep -qE 'Read.*observer-supervise-checklist|observer-supervise-checklist.*Read|\[.*observer-supervise-checklist.*\]' '${SKILL_MD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: su-observer-supervise-channels.md から checklist への reference が追加されている
# ===========================================================================

@test "ac3: su-observer-supervise-channels.md contains reference to observer-supervise-checklist" {
  # AC: su-observer-supervise-channels.md に observer-supervise-checklist への参照が含まれる
  # RED: reference がまだ追加されていないため fail
  run grep -qE 'observer-supervise-checklist' "${CHANNELS_MD}"
  [ "${status}" -eq 0 ]
}

@test "ac3: su-observer-supervise-channels.md checklist reference is not a comment-only line" {
  # AC: checklist への参照がコメント行のみでなく、本文の指示・リンクとして存在する
  # RED: reference がまだ追加されていないため fail
  run bash -c "
    grep -E 'observer-supervise-checklist' '${CHANNELS_MD}' | grep -qvE '^#'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: su-observer-supervise-channels.md checklist reference appears as Read directive or link" {
  # AC: 参照が「Read」指示またはリンク形式（Markdown link or path形式）で記述されている
  # RED: reference がまだ追加されていないため fail
  run bash -c "
    grep -qE 'Read.*observer-supervise-checklist|observer-supervise-checklist.*Read|\[.*observer-supervise-checklist.*\]|\`observer-supervise-checklist\`' '${CHANNELS_MD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: deps.yaml に observer-supervise-checklist エントリが登録されている（type=reference）
# ===========================================================================

@test "ac4: deps.yaml contains observer-supervise-checklist entry" {
  # AC: deps.yaml に observer-supervise-checklist キーが存在する
  # RED: エントリがまだ追加されていないため fail
  run grep -qE '^  observer-supervise-checklist:' "${DEPS_YAML}"
  [ "${status}" -eq 0 ]
}

@test "ac4: deps.yaml observer-supervise-checklist entry has type: reference" {
  # AC: エントリの type が reference である
  # RED: エントリが存在しないため fail
  run bash -c "
    entry_line=\$(grep -n '^  observer-supervise-checklist:' '${DEPS_YAML}' | head -1 | cut -d: -f1)
    [ -n \"\${entry_line}\" ] || exit 1
    # エントリ直後 10 行以内に type: reference が存在する
    awk -v s=\"\${entry_line}\" '
      NR > s && NR < (s+10) && /^    type: reference/ {found=1; exit}
      NR > s && /^  [a-zA-Z]/ {exit}
      END {exit !found}
    ' '${DEPS_YAML}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4: deps.yaml observer-supervise-checklist entry has path pointing to checklist md" {
  # AC: エントリの path が skills/su-observer/refs/observer-supervise-checklist.md を指している
  # RED: エントリが存在しないため fail
  run bash -c "
    entry_line=\$(grep -n '^  observer-supervise-checklist:' '${DEPS_YAML}' | head -1 | cut -d: -f1)
    [ -n \"\${entry_line}\" ] || exit 1
    # エントリ直後 10 行以内に path: skills/su-observer/refs/observer-supervise-checklist.md が存在する
    awk -v s=\"\${entry_line}\" '
      NR > s && NR < (s+10) && /path:.*observer-supervise-checklist\.md/ {found=1; exit}
      NR > s && /^  [a-zA-Z]/ {exit}
      END {exit !found}
    ' '${DEPS_YAML}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4: deps.yaml observer-supervise-checklist entry has description field" {
  # AC: エントリに description フィールドが存在する（空でない）
  # RED: エントリが存在しないため fail
  run bash -c "
    entry_line=\$(grep -n '^  observer-supervise-checklist:' '${DEPS_YAML}' | head -1 | cut -d: -f1)
    [ -n \"\${entry_line}\" ] || exit 1
    # エントリ直後 15 行以内に description: が存在する
    awk -v s=\"\${entry_line}\" '
      NR > s && NR < (s+15) && /description:.*[^[:space:]]/ {found=1; exit}
      NR > s && /^  [a-zA-Z]/ {exit}
      END {exit !found}
    ' '${DEPS_YAML}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4: deps.yaml observer-supervise-checklist is placed in su-observer split refs section" {
  # AC: エントリが su-observer split refs セクション（またはその近傍）に配置されている
  # RED: エントリが存在しないため fail
  run bash -c "
    entry_line=\$(grep -n '^  observer-supervise-checklist:' '${DEPS_YAML}' | head -1 | cut -d: -f1)
    [ -n \"\${entry_line}\" ] || exit 1
    # エントリ前 30 行以内に su-observer の関連コメントまたはキーが存在する
    awk -v s=\"\${entry_line}\" '
      NR >= (s-30) && NR < s && /su-observer/ {found=1}
      END {exit !found}
    ' '${DEPS_YAML}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: bats テスト自身が存在し、5 件以上のテストを含む（self-referential）
#
# 注記: このテストは self-referential である。本ファイル自体が存在し、
#       かつ 5 件以上の @test ブロックを含むことを検証する。
#       このファイルが書き出された時点で GREEN になる（他の AC と異なる）。
# ===========================================================================

@test "ac5: this bats test file exists at expected path" {
  # AC: bats ファイルが plugins/twl/tests/bats/issue-1245-observer-checklist.bats として存在する
  # GREEN: このファイル自体が存在するため、実行時点では pass する
  [ -f "${THIS_BATS}" ]
}

@test "ac5: this bats test file contains at least 5 test blocks" {
  # AC: 本ファイルに 5 件以上の @test ブロックが含まれる
  # GREEN: このファイルが書き出された時点で pass する
  local count
  count="$(grep -c '^@test ' "${THIS_BATS}")"
  [ "${count}" -ge 5 ]
}
