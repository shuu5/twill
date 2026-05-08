#!/usr/bin/env bats
# issue-1551-invariant-n-anchor.bats - TDD RED phase tests for Issue #1551
# "tech-debt(arch): ref-invariants.md に Invariant N / lesson 19 記述を追加"
#
# AC summary:
#   AC1: ref-invariants.md に invariant-n-lesson-structuralization アンカーを追加
#        （ADR-036 が参照する #invariant-n-lesson-structuralization と整合させる）
#   AC2: plugins/twl/CLAUDE.md に Invariant N / lesson 19 への言及を追加
#
# RED: 全テストは実装前の状態で fail する

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  REF_INVARIANTS="${REPO_ROOT}/refs/ref-invariants.md"
  PLUGIN_CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"
  ADR_036="${REPO_ROOT}/architecture/decisions/ADR-036-lesson-structuralization.md"
  export REF_INVARIANTS PLUGIN_CLAUDE_MD ADR_036
}

# ===========================================================================
# AC1: ref-invariants.md に invariant-n-lesson-structuralization アンカー追加
# ===========================================================================

@test "issue-1551: AC1 ref-invariants.md に 'invariant-n-lesson-structuralization' アンカーが存在すること" {
  # RED: HTML アンカー未追加のため fail する
  [ -f "${REF_INVARIANTS}" ]
  grep -qF "invariant-n-lesson-structuralization" "${REF_INVARIANTS}"
}

@test "issue-1551: AC1 ADR-036 が参照するアンカーが ref-invariants.md で解決できること" {
  # RED: ADR-036 が参照する #invariant-n-lesson-structuralization が未定義のため fail する
  [ -f "${ADR_036}" ]
  # ADR-036 内のアンカー参照を取得
  grep -qF "invariant-n-lesson-structuralization" "${ADR_036}"
  # 同一アンカーが ref-invariants.md に存在すること（参照整合性）
  grep -qF "invariant-n-lesson-structuralization" "${REF_INVARIANTS}"
}

# ===========================================================================
# AC2: plugins/twl/CLAUDE.md に Invariant N / lesson 19 の言及を追加
# ===========================================================================

@test "issue-1551: AC2 CLAUDE.md に 'Invariant N' または 'lesson 19' への言及が存在すること" {
  # RED: CLAUDE.md に該当記述がないため fail する
  [ -f "${PLUGIN_CLAUDE_MD}" ]
  grep -qiE "Invariant N|invariant.n|lesson.19|lesson_19" "${PLUGIN_CLAUDE_MD}"
}
