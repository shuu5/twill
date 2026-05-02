#!/usr/bin/env bats
# issue-1254-su-observer-skillmd-constraints.bats
#
# RED-phase tests for Issue #1254:
#   tech-debt: su-observer SKILL.md 肥大化 → observer-constraints.md 分離 + SSoT 参照
#     - SKILL.md 行数を 120 行以下に削減
#     - plugins/twl/skills/su-observer/refs/su-observer-constraints.md を新規作成
#     - SU-* 10 項目 + 禁止事項 10 項目を新規 ref に移動
#     - SKILL.md から refs/su-observer-constraints.md への Read directive 追加
#     - deps.yaml に su-observer-constraints エントリ追加
#     - ref-invariants.md の境界注記更新
#
# AC coverage:
#   AC-1  - SKILL.md 行数が 120 以下（期待値ちょうど 120 行）
#   AC-2  - refs/su-observer-constraints.md が存在しサイズ > 0
#   AC-3  - 新規 ref 内に SU-1〜SU-9（含む SU-6a, SU-6b）の 10 トークン全件が存在
#   AC-4  - 新規 ref 内に既存 MUST NOT 10 項目キーワードが全件存在
#   AC-5  - SKILL.md 内に refs/su-observer-constraints.md を含む Read directive 行が存在
#   AC-6  - 新規 ref の先頭 30 行以内に supervision.md への参照が存在
#   AC-7  - deps.yaml に su-observer-constraints エントリ + loom --check 通過 + README 反映
#   AC-8  - ref-invariants.md 境界注記に 3 キーワード全て存在
#   AC-9  - supervision.md と新規 ref の SU-* テーブル行数が一致
#   AC-10 - SKILL.md 内に bullet 6.7 がちょうど 1 つ存在
#   AC-11 - 新規 ref 内に Layer A-D および su-observer-security-gate.md への参照が存在
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  CONSTRAINTS_MD="${REPO_ROOT}/skills/su-observer/refs/su-observer-constraints.md"
  DEPS_YAML="${REPO_ROOT}/deps.yaml"
  REF_INVARIANTS="${REPO_ROOT}/refs/ref-invariants.md"
  SUPERVISION_MD="${REPO_ROOT}/architecture/domain/contexts/supervision.md"

  export SKILL_MD CONSTRAINTS_MD DEPS_YAML REF_INVARIANTS SUPERVISION_MD
}

# ===========================================================================
# AC-1: SKILL.md 行数が 120 以下（期待値ちょうど 120 行）
# ===========================================================================

@test "ac1: SKILL.md line count is 120 or less" {
  # AC: wc -l plugins/twl/skills/su-observer/SKILL.md の出力が 120 以下であること
  # RED: 現在 152 行のため fail
  local line_count
  line_count="$(wc -l < "${SKILL_MD}")"
  [ "${line_count}" -le 120 ]
}

@test "ac1: SKILL.md line count is exactly 120 (expected after reduction)" {
  # AC: 期待値はちょうど 120 行（wc -l 実測 152 - 33 + 1）
  # RED: 現在 152 行のため fail
  local line_count
  line_count="$(wc -l < "${SKILL_MD}")"
  [ "${line_count}" -eq 120 ]
}

# ===========================================================================
# AC-2: refs/su-observer-constraints.md が存在しファイルサイズ > 0
# ===========================================================================

@test "ac2: refs/su-observer-constraints.md exists" {
  # AC: 新規 ref ファイルが存在すること
  # RED: ファイルがまだ作成されていないため fail
  [ -f "${CONSTRAINTS_MD}" ]
}

@test "ac2: refs/su-observer-constraints.md has non-zero size" {
  # AC: ファイルサイズ > 0 であること
  # RED: ファイルが存在しないため fail
  [ -s "${CONSTRAINTS_MD}" ]
}

# ===========================================================================
# AC-3: 新規 ref 内に SU-* 10 トークン全件が含まれること
#        （SU-1, SU-2, SU-3, SU-4, SU-5, SU-6a, SU-6b, SU-7, SU-8, SU-9）
# ===========================================================================

@test "ac3: constraints.md contains SU-1" {
  # AC: SU-1 が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-1' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-2" {
  # AC: SU-2 が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-2' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-3" {
  # AC: SU-3 が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-3' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-4" {
  # AC: SU-4 が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-4' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-5" {
  # AC: SU-5 が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-5' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-6a" {
  # AC: SU-6a が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-6a' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-6b" {
  # AC: SU-6b が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-6b' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-7" {
  # AC: SU-7 が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-7' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-8" {
  # AC: SU-8 が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-8' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains SU-9" {
  # AC: SU-9 が新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'SU-9' "${CONSTRAINTS_MD}"
}

@test "ac3: constraints.md contains all 10 SU-* tokens (comprehensive check)" {
  # AC: 10 トークン全件が含まれること
  # RED: ファイルが存在しないため fail
  local tokens=( 'SU-1' 'SU-2' 'SU-3' 'SU-4' 'SU-5' 'SU-6a' 'SU-6b' 'SU-7' 'SU-8' 'SU-9' )
  for token in "${tokens[@]}"; do
    grep -q "${token}" "${CONSTRAINTS_MD}" || {
      echo "Missing token: ${token}" >&2
      return 1
    }
  done
}

# ===========================================================================
# AC-4: 新規 ref 内に既存 MUST NOT 10 項目キーワードが全件含まれること
# ===========================================================================

@test "ac4: constraints.md contains MUST-NOT keyword 'Issue の直接実装'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'Issue の直接実装' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword 'AskUserQuestion でモード選択'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'AskUserQuestion でモード選択' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword 'Skill tool による'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'Skill tool による' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword 'Layer 2 介入'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'Layer 2 介入' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword '5 を超える'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q '5 を超える' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword 'context 80%'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'context 80%' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword 'externalize-state を省略'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q 'externalize-state を省略' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword '/compact の自動実行'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q '/compact の自動実行' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword '自動 Issue 起票'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q '自動 Issue 起票' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains MUST-NOT keyword '--with-chain --issue'" {
  # AC: 禁止事項キーワードが新規 ref に含まれること
  # RED: ファイルが存在しないため fail
  grep -q '\-\-with-chain \-\-issue' "${CONSTRAINTS_MD}"
}

@test "ac4: constraints.md contains all 10 MUST-NOT keywords (comprehensive check)" {
  # AC: 10 項目全件が含まれること
  # RED: ファイルが存在しないため fail
  local keywords=(
    'Issue の直接実装'
    'AskUserQuestion でモード選択'
    'Skill tool による'
    'Layer 2 介入'
    '5 を超える'
    'context 80%'
    'externalize-state を省略'
    '/compact の自動実行'
    '自動 Issue 起票'
    '--with-chain --issue'
  )
  for kw in "${keywords[@]}"; do
    grep -q -- "${kw}" "${CONSTRAINTS_MD}" || {
      echo "Missing keyword: ${kw}" >&2
      return 1
    }
  done
}

# ===========================================================================
# AC-5: SKILL.md 内に refs/su-observer-constraints.md を含む Read directive 行が存在
# ===========================================================================

@test "ac5: SKILL.md contains Read directive referencing refs/su-observer-constraints.md" {
  # AC: SKILL.md 内に refs/su-observer-constraints.md を含む Read directive 行が存在すること
  # RED: directive がまだ追加されていないため fail
  grep -qE 'refs/su-observer-constraints\.md' "${SKILL_MD}"
}

# ===========================================================================
# AC-6: 新規 ref の先頭 30 行以内に supervision.md への参照が含まれること
# ===========================================================================

@test "ac6: constraints.md first 30 lines contain reference to supervision.md" {
  # AC: 新規 ref の先頭 30 行以内に architecture/domain/contexts/supervision.md への参照が存在すること
  # RED: ファイルが存在しないため fail
  head -30 "${CONSTRAINTS_MD}" | grep -q 'supervision\.md'
}

# ===========================================================================
# AC-7: deps.yaml に su-observer-constraints エントリ + loom --check 通過 + README 反映
# ===========================================================================

@test "ac7a: deps.yaml contains su-observer-constraints entry" {
  # AC: deps.yaml に su-observer-constraints エントリが存在すること
  # RED: エントリがまだ追加されていないため fail
  grep -q 'su-observer-constraints' "${DEPS_YAML}"
}

@test "ac7b: loom --check passes without errors" {
  # AC: loom --check がエラーなしで終了すること
  # RED: deps.yaml に su-observer-constraints が未登録のため fail
  if ! command -v loom >/dev/null 2>&1; then
    skip "loom command not found"
  fi
  run loom check
  [ "${status}" -eq 0 ]
}

@test "ac7c: README contains su-observer-constraints" {
  # AC: README 内に su-observer-constraints が反映されていること
  # RED: loom --update-readme が未実行のため fail（su-observer-constraints 未記載）
  local readme_path
  readme_path="${REPO_ROOT}/README.md"
  [ -f "${readme_path}" ] || {
    echo "README.md not found at: ${readme_path}" >&2
    return 1
  }
  grep -q 'su-observer-constraints' "${readme_path}"
}

# ===========================================================================
# AC-8: ref-invariants.md 境界注記に 3 キーワード全て存在
#        (a) su-observer-constraints  (b) supervision\.md  (c) su-observer-security-gate
# ===========================================================================

@test "ac8a: ref-invariants.md contains 'su-observer-constraints' keyword" {
  # AC: ref-invariants.md 境界注記に su-observer-constraints が含まれること
  # RED: 境界注記がまだ更新されていないため fail
  grep -q 'su-observer-constraints' "${REF_INVARIANTS}"
}

@test "ac8b: ref-invariants.md contains 'supervision.md' keyword" {
  # AC: ref-invariants.md 境界注記に supervision.md が含まれること
  # RED: 境界注記がまだ更新されていないため fail
  grep -qE 'supervision\.md' "${REF_INVARIANTS}"
}

@test "ac8c: ref-invariants.md contains 'su-observer-security-gate' keyword" {
  # AC: ref-invariants.md 境界注記に su-observer-security-gate が含まれること
  # RED: 境界注記がまだ更新されていないため fail
  grep -q 'su-observer-security-gate' "${REF_INVARIANTS}"
}

@test "ac8: ref-invariants.md contains all 3 required keywords in boundary note" {
  # AC: 1 ファイル内 3 keyword の AND 条件を全て満たすこと
  # RED: 境界注記がまだ更新されていないため fail
  grep -q 'su-observer-constraints' "${REF_INVARIANTS}" || {
    echo "Missing: su-observer-constraints" >&2; return 1
  }
  grep -qE 'supervision\.md' "${REF_INVARIANTS}" || {
    echo "Missing: supervision.md" >&2; return 1
  }
  grep -q 'su-observer-security-gate' "${REF_INVARIANTS}" || {
    echo "Missing: su-observer-security-gate" >&2; return 1
  }
}

# ===========================================================================
# AC-9: supervision.md の SU-* テーブル行数と新規 ref の SU-* テーブル行数が一致
# ===========================================================================

@test "ac9: SU-* row count in constraints.md matches supervision.md" {
  # AC: supervision.md 内の SU-* テーブル行数と新規 ref 内の SU-* テーブル行数が一致すること
  # RED: 新規 ref が存在しないため fail
  local supervision_count constraints_count
  supervision_count="$(grep -c 'SU-[0-9]' "${SUPERVISION_MD}")"
  constraints_count="$(grep -c 'SU-[0-9]' "${CONSTRAINTS_MD}")"
  [ "${supervision_count}" -eq "${constraints_count}" ]
}

# ===========================================================================
# AC-10: SKILL.md 内に bullet 6.7 がちょうど 1 つ存在すること
# ===========================================================================

@test "ac10: SKILL.md contains exactly one bullet '6.7.'" {
  # AC: SKILL.md 内に bullet 6.7 がちょうど 1 つ存在すること（重複なし・欠落なし）
  # RED: 6.7 bullet がまだ追加されていないため fail（現状 0 件）
  local count
  count="$(grep -cE '^6\.7\.' "${SKILL_MD}")"
  [ "${count}" -eq 1 ]
}

# ===========================================================================
# AC-11: 新規 ref 内に Layer A-D および refs/su-observer-security-gate.md への参照が存在
# ===========================================================================

@test "ac11: constraints.md contains 'Layer A-D' reference" {
  # AC: 新規 ref 内に Layer A-D が含まれること
  # RED: ファイルが存在しないため fail
  grep -qE 'Layer A-D|Layer [A-D]' "${CONSTRAINTS_MD}"
}

@test "ac11: constraints.md contains reference to refs/su-observer-security-gate.md" {
  # AC: 新規 ref 内に refs/su-observer-security-gate.md への参照が含まれること
  # RED: ファイルが存在しないため fail
  grep -qE 'refs/su-observer-security-gate\.md|su-observer-security-gate\.md' "${CONSTRAINTS_MD}"
}

@test "ac11: constraints.md contains both Layer A-D and security-gate reference" {
  # AC: 2 keyword の AND 条件を全て満たすこと
  # RED: ファイルが存在しないため fail
  grep -qE 'Layer A-D|Layer [A-D]' "${CONSTRAINTS_MD}" || {
    echo "Missing: Layer A-D reference" >&2; return 1
  }
  grep -qE 'refs/su-observer-security-gate\.md|su-observer-security-gate\.md' "${CONSTRAINTS_MD}" || {
    echo "Missing: su-observer-security-gate.md reference" >&2; return 1
  }
}
